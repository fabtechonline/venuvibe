-- ============================================================================
-- 0010 · Storage bucket for resource images (Phase 3)
-- ----------------------------------------------------------------------------
-- Public-read bucket. A tenant may only write objects under a folder named
-- after one of THEIR tenant ids, i.e. paths look like:
--   <tenant_id>/<resource_id>/<file>
-- SAFE TO RE-RUN.
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('resource-images', 'resource-images', true)
on conflict (id) do nothing;

-- Public read of images in this bucket.
drop policy if exists resource_images_read on storage.objects;
create policy resource_images_read on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'resource-images');

-- Tenants write only under their own tenant-id folder.
drop policy if exists resource_images_write on storage.objects;
create policy resource_images_write on storage.objects
  for all to authenticated
  using (
    bucket_id = 'resource-images'
    and (storage.foldername(name))[1] in (
      select id::text from public.tenants where owner_id = auth.uid()
    )
  )
  with check (
    bucket_id = 'resource-images'
    and (storage.foldername(name))[1] in (
      select id::text from public.tenants where owner_id = auth.uid()
    )
  );
