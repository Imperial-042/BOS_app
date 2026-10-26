alter table public.branches
  add column city text;

alter table public.customer_store_branches
  add column city text,
  add column storefront_published boolean not null default false;

update public.customer_store_branches storefront_branch
set city = branch.city,
    storefront_published = storefront.is_published
from public.branches branch
join public.customer_storefronts storefront
  on storefront.business_id = branch.business_id
where branch.id = storefront_branch.id
  and branch.business_id = storefront_branch.business_id
  and storefront_branch.city is null;

create index customer_store_branches_city_idx
  on public.customer_store_branches (business_id, city, is_active);

drop policy if exists branch_scope_customer_orders
  on public.customer_orders;
create policy branch_scope_customer_orders
  on public.customer_orders as restrictive
  for all to authenticated
  using (public.has_branch_access(business_id, branch_id))
  with check (public.has_branch_access(business_id, branch_id));

drop policy if exists customer_storefronts_read_published
  on public.customer_storefronts;
create policy customer_storefronts_read_published
  on public.customer_storefronts
  for select to authenticated
  using (
    is_published
    and exists (
      select 1
      from public.customer_profiles profile
      join public.customer_store_branches branch
        on branch.business_id = customer_storefronts.business_id
      where profile.id = (select auth.uid())
        and branch.is_active
        and branch.storefront_published
        and nullif(btrim(profile.city), '') is not null
        and nullif(btrim(branch.city), '') is not null
        and regexp_replace(lower(btrim(profile.city)), '[[:space:]]+', ' ', 'g')
          = regexp_replace(lower(btrim(branch.city)), '[[:space:]]+', ' ', 'g')
    )
  );

drop policy if exists customer_store_branches_read_published
  on public.customer_store_branches;
create policy customer_store_branches_read_published
  on public.customer_store_branches
  for select to authenticated
  using (
    is_active
    and storefront_published
    and exists (
      select 1
      from public.customer_profiles profile
      where profile.id = (select auth.uid())
        and nullif(btrim(profile.city), '') is not null
        and nullif(btrim(customer_store_branches.city), '') is not null
        and regexp_replace(lower(btrim(profile.city)), '[[:space:]]+', ' ', 'g')
          = regexp_replace(
              lower(btrim(customer_store_branches.city)),
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
  v_branch_city text;
begin
  select storefront.opening_hours,
         coalesce(business.timezone, 'Asia/Manila'),
         branch.city,
         profile.city
    into v_hours, v_timezone, v_branch_city, v_customer_city
  from public.customer_storefronts storefront
  join public.businesses business
    on business.id = storefront.business_id
  join public.customer_store_branches branch
    on branch.business_id = storefront.business_id
   and branch.id = new.branch_id
   and branch.is_active
  join public.customer_profiles profile
    on profile.id = new.customer_user_id
  where storefront.business_id = new.business_id
    and storefront.is_published;

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

  v_local_time := to_char(now() at time zone v_timezone, 'HH24:MI');
  if v_local_time < v_open or v_local_time >= v_close then
    raise exception 'storefront is currently closed';
  end if;

  return new;
end;
$$;

notify pgrst, 'reload schema';