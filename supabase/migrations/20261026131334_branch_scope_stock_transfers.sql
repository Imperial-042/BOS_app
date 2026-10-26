-- Stock transfers are visible only to members assigned to either endpoint
-- branch (or to members who otherwise have access to every branch).
-- Apply after 002_branch_rls.sql.

begin;

drop policy if exists branch_scope_stock_transfers on public.stock_transfers;
create policy branch_scope_stock_transfers on public.stock_transfers
  as restrictive for all to authenticated
  using (
    public.has_branch_access(business_id, from_branch_id)
    or public.has_branch_access(business_id, to_branch_id)
  )
  with check (
    public.has_branch_access(business_id, from_branch_id)
    or public.has_branch_access(business_id, to_branch_id)
  );

drop policy if exists branch_scope_stock_transfer_items
  on public.stock_transfer_items;
create policy branch_scope_stock_transfer_items
  on public.stock_transfer_items
  as restrictive for all to authenticated
  using (
    exists (
      select 1
      from public.stock_transfers t
      where t.id = stock_transfer_items.transfer_id
        and t.business_id = stock_transfer_items.business_id
        and (
          public.has_branch_access(t.business_id, t.from_branch_id)
          or public.has_branch_access(t.business_id, t.to_branch_id)
        )
    )
  )
  with check (
    exists (
      select 1
      from public.stock_transfers t
      where t.id = stock_transfer_items.transfer_id
        and t.business_id = stock_transfer_items.business_id
        and (
          public.has_branch_access(t.business_id, t.from_branch_id)
          or public.has_branch_access(t.business_id, t.to_branch_id)
        )
    )
  );

commit;
