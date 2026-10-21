-- =====================================================================
-- Green Fish — planos mensais e cobrança
-- config/planos (dono): planos, preços, carência, chave PIX, cobrança ativa
-- assinaturas/<id> (dono grava; a pessoa lê a sua): plano, vencimento, isento, liberação/cancelamento manual, histórico
-- avisos/<id> (a pessoa grava): "já paguei" com referência, para o dono confirmar
-- A situação (em dia / carência / inadimplente) é calculada pelo banco a cada acesso:
-- inadimplente ou cancelado manualmente não salva projetos na conta.
-- Rode no Supabase > SQL Editor depois de supabase_padrao.sql (pode rodar de novo).
-- =====================================================================

create or replace function public.ras_situacao_pagamento(alvo uuid) returns text
language plpgsql stable security definer set search_path = public as $$
declare cfg jsonb; a jsonb; venc timestamptz; car int;
begin
  -- cada pessoa só consulta a própria situação; o dono e o servidor do gateway consultam qualquer uma
  if alvo is distinct from auth.uid() and not public.ras_is_dono()
     and coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'role', '') <> 'service_role' then
    return null;
  end if;
  select data into cfg from public.ras_docs where path = 'config/planos';
  if cfg is null or coalesce((cfg->>'ativa')::boolean, false) = false then return 'isento'; end if;
  if exists (select 1 from public.ras_admins where user_id = alvo and dono) then return 'isento'; end if;
  select data into a from public.ras_docs where path = 'assinaturas/' || alvo;
  if a is null then return 'sem_plano'; end if;
  if a->>'override' = 'liberado' then return 'liberado_manual'; end if;
  if a->>'override' = 'cancelado' then return 'cancelado_manual'; end if;
  if coalesce((a->>'isento')::boolean, false) then return 'isento'; end if;
  if a->>'vencimento' is null then return 'inadimplente'; end if;
  venc := to_timestamp((a->>'vencimento')::bigint / 1000.0);
  car := coalesce((cfg->>'carencia')::int, 5);
  if now() <= venc then return 'em_dia'; end if;
  if now() <= venc + make_interval(days => car) then return 'carencia'; end if;
  return 'inadimplente';
end
$$;

create or replace function public.ras_em_dia(alvo uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.ras_situacao_pagamento(alvo) not in ('inadimplente', 'cancelado_manual')
$$;

create or replace function public.ras_pode(p text, escrever boolean) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  s1 text := split_part(p, '/', 1);
  s2 text := split_part(p, '/', 2);
  s3 text := split_part(p, '/', 3);
  eu text := auth.uid()::text;
begin
  if eu is null then return false; end if;
  if s1 = 'data' then
    return s2 = 'users' and s3 = eu and (not escrever or public.ras_em_dia(auth.uid()));
  end if;
  if s1 in ('assinaturas') then
    return (not escrever and s2 = eu) or public.ras_is_dono();
  end if;
  if s1 in ('avisos') then
    return s2 = eu or public.ras_is_dono();
  end if;
  if s1 in ('inscricoes', 'perfis', 'acessos') then
    if s2 = eu then return not escrever or s1 <> 'acessos' or public.ras_is_dono(); end if;
    if public.ras_is_dono() then return true; end if;
    if escrever then return false; end if;
    return public.ras_is_admin()
       and ((public.ras_pendente(s2) and public.ras_da_minha_equipe(s2)) or public.ras_liberado_por_mim(s2));
  end if;
  if s1 = 'config' then return (not escrever) or public.ras_is_dono(); end if;
  return false;
end
$$;

-- registrar pagamento: dono (manual) ou o servidor do gateway (service_role, automático)
create or replace function public.ras_registrar_pagamento(alvo uuid, meses integer, valor numeric, ref text) returns bigint
language plpgsql volatile security definer set search_path = public as $$
declare a jsonb; base timestamptz; novo timestamptz; papel text;
begin
  papel := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'role', '');
  if not (public.ras_is_dono() or papel = 'service_role') then raise exception 'Somente o dono registra pagamentos'; end if;
  if meses is null or meses < 1 or meses > 24 then raise exception 'Quantidade de meses inválida'; end if;
  select data into a from public.ras_docs where path = 'assinaturas/' || alvo;
  a := coalesce(a, jsonb_build_object('plano', 'basico'));
  base := greatest(now(), coalesce(to_timestamp((a->>'vencimento')::bigint / 1000.0), now()));
  novo := base + make_interval(months => meses);
  a := a || jsonb_build_object(
    'vencimento', (extract(epoch from novo) * 1000)::bigint,
    'ultimoPagamento', (extract(epoch from now()) * 1000)::bigint,
    'historico', (jsonb_build_array(jsonb_build_object('em', (extract(epoch from now()) * 1000)::bigint, 'meses', meses, 'valor', valor, 'ref', left(coalesce(ref, ''), 120), 'por', coalesce(auth.uid()::text, 'gateway')))
                  || coalesce(a->'historico', '[]'::jsonb)) - 24);
  insert into public.ras_docs (path, col, data, updated_at) values ('assinaturas/' || alvo, 'assinaturas', a, now())
    on conflict (path) do update set data = excluded.data, updated_at = now();
  delete from public.ras_docs where path = 'avisos/' || alvo;
  return (extract(epoch from novo) * 1000)::bigint;
end
$$;

-- liberar login também abre a assinatura no plano básico (vence na hora; a carência dá o prazo para pagar)
create or replace function public.ras_aprovar(alvo uuid) returns text
language plpgsql volatile security definer set search_path = public as $$
declare
  ins jsonb; ac jsonb; sou_dono boolean := public.ras_is_dono(); lim int; usados int; base jsonb; cfg jsonb;
begin
  if not public.ras_is_admin() then raise exception 'Somente administradores liberam logins'; end if;
  select data into ins from public.ras_docs where path = 'inscricoes/' || alvo;
  if ins is null or ins->>'status' = 'cancelada' then raise exception 'Esta pessoa não tem inscrição ativa'; end if;
  select data into ac from public.ras_docs where path = 'acessos/' || alvo;
  if ac->>'status' = 'ativo' then return 'ja_ativo'; end if;
  base := coalesce(ac, '{}'::jsonb);
  if not sou_dono then
    if coalesce(ins->>'equipe', '') <> left(auth.uid()::text, 8) then raise exception 'Esta pessoa não é da sua equipe'; end if;
    if ac->>'status' in ('suspenso', 'cancelado') then raise exception 'Bloqueado pelo dono do app'; end if;
    select a.limite into lim from public.ras_admins a where a.user_id = auth.uid();
    select count(*) into usados from public.ras_aprovacoes r where r.admin = auth.uid();
    if usados >= coalesce(lim, 0) then raise exception 'Cota de logins esgotada'; end if;
    if not public.ras_em_dia(auth.uid()) then raise exception 'Mensalidade do administrador em atraso'; end if;
    base := base - 'abas' - 'plano';
  end if;
  insert into public.ras_docs (path, col, data, updated_at)
    values ('acessos/' || alvo, 'acessos',
            base || jsonb_build_object('status', 'ativo', 'em', (extract(epoch from now()) * 1000)::bigint, 'por', auth.uid()),
            now())
    on conflict (path) do update set data = excluded.data, updated_at = now();
  insert into public.ras_aprovacoes (alvo, admin) values (alvo, auth.uid()) on conflict on constraint ras_aprovacoes_pkey do nothing;
  select data into cfg from public.ras_docs where path = 'config/planos';
  if coalesce((cfg->>'ativa')::boolean, false) and not exists (select 1 from public.ras_docs where path = 'assinaturas/' || alvo) then
    insert into public.ras_docs (path, col, data) values ('assinaturas/' || alvo, 'assinaturas',
      jsonb_build_object('plano', 'basico', 'vencimento', (extract(epoch from now()) * 1000)::bigint, 'criada', (extract(epoch from now()) * 1000)::bigint));
  end if;
  return 'ok';
end
$$;

revoke all on function public.ras_registrar_pagamento(uuid, integer, numeric, text) from public, anon;
grant execute on function public.ras_registrar_pagamento(uuid, integer, numeric, text) to authenticated, service_role;
grant execute on function public.ras_situacao_pagamento(uuid) to authenticated;
grant execute on function public.ras_em_dia(uuid) to authenticated;
revoke all on function public.ras_aprovar(uuid) from public, anon;
grant execute on function public.ras_aprovar(uuid) to authenticated;
