-- Keep cloud role assignment and row access aligned with the app permission
-- model. Role checks and permission overrides are evaluated at the database
-- boundary so direct Data API writes cannot bypass the app.

-- Custom roles are synced directly by the app's existing change-feed worker.
create table if not exists public.custom_roles (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete cascade,
  name text not null,
  base_role text not null check (base_role in (
    'manager', 'accountant', 'cashier', 'inventory', 'employee', 'hr', 'staff'
  )),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists custom_roles_business_id_id_key
  on public.custom_roles (business_id, id);
create unique index if not exists custom_roles_business_name_key
  on public.custom_roles (business_id, lower(name));

drop trigger if exists custom_roles_set_updated_at on public.custom_roles;
create trigger custom_roles_set_updated_at
  before update on public.custom_roles
  for each row execute function public.set_updated_at();

alter table public.custom_roles enable row level security;
drop policy if exists custom_roles_select_member on public.custom_roles;
create policy custom_roles_select_member on public.custom_roles
  for select to authenticated
  using (public.is_business_member(business_id));
drop policy if exists custom_roles_insert_owner on public.custom_roles;
create policy custom_roles_insert_owner on public.custom_roles
  for insert to authenticated
  with check (public.is_business_manager(business_id)
    and public.business_role(business_id) = 'owner');
drop policy if exists custom_roles_update_owner on public.custom_roles;
create policy custom_roles_update_owner on public.custom_roles
  for update to authenticated
  using (public.is_business_manager(business_id)
    and public.business_role(business_id) = 'owner')
  with check (public.is_business_manager(business_id)
    and public.business_role(business_id) = 'owner');
drop policy if exists custom_roles_delete_owner on public.custom_roles;
create policy custom_roles_delete_owner on public.custom_roles
  for delete to authenticated
  using (public.is_business_manager(business_id)
    and public.business_role(business_id) = 'owner'
    and not exists (
      select 1
      from public.business_memberships m
      where m.business_id = custom_roles.business_id
        and m.role = 'c_' || custom_roles.id::text
        and m.status <> 'removed'
    )
    and not exists (
      select 1
      from public.business_invites i
      where i.business_id = custom_roles.business_id
        and i.role = 'c_' || custom_roles.id::text
        and i.status = 'pending'
    ));

drop trigger if exists custom_roles_sync_change on public.custom_roles;
create trigger custom_roles_sync_change
  after insert or update or delete on public.custom_roles
  for each row execute function public.log_sync_change();

insert into public.sync_changes (business_id, entity_type, entity_id, operation)
select r.business_id, 'custom_roles', r.id, 'create'
from public.custom_roles r
where not exists (
  select 1 from public.sync_changes c
  where c.entity_type = 'custom_roles' and c.entity_id = r.id
);

-- The id format is stable and matches c_<uuid>, the app's custom-role ID.
alter table public.business_memberships
  drop constraint if exists business_memberships_role_check,
  add constraint business_memberships_role_check check (
    role in (
      'owner', 'manager', 'accountant', 'cashier', 'inventory',
      'employee', 'hr', 'staff'
    )
    or role ~* '^c_[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  );

alter table public.business_invites
  drop constraint if exists business_invites_role_check,
  add constraint business_invites_role_check check (
    role in (
      'manager', 'accountant', 'cashier', 'inventory',
      'employee', 'hr', 'staff'
    )
    or role ~* '^c_[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  );

create or replace function public.is_assignable_business_role(
  p_business_id uuid,
  p_role text
)
returns boolean
language plpgsql
security definer
stable
set search_path = ''
as $$
begin
  if p_business_id is null
     or p_role is null
     or (select auth.uid()) is null
     or not public.is_current_device_session_active() then
    return false;
  end if;
  if p_role in (
    'manager', 'accountant', 'cashier', 'inventory',
    'employee', 'hr', 'staff'
  ) then
    return true;
  end if;
  if p_role !~* '^c_[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return false;
  end if;
  return exists (
    select 1
    from public.custom_roles r
    where r.business_id = p_business_id
      and r.id::text = substr(p_role, 3)
  );
end;
$$;

-- Requires every listed permission. Unknown permissions always deny.
create or replace function public.has_business_permission(
  p_business_id uuid,
  p_permissions text[]
)
returns boolean
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_role text;
  v_base_role text;
  v_permission text;
  v_default boolean;
  v_override boolean;
  v_has_override boolean;
begin
  if p_business_id is null
     or coalesce(array_length(p_permissions, 1), 0) = 0
     or (select auth.uid()) is null
     or not public.is_current_device_session_active() then
    return false;
  end if;

  select m.role into v_role
  from public.business_memberships m
  where m.business_id = p_business_id
    and m.user_id = (select auth.uid())
    and m.status = 'active';
  if v_role is null then
    return false;
  end if;

  if left(v_role, 2) = 'c_' then
    select r.base_role into v_base_role
    from public.custom_roles r
    where r.business_id = p_business_id
      and r.id::text = substr(v_role, 3);
    if v_base_role is null then
      return false;
    end if;
  else
    v_base_role := v_role;
  end if;

  foreach v_permission in array p_permissions loop
    v_default := case v_permission
      when 'dashboard.view' then v_base_role in ('owner', 'manager', 'accountant', 'hr')
      when 'sales.view' then v_base_role in ('owner', 'manager', 'cashier', 'staff')
      when 'sales.create' then v_base_role in ('owner', 'manager', 'cashier', 'staff')
      when 'sales.edit' then v_base_role in ('owner', 'manager')
      when 'sales.void' then v_base_role in ('owner', 'manager')
      when 'sales.discount' then v_base_role in ('owner', 'manager')
      when 'sales.stock_only' then v_base_role in ('owner', 'manager')
      when 'sales.on_credit' then v_base_role in ('owner', 'manager')
      when 'customers.view' then v_base_role in ('owner', 'manager', 'accountant', 'cashier', 'inventory', 'employee', 'hr', 'staff')
      when 'customers.create' then v_base_role in ('owner', 'manager', 'cashier', 'staff')
      when 'customers.edit' then v_base_role in ('owner', 'manager')
      when 'inventory.view' then v_base_role in ('owner', 'manager', 'inventory', 'employee', 'staff')
      when 'inventory.create' then v_base_role in ('owner', 'manager', 'inventory')
      when 'inventory.edit' then v_base_role in ('owner', 'manager', 'inventory')
      when 'inventory.adjust' then v_base_role in ('owner', 'manager', 'inventory')
      when 'purchasing.view' then v_base_role in ('owner', 'manager', 'inventory')
      when 'purchasing.create' then v_base_role in ('owner', 'manager', 'inventory')
      when 'purchasing.edit' then v_base_role in ('owner', 'manager', 'inventory')
      when 'purchasing.receive' then v_base_role in ('owner', 'manager', 'inventory')
      when 'suppliers.view' then v_base_role in ('owner', 'manager', 'accountant', 'inventory')
      when 'suppliers.create' then v_base_role in ('owner', 'manager', 'inventory')
      when 'suppliers.edit' then v_base_role in ('owner', 'manager', 'inventory')
      when 'finance.view' then v_base_role in ('owner', 'accountant')
      when 'finance.create' then v_base_role in ('owner', 'accountant')
      when 'finance.edit' then v_base_role in ('owner', 'accountant')
      when 'finance.post' then v_base_role in ('owner', 'accountant')
      when 'finance.void' then v_base_role in ('owner', 'accountant')
      when 'receivables.view' then v_base_role in ('owner', 'accountant')
      when 'receivables.create' then v_base_role in ('owner', 'accountant')
      when 'payables.view' then v_base_role in ('owner', 'accountant')
      when 'payables.create' then v_base_role in ('owner', 'accountant')
      when 'reports.view' then v_base_role in ('owner', 'manager', 'accountant', 'hr')
      when 'employees.view' then v_base_role in ('owner', 'manager', 'hr')
      when 'employees.manage' then v_base_role in ('owner', 'manager', 'hr')
      when 'hr.self' then v_base_role in ('owner', 'manager', 'accountant', 'cashier', 'inventory', 'employee', 'hr', 'staff')
      when 'hr.manage' then v_base_role in ('owner', 'manager', 'hr')
      when 'users.view' then v_base_role in ('owner', 'hr')
      when 'users.invite' then v_base_role = 'owner'
      when 'users.remove' then v_base_role = 'owner'
      when 'users.manage_roles' then v_base_role = 'owner'
      when 'business.settings' then v_base_role = 'owner'
      when 'business.manage' then v_base_role = 'owner'
      when 'business.delete' then v_base_role = 'owner'
      when 'security.manage' then v_base_role = 'owner'
      when 'branch.manage' then v_base_role = 'owner'
      when 'stock.transfer_create' then v_base_role in ('owner', 'manager', 'inventory')
      when 'stock.transfer_receive' then v_base_role in ('owner', 'manager', 'inventory')
      else null
    end;

    if v_default is null then
      return false;
    end if;
    if v_base_role = 'owner' then
      continue;
    end if;

    select o.granted into v_override
    from public.role_permission_overrides o
    where o.business_id = p_business_id
      and o.role = v_role
      and o.permission = v_permission;
    v_has_override := found;

    if v_has_override then
      v_default := v_override;
    end if;
    if not v_default then
      return false;
    end if;
  end loop;
  return true;
end;
$$;

create or replace function public.has_any_business_permission(
  p_business_id uuid,
  p_permissions text[]
)
returns boolean
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_permission text;
begin
  if p_permissions is null then
    return false;
  end if;
  foreach v_permission in array p_permissions loop
    if public.has_business_permission(p_business_id, array[v_permission]) then
      return true;
    end if;
  end loop;
  return false;
end;
$$;

revoke all on function public.is_assignable_business_role(uuid, text),
  public.has_business_permission(uuid, text[]),
  public.has_any_business_permission(uuid, text[])
  from public, anon;
grant execute on function public.is_assignable_business_role(uuid, text),
  public.has_business_permission(uuid, text[]),
  public.has_any_business_permission(uuid, text[])
  to authenticated;

-- Each permission is enforced in Postgres, including sync/Data API writes.
do $$
declare
  spec text[];
  specs text[][] := array[
    array['journal_entries', 'finance.view', 'finance.create|finance.post', 'finance.edit|finance.post', 'finance.void'],
    array['ledger_lines', 'finance.view', 'finance.post', 'finance.post', 'finance.post'],
    array['income_transactions', 'finance.view', 'finance.create', 'finance.edit', 'finance.void'],
    array['expenses', 'finance.view', 'finance.create', 'finance.edit', 'finance.void'],
    array['receivable_payments', 'receivables.view', 'receivables.create', 'receivables.create', 'receivables.create'],
    array['payable_payments', 'payables.view', 'payables.create', 'payables.create', 'payables.create'],
    array['supplier_purchases', 'purchasing.view', 'purchasing.create', 'purchasing.edit|purchasing.receive', 'purchasing.edit'],
    array['account_transfers', 'finance.view', 'finance.create', 'finance.edit', 'finance.void'],
    array['accounts', 'finance.view', 'finance.create', 'finance.edit', 'finance.edit'],
    array['categories', 'finance.view', 'finance.create', 'finance.edit', 'finance.edit'],
    array['customers', 'customers.view', 'customers.create', 'customers.edit', 'customers.edit'],
    array['suppliers', 'suppliers.view', 'suppliers.create', 'suppliers.edit', 'suppliers.edit'],
    array['supplies', 'inventory.view', 'inventory.create', 'inventory.edit', 'inventory.edit'],
    array['products', 'inventory.view', 'inventory.create', 'inventory.edit', 'inventory.edit'],
    array['inventory_movements', 'inventory.view', 'inventory.adjust|sales.create|purchasing.receive', 'inventory.adjust', 'inventory.adjust'],
    array['business_module_configs', '@member', 'business.settings', 'business.settings', 'business.settings'],
    array['payment_providers', 'finance.view', 'finance.create', 'finance.edit', 'finance.edit'],
    array['pos_sessions', 'sales.view', 'sales.create', 'sales.edit|sales.create', 'sales.void'],
    array['pos_sales', 'sales.view', 'sales.create', 'sales.edit|sales.void|sales.discount|sales.on_credit|sales.stock_only', 'sales.void'],
    array['shopping_carts', 'purchasing.view', 'purchasing.create', 'purchasing.edit', 'purchasing.edit'],
    array['product_categories', 'inventory.view', 'inventory.create', 'inventory.edit', 'inventory.edit']
  ];
  v_table text;
  v_old_suffix text;
  v_select text;
  v_insert text;
  v_update text;
  v_delete text;
begin
  foreach spec slice 1 in array specs loop
    v_table := spec[1];
    foreach v_old_suffix in array array[
      '_select_member', '_insert_member', '_update_member',
      '_delete_manager', '_delete_member',
      '_select', '_insert', '_update', '_delete'
    ] loop
      execute format(
        'drop policy if exists %I on public.%I',
        v_table || v_old_suffix,
        v_table
      );
    end loop;

    if spec[2] = '@member' then
      v_select := 'public.is_business_member(business_id)';
    else
      v_select := format(
        'public.has_business_permission(business_id, ARRAY[%L]::text[])',
        spec[2]
      );
    end if;
    execute format(
      'create policy %I on public.%I for select to authenticated using (%s)',
      'rbac_' || v_table || '_select', v_table, v_select
    );
    v_insert := format(
      'public.has_any_business_permission(business_id, string_to_array(%L, ''|''))',
      spec[3]
    );
    v_update := format(
      'public.has_any_business_permission(business_id, string_to_array(%L, ''|''))',
      spec[4]
    );
    v_delete := format(
      'public.has_any_business_permission(business_id, string_to_array(%L, ''|''))',
      spec[5]
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated with check (%s)',
      'rbac_' || v_table || '_insert', v_table, v_insert
    );
    execute format(
      'create policy %I on public.%I for update to authenticated using (%s) with check (%s)',
      'rbac_' || v_table || '_update', v_table, v_update, v_update
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated using (%s)',
      'rbac_' || v_table || '_delete', v_table, v_delete
    );
  end loop;
end;
$$;

-- Child-row permissions follow the owning sale/cart/product, not the fact
-- that a user can access some unrelated business row.
do $$
declare
  spec text[];
  specs text[][] := array[
    array['pos_sale_items', 'pos_sales', 'sale_id', 'sales.view', 'sales.create', 'sales.edit|sales.create', 'sales.void'],
    array['pos_sale_payments', 'pos_sales', 'sale_id', 'sales.view', 'sales.create', 'sales.edit|sales.create', 'sales.void'],
    array['pos_sale_tenders', 'pos_sales', 'sale_id', 'sales.view', 'sales.create', 'sales.edit|sales.create', 'sales.void'],
    array['shopping_cart_items', 'shopping_carts', 'cart_id', 'purchasing.view', 'purchasing.create', 'purchasing.edit|purchasing.create', 'purchasing.edit'],
    array['supply_price_history', 'supplies', 'supply_id', 'inventory.view', 'purchasing.create', 'purchasing.edit|purchasing.create', 'purchasing.edit'],
    array['recipes', 'products', 'product_id', 'inventory.view', 'inventory.create', 'inventory.edit|inventory.create', 'inventory.edit']
  ];
  v_cond text;
  v_table text;
  v_parent text;
  v_key text;
  v_old_suffix text;
begin
  foreach spec slice 1 in array specs loop
    v_table := spec[1];
    v_parent := spec[2];
    v_key := spec[3];
    v_cond := format(
      'exists (select 1 from public.%I p where p.id = %I.%I '
      'and public.has_business_permission(p.business_id, ARRAY[%L]::text[]))',
      v_parent, v_table, v_key, spec[4]
    );
    foreach v_old_suffix in array array[
      '_select', '_insert', '_update', '_delete'
    ] loop
      execute format(
        'drop policy if exists %I on public.%I',
        v_table || v_old_suffix,
        v_table
      );
    end loop;

    execute format(
      'create policy %I on public.%I for select to authenticated using (%s)',
      'rbac_' || v_table || '_select', v_table, v_cond
    );
    v_cond := format(
      'exists (select 1 from public.%I p where p.id = %I.%I '
      'and public.has_business_permission(p.business_id, ARRAY[%L]::text[]) '
      'and public.has_any_business_permission(p.business_id, string_to_array(%L, ''|'')))',
      v_parent, v_table, v_key, spec[4], spec[5]
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated with check (%s)',
      'rbac_' || v_table || '_insert', v_table, v_cond
    );
    v_cond := format(
      'exists (select 1 from public.%I p where p.id = %I.%I '
      'and public.has_business_permission(p.business_id, ARRAY[%L]::text[]) '
      'and public.has_any_business_permission(p.business_id, string_to_array(%L, ''|'')))',
      v_parent, v_table, v_key, spec[4], spec[6]
    );
    execute format(
      'create policy %I on public.%I for update to authenticated using (%s) with check (%s)',
      'rbac_' || v_table || '_update', v_table, v_cond, v_cond
    );
    v_cond := format(
      'exists (select 1 from public.%I p where p.id = %I.%I '
      'and public.has_business_permission(p.business_id, ARRAY[%L]::text[]) '
      'and public.has_any_business_permission(p.business_id, string_to_array(%L, ''|'')))',
      v_parent, v_table, v_key, spec[4], spec[7]
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated using (%s)',
      'rbac_' || v_table || '_delete', v_table, v_cond
    );
  end loop;
end;
$$;

-- recipe_components resolve through recipe -> product.
drop policy if exists recipe_components_select on public.recipe_components;
drop policy if exists recipe_components_insert on public.recipe_components;
drop policy if exists recipe_components_update on public.recipe_components;
drop policy if exists recipe_components_delete on public.recipe_components;
create policy rbac_recipe_components_select on public.recipe_components
  for select to authenticated using (
    exists (
      select 1 from public.recipes r
      join public.products p on p.id = r.product_id
      where r.id = recipe_components.recipe_id
        and public.has_business_permission(p.business_id, ARRAY['inventory.view']::text[])
    )
  );
create policy rbac_recipe_components_insert on public.recipe_components
  for insert to authenticated with check (
    exists (
      select 1 from public.recipes r
      join public.products p on p.id = r.product_id
      where r.id = recipe_components.recipe_id
        and public.has_business_permission(p.business_id, ARRAY['inventory.view']::text[])
        and public.has_any_business_permission(p.business_id, ARRAY['inventory.create']::text[])
    )
  );
create policy rbac_recipe_components_update on public.recipe_components
  for update to authenticated using (
    exists (
      select 1 from public.recipes r
      join public.products p on p.id = r.product_id
      where r.id = recipe_components.recipe_id
        and public.has_business_permission(p.business_id, ARRAY['inventory.view']::text[])
        and public.has_any_business_permission(p.business_id, ARRAY['inventory.edit', 'inventory.create']::text[])
    )
  ) with check (
    exists (
      select 1 from public.recipes r
      join public.products p on p.id = r.product_id
      where r.id = recipe_components.recipe_id
        and public.has_business_permission(p.business_id, ARRAY['inventory.view']::text[])
        and public.has_any_business_permission(p.business_id, ARRAY['inventory.edit', 'inventory.create']::text[])
    )
  );
create policy rbac_recipe_components_delete on public.recipe_components
  for delete to authenticated using (
    exists (
      select 1 from public.recipes r
      join public.products p on p.id = r.product_id
      where r.id = recipe_components.recipe_id
        and public.has_business_permission(p.business_id, ARRAY['inventory.view']::text[])
        and public.has_any_business_permission(p.business_id, ARRAY['inventory.edit']::text[])
    )
  );

-- Permission overrides are security settings; only users with security.manage
-- may change them. Members can read the selected business's configured roles.
drop policy if exists role_permission_overrides_select
  on public.role_permission_overrides;
drop policy if exists role_permission_overrides_insert
  on public.role_permission_overrides;
drop policy if exists role_permission_overrides_update
  on public.role_permission_overrides;
drop policy if exists role_permission_overrides_delete
  on public.role_permission_overrides;
create policy rbac_permission_overrides_select on public.role_permission_overrides
  for select to authenticated
  using (public.is_business_member(business_id));
create policy rbac_permission_overrides_insert on public.role_permission_overrides
  for insert to authenticated
  with check (public.has_business_permission(business_id, ARRAY['security.manage']::text[]));
create policy rbac_permission_overrides_update on public.role_permission_overrides
  for update to authenticated
  using (public.has_business_permission(business_id, ARRAY['security.manage']::text[]))
  with check (public.has_business_permission(business_id, ARRAY['security.manage']::text[]));
create policy rbac_permission_overrides_delete on public.role_permission_overrides
  for delete to authenticated
  using (public.has_business_permission(business_id, ARRAY['security.manage']::text[]));

-- Roles, memberships and invitations are managed through validated service
-- RPCs. Do not allow a client to write an arbitrary membership role directly.
drop policy if exists memberships_insert_manage on public.business_memberships;
drop policy if exists memberships_update_manage on public.business_memberships;
drop policy if exists memberships_delete_manage on public.business_memberships;
revoke insert, update, delete on public.business_memberships from anon, authenticated;
grant select on public.business_memberships to authenticated;

drop policy if exists business_invites_select_manager on public.business_invites;
drop policy if exists business_invites_insert_manager on public.business_invites;
drop policy if exists business_invites_update_manager on public.business_invites;
create policy business_invites_select_inviter on public.business_invites
  for select to authenticated
  using (public.has_business_permission(business_id, ARRAY['users.invite']::text[]));
create policy business_invites_insert_inviter on public.business_invites
  for insert to authenticated
  with check (
    public.has_business_permission(business_id, ARRAY['users.invite']::text[])
    and public.is_assignable_business_role(business_id, role)
  );
revoke update, delete on public.business_invites from anon, authenticated;
grant select, insert on public.business_invites to authenticated;

-- Custom role changes are owner-only, matching CustomRoleService.
revoke insert, update, delete on public.custom_roles from anon, authenticated;
grant select, insert, update, delete on public.custom_roles to authenticated;

-- Add the roles offered by the app and validate custom role IDs against this
-- business before changing any member's role.
create or replace function public.set_member_role(
  p_business_id uuid,
  p_user_id uuid,
  p_role text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.business_role(p_business_id) is distinct from 'owner' then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  if p_user_id = (select auth.uid()) then
    raise exception 'cannot change your own role';
  end if;
  if not public.is_assignable_business_role(p_business_id, p_role) then
    raise exception 'invalid role';
  end if;
  update public.business_memberships
  set role = p_role, updated_at = now()
  where business_id = p_business_id and user_id = p_user_id
    and role <> 'owner' and status <> 'removed';
  if not found then
    raise exception 'member not found';
  end if;
end;
$$;

create or replace function public.redeem_invite_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invite public.business_invites%rowtype;
  v_existing public.business_memberships%rowtype;
  v_membership_id uuid;
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception 'not authenticated';
  end if;
  if not public.is_current_device_session_active() then
    raise exception 'device authorization required';
  end if;

  select * into v_invite
  from public.business_invites
  where code = upper(btrim(p_code)) and status = 'pending'
  for update;
  if not found or not public.is_assignable_business_role(v_invite.business_id, v_invite.role) then
    raise exception 'invalid or used invite code';
  end if;

  select * into v_existing
  from public.business_memberships
  where business_id = v_invite.business_id and user_id = v_user_id
  for update;
  if found and v_existing.status <> 'removed' then
    raise exception 'you already have a membership in this business';
  end if;

  update public.business_invites
  set status = 'used', used_by_user_id = v_user_id, used_at = now()
  where id = v_invite.id and status = 'pending';
  if not found then
    raise exception 'invalid or used invite code';
  end if;

  insert into public.business_memberships (business_id, user_id, role, status)
  values (v_invite.business_id, v_user_id, v_invite.role, 'active')
  on conflict (business_id, user_id) do update
    set role = excluded.role, status = 'active', updated_at = now()
    where public.business_memberships.status = 'removed'
  returning id into v_membership_id;
  if v_membership_id is null then
    raise exception 'could not redeem invitation';
  end if;
  return v_membership_id;
end;
$$;

revoke all on function public.set_member_role(uuid, uuid, text),
  public.redeem_invite_code(text) from public, anon;
grant execute on function public.set_member_role(uuid, uuid, text),
  public.redeem_invite_code(text) to authenticated;

-- Branch assignment and transfer writes must use the declared permissions,
-- not broad membership or built-in-role checks.
drop policy if exists branches_write on public.branches;
create policy rbac_branches_insert on public.branches
  for insert to authenticated
  with check (public.has_business_permission(business_id, ARRAY['branch.manage']::text[]));
create policy rbac_branches_update on public.branches
  for update to authenticated
  using (public.has_business_permission(business_id, ARRAY['branch.manage']::text[]))
  with check (public.has_business_permission(business_id, ARRAY['branch.manage']::text[]));
create policy rbac_branches_delete on public.branches
  for delete to authenticated
  using (public.has_business_permission(business_id, ARRAY['branch.manage']::text[]));

drop policy if exists branch_members_write on public.branch_members;
create policy rbac_branch_members_insert on public.branch_members
  for insert to authenticated
  with check (public.has_business_permission(business_id, ARRAY['branch.manage']::text[]));
create policy rbac_branch_members_update on public.branch_members
  for update to authenticated
  using (public.has_business_permission(business_id, ARRAY['branch.manage']::text[]))
  with check (public.has_business_permission(business_id, ARRAY['branch.manage']::text[]));
create policy rbac_branch_members_delete on public.branch_members
  for delete to authenticated
  using (public.has_business_permission(business_id, ARRAY['branch.manage']::text[]));

drop policy if exists product_stock_movements_write
  on public.product_stock_movements;
drop policy if exists product_stock_movements_read
  on public.product_stock_movements;
create policy rbac_stock_movements_select on public.product_stock_movements
  for select to authenticated
  using (public.has_business_permission(business_id, ARRAY['inventory.view']::text[]));
create policy rbac_stock_movements_insert on public.product_stock_movements
  for insert to authenticated with check (
    public.has_any_business_permission(
      business_id,
      ARRAY['inventory.adjust', 'sales.create', 'purchasing.receive', 'stock.transfer_receive']::text[]
    )
  );
create policy rbac_stock_movements_update on public.product_stock_movements
  for update to authenticated using (
    public.has_business_permission(business_id, ARRAY['inventory.adjust']::text[])
  ) with check (
    public.has_business_permission(business_id, ARRAY['inventory.adjust']::text[])
  );
create policy rbac_stock_movements_delete on public.product_stock_movements
  for delete to authenticated using (
    public.has_business_permission(business_id, ARRAY['inventory.adjust']::text[])
  );

drop policy if exists stock_transfers_write on public.stock_transfers;
drop policy if exists stock_transfers_read on public.stock_transfers;
create policy rbac_stock_transfers_select on public.stock_transfers
  for select to authenticated
  using (
    public.has_any_business_permission(
      business_id,
      ARRAY['stock.transfer_create', 'stock.transfer_receive']::text[]
    )
  );
create policy rbac_stock_transfers_insert on public.stock_transfers
  for insert to authenticated with check (
    public.has_business_permission(business_id, ARRAY['stock.transfer_create']::text[])
  );
create policy rbac_stock_transfers_update on public.stock_transfers
  for update to authenticated using (
    public.has_any_business_permission(
      business_id,
      ARRAY['stock.transfer_create', 'stock.transfer_receive']::text[]
    )
  ) with check (
    public.has_any_business_permission(
      business_id,
      ARRAY['stock.transfer_create', 'stock.transfer_receive']::text[]
    )
  );
create policy rbac_stock_transfers_delete on public.stock_transfers
  for delete to authenticated using (
    public.has_business_permission(business_id, ARRAY['stock.transfer_create']::text[])
  );

drop policy if exists stock_transfer_items_write
  on public.stock_transfer_items;
drop policy if exists stock_transfer_items_read
  on public.stock_transfer_items;
create policy rbac_stock_transfer_items_select on public.stock_transfer_items
  for select to authenticated
  using (
    exists (
      select 1 from public.stock_transfers t
      where t.id = stock_transfer_items.transfer_id
        and public.has_any_business_permission(
          t.business_id,
          ARRAY['stock.transfer_create', 'stock.transfer_receive']::text[]
        )
    )
  );
create policy rbac_stock_transfer_items_insert on public.stock_transfer_items
  for insert to authenticated with check (
    exists (
      select 1 from public.stock_transfers t
      where t.id = stock_transfer_items.transfer_id
        and public.has_business_permission(t.business_id, ARRAY['stock.transfer_create']::text[])
    )
  );
create policy rbac_stock_transfer_items_update on public.stock_transfer_items
  for update to authenticated using (
    exists (
      select 1 from public.stock_transfers t
      where t.id = stock_transfer_items.transfer_id
        and public.has_any_business_permission(
          t.business_id,
          ARRAY['stock.transfer_create', 'stock.transfer_receive']::text[]
        )
    )
  ) with check (
    exists (
      select 1 from public.stock_transfers t
      where t.id = stock_transfer_items.transfer_id
        and public.has_any_business_permission(
          t.business_id,
          ARRAY['stock.transfer_create', 'stock.transfer_receive']::text[]
        )
    )
  );
create policy rbac_stock_transfer_items_delete on public.stock_transfer_items
  for delete to authenticated using (
    exists (
      select 1 from public.stock_transfers t
      where t.id = stock_transfer_items.transfer_id
        and public.has_business_permission(t.business_id, ARRAY['stock.transfer_create']::text[])
    )
  );

notify pgrst, 'reload schema';