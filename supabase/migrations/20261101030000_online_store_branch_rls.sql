-- Limit online-store management and order visibility to assigned branches.

create or replace function public.online_store_can_manage_branch(
  p_business_id uuid,
  p_branch_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_business_manager(p_business_id)
    or exists (
      select 1
      from public.branch_members bm
      where bm.business_id = p_business_id
        and bm.branch_id = p_branch_id
        and bm.user_id = auth.uid()
        and bm.status = 'active'
    );
$$;

revoke all on function public.online_store_can_manage_branch(uuid, uuid)
  from public, anon;
grant execute on function public.online_store_can_manage_branch(uuid, uuid)
  to authenticated;

drop policy if exists customer_store_branches_manage
  on public.customer_store_branches;
create policy customer_store_branches_manage
  on public.customer_store_branches for all to authenticated
  using (
    public.online_store_can_manage_branch(business_id, id)
  )
  with check (
    public.online_store_can_manage_branch(business_id, id)
  );

drop policy if exists customer_storefronts_manage
  on public.customer_storefronts;
create policy customer_storefronts_manage
  on public.customer_storefronts for all to authenticated
  using (
    public.is_business_manager(business_id)
    or exists (
      select 1
      from public.branch_members bm
      where bm.business_id = customer_storefronts.business_id
        and bm.user_id = auth.uid()
        and bm.status = 'active'
    )
  )
  with check (
    public.is_business_manager(business_id)
    or exists (
      select 1
      from public.branch_members bm
      where bm.business_id = customer_storefronts.business_id
        and bm.user_id = auth.uid()
        and bm.status = 'active'
    )
  );

drop policy if exists customer_catalog_items_manage
  on public.customer_catalog_items;
create policy customer_catalog_items_manage
  on public.customer_catalog_items for all to authenticated
  using (
    public.is_business_manager(business_id)
    or exists (
      select 1
      from public.branch_members bm
      where bm.business_id = customer_catalog_items.business_id
        and bm.user_id = auth.uid()
        and bm.status = 'active'
    )
  )
  with check (
    public.is_business_manager(business_id)
    or exists (
      select 1
      from public.branch_members bm
      where bm.business_id = customer_catalog_items.business_id
        and bm.user_id = auth.uid()
        and bm.status = 'active'
    )
  );

drop policy if exists customer_branch_catalog_items_manage
  on public.customer_branch_catalog_items;
create policy customer_branch_catalog_items_manage
  on public.customer_branch_catalog_items for all to authenticated
  using (
    public.online_store_can_manage_branch(business_id, branch_id)
  )
  with check (
    public.online_store_can_manage_branch(business_id, branch_id)
    and public.customer_branch_item_matches(
      branch_id,
      catalog_item_id,
      business_id
    )
  );

drop policy if exists customer_orders_read_business
  on public.customer_orders;
create policy customer_orders_read_business
  on public.customer_orders for select to authenticated
  using (
    public.online_store_can_manage_branch(business_id, branch_id)
  );

drop policy if exists customer_orders_update_business
  on public.customer_orders;
create policy customer_orders_update_business
  on public.customer_orders for update to authenticated
  using (
    public.online_store_can_manage_branch(business_id, branch_id)
  )
  with check (
    public.online_store_can_manage_branch(business_id, branch_id)
  );
