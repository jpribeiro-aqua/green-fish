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
