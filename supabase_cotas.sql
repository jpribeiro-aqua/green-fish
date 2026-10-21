-- =====================================================================
-- RAS Multitanques — administradores restritos com cota de logins
-- Administradores (não donos) só: veem todas as abas e liberam logins,
-- até a quantidade que o dono definir. Todo o resto é só do dono.
-- Rode no Supabase > SQL Editor depois de supabase_setup.sql e supabase_admins.sql.
-- =====================================================================

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
