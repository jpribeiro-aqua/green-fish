-- =====================================================================
-- RAS Multitanques — privacidade entre administradores
-- Administrador (não dono) só enxerga quem está aguardando aprovação
-- e quem ele mesmo liberou. O dono continua vendo todos.
-- Rode no Supabase > SQL Editor depois de supabase_cotas.sql (pode rodar de novo).
-- =====================================================================

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
