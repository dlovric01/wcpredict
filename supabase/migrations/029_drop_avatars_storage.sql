-- ============================================================
-- WC2026 Prediction App — Drop avatars storage bucket
-- Migration 029
--
-- Reverts migration 028. The profile-image upload feature was
-- removed from the client; drop the bucket + policies so the
-- attack surface and storage cost go with it.
--
-- The `profiles.avatar_url` column is preserved — it pre-dates
-- 028 (initial schema, migration 001) and may still hold URLs
-- from OAuth provider metadata in the future.
--
-- Note: Supabase installs `protect_delete()` triggers on
-- `storage.buckets` and `storage.objects` that raise unless
-- `storage.allow_delete_query = 'true'` is set on the local
-- transaction. We opt-in deliberately for this one statement.
-- The bucket has never been written to (the upload feature
-- shipped briefly and never succeeded against this project), so
-- no objects need to be cleaned up first.
-- ============================================================

drop policy if exists "avatars_public_read"  on storage.objects;
drop policy if exists "avatars_owner_insert" on storage.objects;
drop policy if exists "avatars_owner_update" on storage.objects;
drop policy if exists "avatars_owner_delete" on storage.objects;

do $$
begin
  set local storage.allow_delete_query = 'true';
  delete from storage.objects where bucket_id = 'avatars';
  delete from storage.buckets where id = 'avatars';
end$$;
