create table if not exists public.product_option_groups (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  name text not null,
  is_required boolean not null default false,
  allow_multiple boolean not null default false,
  min_selections integer not null default 0 check (min_selections >= 0),
  max_selections integer check (max_selections is null or max_selections >= min_selections),
  is_add_on boolean not null default false,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  unique (id, product_id)
);

create table if not exists public.product_option_choices (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  group_id uuid not null references public.product_option_groups(id) on delete cascade,
  name text not null,
  price_delta_cents integer not null default 0,
  inventory_product_id uuid references public.products(id) on delete set null,
  inventory_quantity double precision not null default 0 check (inventory_quantity >= 0),
  sort_order integer not null default 0,
  is_active boolean not null default true,
  foreign key (group_id, product_id) references public.product_option_groups(id, product_id)
    on delete cascade
);

create index if not exists product_option_groups_product_idx
  on public.product_option_groups(product_id, is_active, sort_order);
create index if not exists product_option_choices_group_idx
  on public.product_option_choices(group_id, is_active, sort_order);

alter table public.product_option_groups enable row level security;
alter table public.product_option_choices enable row level security;

revoke all on public.product_option_groups, public.product_option_choices
  from anon;
grant select, insert, update, delete
  on public.product_option_groups, public.product_option_choices
  to authenticated;

create policy product_option_groups_read_business
  on public.product_option_groups for select to authenticated
  using (public.is_business_member(business_id));
create policy product_option_groups_read_published
  on public.product_option_groups for select to authenticated
  using (exists (
    select 1 from public.customer_catalog_items c
    where c.id = product_option_groups.product_id
      and c.business_id = product_option_groups.business_id
      and c.is_available
  ));
create policy product_option_groups_manage
  on public.product_option_groups for all to authenticated
  using (public.is_business_manager(business_id))
  with check (public.is_business_manager(business_id));

create policy product_option_choices_read_business
  on public.product_option_choices for select to authenticated
  using (public.is_business_member(business_id));
create policy product_option_choices_read_published
  on public.product_option_choices for select to authenticated
  using (exists (
    select 1 from public.customer_catalog_items c
    where c.id = product_option_choices.product_id
      and c.business_id = product_option_choices.business_id
      and c.is_available
  ));
create policy product_option_choices_manage
  on public.product_option_choices for all to authenticated
  using (public.is_business_manager(business_id))
  with check (
    public.is_business_manager(business_id)
    and exists (
      select 1
      from public.product_option_groups g
      where g.id = product_option_choices.group_id
        and g.product_id = product_option_choices.product_id
        and g.business_id = product_option_choices.business_id
    )
  );
