-- =====================================================================
-- U-BIKE — Supabase Storage: rider verification documents
-- Run this in the Supabase SQL Editor (after schema.sql).
-- Creates a PRIVATE bucket and RLS so:
--   • a rider can upload/read files only inside their own folder (uid/...)
--   • admins (profiles.role = 'admin') can read every document
--   • the backend service-role key bypasses RLS automatically
-- Files are stored as:  rider-documents/<auth_uid>/<doc_key>.jpg
-- =====================================================================

-- 1) Create the bucket (private, 10 MB limit, images + pdf only).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'rider-documents',
  'rider-documents',
  false,
  10485760,
  array['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- storage.objects already has RLS enabled by Supabase. Define our policies.
drop policy if exists "rider docs - insert own" on storage.objects;
drop policy if exists "rider docs - update own" on storage.objects;
drop policy if exists "rider docs - read own or admin" on storage.objects;
drop policy if exists "rider docs - delete own or admin" on storage.objects;

-- 2) Rider can UPLOAD into their own folder (first path segment = their uid).
create policy "rider docs - insert own"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'rider-documents'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- 3) Rider can OVERWRITE/replace files in their own folder.
create policy "rider docs - update own"
on storage.objects for update to authenticated
using (
  bucket_id = 'rider-documents'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- 4) Rider can READ their own docs; admins can READ everyone's.
create policy "rider docs - read own or admin"
on storage.objects for select to authenticated
using (
  bucket_id = 'rider-documents'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  )
);

-- 5) Rider or admin can DELETE (e.g. re-capturing a document).
create policy "rider docs - delete own or admin"
on storage.objects for delete to authenticated
using (
  bucket_id = 'rider-documents'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  )
);
