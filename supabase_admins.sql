-- =====================================================================
-- RAS Multitanques — versão avançada: dono do app e administradores
-- Rode no Supabase > SQL Editor depois do supabase_setup.sql (pode rodar de novo).
-- =====================================================================

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
