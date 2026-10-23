-- 20261004010000_cloud_schema_alignment.sql
--
-- Brings the cloud schema in line with the tables and columns the app's
-- local database and sync engine already use, and completes the change feed.
--
-- Replaces 0011_complete_sync_change_feed.sql, which could not be applied:
-- it attached triggers to tables no migration created and declared a trigger
-- function with arguments. All access goes through the device-aware
-- public.is_business_member / public.is_business_manager helpers.
--
-- Not included: supply_unit_conversions (composite key, no `id`; the sync
-- engine does not carry it yet).

-- ---------------------------------------------------------------------------
-- 1. Missing columns on existing tables
-- ---------------------------------------------------------------------------

alter table public.product_categories
  add column if not exists sort_order integer not null default 0;

drop trigger if exists product_categories_set_updated_at
  on public.product_categories;
create trigger product_categories_set_updated_at
  before update on public.product_categories
  for each row execute function public.set_updated_at();

create unique index if not exists product_categories_id_business_key
  on public.product_categories (id, business_id);
create unique index if not exists products_id_business_key
  on public.products (id, business_id);
create unique index if not exists supplies_id_business_key
  on public.supplies (id, business_id);
create unique index if not exists expenses_id_business_key
  on public.expenses (id, business_id);

alter table public.products
  add column if not exists category_id uuid,
  add column if not exists description text,
  add column if not exists low_stock_threshold double precision,
  add column if not exists is_sellable boolean not null default true,
  add column if not exists sort_order integer not null default 0;

alter table public.supplies
  add column if not exists brand text,
  add column if not exists unit_quantity double precision,
  add column if not exists unit text,
  add column if not exists last_store_name text,
  add column if not exists last_store_address text,
  add column if not exists notes text,
  add column if not exists minimum_stock double precision not null default 0,
  add column if not exists maximum_stock double precision not null default 0,
  add column if not exists low_stock_threshold double precision,
  add column if not exists units_per_purchase double precision not null default 1,
  add column if not exists category_id uuid,
  add column if not exists is_sold_by_weight boolean not null default false,
  add column if not exists image_path text,
  add column if not exists sort_order integer not null default 0;

-- A product/supply category must belong to the same business.
alter table public.products
  drop constraint if exists products_same_business_category,
  add constraint products_same_business_category
    foreign key (category_id, business_id)
    references public.product_categories (id, business_id)
    on delete set null (category_id);

alter table public.supplies
  drop constraint if exists supplies_same_business_category,
  add constraint supplies_same_business_category
    foreign key (category_id, business_id)
    references public.product_categories (id, business_id)
    on delete set null (category_id);

create index if not exists products_category_idx
  on public.products (category_id);
create index if not exists supplies_category_idx
  on public.supplies (category_id);

-- ---------------------------------------------------------------------------
-- 2. Tables with their own business_id
-- ---------------------------------------------------------------------------

create table if not exists public.payment_providers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  name text not null,
  kind text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists payment_providers_business_idx
  on public.payment_providers (business_id);

create table if not exists public.pos_sessions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  opening_cash bigint not null default 0,
  counted_cash bigint,
  expected_cash bigint,
  status text not null default 'open',
  notes text,
  created_at timestamptz not null default now()
);
create index if not exists pos_sessions_business_idx
  on public.pos_sessions (business_id);
create unique index if not exists pos_sessions_id_business_key
  on public.pos_sessions (id, business_id);

create table if not exists public.pos_sales (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  sale_date timestamptz not null default now(),
  total_amount bigint not null default 0,
  is_stock_only boolean not null default false,
  payment_account_id uuid,
  notes text,
  session_id uuid,
  is_voided boolean not null default false,
  voided_at timestamptz,
  void_reason text,
  created_at timestamptz not null default now(),
  constraint pos_sales_same_business_account
    foreign key (payment_account_id, business_id)
    references public.accounts (id, business_id) on delete restrict,
  constraint pos_sales_same_business_session
    foreign key (session_id, business_id)
    references public.pos_sessions (id, business_id) on delete restrict
);
create index if not exists pos_sales_business_idx
  on public.pos_sales (business_id, sale_date);
create index if not exists pos_sales_session_idx
  on public.pos_sales (session_id);
create unique index if not exists pos_sales_id_business_key
  on public.pos_sales (id, business_id);

create table if not exists public.shopping_carts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  cart_date timestamptz not null,
  store_name text,
  store_address text,
  total_amount bigint not null,
  expense_id uuid,
  created_at timestamptz not null default now(),
  constraint shopping_carts_same_business_expense
    foreign key (expense_id, business_id)
    references public.expenses (id, business_id) on delete restrict
);
create index if not exists shopping_carts_business_idx
  on public.shopping_carts (business_id, cart_date);

create table if not exists public.role_permission_overrides (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  role text not null,
  permission text not null,
  granted boolean not null,
  updated_at timestamptz not null default now(),
  unique (business_id, role, permission)
);

drop trigger if exists role_permission_overrides_set_updated_at
  on public.role_permission_overrides;
create trigger role_permission_overrides_set_updated_at
  before update on public.role_permission_overrides
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3. Child tables (business resolved through the parent row)
-- ---------------------------------------------------------------------------

create table if not exists public.pos_sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.pos_sales (id) on delete cascade,
  product_id uuid references public.products (id) on delete set null,
  product_name text not null,
  unit text not null,
  unit_price bigint not null,
  quantity double precision not null,
  line_total bigint not null
);
create index if not exists pos_sale_items_sale_idx
  on public.pos_sale_items (sale_id);
create index if not exists pos_sale_items_product_idx
  on public.pos_sale_items (product_id);

create table if not exists public.pos_sale_payments (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.pos_sales (id) on delete cascade,
  reference_no text,
  amount_paid bigint not null,
  paid_at timestamptz,
  provider text,
  photo_path text,
  created_at timestamptz not null default now()
);
create index if not exists pos_sale_payments_sale_idx
  on public.pos_sale_payments (sale_id);

create table if not exists public.pos_sale_tenders (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.pos_sales (id) on delete cascade,
  account_id uuid not null references public.accounts (id) on delete restrict,
  amount bigint not null,
  tendered bigint,
  change_given bigint not null default 0,
  reference_no text,
  paid_at timestamptz,
  provider text,
  photo_path text,
  created_at timestamptz not null default now()
);
create index if not exists pos_sale_tenders_sale_idx
  on public.pos_sale_tenders (sale_id);
create index if not exists pos_sale_tenders_account_idx
  on public.pos_sale_tenders (account_id);

create table if not exists public.recipes (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  yield_quantity double precision not null default 1,
  notes text,
  created_at timestamptz not null default now()
);
create index if not exists recipes_product_idx on public.recipes (product_id);

create table if not exists public.recipe_components (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.recipes (id) on delete cascade,
  component_type text not null,
  supply_id uuid references public.supplies (id) on delete restrict,
  component_product_id uuid references public.products (id) on delete restrict,
  quantity_required double precision not null,
  unit text not null
);
create index if not exists recipe_components_recipe_idx
  on public.recipe_components (recipe_id);
create index if not exists recipe_components_supply_idx
  on public.recipe_components (supply_id);
create index if not exists recipe_components_product_idx
  on public.recipe_components (component_product_id);

create table if not exists public.shopping_cart_items (
  id uuid primary key default gen_random_uuid(),
  cart_id uuid not null references public.shopping_carts (id) on delete cascade,
  supply_id uuid references public.supplies (id) on delete set null,
  item_name text not null,
  brand text,
  unit_quantity double precision,
  unit text,
  unit_price bigint not null,
  quantity integer not null default 1,
  is_weighted boolean not null default false,
  weight_quantity double precision,
  stock_units_per_unit double precision not null default 1,
  gross_line_total bigint not null default 0,
  discount_type text not null default 'none',
  discount_value double precision not null default 0,
  discount_amount bigint not null default 0,
  line_total bigint not null,
  original_unit_price bigint,
  original_stock_units_per_unit double precision
);
create index if not exists shopping_cart_items_cart_idx
  on public.shopping_cart_items (cart_id);
create index if not exists shopping_cart_items_supply_idx
  on public.shopping_cart_items (supply_id);

create table if not exists public.supply_price_history (
  id uuid primary key default gen_random_uuid(),
  supply_id uuid not null references public.supplies (id) on delete cascade,
  price bigint not null,
  store_name text not null,
  store_address text,
  supplier_id uuid references public.suppliers (id) on delete set null,
  recorded_date timestamptz not null,
  notes text,
  created_at timestamptz not null default now(),
  purchase_quantity double precision not null default 1,
  units_per_purchase_at_time double precision not null default 1,
  shopping_cart_item_id uuid
    references public.shopping_cart_items (id) on delete set null
);
create index if not exists supply_price_history_supply_idx
  on public.supply_price_history (supply_id);
create index if not exists supply_price_history_supplier_idx
  on public.supply_price_history (supplier_id);

-- ---------------------------------------------------------------------------
-- 4. inventory_movements: columns the app records, business from the supply
-- ---------------------------------------------------------------------------

alter table public.inventory_movements
  add column if not exists unit text not null default 'unit',
  add column if not exists reference_type text,
  add column if not exists reference_id text,
  add column if not exists shopping_cart_item_id uuid
    references public.shopping_cart_items (id) on delete set null;

-- The app does not send business_id for movements; derive it from the
-- supply. Row-level security and the same-business foreign key still apply.
create or replace function public.set_inventory_movement_business()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.business_id is null then
    select s.business_id into new.business_id
    from public.supplies s
    where s.id = new.supply_id;
  end if;
  return new;
end;
$$;
revoke all on function public.set_inventory_movement_business()
  from public, anon, authenticated;

drop trigger if exists inventory_movements_set_business
  on public.inventory_movements;
create trigger inventory_movements_set_business
  before insert on public.inventory_movements
  for each row execute function public.set_inventory_movement_business();

-- ---------------------------------------------------------------------------
-- 5. Row-level security
-- ---------------------------------------------------------------------------

do $$
declare
  t text;
  direct_tables text[] := array[
    'payment_providers', 'pos_sessions', 'pos_sales', 'shopping_carts'
  ];
  child_tables text[] := array[
    'pos_sale_items', 'pos_sale_payments', 'pos_sale_tenders', 'recipes',
    'recipe_components', 'shopping_cart_items', 'supply_price_history'
  ];
begin
  foreach t in array direct_tables || array['role_permission_overrides']
                     || child_tables loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from anon, authenticated', t);
    execute format(
      'grant select, insert, update, delete on table public.%I to authenticated',
      t);
  end loop;

  foreach t in array direct_tables loop
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format(
      'create policy %I on public.%I for select to authenticated '
      'using (public.is_business_member(business_id))', t || '_select', t);

    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format(
      'create policy %I on public.%I for insert to authenticated '
      'with check (public.is_business_member(business_id))', t || '_insert', t);

    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format(
      'create policy %I on public.%I for update to authenticated '
      'using (public.is_business_member(business_id)) '
      'with check (public.is_business_member(business_id))', t || '_update', t);

    execute format('drop policy if exists %I on public.%I', t || '_delete', t);
    execute format(
      'create policy %I on public.%I for delete to authenticated '
      'using (public.is_business_manager(business_id))', t || '_delete', t);
  end loop;
end;
$$;

-- Permission overrides change who can do what: managers only.
drop policy if exists role_permission_overrides_select
  on public.role_permission_overrides;
create policy role_permission_overrides_select
  on public.role_permission_overrides for select to authenticated
  using (public.is_business_member(business_id));

drop policy if exists role_permission_overrides_insert
  on public.role_permission_overrides;
create policy role_permission_overrides_insert
  on public.role_permission_overrides for insert to authenticated
  with check (public.is_business_manager(business_id));

drop policy if exists role_permission_overrides_update
  on public.role_permission_overrides;
create policy role_permission_overrides_update
  on public.role_permission_overrides for update to authenticated
  using (public.is_business_manager(business_id))
  with check (public.is_business_manager(business_id));

drop policy if exists role_permission_overrides_delete
  on public.role_permission_overrides;
create policy role_permission_overrides_delete
  on public.role_permission_overrides for delete to authenticated
  using (public.is_business_manager(business_id));

-- Child rows are visible and writable to members of the parent's business.
do $$
declare
  spec text[];
  specs text[][] := array[
    array['pos_sale_items', 'pos_sales', 'sale_id'],
    array['pos_sale_payments', 'pos_sales', 'sale_id'],
    array['pos_sale_tenders', 'pos_sales', 'sale_id'],
    array['recipes', 'products', 'product_id'],
    array['shopping_cart_items', 'shopping_carts', 'cart_id'],
    array['supply_price_history', 'supplies', 'supply_id']
  ];
  child text;
  parent text;
  fk text;
  cond text;
begin
  foreach spec slice 1 in array specs loop
    child := spec[1];
    parent := spec[2];
    fk := spec[3];
    cond := format(
      'exists (select 1 from public.%I p where p.id = %I.%I '
      'and public.is_business_member(p.business_id))', parent, child, fk);

    execute format('drop policy if exists %I on public.%I', child || '_select', child);
    execute format('create policy %I on public.%I for select to authenticated using (%s)',
      child || '_select', child, cond);
    execute format('drop policy if exists %I on public.%I', child || '_insert', child);
    execute format('create policy %I on public.%I for insert to authenticated with check (%s)',
      child || '_insert', child, cond);
    execute format('drop policy if exists %I on public.%I', child || '_update', child);
    execute format('create policy %I on public.%I for update to authenticated using (%s) with check (%s)',
      child || '_update', child, cond, cond);
    execute format('drop policy if exists %I on public.%I', child || '_delete', child);
    execute format('create policy %I on public.%I for delete to authenticated using (%s)',
      child || '_delete', child, cond);
  end loop;
end;
$$;

-- recipe_components resolve their business through recipe -> product.
do $$
declare
  cond constant text :=
    'exists (select 1 from public.recipes r join public.products p '
    'on p.id = r.product_id where r.id = recipe_components.recipe_id '
    'and public.is_business_member(p.business_id))';
begin
  drop policy if exists recipe_components_select on public.recipe_components;
  execute 'create policy recipe_components_select on public.recipe_components '
    'for select to authenticated using (' || cond || ')';
  drop policy if exists recipe_components_insert on public.recipe_components;
  execute 'create policy recipe_components_insert on public.recipe_components '
    'for insert to authenticated with check (' || cond || ')';
  drop policy if exists recipe_components_update on public.recipe_components;
  execute 'create policy recipe_components_update on public.recipe_components '
    'for update to authenticated using (' || cond || ') with check (' || cond || ')';
  drop policy if exists recipe_components_delete on public.recipe_components;
  execute 'create policy recipe_components_delete on public.recipe_components '
    'for delete to authenticated using (' || cond || ')';
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Change feed
-- ---------------------------------------------------------------------------

-- Child rows have no business_id; the parent table and key column come from
-- the trigger arguments (TG_ARGV), e.g. execute function
-- log_sync_change_via_parent('pos_sales', 'sale_id').
create or replace function public.log_sync_change_via_parent()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb;
  v_entity_id uuid;
  v_parent_id uuid;
  v_business_id uuid;
  v_op text;
begin
  if TG_OP = 'DELETE' then
    v_row := to_jsonb(OLD);
    v_op := 'delete';
  else
    v_row := to_jsonb(NEW);
    v_op := case TG_OP when 'INSERT' then 'create' else 'update' end;
  end if;

  v_entity_id := (v_row ->> 'id')::uuid;
  v_parent_id := (v_row ->> TG_ARGV[1])::uuid;

  execute format('select business_id from public.%I where id = $1', TG_ARGV[0])
    into v_business_id
    using v_parent_id;

  -- A cascading delete may already have removed the parent; the parent's own
  -- feed entry covers it.
  if v_business_id is null then
    return coalesce(NEW, OLD);
  end if;

  insert into public.sync_changes (business_id, entity_type, entity_id, operation)
  values (v_business_id, TG_TABLE_NAME, v_entity_id, v_op);

  return coalesce(NEW, OLD);
end;
$$;

create or replace function public.log_sync_change_via_recipe()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipe_id uuid;
  v_entity_id uuid;
  v_business_id uuid;
  v_op text;
begin
  if TG_OP = 'DELETE' then
    v_recipe_id := OLD.recipe_id;
    v_entity_id := OLD.id;
    v_op := 'delete';
  else
    v_recipe_id := NEW.recipe_id;
    v_entity_id := NEW.id;
    v_op := case TG_OP when 'INSERT' then 'create' else 'update' end;
  end if;

  select p.business_id into v_business_id
  from public.recipes r
  join public.products p on p.id = r.product_id
  where r.id = v_recipe_id;

  if v_business_id is null then
    return coalesce(NEW, OLD);
  end if;

  insert into public.sync_changes (business_id, entity_type, entity_id, operation)
  values (v_business_id, TG_TABLE_NAME, v_entity_id, v_op);

  return coalesce(NEW, OLD);
end;
$$;

revoke all on function public.log_sync_change_via_parent(),
  public.log_sync_change_via_recipe()
  from public, anon, authenticated;

-- Direct-business tables. Existing sync triggers use create/update/delete via
-- log_sync_change(); INSERT is recorded as 'create' to match the check
-- constraint (see 0009).
do $$
declare
  t text;
  direct_tables text[] := array[
    'ledger_lines', 'product_categories', 'payment_providers',
    'pos_sessions', 'pos_sales', 'shopping_carts',
    'role_permission_overrides'
  ];
begin
  foreach t in array direct_tables loop
    execute format('drop trigger if exists %I on public.%I', t || '_sync_change', t);
    execute format(
      'create trigger %I after insert or update or delete on public.%I '
      'for each row execute function public.log_sync_change()',
      t || '_sync_change', t);
  end loop;
end;
$$;

drop trigger if exists pos_sale_items_sync_change on public.pos_sale_items;
create trigger pos_sale_items_sync_change
  after insert or update or delete on public.pos_sale_items
  for each row execute function public.log_sync_change_via_parent('pos_sales', 'sale_id');

drop trigger if exists pos_sale_payments_sync_change on public.pos_sale_payments;
create trigger pos_sale_payments_sync_change
  after insert or update or delete on public.pos_sale_payments
  for each row execute function public.log_sync_change_via_parent('pos_sales', 'sale_id');

drop trigger if exists pos_sale_tenders_sync_change on public.pos_sale_tenders;
create trigger pos_sale_tenders_sync_change
  after insert or update or delete on public.pos_sale_tenders
  for each row execute function public.log_sync_change_via_parent('pos_sales', 'sale_id');

drop trigger if exists shopping_cart_items_sync_change on public.shopping_cart_items;
create trigger shopping_cart_items_sync_change
  after insert or update or delete on public.shopping_cart_items
  for each row execute function public.log_sync_change_via_parent('shopping_carts', 'cart_id');

drop trigger if exists supply_price_history_sync_change on public.supply_price_history;
create trigger supply_price_history_sync_change
  after insert or update or delete on public.supply_price_history
  for each row execute function public.log_sync_change_via_parent('supplies', 'supply_id');

drop trigger if exists recipes_sync_change on public.recipes;
create trigger recipes_sync_change
  after insert or update or delete on public.recipes
  for each row execute function public.log_sync_change_via_parent('products', 'product_id');

drop trigger if exists recipe_components_sync_change on public.recipe_components;
create trigger recipe_components_sync_change
  after insert or update or delete on public.recipe_components
  for each row execute function public.log_sync_change_via_recipe();

notify pgrst, 'reload schema';
