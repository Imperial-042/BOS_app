begin;

-- 1. Helper functions (run as owner, so they don't trigger RLS recursion)

-- Does any branch sell this item? (used by the catalog_items read policy)
create or replace function public.customer_item_is_sold(p_item uuid)
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.customer_branch_catalog_items bc
    where bc.catalog_item_id = p_item
  );
$$;

-- Can the signed-in customer see this branch? (published + same city)
create or replace function public.customer_can_see_branch(p_branch uuid)
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.customer_store_branches b
    join public.customer_storefronts s
      on s.business_id = b.business_id and s.is_published
    join public.customer_profiles p
      on p.id = (select auth.uid())
    where b.id = p_branch
      and b.is_active
      and b.storefront_published
      and nullif(btrim(p.city), '') is not null
      and nullif(btrim(b.city), '') is not null
      and regexp_replace(lower(btrim(p.city)), '[[:space:]]+', ' ', 'g')
        = regexp_replace(lower(btrim(b.city)), '[[:space:]]+', ' ', 'g')
  );
$$;

-- Do the branch and the item both belong to this business? (write check)
create or replace function public.customer_branch_item_matches(
  p_branch uuid, p_item uuid, p_business uuid)
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.customer_store_branches b
                 where b.id = p_branch and b.business_id = p_business)
     and exists (select 1 from public.customer_catalog_items c
                 where c.id = p_item and c.business_id = p_business);
$$;

revoke all on function
  public.customer_item_is_sold(uuid),
  public.customer_can_see_branch(uuid),
  public.customer_branch_item_matches(uuid, uuid, uuid)
  from public, anon;
grant execute on function
  public.customer_item_is_sold(uuid),
  public.customer_can_see_branch(uuid),
  public.customer_branch_item_matches(uuid, uuid, uuid)
  to authenticated;

-- 2. Recreate the policies without cross-table subqueries

drop policy if exists customer_branch_catalog_items_manage
  on public.customer_branch_catalog_items;
drop policy if exists customer_branch_catalog_items_read
  on public.customer_branch_catalog_items;
drop policy if exists customer_catalog_items_read_published
  on public.customer_catalog_items;

create policy customer_branch_catalog_items_manage
  on public.customer_branch_catalog_items for all to authenticated
  using (public.is_business_manager(business_id))
  with check (
    public.is_business_manager(business_id)
    and public.customer_branch_item_matches(branch_id, catalog_item_id, business_id)
  );

create policy customer_branch_catalog_items_read
  on public.customer_branch_catalog_items for select to authenticated
  using (public.customer_can_see_branch(branch_id));

create policy customer_catalog_items_read_published
  on public.customer_catalog_items for select to authenticated
  using (is_available and public.customer_item_is_sold(id));

notify pgrst, 'reload schema';
commit;