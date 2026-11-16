-- Green Fish v248 · Ordens de despesca e transporte na nuvem
-- Documentos na tabela ras_docs (a mesma do app), separados por responsável:
--   ordesp/<uid do responsável>/<código da ordem>   uma ordem (aceite, captura, transporte, chegada, rastreabilidade)
--   ordesp/<uid do responsável>/_cfg                numeração das ordens, fábrica e últimos dados usados
-- Responsável = o dono do app ou um administrador (coordenador de equipe): só ele grava e altera as próprias ordens.
-- Colaborador com acesso ativo: só LÊ as ordens de quem coordena a equipe dele
--   (o administrador da equipe; sem equipe, o dono do app).
-- Não altera nenhuma regra existente: só acrescenta funções e políticas novas para o caminho ordesp/.

-- de quem são as ordens que esta conta vê (o próprio uid quando ela é responsável)
create or replace function public.ras_ordesp_lider() returns text
language plpgsql stable security definer set search_path = public as $$
declare
  eu uuid := auth.uid();
  ac jsonb;
  eq text;
  r text;
begin
  if eu is null then return null; end if;
  if public.ras_is_dono() or public.ras_is_admin() then return eu::text; end if;
  select data into ac from public.ras_docs where path = 'acessos/' || eu::text;
  if coalesce(ac->>'status', '') <> 'ativo' then return null; end if;
  select data->>'equipe' into eq from public.ras_docs where path = 'inscricoes/' || eu::text;
  if coalesce(eq, '') <> '' then
    select a.user_id::text into r from public.ras_admins a where left(a.user_id::text, 8) = eq limit 1;
    if r is not null then return r; end if;
  end if;
  if coalesce(ac->>'por', '') <> '' then
    select a.user_id::text into r from public.ras_admins a where a.user_id::text = ac->>'por' limit 1;
    if r is not null then return r; end if;
  end if;
  select a.user_id::text into r from public.ras_admins a where a.dono limit 1;
  return r;
end
$$;
revoke all on function public.ras_ordesp_lider() from public, anon;
grant execute on function public.ras_ordesp_lider() to authenticated;

create or replace function public.ras_ordesp_pode(p text, escrever boolean) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  eu text := auth.uid()::text;
  s2 text := split_part(p, '/', 2);
begin
  if eu is null or split_part(p, '/', 1) <> 'ordesp' or s2 = '' or split_part(p, '/', 3) = '' then return false; end if;
  if s2 = eu then return (not escrever) or public.ras_ordesp_lider() = eu; end if;
  if escrever then return false; end if;
  if public.ras_is_dono() then return true; end if;
  return s2 = public.ras_ordesp_lider();
end
$$;
revoke all on function public.ras_ordesp_pode(text, boolean) from public, anon;
grant execute on function public.ras_ordesp_pode(text, boolean) to authenticated;

drop policy if exists ras_ordesp_sel on public.ras_docs;
drop policy if exists ras_ordesp_ins on public.ras_docs;
drop policy if exists ras_ordesp_upd on public.ras_docs;
drop policy if exists ras_ordesp_del on public.ras_docs;
create policy ras_ordesp_sel on public.ras_docs for select to authenticated using (public.ras_ordesp_pode(path, false));
create policy ras_ordesp_ins on public.ras_docs for insert to authenticated with check (public.ras_ordesp_pode(path, true) and col = regexp_replace(path, '/[^/]+$', ''));
create policy ras_ordesp_upd on public.ras_docs for update to authenticated using (public.ras_ordesp_pode(path, true)) with check (public.ras_ordesp_pode(path, true) and col = regexp_replace(path, '/[^/]+$', ''));
create policy ras_ordesp_del on public.ras_docs for delete to authenticated using (public.ras_ordesp_pode(path, true));

-- tempo real (o Supabase Realtime respeita as regras de leitura acima)
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'ras_docs') then
    execute 'alter publication supabase_realtime add table public.ras_docs';
  end if;
exception when undefined_object then null;
end $$;
