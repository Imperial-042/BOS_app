begin;

-- Leave and employee pay data do not carry a branch_id. Their employee
-- assignment is the branch scope, so use the same visibility helper as the
-- employee roster.
do $$
declare
  table_name text;
begin
  foreach table_name in array array['leave_requests', 'payroll_profiles'] loop
    execute format(
      'alter table public.%I enable row level security',
      table_name
    );
    execute format(
      'drop policy if exists branch_scoped_%I on public.%I',
      table_name,
      table_name
    );
    execute format(
      'create policy branch_scoped_%I on public.%I as restrictive for all '
      'to authenticated using (public.bos_can_view_employee('
      'business_id, user_id)) with check (public.bos_can_view_employee('
      'business_id, user_id))',
      table_name,
      table_name
    );
  end loop;
end $$;

alter table public.payroll_items enable row level security;
drop policy if exists branch_scoped_payroll_items on public.payroll_items;
create policy branch_scoped_payroll_items on public.payroll_items
  as restrictive for all to authenticated
  using (
    public.bos_can_view_employee(
      (select run.business_id
       from public.payroll_runs run
       where run.id = payroll_items.run_id),
      user_id
    )
  )
  with check (
    public.bos_can_view_employee(
      (select run.business_id
       from public.payroll_runs run
       where run.id = payroll_items.run_id),
      user_id
    )
  );

-- Payroll runs are business-wide containers, but a user must not even see a
-- run that contains no employee visible in their branch scope.
alter table public.payroll_runs enable row level security;
drop policy if exists branch_scoped_payroll_runs on public.payroll_runs;
create policy branch_scoped_payroll_runs on public.payroll_runs
  as restrictive for select to authenticated
  using (
    exists (
      select 1
      from public.payroll_items item
      where item.run_id = payroll_runs.id
        and public.bos_can_view_employee(payroll_runs.business_id, item.user_id)
    )
  );

commit;

notify pgrst, 'reload schema';
