-- =====================================================================
-- RAS Multitanques — configuração do banco no Supabase
-- Cole tudo no Supabase > SQL Editor > New query e clique em Run.
-- Pode rodar de novo sem problema (é idempotente).
-- =====================================================================

-- Documentos do app (projetos, inscrições, decisões do administrador, perfis e configurações)
create table if not exists public.ras_docs (
  path       text primary key,
  col        text not null,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create index if not exists ras_docs_col on public.ras_docs (col);

-- Administradores do app
create table if not exists public.ras_admins (
  user_id uuid primary key references auth.users (id) on delete cascade
);

alter table public.ras_docs   enable row level security;
alter table public.ras_admins enable row level security;

create or replace function public.ras_is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.ras_admins where user_id = auth.uid())
$$;

-- Quem pode ler ou gravar cada caminho
--   data/users/<id>/...  -> só a própria pessoa (projetos são privados, nem o administrador vê)
--   inscricoes/<id>, perfis/<id> -> a própria pessoa grava; o administrador lê e grava
--   acessos/<id>         -> só o administrador grava; a pessoa lê a sua decisão
--   config/...           -> todos com conta leem; só o administrador grava
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
  if s1 in ('inscricoes', 'perfis') then return s2 = eu or public.ras_is_admin(); end if;
  if s1 = 'acessos' then return (not escrever and s2 = eu) or public.ras_is_admin(); end if;
  if s1 = 'config' then return (not escrever) or public.ras_is_admin(); end if;
  return false;
end
$$;

drop policy if exists ras_ler     on public.ras_docs;
drop policy if exists ras_inserir on public.ras_docs;
drop policy if exists ras_alterar on public.ras_docs;
drop policy if exists ras_apagar  on public.ras_docs;
create policy ras_ler     on public.ras_docs for select to authenticated using (public.ras_pode(path, false));
create policy ras_inserir on public.ras_docs for insert to authenticated with check (public.ras_pode(path, true) and col = regexp_replace(path, '/[^/]+$', ''));
create policy ras_alterar on public.ras_docs for update to authenticated using (public.ras_pode(path, true)) with check (public.ras_pode(path, true) and col = regexp_replace(path, '/[^/]+$', ''));
create policy ras_apagar  on public.ras_docs for delete to authenticated using (public.ras_pode(path, true));

grant select, insert, update, delete on public.ras_docs to authenticated;
grant execute on function public.ras_is_admin() to authenticated;

-- A primeira conta criada no app vira administradora automaticamente
create or replace function public.ras_primeiro_admin() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.ras_admins) then
    insert into public.ras_admins (user_id) values (new.id);
  end if;
  return new;
end
$$;
drop trigger if exists ras_primeiro_admin on auth.users;
create trigger ras_primeiro_admin after insert on auth.users
  for each row execute function public.ras_primeiro_admin();

-- Para tornar outra conta administradora (troque o e-mail):
-- insert into public.ras_admins (user_id) select id from auth.users where email = 'pessoa@exemplo.com' on conflict do nothing;

-- ---- Versão avançada: dono do app e administradores ----
alter table public.ras_admins add column if not exists dono boolean not null default false;

-- a conta administradora mais antiga vira a dona do app (se ainda não houver dono)
update public.ras_admins set dono = true
 where user_id = (select a.user_id from public.ras_admins a join auth.users u on u.id = a.user_id order by u.created_at limit 1)
   and not exists (select 1 from public.ras_admins where dono);

create or replace function public.ras_is_dono() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.ras_admins where user_id = auth.uid() and dono)
$$;

-- lista de administradores (só administradores enxergam)
create or replace function public.ras_listar_admins() returns table (user_id uuid, dono boolean)
language sql stable security definer set search_path = public as $$
  select a.user_id, a.dono from public.ras_admins a where public.ras_is_admin()
$$;

-- tornar ou remover administrador: só o dono; o dono nunca é removido
create or replace function public.ras_definir_admin(alvo uuid, ser boolean) returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  if not public.ras_is_dono() then raise exception 'Somente o dono do app escolhe administradores'; end if;
  if ser then
    insert into public.ras_admins (user_id, dono) values (alvo, false) on conflict (user_id) do nothing;
  else
    if exists (select 1 from public.ras_admins where user_id = alvo and dono) then raise exception 'O dono do app não pode ser removido'; end if;
    delete from public.ras_admins where user_id = alvo and not dono;
  end if;
end
$$;

-- a primeira conta criada vira administradora e dona
create or replace function public.ras_primeiro_admin() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.ras_admins) then
    insert into public.ras_admins (user_id, dono) values (new.id, true);
  end if;
  return new;
end
$$;

revoke all on function public.ras_definir_admin(uuid, boolean) from public, anon;
grant execute on function public.ras_is_dono() to authenticated;
grant execute on function public.ras_listar_admins() to authenticated;
grant execute on function public.ras_definir_admin(uuid, boolean) to authenticated;

-- ---- Administradores restritos com cota de logins ----
alter table public.ras_admins add column if not exists limite integer not null default 0;

create table if not exists public.ras_aprovacoes (
  alvo  uuid primary key,
  admin uuid not null,
  em    timestamptz not null default now()
);
alter table public.ras_aprovacoes enable row level security;

-- regras de leitura e gravação: administradores leem; só o dono grava decisões e configurações
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
  if s1 in ('inscricoes', 'perfis') then
    return s2 = eu or (case when escrever then public.ras_is_dono() else public.ras_is_admin() end);
  end if;
  if s1 = 'acessos' then
    return (not escrever and (s2 = eu or public.ras_is_admin())) or public.ras_is_dono();
  end if;
  if s1 = 'config' then return (not escrever) or public.ras_is_dono(); end if;
  return false;
end
$$;

drop function if exists public.ras_listar_admins();
create function public.ras_listar_admins() returns table (user_id uuid, dono boolean, limite integer, usados integer)
language sql stable security definer set search_path = public as $$
  select a.user_id, a.dono, a.limite,
         (select count(*)::int from public.ras_aprovacoes r where r.admin = a.user_id)
    from public.ras_admins a where public.ras_is_admin()
$$;

create or replace function public.ras_minha_cota() returns table (limite integer, usados integer, dono boolean)
language sql stable security definer set search_path = public as $$
  select a.limite, (select count(*)::int from public.ras_aprovacoes r where r.admin = a.user_id), a.dono
    from public.ras_admins a where a.user_id = auth.uid()
$$;

-- o dono define quantos logins cada administrador pode liberar
create or replace function public.ras_definir_limite(alvo uuid, novo integer) returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  if not public.ras_is_dono() then raise exception 'Somente o dono do app define a cota'; end if;
  if novo is null or novo < 0 then raise exception 'Cota inválida'; end if;
  update public.ras_admins set limite = novo where user_id = alvo and not dono;
end
$$;

-- liberar o login de uma pessoa inscrita (administrador: dentro da cota; dono: sem limite)
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

revoke all on function public.ras_definir_limite(uuid, integer) from public, anon;
revoke all on function public.ras_aprovar(uuid) from public, anon;
grant execute on function public.ras_listar_admins() to authenticated;
grant execute on function public.ras_minha_cota() to authenticated;
grant execute on function public.ras_definir_limite(uuid, integer) to authenticated;
grant execute on function public.ras_aprovar(uuid) to authenticated;

-- ---- Privacidade entre administradores ----
create or replace function public.ras_pendente(id text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.ras_docs i where i.path = 'inscricoes/' || id and coalesce(i.data->>'status', '') <> 'cancelada')
     and coalesce((select a.data->>'status' from public.ras_docs a where a.path = 'acessos/' || id), '') not in ('ativo', 'suspenso', 'cancelado')
$$;

create or replace function public.ras_liberado_por_mim(id text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.ras_aprovacoes r where r.alvo::text = id and r.admin = auth.uid())
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
    return public.ras_is_admin() and (public.ras_pendente(s2) or public.ras_liberado_por_mim(s2));
  end if;
  if s1 = 'config' then return (not escrever) or public.ras_is_dono(); end if;
  return false;
end
$$;

-- administrador comum só vê a própria linha na lista de administradores
drop function if exists public.ras_listar_admins();
create function public.ras_listar_admins() returns table (user_id uuid, dono boolean, limite integer, usados integer)
language sql stable security definer set search_path = public as $$
  select a.user_id, a.dono, a.limite,
         (select count(*)::int from public.ras_aprovacoes r where r.admin = a.user_id)
    from public.ras_admins a
   where public.ras_is_dono() or (public.ras_is_admin() and a.user_id = auth.uid())
$$;

revoke all on function public.ras_pendente(text) from public, anon;
revoke all on function public.ras_liberado_por_mim(text) from public, anon;
grant execute on function public.ras_pendente(text) to authenticated;
grant execute on function public.ras_liberado_por_mim(text) to authenticated;
grant execute on function public.ras_listar_admins() to authenticated;

-- ---- Equipes de administradores ----
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

-- ---- Logins liberados por administrador: só abas padrão ----
create or replace function public.ras_aprovar(alvo uuid) returns text
language plpgsql volatile security definer set search_path = public as $$
declare
  ins jsonb; ac jsonb; sou_dono boolean := public.ras_is_dono(); lim int; usados int; base jsonb;
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
    base := base - 'abas' - 'plano';   -- liberado por administrador: só as abas padrão
  end if;
  insert into public.ras_docs (path, col, data, updated_at)
    values ('acessos/' || alvo, 'acessos',
            base || jsonb_build_object('status', 'ativo', 'em', (extract(epoch from now()) * 1000)::bigint, 'por', auth.uid()),
            now())
    on conflict (path) do update set data = excluded.data, updated_at = now();
  insert into public.ras_aprovacoes (alvo, admin) values (alvo, auth.uid()) on conflict on constraint ras_aprovacoes_pkey do nothing;
  return 'ok';
end
$$;
revoke all on function public.ras_aprovar(uuid) from public, anon;
grant execute on function public.ras_aprovar(uuid) to authenticated;


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


-- =====================================================================
-- Green Fish — o dono do app consulta os projetos de todos os clientes
-- Somente leitura: o dono lê data/users/<id>/...; só a própria pessoa grava ou exclui.
-- Rode no Supabase > SQL Editor depois de supabase_cobranca.sql (pode rodar de novo).
-- =====================================================================

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
    if s2 = 'users' and s3 = eu then return not escrever or public.ras_em_dia(auth.uid()); end if;
    return s2 = 'users' and not escrever and public.ras_is_dono();   -- dono consulta (só leitura) os projetos de todos
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
