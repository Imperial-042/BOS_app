-- ============================================================================
-- BOS multi-branch: BRANCH ISOLATION at the database level.
-- Run AFTER 001_multi_branch.sql, and only once every device runs the branch
-- build (an old build writes rows under the Main Branch, which a user assigned
-- only to another branch would then be refused).
--
-- Uses RESTRICTIVE policies: they are AND-ed with your existing per-command
-- policies (is_business_member / is_business_manager ...), so none of your
-- existing policies are touched. Child tables (pos_sale_items, tenders,
-- payments) already check their parent pos_sales, so they inherit the rule.
--
-- Rule (same as the app):
--   * row without a branch                      -> allowed (company-wide)
--   * owner                                     -> every branch
--   * member with NO active branch assignment   -> every branch
--   * member with assignments                   -> only the assigned branches
-- ============================================================================
begin;

create or replace function public.has_branch_access(p_business uuid, p_branch uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_branch is null
      or public.bos_role_in(p_business, array['owner'])
      or not exists (
           select 1 from public.branch_members bm
           where bm.business_id = p_business
             and bm.user_id = (select auth.uid())
             and bm.status = 'active')
      or exists (
           select 1 from public.branch_members bm
           where bm.branch_id = p_branch
             and bm.user_id = (select auth.uid())
             and bm.status = 'active');
$$;

revoke all on function public.has_branch_access(uuid, uuid) from public, anon;
grant execute on function public.has_branch_access(uuid, uuid) to authenticated;

do $$
declare t text;
begin
  foreach t in array array['pos_sessions','pos_sales','pos_tables','inventory_movements',
                           'product_stock_movements','shopping_carts'] loop
    execute format('drop policy if exists %I on public.%I', 'branch_scope_' || t, t);
    execute format(
      'create policy %I on public.%I as restrictive for all to authenticated '
      'using (public.has_branch_access(business_id, branch_id)) '
      'with check (public.has_branch_access(business_id, branch_id))',
      'branch_scope_' || t, t);
  end loop;

  -- people records: a person can always see their own
  foreach t in array array['attendance_records','schedule_shifts'] loop
    execute format('drop policy if exists %I on public.%I', 'branch_scope_' || t, t);
    execute format(
      'create policy %I on public.%I as restrictive for all to authenticated '
      'using (user_id = (select auth.uid()) or public.has_branch_access(business_id, branch_id)) '
      'with check (user_id = (select auth.uid()) or public.has_branch_access(business_id, branch_id))',
      'branch_scope_' || t, t);
  end loop;
end $$;

commit;

-- ROLLBACK (if anyone gets locked out):
-- do $$ declare t text; begin
--   foreach t in array array['pos_sessions','pos_sales','pos_tables','inventory_movements',
--     'product_stock_movements','shopping_carts','attendance_records','schedule_shifts'] loop
--     execute format('drop policy if exists %I on public.%I', 'branch_scope_' || t, t);
--   end loop; end $$;