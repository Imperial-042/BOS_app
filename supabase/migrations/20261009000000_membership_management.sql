create or replace function public.set_member_role(
  p_business_id uuid, p_user_id uuid, p_role text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if public.business_role(p_business_id) is distinct from 'owner' then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  if p_user_id = (select auth.uid()) then raise exception 'cannot change your own role'; end if;
  if p_role not in ('manager','accountant','cashier','inventory','employee') then
    raise exception 'invalid role';
  end if;
  update public.business_memberships set role = p_role, updated_at = now()
  where business_id = p_business_id and user_id = p_user_id
    and role <> 'owner' and status <> 'removed';
  if not found then raise exception 'member not found'; end if;
end $$;

create or replace function public.set_member_suspended(
  p_business_id uuid, p_user_id uuid, p_suspended boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if public.business_role(p_business_id) is distinct from 'owner' then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  update public.business_memberships
  set status = case when p_suspended then 'suspended' else 'active' end, updated_at = now()
  where business_id = p_business_id and user_id = p_user_id
    and role <> 'owner' and status in ('active','suspended');
  if not found then raise exception 'member not found'; end if;
end $$;

create or replace function public.remove_member(p_business_id uuid, p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.business_role(p_business_id) is distinct from 'owner' then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  update public.business_memberships set status = 'removed', updated_at = now()
  where business_id = p_business_id and user_id = p_user_id
    and role <> 'owner' and status <> 'removed';
  if not found then raise exception 'member not found'; end if;
end $$;

create or replace function public.transfer_ownership(p_business_id uuid, p_new_owner uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.business_role(p_business_id) is distinct from 'owner' then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  if not exists (select 1 from public.business_memberships
                 where business_id = p_business_id and user_id = p_new_owner
                   and status = 'active') then
    raise exception 'new owner must be an active member';
  end if;
  update public.business_memberships set role = 'manager', updated_at = now()
  where business_id = p_business_id and user_id = (select auth.uid());
  update public.business_memberships set role = 'owner', updated_at = now()
  where business_id = p_business_id and user_id = p_new_owner;
  update public.businesses set owner_user_id = p_new_owner where id = p_business_id;
end $$;

create or replace function public.revoke_invite_code(p_business_id uuid, p_code text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_business_manager(p_business_id) then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  update public.business_invites set status = 'revoked'
  where business_id = p_business_id and code = upper(btrim(p_code)) and status = 'pending';
end $$;

-- Heals legacy owners whose business exists in the cloud with no membership row.
create or replace function public.claim_owner_membership(p_business_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_current_device_session_active() then
    raise exception 'device authorization required' using errcode = '42501';
  end if;
  if not exists (select 1 from public.businesses
                 where id = p_business_id and owner_user_id = (select auth.uid())) then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  insert into public.business_memberships (business_id, user_id, role, status)
  values (p_business_id, (select auth.uid()), 'owner', 'active')
  on conflict (business_id, user_id) do nothing;
end $$;

revoke all on function public.set_member_role(uuid,uuid,text),
  public.set_member_suspended(uuid,uuid,boolean), public.remove_member(uuid,uuid),
  public.transfer_ownership(uuid,uuid), public.revoke_invite_code(uuid,text),
  public.claim_owner_membership(uuid) from public, anon;
grant execute on function public.set_member_role(uuid,uuid,text),
  public.set_member_suspended(uuid,uuid,boolean), public.remove_member(uuid,uuid),
  public.transfer_ownership(uuid,uuid), public.revoke_invite_code(uuid,text),
  public.claim_owner_membership(uuid) to authenticated;

-- Feed backfill for tables uploaded before their triggers existed.
do $$
declare t text;
begin
  foreach t in array array['accounts','categories','customers','suppliers',
    'journal_entries','income_transactions','expenses','receivable_payments',
    'payable_payments','supplier_purchases','account_transfers','supplies',
    'products','business_module_configs'] loop
    execute format(
      'insert into public.sync_changes (business_id, entity_type, entity_id, operation) '
      'select r.business_id, %L, r.id, ''create'' from public.%I r '
      'where not exists (select 1 from public.sync_changes c '
      'where c.entity_type = %L and c.entity_id = r.id)', t, t, t);
  end loop;
end $$;

notify pgrst, 'reload schema';