-- =====================================================================
-- RAS Multitanques — equipes de administradores
-- Cada administrador tem um código/link de convite (8 primeiros caracteres do id).
-- Quem se inscreve com o código fica na equipe dele: só ele (e o dono) vê e libera.
-- Rode no Supabase > SQL Editor depois de supabase_privacidade.sql (pode rodar de novo).
-- =====================================================================

create or replace function public.ras_meu_codigo() returns text
language sql stable as $$ select left(auth.uid()::text, 8) $$;

create or replace function public.ras_da_minha_equipe(id text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.ras_docs i where i.path = 'inscricoes/' || id and i.data->>'equipe' = left(auth.uid()::text, 8))
$$;

-- nome do administrador dono de um código de equipe (só o nome; nada mais)
create or replace function public.ras_nome_equipe(codigo text) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(p.data->>'nome', ''), 'Administrador')
    from public.ras_admins a left join public.ras_docs p on p.path = 'perfis/' || a.user_id
   where left(a.user_id::text, 8) = lower(codigo) limit 1
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
  if s1 = 'data' then return s2 = 'users' and s3 = eu; end if;
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

-- liberar login: administrador só libera quem é da equipe dele, dentro da cota; dono libera qualquer um
create or replace function public.ras_aprovar(alvo uuid) returns text
language plpgsql volatile security definer set search_path = public as $$
declare
  ins jsonb; ac jsonb; sou_dono boolean := public.ras_is_dono(); lim int; usados int;
begin
  if not public.ras_is_admin() then raise exception 'Somente administradores liberam logins'; end if;
  select data into ins from public.ras_docs where path = 'inscricoes/' || alvo;
  if ins is null or ins->>'status' = 'cancelada' then raise exception 'Esta pessoa não tem inscrição ativa'; end if;
  select data into ac from public.ras_docs where path = 'acessos/' || alvo;
  if ac->>'status' = 'ativo' then return 'ja_ativo'; end if;
  if not sou_dono then
    if coalesce(ins->>'equipe', '') <> left(auth.uid()::text, 8) then raise exception 'Esta pessoa não é da sua equipe'; end if;
    if ac->>'status' in ('suspenso', 'cancelado') then raise exception 'Bloqueado pelo dono do app'; end if;
    select a.limite into lim from public.ras_admins a where a.user_id = auth.uid();
    select count(*) into usados from public.ras_aprovacoes r where r.admin = auth.uid();
    if usados >= coalesce(lim, 0) then raise exception 'Cota de logins esgotada'; end if;
  end if;
  insert into public.ras_docs (path, col, data, updated_at)
    values ('acessos/' || alvo, 'acessos',
            coalesce(ac, '{}'::jsonb) || jsonb_build_object('status', 'ativo', 'em', (extract(epoch from now()) * 1000)::bigint, 'por', auth.uid()),
            now())
    on conflict (path) do update set data = excluded.data, updated_at = now();
  insert into public.ras_aprovacoes (alvo, admin) values (alvo, auth.uid()) on conflict on constraint ras_aprovacoes_pkey do nothing;
  return 'ok';
end
$$;

revoke all on function public.ras_da_minha_equipe(text) from public, anon;
grant execute on function public.ras_da_minha_equipe(text) to authenticated;
grant execute on function public.ras_nome_equipe(text) to authenticated;
grant execute on function public.ras_meu_codigo() to authenticated;
