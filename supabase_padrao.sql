-- =====================================================================
-- Green Fish — logins liberados por administrador recebem só as abas padrão
-- (o administrador não define abas nem versão; o dono continua podendo mudar depois)
-- Rode no Supabase > SQL Editor depois de supabase_equipes.sql (pode rodar de novo).
-- =====================================================================
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
