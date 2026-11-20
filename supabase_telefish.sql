-- Green Fish v317 · TeleFish: servidor TURN da equipe
-- O dono do app configura o TURN uma vez no app (TeleFish › 🛰 Rede) e ele fica em ras_docs, caminho config/telefish.
-- Todos com conta já leem config/... pelas regras existentes. Este arquivo só garante que
-- SOMENTE O DONO grava ou apaga config/telefish (administradores de equipe não podem mudar).
-- Rode no Supabase > SQL Editor (pode rodar de novo). Não altera nenhuma outra regra.

drop policy if exists ras_telefish_dono_ins on public.ras_docs;
drop policy if exists ras_telefish_dono_upd on public.ras_docs;
drop policy if exists ras_telefish_dono_del on public.ras_docs;

create policy ras_telefish_dono_ins on public.ras_docs as restrictive for insert to authenticated
  with check (path <> 'config/telefish' or public.ras_is_dono());
create policy ras_telefish_dono_upd on public.ras_docs as restrictive for update to authenticated
  using (path <> 'config/telefish' or public.ras_is_dono())
  with check (path <> 'config/telefish' or public.ras_is_dono());
create policy ras_telefish_dono_del on public.ras_docs as restrictive for delete to authenticated
  using (path <> 'config/telefish' or public.ras_is_dono());
