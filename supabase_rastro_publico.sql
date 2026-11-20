-- Green Fish v323 · página pública do consumidor (QR code da etiqueta)
-- Cada lote publicado fica em ras_docs, caminho publico/rastro/<código>, só com dados sem identificação pessoal
-- (espécie, região, datas, sanidade, qualidade e produto — sem nome, CPF/CNPJ nem coordenadas).
--   * qualquer pessoa (mesmo sem login) LÊ apenas os documentos publico/rastro/...
--   * quem tem conta publica, atualiza e apaga só os que ela mesma publicou (data.por = o próprio usuário); o dono pode apagar qualquer um
-- Não altera nenhuma outra regra. Rode no Supabase > SQL Editor (pode rodar de novo).

grant select on public.ras_docs to anon;

drop policy if exists ras_pub_rastro_sel on public.ras_docs;
drop policy if exists ras_pub_rastro_ins on public.ras_docs;
drop policy if exists ras_pub_rastro_upd on public.ras_docs;
drop policy if exists ras_pub_rastro_del on public.ras_docs;

create policy ras_pub_rastro_sel on public.ras_docs for select to anon, authenticated
  using (path like 'publico/rastro/%');
create policy ras_pub_rastro_ins on public.ras_docs for insert to authenticated
  with check (path like 'publico/rastro/%' and col = 'publico/rastro' and data->>'por' = auth.uid()::text);
create policy ras_pub_rastro_upd on public.ras_docs for update to authenticated
  using (path like 'publico/rastro/%' and (data->>'por' = auth.uid()::text or public.ras_is_dono()))
  with check (path like 'publico/rastro/%' and col = 'publico/rastro' and data->>'por' = auth.uid()::text);
create policy ras_pub_rastro_del on public.ras_docs for delete to authenticated
  using (path like 'publico/rastro/%' and (data->>'por' = auth.uid()::text or public.ras_is_dono()));
