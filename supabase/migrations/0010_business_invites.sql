-- 0010_business_invites.sql
-- Cross-device invite codes: a code generated on the owner's device must be
-- redeemable by a new user registering on a different device. The Drift
-- business_invites table is local-only, so a clean-install device never sees
-- codes created elsewhere. This is the cloud source of truth.

create table public.business_invites (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete cascade,
  code text not null,
  role text not null check (role in (
    'manager', 'accountant', 'cashier', 'inventory', 'employee'
  )),
  status text not null default 'pending' check (status in ('pending', 'used', 'revoked')),
  created_by uuid not null references auth.users (id),
  used_by_user_id uuid references auth.users (id),
  used_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Codes are unique globally so a lookup by code is unambiguous.
create unique index business_invites_code_key on public.business_invites (code);
create index business_invites_business_id_idx on public.business_invites (business_id);

create trigger business_invites_set_updated_at
  before update on public.business_invites
  for each row execute function public.set_updated_at();

alter table public.business_invites enable row level security;

-- Owner/manager of the business can create and list its invite codes.
create policy business_invites_select_manager on public.business_invites
  for select to authenticated
  using (public.is_business_manager(business_id));

create policy business_invites_insert_manager on public.business_invites
  for insert to authenticated
  with check (public.is_business_manager(business_id));

create policy business_invites_update_manager on public.business_invites
  for update to authenticated
  using (public.is_business_manager(business_id))
  with check (public.is_business_manager(business_id));

-- A code must be *validated* and *redeemed* by someone who is NOT a member
-- yet. Doing that with plain RLS would expose every code to every user, so
-- redemption goes through a security-definer function that validates the
-- code server-side and stamps auth.uid() as the new member.
create or replace function public.redeem_invite_code(p_code text)
returns uuid  -- returns the membership id
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.business_invites%rowtype;
  v_membership_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select * into v_invite
  from public.business_invites
  where code = upper(btrim(p_code)) and status = 'pending'
  limit 1;

  if not found then
    raise exception 'invalid or used invite code';
  end if;

  -- Mark the code used exactly once (concurrent redeems lose the race).
  update public.business_invites
  set status = 'used', used_by_user_id = auth.uid(), used_at = now()
  where id = v_invite.id and status = 'pending';
  if not found then
    raise exception 'invalid or used invite code';
  end if;

  insert into public.business_memberships (business_id, user_id, role, status)
  values (v_invite.business_id, auth.uid(), v_invite.role, 'active')
  on conflict (business_id, user_id) do update
    set role = excluded.role, status = 'active', updated_at = now()
  returning id into v_membership_id;

  return v_membership_id;
end;
$$;

-- Validation-only read so the register screen can check a code before
-- creating the account without exposing the whole invites table.
create or replace function public.validate_invite_code(p_code text)
returns text  -- returns the role id, or null when invalid
language sql
security definer
stable
set search_path = public
as $$
  select role
  from public.business_invites
  where code = upper(btrim(p_code)) and status = 'pending'
  limit 1;
$$;
