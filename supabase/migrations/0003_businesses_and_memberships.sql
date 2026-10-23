-- 0003_businesses_and_memberships.sql
-- The multi-tenant core: businesses + who belongs to them.

-- ---------------------------------------------------------------------------
-- businesses
-- ---------------------------------------------------------------------------
create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users (id) on delete restrict,
  name text not null,
  legal_name text,
  business_type text,
  industry text,
  description text,
  email text,
  phone text,
  address text,
  barangay text,
  city text,
  province text,
  country text,
  postal_code text,
  currency_code text not null default 'PHP',
  timezone text not null default 'Asia/Manila',
  logo_path text,
  starting_capital bigint not null default 0, -- cents
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Names are NOT unique — two tenants may both be called "My Store".
create index businesses_owner_user_id_idx on public.businesses (owner_user_id);

create trigger businesses_set_updated_at
  before update on public.businesses
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- business_memberships
-- ---------------------------------------------------------------------------
-- Stable UUID id; one active membership per (business, user). Role ids match
-- the app's BosRole ids; extend by adding new ids, no schema change needed.
create table public.business_memberships (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in (
    'owner', 'manager', 'accountant', 'cashier', 'inventory', 'employee'
  )),
  status text not null default 'active' check (status in (
    'invited', 'active', 'suspended', 'removed'
  )),
  invited_by uuid references auth.users (id),
  joined_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- At most one non-removed membership per user per business.
create unique index business_memberships_business_user_key
  on public.business_memberships (business_id, user_id)
  where status <> 'removed';

-- Single-owner model: at most one live owner per business.
create unique index business_memberships_one_owner_idx
  on public.business_memberships (business_id)
  where role = 'owner' and status <> 'removed';

-- RLS lookup path: auth.uid() -> memberships -> business_id.
create index business_memberships_user_id_idx
  on public.business_memberships (user_id, status);
create index business_memberships_business_id_idx
  on public.business_memberships (business_id);

create trigger business_memberships_set_updated_at
  before update on public.business_memberships
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- create_business_with_owner
-- ---------------------------------------------------------------------------
-- Atomic business creation: the business row AND its owner membership land
-- together or not at all. Runs as the function owner (security definer) so
-- the sanctioned creation path isn't blocked by RLS; authorization is still
-- enforced by requiring an authenticated caller and stamping auth.uid() as
-- both owner_user_id and the membership's user_id — the caller can never
-- create a business owned by someone else.
create or replace function public.create_business_with_owner(
  p_name text,
  p_business_type text default null,
  p_industry text default null,
  p_currency_code text default 'PHP',
  p_timezone text default 'Asia/Manila'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if btrim(p_name) = '' then
    raise exception 'business name is required';
  end if;

  insert into public.businesses (
    owner_user_id, name, business_type, industry, currency_code, timezone
  ) values (
    auth.uid(), btrim(p_name), p_business_type, p_industry,
    coalesce(p_currency_code, 'PHP'), coalesce(p_timezone, 'Asia/Manila')
  )
  returning id into v_business_id;

  insert into public.business_memberships (business_id, user_id, role)
  values (v_business_id, auth.uid(), 'owner');

  return v_business_id;
end;
$$;
