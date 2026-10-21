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

select 'ok' as projetos_dono;
