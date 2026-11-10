alter table public.customer_orders
  add column if not exists payment_method text not null default 'cash';

alter table public.customer_orders
  drop constraint if exists customer_orders_payment_method_check;

alter table public.customer_orders
  add constraint customer_orders_payment_method_check
  check (payment_method in ('cash', 'gcash', 'maya', 'card'));

alter table public.customer_order_items
  add column if not exists options jsonb not null default '[]'::jsonb;

alter table public.customer_order_items
  drop constraint if exists customer_order_items_options_array;

alter table public.customer_order_items
  add constraint customer_order_items_options_array
  check (jsonb_typeof(options) = 'array');

drop function if exists public.submit_customer_order(
  uuid, uuid, text, boolean, text, text, jsonb
);

create function public.submit_customer_order(
  p_business_id uuid,
  p_branch_id uuid,
  p_phone text,
  p_requests_official_receipt boolean,
  p_tin text,
  p_notes text,
  p_items jsonb,
  p_payment_method text default 'cash'
)
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
  v_option jsonb;
  v_catalog public.customer_catalog_items%rowtype;
  v_quantity numeric(12, 3);
  v_option_total integer;
  v_unit_price bigint;
  v_line_total bigint;
  v_options jsonb;
  v_option_names text;
  v_total bigint := 0;
  v_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if p_payment_method not in ('cash', 'gcash', 'maya', 'card') then
    raise exception 'unsupported payment method';
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
    id, business_id, customer_user_id, branch_id, branch_name, currency_code,
    status, customer_name, customer_phone, requests_official_receipt,
    customer_tin, notes, payment_method, total_cents
  ) values (
    v_order_id, p_business_id, v_user_id, p_branch_id, v_branch_name,
    v_currency_code, 'pending', v_customer_name, btrim(p_phone),
    coalesce(p_requests_official_receipt, false),
    case when p_requests_official_receipt then btrim(p_tin) else null end,
    nullif(btrim(coalesce(p_notes, '')), ''), p_payment_method, 1
  );

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if (v_item ->> 'catalog_item_id') is null
       or (v_item ->> 'quantity') is null
       or jsonb_typeof(coalesce(v_item -> 'options', '[]'::jsonb)) is distinct from 'array' then
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

    v_option_total := 0;
    v_options := '[]'::jsonb;
    v_option_names := '';
    for v_option in select value from jsonb_array_elements(v_item -> 'options')
    loop
      if (v_option ->> 'choiceId') !~* '^[0-9a-f-]{36}$' then
        raise exception 'invalid product option';
      end if;
      if not exists (
        select 1
        from public.product_option_choices choice
        join public.product_option_groups grp on grp.id = choice.group_id
        where choice.id = (v_option ->> 'choiceId')::uuid
          and choice.product_id = v_catalog.id
          and choice.business_id = p_business_id
          and choice.is_active
          and grp.is_active
      ) then
        raise exception 'product option is unavailable';
      end if;
      select choice.price_delta_cents
        into v_unit_price
      from public.product_option_choices choice
      where choice.id = (v_option ->> 'choiceId')::uuid;
      v_option_total := v_option_total + v_unit_price::integer;
      v_options := v_options || jsonb_build_array(v_option);
      v_option_names := concat_ws(', ', v_option_names, v_option ->> 'choiceName');
    end loop;

    if exists (
      select 1
      from public.product_option_groups grp
      where grp.product_id = v_catalog.id
        and grp.business_id = p_business_id
        and grp.is_active
        and (
          (
            grp.is_required
            and not exists (
              select 1
              from jsonb_array_elements(v_item -> 'options') selected
              join public.product_option_choices selected_choice
                on selected_choice.id = (selected ->> 'choiceId')::uuid
              where selected_choice.group_id = grp.id
                and selected_choice.is_active
            )
          )
          or (
            (
              select count(*)
              from jsonb_array_elements(v_item -> 'options') selected
              join public.product_option_choices selected_choice
                on selected_choice.id = (selected ->> 'choiceId')::uuid
              where selected_choice.group_id = grp.id
                and selected_choice.is_active
            ) < grp.min_selections
          )
          or (
            grp.max_selections is not null
            and (
              select count(*)
              from jsonb_array_elements(v_item -> 'options') selected
              join public.product_option_choices selected_choice
                on selected_choice.id = (selected ->> 'choiceId')::uuid
              where selected_choice.group_id = grp.id
                and selected_choice.is_active
            ) > grp.max_selections
          )
          or (
            not grp.allow_multiple
            and (
              select count(*)
              from jsonb_array_elements(v_item -> 'options') selected
              join public.product_option_choices selected_choice
                on selected_choice.id = (selected ->> 'choiceId')::uuid
              where selected_choice.group_id = grp.id
                and selected_choice.is_active
            ) > 1
          )
        )
    ) then
      raise exception 'invalid product option selections';
    end if;

    v_unit_price := v_catalog.price_cents + v_option_total;
    if v_unit_price < 0 then
      raise exception 'order item price is invalid';
    end if;
    v_line_total := round(v_unit_price * v_quantity)::bigint;
    if v_line_total <= 0 then
      raise exception 'order item total must be greater than zero';
    end if;
    insert into public.customer_order_items (
      order_id, catalog_item_id, item_name, unit, quantity,
      unit_price_cents, total_cents, options
    ) values (
      v_order_id, v_catalog.id,
      case when v_option_names = '' then v_catalog.name
           else v_catalog.name || ' (' || v_option_names || ')' end,
      v_catalog.unit, v_quantity, v_unit_price, v_line_total, v_options
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

revoke all on function public.submit_customer_order(
  uuid, uuid, text, boolean, text, text, jsonb, text
) from public, anon;
grant execute on function public.submit_customer_order(
  uuid, uuid, text, boolean, text, text, jsonb, text
) to authenticated;

drop function if exists public.submit_customer_delivery_order(
  uuid, uuid, text, boolean, text, text, jsonb, jsonb,
  double precision, double precision, double precision
);

create function public.submit_customer_delivery_order(
  p_business_id uuid,
  p_branch_id uuid,
  p_phone text,
  p_requests_official_receipt boolean,
  p_tin text,
  p_notes text,
  p_items jsonb,
  p_address_snapshot jsonb,
  p_delivery_latitude double precision,
  p_delivery_longitude double precision,
  p_delivery_accuracy_meters double precision,
  p_payment_method text default 'cash'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if p_address_snapshot is null
     or nullif(btrim(p_address_snapshot ->> 'formatted_address'), '') is null then
    raise exception 'delivery address is required';
  end if;
  if p_delivery_latitude is not null
     and (p_delivery_latitude < -90 or p_delivery_latitude > 90) then
    raise exception 'invalid delivery latitude';
  end if;
  if p_delivery_longitude is not null
     and (p_delivery_longitude < -180 or p_delivery_longitude > 180) then
    raise exception 'invalid delivery longitude';
  end if;

  v_order_id := public.submit_customer_order(
    p_business_id, p_branch_id, p_phone, p_requests_official_receipt,
    p_tin, p_notes, p_items, p_payment_method
  );

  update public.customer_orders
     set fulfillment_type = 'delivery',
         delivery_address_snapshot = p_address_snapshot,
         delivery_latitude = p_delivery_latitude,
         delivery_longitude = p_delivery_longitude,
         delivery_accuracy_meters = p_delivery_accuracy_meters
   where id = v_order_id
     and customer_user_id = (select auth.uid());
  return v_order_id;
end;
$function$;

revoke all on function public.submit_customer_delivery_order(
  uuid, uuid, text, boolean, text, text, jsonb, jsonb,
  double precision, double precision, double precision, text
) from public, anon;
grant execute on function public.submit_customer_delivery_order(
  uuid, uuid, text, boolean, text, text, jsonb, jsonb,
  double precision, double precision, double precision, text
) to authenticated;

notify pgrst, 'reload schema';
