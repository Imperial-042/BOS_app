begin;

create schema if not exists extensions;
create extension if not exists postgis with schema extensions;

create table if not exists public.branch_locations (
  branch_id uuid primary key references public.branches (id) on delete cascade,
  business_id uuid not null references public.businesses (id) on delete cascade,
  country text,
  region text,
  province text,
  city text,
  barangay text,
  street_address text,
  building_or_unit text,
  postal_code text,
  landmark text,
  formatted_address text,
  latitude double precision,
  longitude double precision,
  location_accuracy_meters double precision,
  location_verified text not null default 'unverified'
    check (location_verified in ('unverified', 'confirmed', 'updated')),
  location_updated_at timestamptz not null default now(),
  point extensions.geography(point, 4326),
  check (latitude is null or latitude between -90 and 90),
  check (longitude is null or longitude between -180 and 180),
  check (
    (latitude is null and longitude is null)
    or (latitude is not null and longitude is not null)
  ),
  unique (business_id, branch_id)
);

create index if not exists branch_locations_business_idx
  on public.branch_locations (business_id);
create index if not exists branch_locations_point_gist_idx
  on public.branch_locations using gist (point);

create or replace function public.sync_branch_location_point()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.latitude is null or new.longitude is null then
    new.point := null;
  else
    new.point := extensions.st_setsrid(
      extensions.st_makepoint(new.longitude, new.latitude), 4326
    )::extensions.geography;
  end if;
  new.location_updated_at := now();
  return new;
end;
$$;

drop trigger if exists branch_locations_point_trigger
  on public.branch_locations;
create trigger branch_locations_point_trigger
  before insert or update on public.branch_locations
  for each row execute function public.sync_branch_location_point();

create table if not exists public.customer_addresses (
  id uuid primary key default gen_random_uuid(),
  customer_user_id uuid not null references public.customer_profiles (id)
    on delete cascade,
  label text not null check (label in ('home', 'work', 'other')),
  recipient_name text not null,
  contact_number text not null,
  country text,
  region text,
  province text,
  city text,
  barangay text,
  street_address text,
  building_or_unit text,
  postal_code text,
  landmark text,
  formatted_address text,
  latitude double precision,
  longitude double precision,
  location_accuracy_meters double precision,
  point extensions.geography(point, 4326),
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (latitude is null or latitude between -90 and 90),
  check (longitude is null or longitude between -180 and 180),
  check (
    (latitude is null and longitude is null)
    or (latitude is not null and longitude is not null)
  )
);

create unique index if not exists customer_addresses_default_idx
  on public.customer_addresses (customer_user_id)
  where is_default;
create index if not exists customer_addresses_customer_idx
  on public.customer_addresses (customer_user_id, updated_at desc);
create index if not exists customer_addresses_point_gist_idx
  on public.customer_addresses using gist (point);

create or replace function public.sync_customer_address_point()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.latitude is null or new.longitude is null then
    new.point := null;
  else
    new.point := extensions.st_setsrid(
      extensions.st_makepoint(new.longitude, new.latitude), 4326
    )::extensions.geography;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists customer_addresses_point_trigger
  on public.customer_addresses;
create trigger customer_addresses_point_trigger
  before insert or update on public.customer_addresses
  for each row execute function public.sync_customer_address_point();

create or replace function public.clear_other_default_customer_addresses()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.is_default then
    update public.customer_addresses
       set is_default = false
     where customer_user_id = new.customer_user_id
       and id <> new.id
       and is_default;
  end if;
  return new;
end;
$$;

drop trigger if exists customer_addresses_default_trigger
  on public.customer_addresses;
create trigger customer_addresses_default_trigger
  before insert or update of is_default, customer_user_id
  on public.customer_addresses
  for each row execute function public.clear_other_default_customer_addresses();

alter table public.customer_orders
  add column if not exists fulfillment_type text not null default 'pickup'
    check (fulfillment_type in ('pickup', 'delivery')),
  add column if not exists delivery_address_snapshot jsonb,
  add column if not exists delivery_latitude double precision,
  add column if not exists delivery_longitude double precision,
  add column if not exists delivery_accuracy_meters double precision;

alter table public.branch_locations enable row level security;
alter table public.customer_addresses enable row level security;

drop policy if exists branch_locations_manage on public.branch_locations;
create policy branch_locations_manage on public.branch_locations
  for all to authenticated
  using (public.is_business_manager(business_id))
  with check (
    public.is_business_manager(business_id)
    and exists (
      select 1 from public.branches b
      where b.id = branch_id and b.business_id = branch_locations.business_id
    )
  );

drop policy if exists branch_locations_public_read on public.branch_locations;
create policy branch_locations_public_read on public.branch_locations
  for select to authenticated
  using (
    exists (
      select 1
      from public.customer_store_branches b
      join public.customer_storefronts s on s.business_id = b.business_id
      where b.id = branch_id
        and b.business_id = branch_locations.business_id
        and b.is_active
        and b.storefront_published
        and s.is_published
    )
  );

drop policy if exists customer_addresses_self_manage on public.customer_addresses;
create policy customer_addresses_self_manage on public.customer_addresses
  for all to authenticated
  using (customer_user_id = (select auth.uid()))
  with check (customer_user_id = (select auth.uid()));

drop policy if exists customer_addresses_order_read on public.customer_addresses;
create policy customer_addresses_order_read on public.customer_addresses
  for select to authenticated
  using (
    exists (
      select 1
      from public.customer_orders o
      where o.customer_user_id = customer_addresses.customer_user_id
        and o.delivery_address_snapshot->>'address_id' = customer_addresses.id::text
        and public.is_business_manager(o.business_id)
    )
  );

commit;
