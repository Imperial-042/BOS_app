alter table public.customer_profiles
  add column city text,
  add column address text;

alter table public.customer_storefronts
  add column opening_hours jsonb not null default '{}'::jsonb,
  add constraint customer_storefronts_opening_hours_object
    check (jsonb_typeof(opening_hours) = 'object');

drop policy if exists customer_storefronts_read_published
  on public.customer_storefronts;
create policy customer_storefronts_read_published
  on public.customer_storefronts
  for select to authenticated
  using (
    is_published
    and exists (
      select 1
      from public.customer_profiles p
      where p.id = (select auth.uid())
        and nullif(btrim(p.city), '') is not null
        and regexp_replace(lower(btrim(p.city)), '[[:space:]]+', ' ', 'g')
          = regexp_replace(
              lower(btrim(customer_storefronts.city)),
              '[[:space:]]+',
              ' ',
              'g'
            )
    )
  );

create or replace function public.enforce_customer_order_store_hours()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_hours jsonb;
  v_timezone text;
  v_today jsonb;
  v_local_time text;
  v_open text;
  v_close text;
  v_customer_city text;
  v_store_city text;
begin
  select s.opening_hours,
         coalesce(b.timezone, 'Asia/Manila'),
         s.city,
         p.city
    into v_hours, v_timezone, v_store_city, v_customer_city
  from public.customer_storefronts s
  join public.businesses b on b.id = s.business_id
  join public.customer_profiles p on p.id = new.customer_user_id
  where s.business_id = new.business_id
    and s.is_published;

  if not found then
    raise exception 'storefront unavailable for your city';
  end if;
  if nullif(btrim(v_customer_city), '') is null
     or v_store_city is null
     or regexp_replace(lower(btrim(v_customer_city)), '[[:space:]]+', ' ', 'g')
        <> regexp_replace(lower(btrim(v_store_city)), '[[:space:]]+', ' ', 'g') then
    raise exception 'storefront unavailable for your city';
  end if;

  if v_hours = '{}'::jsonb then
    return new;
  end if;

  v_today := v_hours -> extract(
    isodow from (now() at time zone v_timezone)
  )::integer::text;
  if jsonb_typeof(v_today) is distinct from 'object' then
    raise exception 'storefront is currently closed';
  end if;

  v_open := v_today ->> 'open';
  v_close := v_today ->> 'close';
  if v_open is null
     or v_close is null
     or v_open !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
     or v_close !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
     or v_open >= v_close then
    raise exception 'storefront hours are not configured correctly';
  end if;

  v_local_time := to_char(
    now() at time zone v_timezone,
    'HH24:MI'
  );
  if v_local_time < v_open or v_local_time >= v_close then
    raise exception 'storefront is currently closed';
  end if;

  return new;
end;
$$;

create trigger customer_orders_enforce_store_hours
  before insert on public.customer_orders
  for each row execute function public.enforce_customer_order_store_hours();

revoke all on function public.enforce_customer_order_store_hours()
  from public, anon, authenticated;