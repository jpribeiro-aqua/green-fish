-- Green Fish · verificação em duas etapas (TOTP) obrigatória no servidor
-- Rode UMA vez no Supabase: Dashboard › SQL Editor › New query › colar › Run.
-- Efeito: quem ATIVOU a verificação em duas etapas só lê e grava os dados depois de digitar o código
-- (sessão "aal2"). Quem não ativou continua entrando só com a senha, como hoje.

create or replace function public.ras_aal_ok()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select auth.jwt() ->> 'aal'), 'aal1') = 'aal2'
      or not exists (
        select 1 from auth.mfa_factors f
        where f.user_id = (select auth.uid()) and f.status = 'verified'
      );
$$;

revoke all on function public.ras_aal_ok() from public;
grant execute on function public.ras_aal_ok() to authenticated;

-- políticas RESTRITIVAS: somam-se às que já existem (não as substituem)
drop policy if exists ras_mfa on public.ras_docs;
create policy ras_mfa on public.ras_docs as restrictive for all to authenticated
  using (public.ras_aal_ok()) with check (public.ras_aal_ok());

drop policy if exists ras_mfa on public.ras_admins;
create policy ras_mfa on public.ras_admins as restrictive for all to authenticated
  using (public.ras_aal_ok()) with check (public.ras_aal_ok());

drop policy if exists ras_mfa on public.ras_aprovacoes;
create policy ras_mfa on public.ras_aprovacoes as restrictive for all to authenticated
  using (public.ras_aal_ok()) with check (public.ras_aal_ok());

-- Para desativar a verificação de alguém que perdeu o celular (rode como dono):
-- delete from auth.mfa_factors where user_id = (select id from auth.users where email = 'email@da.pessoa');
