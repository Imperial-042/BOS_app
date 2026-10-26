create table public.pos_returns (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  sale_id uuid not null,
  refund_account_id uuid not null,
  reason text not null check (char_length(btrim(reason)) between 1 and 500),
  created_by text,
  created_at timestamptz not null default now(),
  constraint pos_returns_sale_business_fk
    foreign key (sale_id, business_id)
    references public.pos_sales (id, business_id) on delete restrict,
  constraint pos_returns_account_business_fk
    foreign key (refund_account_id, business_id)
    references public.accounts (id, business_id) on delete restrict
);

create index pos_returns_business_created_idx
  on public.pos_returns (business_id, created_at desc);
create index pos_returns_sale_idx on public.pos_returns (sale_id);

create table public.pos_return_items (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null
    references public.pos_returns (id) on delete restrict,
  sale_item_id uuid not null
    references public.pos_sale_items (id) on delete restrict,
  quantity double precision not null check (quantity > 0),
  refund_amount bigint not null check (refund_amount >= 0)
);

create index pos_return_items_return_idx
  on public.pos_return_items (return_id);
create index pos_return_items_sale_item_idx
  on public.pos_return_items (sale_item_id);

alter table public.pos_returns enable row level security;
alter table public.pos_return_items enable row level security;

revoke all on table public.pos_returns, public.pos_return_items
  from anon, authenticated;
grant select, insert on table public.pos_returns, public.pos_return_items
  to authenticated;

create policy pos_returns_select on public.pos_returns
  for select to authenticated
  using (
    public.has_any_business_permission(
      business_id, array['sales.view', 'sales.void']::text[]
    )
  );
create policy pos_returns_insert on public.pos_returns
  for insert to authenticated
  with check (
    public.has_business_permission(business_id, array['sales.void']::text[])
  );
create policy pos_return_items_select on public.pos_return_items
  for select to authenticated
  using (
    exists (
      select 1
      from public.pos_returns r
      where r.id = pos_return_items.return_id
        and public.has_any_business_permission(
          r.business_id, array['sales.view', 'sales.void']::text[]
        )
    )
  );
create policy pos_return_items_insert on public.pos_return_items
  for insert to authenticated
  with check (
    exists (
      select 1
      from public.pos_returns r
      join public.pos_sale_items si on si.id = pos_return_items.sale_item_id
      where r.id = pos_return_items.return_id
        and si.sale_id = r.sale_id
        and public.has_business_permission(
          r.business_id, array['sales.void']::text[]
        )
    )
  );

create policy pos_return_product_stock_insert
  on public.product_stock_movements
  for insert to authenticated
  with check (
    movement_type = 'pos_return'
    and reference_type = 'pos_return'
    and exists (
      select 1
      from public.pos_returns r
      where r.id::text = product_stock_movements.reference_id
        and r.business_id = product_stock_movements.business_id
        and public.has_business_permission(
          r.business_id, array['sales.void']::text[]
        )
    )
  );

create policy pos_return_supply_stock_insert
  on public.inventory_movements
  for insert to authenticated
  with check (
    movement_type = 'pos_return'
    and reference_type = 'pos_return'
    and exists (
      select 1
      from public.pos_returns r
      where r.id::text = inventory_movements.reference_id
        and r.business_id = inventory_movements.business_id
        and public.has_business_permission(
          r.business_id, array['sales.void']::text[]
        )
    )
  );

create policy pos_return_product_stock_guard
  on public.product_stock_movements
  as restrictive
  for insert to authenticated
  with check (
    movement_type <> 'pos_return'
    or (
      reference_type = 'pos_return'
      and exists (
        select 1
        from public.pos_returns r
        where r.id::text = product_stock_movements.reference_id
          and r.business_id = product_stock_movements.business_id
          and public.has_business_permission(
            r.business_id, array['sales.void']::text[]
          )
      )
    )
  );
create policy pos_return_supply_stock_guard
  on public.inventory_movements
  as restrictive
  for insert to authenticated
  with check (
    movement_type <> 'pos_return'
    or (
      reference_type = 'pos_return'
      and exists (
        select 1
        from public.pos_returns r
        where r.id::text = inventory_movements.reference_id
          and r.business_id = inventory_movements.business_id
          and public.has_business_permission(
            r.business_id, array['sales.void']::text[]
          )
      )
    )
  );

create or replace function public.validate_pos_return_header()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale public.pos_sales%rowtype;
  v_account public.accounts%rowtype;
begin
  if (select auth.uid()) is null
     or not public.is_current_device_session_active()
     or not public.has_business_permission(
       new.business_id, array['sales.void']::text[]
     ) then
    raise exception 'not authorized to record a return'
      using errcode = '42501';
  end if;

  select * into v_sale
  from public.pos_sales s
  where s.id = new.sale_id
    and s.business_id = new.business_id
  for key share;
  if not found or v_sale.is_voided or v_sale.is_stock_only then
    raise exception 'receipt cannot be returned';
  end if;

  select * into v_account
  from public.accounts a
  where a.id = new.refund_account_id
    and a.business_id = new.business_id
  for key share;
  if not found or not v_account.is_active or not v_account.is_payment_account then
    raise exception 'refund account must be an active payment account';
  end if;

  return new;
end;
$$;

revoke all on function public.validate_pos_return_header()
  from public, anon, authenticated;
create trigger pos_returns_validate
  before insert on public.pos_returns
  for each row execute function public.validate_pos_return_header();

create or replace function public.validate_pos_return_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_return public.pos_returns%rowtype;
  v_sale public.pos_sales%rowtype;
  v_sale_item public.pos_sale_items%rowtype;
  v_existing public.pos_return_items%rowtype;
  v_gross numeric;
  v_allocated_net bigint;
  v_previous_quantity numeric;
  v_previous_refund bigint;
  v_expected_refund bigint;
  v_previous_allocations bigint;
begin
  if (select auth.uid()) is null
     or not public.is_current_device_session_active() then
    raise exception 'device authorization required' using errcode = '42501';
  end if;

  select * into v_return
  from public.pos_returns r
  where r.id = new.return_id;
  if not found then
    raise exception 'return record not found';
  end if;

  if not public.has_business_permission(
    v_return.business_id, array['sales.void']::text[]
  ) then
    raise exception 'not authorized to record a return'
      using errcode = '42501';
  end if;

  select * into v_existing
  from public.pos_return_items ri
  where ri.id = new.id;
  if found then
    if v_existing.return_id is distinct from new.return_id
       or v_existing.sale_item_id is distinct from new.sale_item_id
       or v_existing.quantity is distinct from new.quantity
       or v_existing.refund_amount is distinct from new.refund_amount then
      raise exception 'return item id already exists with different data';
    end if;
    return null;
  end if;

  select * into v_sale_item
  from public.pos_sale_items si
  where si.id = new.sale_item_id
  for update;
  if not found or v_sale_item.sale_id <> v_return.sale_id then
    raise exception 'return item does not belong to this sale';
  end if;

  select * into v_sale
  from public.pos_sales s
  where s.id = v_return.sale_id
    and s.business_id = v_return.business_id;
  if not found or v_sale.is_voided or v_sale.is_stock_only then
    raise exception 'receipt cannot be returned';
  end if;

  if new.quantity <= 0
     or new.quantity = 'NaN'::double precision
     or new.refund_amount < 0 then
    raise exception 'invalid returned quantity or refund amount';
  end if;

  select
    coalesce(sum(ri.quantity::numeric), 0),
    coalesce(sum(ri.refund_amount), 0)
  into v_previous_quantity, v_previous_refund
  from public.pos_return_items ri
  join public.pos_returns r on r.id = ri.return_id
  where r.sale_id = v_return.sale_id
    and ri.sale_item_id = v_sale_item.id;

  if v_previous_quantity + new.quantity::numeric >
     v_sale_item.quantity::numeric then
    raise exception 'returned quantity exceeds quantity sold';
  end if;

  select coalesce(sum(si.line_total::numeric), 0)
  into v_gross
  from public.pos_sale_items si
  where si.sale_id = v_return.sale_id;
  if v_gross <= 0 then
    raise exception 'receipt has no refundable total';
  end if;

  select coalesce(
    sum(round(si.line_total::numeric * v_sale.total_amount::numeric / v_gross)),
    0
  )::bigint
  into v_previous_allocations
  from public.pos_sale_items si
  where si.sale_id = v_return.sale_id
    and si.id < v_sale_item.id;

  if v_sale_item.id = (
    select max(si.id)
    from public.pos_sale_items si
    where si.sale_id = v_return.sale_id
  ) then
    v_allocated_net := v_sale.total_amount - v_previous_allocations;
  else
    v_allocated_net := round(
      v_sale_item.line_total::numeric * v_sale.total_amount::numeric / v_gross
    )::bigint;
  end if;

  v_expected_refund := round(
    v_allocated_net::numeric *
    (v_previous_quantity + new.quantity::numeric) /
    v_sale_item.quantity::numeric
  )::bigint - v_previous_refund;

  if new.refund_amount <> v_expected_refund then
    raise exception 'refund amount does not match the remaining sale value';
  end if;

  return new;
end;
$$;

revoke all on function public.validate_pos_return_item()
  from public, anon, authenticated;
create trigger pos_return_items_validate
  before insert on public.pos_return_items
  for each row execute function public.validate_pos_return_item();

create trigger pos_returns_sync_change
  after insert or update or delete on public.pos_returns
  for each row execute function public.log_sync_change();
create trigger pos_return_items_sync_change
  after insert or update or delete on public.pos_return_items
  for each row execute function
    public.log_sync_change_via_parent('pos_returns', 'return_id');

create trigger pos_returns_audit_change
  after insert or update or delete on public.pos_returns
  for each row execute function public.capture_business_audit();
create trigger pos_return_items_audit_change
  after insert or update or delete on public.pos_return_items
  for each row execute function
    public.capture_business_audit('pos_returns', 'return_id');

notify pgrst, 'reload schema';