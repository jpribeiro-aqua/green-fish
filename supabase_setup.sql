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
