begin;

-- Which products each branch sells
create table if not exists public.customer_branch_catalog_items (
  branch_id uuid not null
    references public.customer_store_branches(id) on delete cascade,
  catalog_item_id uuid not null
    references public.customer_catalog_items(id) on delete cascade,
  business_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (branch_id, catalog_item_id)
);
create index if not exists ix_cbci_business
  on public.customer_branch_catalog_items (business_id);
create index if not exists ix_cbci_item
  on public.customer_branch_catalog_items (catalog_item_id);

alter table public.customer_branch_catalog_items enable row level security;
revoke all on public.customer_branch_catalog_items from anon;
grant select, insert, update, delete
  on public.customer_branch_catalog_items to authenticated;

drop policy if exists customer_branch_catalog_items_manage
  on public.customer_branch_catalog_items;
create policy customer_branch_catalog_items_manage
  on public.customer_branch_catalog_items for all to authenticated
  using (public.is_business_manager(business_id))
  with check (
    public.is_business_manager(business_id)
    and exists (select 1 from public.customer_store_branches b
                where b.id = customer_branch_catalog_items.branch_id
                  and b.business_id = customer_branch_catalog_items.business_id)
    and exists (select 1 from public.customer_catalog_items c
                where c.id = customer_branch_catalog_items.catalog_item_id
                  and c.business_id = customer_branch_catalog_items.business_id)
  );

-- Customers see a link only if they can see the branch (published + their city)
drop policy if exists customer_branch_catalog_items_read
  on public.customer_branch_catalog_items;
create policy customer_branch_catalog_items_read
  on public.customer_branch_catalog_items for select to authenticated
  using (
    exists (select 1 from public.customer_store_branches b
            where b.id = customer_branch_catalog_items.branch_id)
    and exists (select 1 from public.customer_storefronts s
                where s.business_id = customer_branch_catalog_items.business_id
                  and s.is_published)
  );

-- Customers may only read items that some visible branch sells
drop policy if exists customer_catalog_items_read_published
  on public.customer_catalog_items;
create policy customer_catalog_items_read_published
  on public.customer_catalog_items for select to authenticated
  using (
    is_available
    and exists (select 1 from public.customer_branch_catalog_items bc
                where bc.catalog_item_id = customer_catalog_items.id)
  );

-- Backfill: every branch keeps today's catalog, so nothing disappears
insert into public.customer_branch_catalog_items (branch_id, catalog_item_id, business_id)
select b.id, c.id, c.business_id
from public.customer_store_branches b
join public.customer_catalog_items c on c.business_id = b.business_id
on conflict do nothing;

-- Orders: item must be sold at the chosen branch
create or replace function public.submit_customer_order(
  p_business_id uuid, p_branch_id uuid, p_phone text,
  p_requests_official_receipt boolean, p_tin text, p_notes text, p_items jsonb)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
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
  if not exists (select 1 from public.customer_profiles p where p.id = v_user_id) then
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
  where b.id = p_branch_id and b.business_id = p_business_id
    and b.is_active and b.storefront_published;
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
    if not exists (
      select 1 from public.customer_branch_catalog_items bc
      where bc.branch_id = p_branch_id and bc.catalog_item_id = v_catalog.id
    ) then
      raise exception 'catalog item unavailable at this branch';
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
$function$;

notify pgrst, 'reload schema';
commit;