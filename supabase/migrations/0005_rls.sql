-- 0005_rls.sql
-- Row Level Security: every business-owned table is locked to members of that
-- business. Membership is resolved through a security-definer helper to avoid
-- recursive RLS on business_memberships itself.

-- ---------------------------------------------------------------------------
-- Membership helpers (security definer, run as the function owner, so they
-- bypass RLS on business_memberships when resolving membership — this is the
-- standard, safe way to avoid infinite recursion. They read only rows keyed
-- by the explicit auth.uid() / business id, never arbitrary input).
-- ---------------------------------------------------------------------------

-- Is the current user an active member of this business (any role)?
create or replace function public.is_business_member(p_business_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.business_memberships m
    where m.business_id = p_business_id
      and m.user_id = auth.uid()
      and m.status = 'active'
  );
$$;

-- Current user's role in this business, or null.
create or replace function public.business_role(p_business_id uuid)
returns text
language sql
security definer
stable
set search_path = public
as $$
  select m.role
  from public.business_memberships m
  where m.business_id = p_business_id
    and m.user_id = auth.uid()
    and m.status = 'active'
  limit 1;
$$;

-- Owner or manager?
create or replace function public.is_business_manager(p_business_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.business_role(p_business_id) in ('owner', 'manager');
$$;

-- ---------------------------------------------------------------------------
-- Enable RLS + the standard 4-operation policy set.
-- SELECT/INSERT/UPDATE/DELETE are separate so roles can diverge later without
-- a rewrite: read is open to all members, writes are open to active members,
-- and delete is restricted to managers/owners on financial history tables.
-- ---------------------------------------------------------------------------

-- profiles: you read your own; any member sees co-members' names later.
alter table public.profiles enable row level security;
create policy profiles_select_self on public.profiles
  for select using (id = auth.uid());
create policy profiles_update_self on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());
-- inserts happen only through the handle_new_user trigger (security definer).

-- businesses: visible to members; created by authenticated users; only owners
-- update/delete (deleting a business is owner-only and usually archived
-- instead — financial history is preserved).
alter table public.businesses enable row level security;
create policy businesses_select_member on public.businesses
  for select using (public.is_business_member(id));
create policy businesses_insert_authenticated on public.businesses
  for insert with check (auth.uid() = owner_user_id);
create policy businesses_update_owner on public.businesses
  for update using (public.business_role(id) = 'owner')
  with check (public.business_role(id) = 'owner');
create policy businesses_delete_owner on public.businesses
  for delete using (public.business_role(id) = 'owner');

-- business_memberships: members can read their business's roster; only
-- owner/manager manage it; joining yourself (active owner creation) is allowed.
alter table public.business_memberships enable row level security;
create policy memberships_select_member on public.business_memberships
  for select using (
    public.is_business_member(business_id) or user_id = auth.uid()
  );
create policy memberships_insert_manage on public.business_memberships
  for insert with check (
    public.is_business_manager(business_id) or user_id = auth.uid()
  );
create policy memberships_update_manage on public.business_memberships
  for update using (public.is_business_manager(business_id))
  with check (public.is_business_manager(business_id));
create policy memberships_delete_manage on public.business_memberships
  for delete using (public.is_business_manager(business_id));

-- ---------------------------------------------------------------------------
-- Generic member-readable, member-writable business-owned tables.
-- Delete on financial/ledger tables is manager+ (history preservation);
-- master data deletes stay member-allowed for cleanup of unused records.
-- ---------------------------------------------------------------------------

-- Macro-like application of the standard policy set per table.
-- member read/write; manager+ delete for the financial-history tables.
do $$
declare
  t text;
  financial_tables text[] := array[
    'journal_entries', 'ledger_lines', 'income_transactions', 'expenses',
    'receivable_payments', 'payable_payments', 'supplier_purchases',
    'account_transfers'
  ];
  master_tables text[] := array[
    'accounts', 'categories', 'customers', 'suppliers', 'supplies',
    'inventory_movements', 'products', 'business_module_configs'
  ];
begin
  foreach t in array financial_tables || master_tables loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy %I on public.%I for select using (public.is_business_member(business_id))',
      t || '_select_member', t);
    execute format(
      'create policy %I on public.%I for insert with check (public.is_business_member(business_id))',
      t || '_insert_member', t);
    execute format(
      'create policy %I on public.%I for update using (public.is_business_member(business_id)) with check (public.is_business_member(business_id))',
      t || '_update_member', t);
  end loop;

  -- Financial history: delete is manager+ only.
  foreach t in array financial_tables loop
    execute format(
      'create policy %I on public.%I for delete using (public.is_business_manager(business_id))',
      t || '_delete_manager', t);
  end loop;

  -- Master data: members may delete (e.g. unused accounts/categories).
  foreach t in array master_tables loop
    execute format(
      'create policy %I on public.%I for delete using (public.is_business_member(business_id))',
      t || '_delete_member', t);
  end loop;
end;
$$;
