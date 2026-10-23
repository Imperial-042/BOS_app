-- ============================================================
-- 0013 — PRODUCT CATEGORIES
-- ============================================================

create table if not exists public.product_categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null
    references public.businesses(id)
    on delete cascade,
  name text not null,
  description text,
  color_hex text,
  sort_order integer not null default 0,
is_active boolean not null default true,
created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists ix_product_categories_business
  on public.product_categories (business_id, is_active, sort_order);

-- Keep updated_at consistent with the rest of the cloud schema.
drop trigger if exists product_categories_set_updated_at
  on public.product_categories;

create trigger product_categories_set_updated_at
before update on public.product_categories
for each row
execute function public.set_updated_at();

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

alter table public.product_categories enable row level security;

drop policy if exists product_categories_select
  on public.product_categories;

create policy product_categories_select
on public.product_categories
for select
to authenticated
using (
  exists (
    select 1
    from public.business_memberships bm
    where bm.business_id = product_categories.business_id
      and bm.user_id = auth.uid()
      and bm.status = 'active'
  )
);

drop policy if exists product_categories_insert
  on public.product_categories;

create policy product_categories_insert
on public.product_categories
for insert
to authenticated
with check (
  exists (
    select 1
    from public.business_memberships bm
    where bm.business_id = product_categories.business_id
      and bm.user_id = auth.uid()
      and bm.status = 'active'
  )
);

drop policy if exists product_categories_update
  on public.product_categories;

create policy product_categories_update
on public.product_categories
for update
to authenticated
using (
  exists (
    select 1
    from public.business_memberships bm
    where bm.business_id = product_categories.business_id
      and bm.user_id = auth.uid()
      and bm.status = 'active'
  )
)
with check (
  exists (
    select 1
    from public.business_memberships bm
    where bm.business_id = product_categories.business_id
      and bm.user_id = auth.uid()
      and bm.status = 'active'
  )
);

drop policy if exists product_categories_delete
  on public.product_categories;

create policy product_categories_delete
on public.product_categories
for delete
to authenticated
using (
  exists (
    select 1
    from public.business_memberships bm
    where bm.business_id = product_categories.business_id
      and bm.user_id = auth.uid()
      and bm.status = 'active'
  )
);

-- Refresh PostgREST schema cache.
notify pgrst, 'reload schema';