create or replace function public.cleanup_orphan_catalog_items(
  p_business_id uuid
)
returns void
language sql
set search_path = public
as $$
  delete from public.customer_catalog_items as catalog
  where catalog.business_id = p_business_id
    and not exists (
      select 1
      from public.customer_branch_catalog_items as branch_catalog
      where branch_catalog.business_id = p_business_id
        and branch_catalog.catalog_item_id = catalog.id
    );
$$;

revoke all on function public.cleanup_orphan_catalog_items(uuid)
  from public, anon;
grant execute on function public.cleanup_orphan_catalog_items(uuid)
  to authenticated;

notify pgrst, 'reload schema';
