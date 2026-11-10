begin;

drop policy if exists branch_members_read on public.branch_members;
create policy branch_members_read on public.branch_members
  for select to authenticated
  using (public.has_branch_access(business_id, branch_id));

create or replace function public.bos_can_view_employee(
  p_business uuid,
  p_employee uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select public.bos_is_member(p_business)
    and (
      p_employee = (select auth.uid())
      or public.bos_role_in(p_business, array['owner'])
      or not exists (
        select 1
        from public.branch_members target
        where target.business_id = p_business
          and target.user_id = p_employee
          and target.status = 'active'
      )
      or exists (
        select 1
        from public.branch_members target
        join public.branch_members viewer
          on viewer.business_id = target.business_id
         and viewer.branch_id = target.branch_id
         and viewer.user_id = (select auth.uid())
         and viewer.status = 'active'
        where target.business_id = p_business
          and target.user_id = p_employee
          and target.status = 'active'
      )
    );
$function$;

revoke all on function public.bos_can_view_employee(uuid, uuid)
  from public, anon;
grant execute on function public.bos_can_view_employee(uuid, uuid)
  to authenticated;

create or replace function public.bos_visible_employee_ids(p_business uuid)
returns table(user_id uuid)
language sql
stable
security definer
set search_path = ''
as $function$
  select m.user_id
  from public.business_memberships m
  where m.business_id = p_business
    and m.status = 'active'
    and public.bos_can_view_employee(p_business, m.user_id);
$function$;

revoke all on function public.bos_visible_employee_ids(uuid)
  from public, anon;
grant execute on function public.bos_visible_employee_ids(uuid)
  to authenticated;

alter table public.employee_profiles enable row level security;
drop policy if exists employee_profiles_branch_scope on public.employee_profiles;
create policy employee_profiles_branch_scope on public.employee_profiles
  as restrictive for select to authenticated
  using (public.bos_can_view_employee(business_id, user_id));

commit;

notify pgrst, 'reload schema';
