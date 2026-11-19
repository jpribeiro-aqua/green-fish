-- Green Fish · v307: arquivos dos projetos (gravações do TeleFish, atas, figuras e documentos) no Supabase Storage.
-- Rode UMA vez no Supabase › SQL Editor. Cada usuário guarda na própria pasta <id do usuário>/<projeto>/;
-- o dono do app (public.ras_is_dono) lê, envia e apaga nas pastas de todos os clientes.
-- Limite por arquivo: 50 MB (o máximo do plano gratuito; no plano pago pode aumentar aqui e em Storage › Settings).

insert into storage.buckets (id, name, public, file_size_limit)
values ('greenfish-arquivos', 'greenfish-arquivos', false, 52428800)
on conflict (id) do update set public = false;

drop policy if exists "gf_arquivos_ler" on storage.objects;
drop policy if exists "gf_arquivos_enviar" on storage.objects;
drop policy if exists "gf_arquivos_trocar" on storage.objects;
drop policy if exists "gf_arquivos_apagar" on storage.objects;

create policy "gf_arquivos_ler" on storage.objects for select to authenticated
  using (bucket_id = 'greenfish-arquivos' and ((storage.foldername(name))[1] = auth.uid()::text or public.ras_is_dono()));

create policy "gf_arquivos_enviar" on storage.objects for insert to authenticated
  with check (bucket_id = 'greenfish-arquivos' and ((storage.foldername(name))[1] = auth.uid()::text or public.ras_is_dono()));

create policy "gf_arquivos_trocar" on storage.objects for update to authenticated
  using (bucket_id = 'greenfish-arquivos' and ((storage.foldername(name))[1] = auth.uid()::text or public.ras_is_dono()))
  with check (bucket_id = 'greenfish-arquivos' and ((storage.foldername(name))[1] = auth.uid()::text or public.ras_is_dono()));

create policy "gf_arquivos_apagar" on storage.objects for delete to authenticated
  using (bucket_id = 'greenfish-arquivos' and ((storage.foldername(name))[1] = auth.uid()::text or public.ras_is_dono()));
