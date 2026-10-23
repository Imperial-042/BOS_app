-- 0006_storage.sql
-- Supabase Storage buckets + RLS. Buckets are PRIVATE by default; access is
-- authorized by business membership, resolved from the path's first segment:
--   businesses/{business_id}/{...}
-- The path is never the security boundary by itself — the RLS policy checks
-- the extracted business_id against actual membership.

insert into storage.buckets (id, name, public)
values
  ('business-assets', 'business-assets', false),
  ('receipts', 'receipts', false)
on conflict (id) do nothing;

-- Helper: extract the business_id from an object path's first segment
-- ("businesses/<uuid>/..."). Returns null for any other shape.
create or replace function public.storage_business_id(p_object_name text)
returns uuid
language sql
immutable
set search_path = public
as $$
  select case
    when p_object_name like 'businesses/%'
      and split_part(p_object_name, '/', 2) ~ '^[0-9a-fA-F-]{36}$'
    then split_part(p_object_name, '/', 2)::uuid
    else null
  end;
$$;

-- Read: only members of the path's business can read the object.
create policy storage_objects_read_member on storage.objects
  for select to authenticated
  using (
    bucket_id in ('business-assets', 'receipts')
    and public.is_business_member(public.storage_business_id(name))
  );

-- Write: only members can place objects into the business namespace.
create policy storage_objects_write_member on storage.objects
  for insert to authenticated
  with check (
    bucket_id in ('business-assets', 'receipts')
    and public.is_business_member(public.storage_business_id(name))
  );

create policy storage_objects_update_member on storage.objects
  for update to authenticated
  using (
    bucket_id in ('business-assets', 'receipts')
    and public.is_business_member(public.storage_business_id(name))
  )
  with check (
    bucket_id in ('business-assets', 'receipts')
    and public.is_business_member(public.storage_business_id(name))
  );

-- Delete: managers/owners only (files are business history).
create policy storage_objects_delete_manager on storage.objects
  for delete to authenticated
  using (
    bucket_id in ('business-assets', 'receipts')
    and public.is_business_manager(public.storage_business_id(name))
  );
