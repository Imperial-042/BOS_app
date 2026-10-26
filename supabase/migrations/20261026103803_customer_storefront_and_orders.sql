create table public.customer_profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (length(btrim(display_name)) between 1 and 120),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.customer_storefronts (
  business_id uuid primary key references public.businesses (id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 160),
  description text,
  phone text,
  address text,
  city text,
  currency_code text not null default 'PHP'
    check (currency_code ~ '^[A-Z]{3}$'),
  is_published boolean not null default false,
  offline_enabled boolean not null default false,
  points_per_currency_unit integer not null default 0
    check (points_per_currency_unit between 0 and 1000),
  updated_at timestamptz not null default now()
);

create table public.customer_store_branches (
  id uuid primary key references public.branches (id) on delete cascade,
  business_id uuid not null references public.businesses (id) on delete cascade,
  name text not null,
  address text,
  is_active boolean not null default true,
  updated_at timestamptz not null default now(),
  unique (business_id, id)
);
create index customer_store_branches_business_idx
  on public.customer_store_branches (business_id, is_active);

-- This allow-listed snapshot intentionally excludes internal products fields
-- such as SKU/barcode, stock, recipes, costing, and supplier information.
create table public.customer_catalog_items (
  id uuid primary key,
  business_id uuid not null references public.businesses (id) on delete cascade,
  name text not null check (length(btrim(name)) between 1 and 160),
  description text,
  category text,
  unit text not null,
  price_cents bigint check (price_cents is null or price_cents >= 0),
  image_url text,
  is_available boolean not null default true,
  updated_at timestamptz not null default now(),
  unique (business_id, id)
);
create index customer_catalog_items_store_idx
  on public.customer_catalog_items (business_id, is_available, name);

create table public.customer_store_follows (
  customer_user_id uuid not null references public.customer_profiles (id) on delete cascade,
  business_id uuid not null references public.customer_storefronts (business_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (customer_user_id, business_id)
);
create index customer_store_follows_business_idx
  on public.customer_store_follows (business_id, created_at desc);

create table public.customer_orders (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  customer_user_id uuid not null references public.customer_profiles (id) on delete restrict,
  branch_id uuid not null,
  branch_name text not null,
  currency_code text not null default 'PHP'
    check (currency_code ~ '^[A-Z]{3}$'),
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'rejected', 'preparing', 'ready', 'completed', 'cancelled')),
  customer_name text not null,
  customer_phone text not null,
  requests_official_receipt boolean not null default false,
  customer_tin text,
  notes text,
  total_cents bigint not null check (total_cents > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (business_id, branch_id)
    references public.customer_store_branches (business_id, id)
    on delete restrict,
  check (
    (requests_official_receipt and customer_tin is not null and length(btrim(customer_tin)) > 0)
    or (not requests_official_receipt and customer_tin is null)
  )
);
create index customer_orders_customer_created_idx
  on public.customer_orders (customer_user_id, created_at desc);
create index customer_orders_business_status_created_idx
  on public.customer_orders (business_id, status, created_at desc);

create table public.customer_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.customer_orders (id) on delete cascade,
  catalog_item_id uuid not null,
  item_name text not null,
  unit text not null,
  quantity numeric(12, 3) not null check (quantity > 0 and quantity <= 1000),
  unit_price_cents bigint not null check (unit_price_cents >= 0),
  total_cents bigint not null check (total_cents > 0)
);
create index customer_order_items_order_idx on public.customer_order_items (order_id);

create table public.customer_loyalty_entries (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete cascade,
  customer_user_id uuid not null references public.customer_profiles (id) on delete cascade,
  order_id uuid not null unique references public.customer_orders (id) on delete restrict,
  points integer not null check (points > 0),
  created_at timestamptz not null default now()
);
create index customer_loyalty_customer_store_idx
  on public.customer_loyalty_entries (customer_user_id, business_id, created_at desc);

create trigger customer_profiles_set_updated_at
  before update on public.customer_profiles
  for each row execute function public.set_updated_at();
create trigger customer_storefronts_set_updated_at
  before update on public.customer_storefronts
  for each row execute function public.set_updated_at();
create trigger customer_store_branches_set_updated_at
  before update on public.customer_store_branches
  for each row execute function public.set_updated_at();
create trigger customer_catalog_items_set_updated_at
  before update on public.customer_catalog_items
  for each row execute function public.set_updated_at();
create trigger customer_orders_set_updated_at
  before update on public.customer_orders
  for each row execute function public.set_updated_at();

alter table public.customer_profiles enable row level security;
alter table public.customer_storefronts enable row level security;
alter table public.customer_store_branches enable row level security;
alter table public.customer_catalog_items enable row level security;
alter table public.customer_store_follows enable row level security;
alter table public.customer_orders enable row level security;
alter table public.customer_order_items enable row level security;
alter table public.customer_loyalty_entries enable row level security;

create policy customer_profiles_select_self on public.customer_profiles
  for select to authenticated using (id = (select auth.uid()));
create policy customer_profiles_insert_self on public.customer_profiles
  for insert to authenticated with check (id = (select auth.uid()));
create policy customer_profiles_update_self on public.customer_profiles
  for update to authenticated using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create policy customer_storefronts_read_published on public.customer_storefronts
  for select to authenticated using (is_published);
create policy customer_storefronts_manage on public.customer_storefronts
  for all to authenticated
  using (public.is_business_manager(business_id))
  with check (public.is_business_manager(business_id));

create policy customer_store_branches_read_published on public.customer_store_branches
  for select to authenticated using (
    is_active and exists (
      select 1 from public.customer_storefronts s
      where s.business_id = customer_store_branches.business_id and s.is_published
    )
  );
create policy customer_store_branches_manage on public.customer_store_branches
  for all to authenticated
  using (public.is_business_manager(business_id))
  with check (public.is_business_manager(business_id));

create policy customer_catalog_items_read_published on public.customer_catalog_items
  for select to authenticated using (
    exists (
      select 1 from public.customer_storefronts s
      where s.business_id = customer_catalog_items.business_id and s.is_published
    )
  );
create policy customer_catalog_items_manage on public.customer_catalog_items
  for all to authenticated
  using (public.is_business_manager(business_id))
  with check (public.is_business_manager(business_id));

create policy customer_store_follows_select_self on public.customer_store_follows
  for select to authenticated using (customer_user_id = (select auth.uid()));
create policy customer_store_follows_insert_self on public.customer_store_follows
  for insert to authenticated with check (
    customer_user_id = (select auth.uid())
    and exists (
      select 1 from public.customer_profiles p where p.id = (select auth.uid())
    )
    and exists (
      select 1 from public.customer_storefronts s
      where s.business_id = customer_store_follows.business_id and s.is_published
    )
  );
create policy customer_store_follows_delete_self on public.customer_store_follows
  for delete to authenticated using (customer_user_id = (select auth.uid()));

create policy customer_orders_read_customer on public.customer_orders
  for select to authenticated using (customer_user_id = (select auth.uid()));
create policy customer_orders_read_business on public.customer_orders
  for select to authenticated using (public.is_business_member(business_id));
create policy customer_orders_update_business on public.customer_orders
  for update to authenticated using (public.is_business_member(business_id))
  with check (public.is_business_member(business_id));

create policy customer_order_items_read on public.customer_order_items
  for select to authenticated using (
    exists (
      select 1 from public.customer_orders o
      where o.id = customer_order_items.order_id
        and (o.customer_user_id = (select auth.uid())
          or public.is_business_member(o.business_id))
    )
  );

create policy customer_loyalty_read_customer on public.customer_loyalty_entries
  for select to authenticated using (customer_user_id = (select auth.uid()));
create policy customer_loyalty_read_business on public.customer_loyalty_entries
  for select to authenticated using (public.is_business_member(business_id));

revoke all on public.customer_profiles, public.customer_storefronts,
  public.customer_store_branches, public.customer_catalog_items,
  public.customer_store_follows, public.customer_orders,
  public.customer_order_items, public.customer_loyalty_entries
  from public, anon;
grant select, insert, update on public.customer_profiles to authenticated;
grant select, insert, update on public.customer_storefronts to authenticated;
grant select, insert, update, delete on public.customer_store_branches to authenticated;
grant select, insert, update, delete on public.customer_catalog_items to authenticated;
grant select, insert, delete on public.customer_store_follows to authenticated;
grant select on public.customer_orders, public.customer_order_items,
  public.customer_loyalty_entries to authenticated;
grant update (status) on public.customer_orders to authenticated;

create or replace function public.submit_customer_order(
  p_business_id uuid,
  p_branch_id uuid,
  p_phone text,
  p_requests_official_receipt boolean,
  p_tin text,
  p_notes text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_customer_name text;
  v_branch_name text;
  v_currency_code text;
  v_order_id uuid := gen_random_uuid();
  v_item jsonb;
  v_catalog public.customer_catalog_items%rowtype;
  v_quantity numeric(12, 3);
  v_line_total bigint;
  v_total bigint := 0;
  v_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.customer_profiles p where p.id = v_user_id
  ) then
    raise exception 'customer profile required' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.customer_storefronts s
    where s.business_id = p_business_id and s.is_published
  ) then
    raise exception 'storefront unavailable';
  end if;
  if not exists (
    select 1 from public.customer_store_follows f
    where f.customer_user_id = v_user_id and f.business_id = p_business_id
  ) then
    raise exception 'follow the store before placing an order';
  end if;
  select p.display_name into v_customer_name
  from public.customer_profiles p where p.id = v_user_id;
  select b.name, s.currency_code into v_branch_name, v_currency_code
  from public.customer_store_branches b
  join public.customer_storefronts s on s.business_id = b.business_id
  where b.id = p_branch_id and b.business_id = p_business_id and b.is_active;
  if v_branch_name is null then
    raise exception 'pickup branch unavailable';
  end if;
  if length(btrim(coalesce(p_phone, ''))) < 5 then
    raise exception 'enter a valid contact phone number';
  end if;
  if coalesce(p_requests_official_receipt, false)
     and length(btrim(coalesce(p_tin, ''))) = 0 then
    raise exception 'TIN is required for an official receipt';
  end if;
  if not coalesce(p_requests_official_receipt, false) and p_tin is not null then
    raise exception 'TIN is only accepted when an official receipt is requested';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items) = 0
     or jsonb_array_length(p_items) > 100 then
    raise exception 'invalid order items';
  end if;

  insert into public.customer_orders (
    id, business_id, customer_user_id, branch_id, branch_name, currency_code, status,
    customer_name, customer_phone, requests_official_receipt, customer_tin,
    notes, total_cents
  ) values (
    v_order_id, p_business_id, v_user_id, p_branch_id, v_branch_name, v_currency_code,
    'pending', v_customer_name, btrim(p_phone),
    coalesce(p_requests_official_receipt, false),
    case when p_requests_official_receipt then btrim(p_tin) else null end,
    nullif(btrim(coalesce(p_notes, '')), ''), 1
  );

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if (v_item ->> 'catalog_item_id') is null
       or (v_item ->> 'quantity') is null then
      raise exception 'invalid order item';
    end if;
    if (v_item ->> 'catalog_item_id') !~* '^[0-9a-f-]{36}$' then
      raise exception 'invalid catalog item';
    end if;
    v_quantity := (v_item ->> 'quantity')::numeric;
    if v_quantity <= 0 or v_quantity > 1000 then
      raise exception 'invalid item quantity';
    end if;
    select * into v_catalog
    from public.customer_catalog_items c
    where c.id = (v_item ->> 'catalog_item_id')::uuid
      and c.business_id = p_business_id
      and c.is_available;
    if not found then
      raise exception 'catalog item unavailable';
    end if;
    if v_catalog.price_cents is null then
      raise exception 'catalog item has no orderable price';
    end if;
    v_line_total := round(v_catalog.price_cents * v_quantity)::bigint;
    if v_line_total <= 0 then
      raise exception 'order item total must be greater than zero';
    end if;
    insert into public.customer_order_items (
      order_id, catalog_item_id, item_name, unit, quantity,
      unit_price_cents, total_cents
    ) values (
      v_order_id, v_catalog.id, v_catalog.name, v_catalog.unit, v_quantity,
      v_catalog.price_cents, v_line_total
    );
    v_total := v_total + v_line_total;
    v_count := v_count + 1;
  end loop;

  if v_count = 0 then
    raise exception 'order must include an item';
  end if;
  update public.customer_orders set total_cents = v_total where id = v_order_id;
  return v_order_id;
end;
$$;

create or replace function public.award_customer_order_points()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_points_per_currency integer;
  v_points integer;
begin
  if new.status = 'completed' and old.status is distinct from 'completed' then
    select s.points_per_currency_unit into v_points_per_currency
    from public.customer_storefronts s where s.business_id = new.business_id;
    v_points := floor((new.total_cents::numeric / 100) * coalesce(v_points_per_currency, 0))::integer;
    if v_points > 0 then
      insert into public.customer_loyalty_entries (
        business_id, customer_user_id, order_id, points
      ) values (new.business_id, new.customer_user_id, new.id, v_points)
      on conflict (order_id) do nothing;
    end if;
  end if;
  return new;
end;
$$;

create trigger customer_order_award_points
  after update of status on public.customer_orders
  for each row execute function public.award_customer_order_points();

revoke all on function public.submit_customer_order(uuid, uuid, text, boolean, text, text, jsonb)
  from public, anon;
grant execute on function public.submit_customer_order(uuid, uuid, text, boolean, text, text, jsonb)
  to authenticated;
revoke all on function public.award_customer_order_points() from public, anon, authenticated;

notify pgrst, 'reload schema';