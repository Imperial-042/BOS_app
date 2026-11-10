begin;

alter table public.customer_store_branches
  add column if not exists availability_override jsonb;

alter table public.customer_store_branches
  drop constraint if exists customer_store_branches_availability_override_object;

alter table public.customer_store_branches
  add constraint customer_store_branches_availability_override_object
  check (
    availability_override is null
    or jsonb_typeof(availability_override) = 'object'
  );

create or replace function public.enforce_customer_order_store_hours()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_hours jsonb;
  v_override jsonb;
  v_timezone text;
  v_today jsonb;
  v_previous jsonb;
  v_local_date date;
  v_local_minutes integer;
  v_open integer;
  v_close integer;
  v_previous_open integer;
  v_previous_close integer;
  v_customer_city text;
  v_branch_city text;
  v_day integer;
  v_override_start date;
  v_override_end date;
begin
  select branch.opening_hours,
         branch.availability_override,
         coalesce(business.timezone, 'Asia/Manila'),
         branch.city,
         profile.city
    into v_hours, v_override, v_timezone, v_branch_city, v_customer_city
  from public.customer_store_branches branch
  join public.customer_storefronts storefront
    on storefront.business_id = branch.business_id
   and storefront.is_published
  join public.businesses business on business.id = branch.business_id
  join public.customer_profiles profile
    on profile.id = new.customer_user_id
  where branch.id = new.branch_id
    and branch.business_id = new.business_id
    and branch.is_active
    and branch.storefront_published;

  if not found
     or nullif(btrim(v_customer_city), '') is null
     or nullif(btrim(v_branch_city), '') is null
     or regexp_replace(lower(btrim(v_customer_city)), '[[:space:]]+', ' ', 'g')
        <> regexp_replace(lower(btrim(v_branch_city)), '[[:space:]]+', ' ', 'g') then
    raise exception 'pickup branch unavailable for your city';
  end if;

  v_local_date := (now() at time zone v_timezone)::date;
  if jsonb_typeof(v_override) = 'object' then
    v_override_start := (v_override ->> 'start_date')::date;
    v_override_end := (v_override ->> 'end_date')::date;
    if v_local_date between v_override_start and v_override_end then
      if v_override ->> 'mode' = 'open' then
        return new;
      end if;
      raise exception 'this branch is closed for a special occasion';
    end if;
  end if;

  if v_hours = '{}'::jsonb then
    return new;
  end if;

  v_day := extract(isodow from (now() at time zone v_timezone))::integer;
  v_local_minutes :=
    extract(hour from (now() at time zone v_timezone))::integer * 60
    + extract(minute from (now() at time zone v_timezone))::integer;
  v_today := v_hours -> v_day::text;

  if jsonb_typeof(v_today) = 'object' then
    if (v_today ->> 'open') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
       or (v_today ->> 'close') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
      raise exception 'branch hours are not configured correctly';
    end if;
    v_open := split_part(v_today ->> 'open', ':', 1)::integer * 60
      + split_part(v_today ->> 'open', ':', 2)::integer;
    v_close := split_part(v_today ->> 'close', ':', 1)::integer * 60
      + split_part(v_today ->> 'close', ':', 2)::integer;
    if v_open = v_close
       or (v_open < v_close
           and v_local_minutes >= v_open
           and v_local_minutes < v_close)
       or (v_open > v_close
           and (v_local_minutes >= v_open or v_local_minutes < v_close)) then
      return new;
    end if;
  end if;

  v_previous := v_hours -> (((v_day + 5) % 7) + 1)::text;
  if jsonb_typeof(v_previous) = 'object' then
    v_previous_open := split_part(v_previous ->> 'open', ':', 1)::integer * 60
      + split_part(v_previous ->> 'open', ':', 2)::integer;
    v_previous_close := split_part(v_previous ->> 'close', ':', 1)::integer * 60
      + split_part(v_previous ->> 'close', ':', 2)::integer;
    if v_previous_open > v_previous_close
       and v_local_minutes < v_previous_close then
      return new;
    end if;
  end if;

  raise exception 'this branch is currently closed';
end;
$function$;

commit;

notify pgrst, 'reload schema';
