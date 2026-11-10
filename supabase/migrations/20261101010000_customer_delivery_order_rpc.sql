create or replace function public.submit_customer_delivery_order(
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
  p_delivery_accuracy_meters double precision
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
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
    p_business_id,
    p_branch_id,
    p_phone,
    p_requests_official_receipt,
    p_tin,
    p_notes,
    p_items
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
$$;

revoke all on function public.submit_customer_delivery_order(
  uuid, uuid, text, boolean, text, text, jsonb, jsonb,
  double precision, double precision, double precision
) from public, anon;
grant execute on function public.submit_customer_delivery_order(
  uuid, uuid, text, boolean, text, text, jsonb, jsonb,
  double precision, double precision, double precision
) to authenticated;
