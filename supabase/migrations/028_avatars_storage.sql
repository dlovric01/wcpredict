-- ============================================================
-- WC2026 Prediction App — Avatars storage bucket
-- Migration 028
--
-- Adds the `avatars` storage bucket used by the profile screen to
-- let signed-in users upload a profile photo. Bucket is public so
-- avatars can be fetched anonymously via the public URL stored in
-- `profiles.avatar_url`; writes are restricted to the owning user.
--
-- Path convention: `<user_id>/avatar.<ext>` (one file per user; we
-- upsert to overwrite). The first folder segment matching auth.uid()
-- is what RLS enforces.
-- ============================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  true,
  5 * 1024 * 1024,                                    -- 5 MiB cap
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
on conflict (id) do update set
  public              = excluded.public,
  file_size_limit     = excluded.file_size_limit,
  allowed_mime_types  = excluded.allowed_mime_types;

-- Drop any prior versions so this migration is idempotent.
drop policy if exists "avatars_public_read"    on storage.objects;
drop policy if exists "avatars_owner_insert"   on storage.objects;
drop policy if exists "avatars_owner_update"   on storage.objects;
drop policy if exists "avatars_owner_delete"   on storage.objects;

-- Anyone (including unauthenticated) can read avatar files.
create policy "avatars_public_read"
  on storage.objects for select
  using (bucket_id = 'avatars');

-- Authenticated users can upload only into their own `<uid>/...` folder.
create policy "avatars_owner_insert"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "avatars_owner_update"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "avatars_owner_delete"
  on storage.objects for delete
  using (
    bucket_id = 'avatars'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );
