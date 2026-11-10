alter table public.customer_store_branches
  add column if not exists phone text,
  add column if not exists opening_hours jsonb not null default '{}'::jsonb;

alter table public.customer_store_branches
  add constraint customer_store_branches_opening_hours_object
  check (jsonb_typeof(opening_hours) = 'object');

-- Keep today's behaviour for existing data: every branch starts with the
-- hours the storefront had.
update public.customer_store_branches csb
set opening_hours = s.opening_hours,
    phone = coalesce(br.phone, s.phone)
from public.customer_storefronts s, public.branches br
where s.business_id = csb.business_id
  and br.id = csb.id;

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
  v_branch_city text;
begin
  select branch.opening_hours,
         coalesce(business.timezone, 'Asia/Manila'),
         branch.city,
         profile.city
    into v_hours, v_timezone, v_branch_city, v_customer_city
  from public.customer_store_branches branch
  join public.customer_storefronts storefront
    on storefront.business_id = branch.business_id
   and storefront.is_published
  join public.businesses business on business.id = branch.business_id
  join public.customer_profiles profile on profile.id = new.customer_user_id
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

  if v_hours = '{}'::jsonb then
    return new;
  end if;

  v_today := v_hours -> extract(
    isodow from (now() at time zone v_timezone)
  )::integer::text;
  if jsonb_typeof(v_today) is distinct from 'object' then
    raise exception 'this branch is currently closed';
  end if;

  v_open := v_today ->> 'open';
  v_close := v_today ->> 'close';
  if v_open is null or v_close is null
     or v_open !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
     or v_close !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
     or v_open >= v_close then
    raise exception 'branch hours are not configured correctly';
  end if;

  v_local_time := to_char(now() at time zone v_timezone, 'HH24:MI');
  if v_local_time < v_open or v_local_time >= v_close then
    raise exception 'this branch is currently closed';
  end if;

  return new;
end;
$$;

notify pgrst, 'reload schema';