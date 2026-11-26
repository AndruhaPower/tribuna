-- Фото профиля (D43): приватное хранилище avatars, файл <user id>.jpg, каждый видит и меняет только своё.
-- Удаление аккаунта стирает фото в Edge Function delete-account (до удаления пользователя).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 1048576, array['image/jpeg'])
on conflict (id) do nothing;

create policy avatars_select_own on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and name = auth.uid()::text || '.jpg');
create policy avatars_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and name = auth.uid()::text || '.jpg');
create policy avatars_update_own on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and name = auth.uid()::text || '.jpg')
  with check (bucket_id = 'avatars' and name = auth.uid()::text || '.jpg');
create policy avatars_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and name = auth.uid()::text || '.jpg');
