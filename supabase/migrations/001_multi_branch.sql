-- ============================================================================
-- BOS multi-branch: SERVER migration. Run ONCE in the Supabase SQL Editor.
-- Runs in one transaction: if anything fails, nothing is applied.
-- Run this BEFORE installing any app build that knows about branches.
-- ============================================================================
begin;

create extension if not exists "uuid-ossp" with schema extensions;

-- 1. Helper functions -------------------------------------------------------
create or replace function public.bos_is_member(p_business uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.business_memberships m
    where m.business_id = p_business
      and m.user_id = (select auth.uid())
      and m.status = 'active');
$$;

-- True when the caller's role (custom roles resolve to their base role) is in p_roles.
create or replace function public.bos_role_in(p_business uuid, p_roles text[])
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.business_memberships m
    left join public.custom_roles cr
      on left(m.role, 2) = 'c_'
     and cr.business_id = m.business_id
     and cr.id::text = substr(m.role, 3)
    where m.business_id = p_business
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and coalesce(cr.base_role, m.role) = any (p_roles));
$$;

revoke all on function public.bos_is_member(uuid), public.bos_role_in(uuid, text[]) from public, anon;
grant execute on function public.bos_is_member(uuid), public.bos_role_in(uuid, text[]) to authenticated;

-- 2. New tables --------------------------------------------------------------
create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  name text not null check (char_length(btrim(name)) between 1 and 80),
  code text,
  address text,
  phone text,
  cash_account_id uuid,
  is_headquarters boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, code)
);
create unique index if not exists ux_branches_one_hq
  on public.branches (business_id) where is_headquarters;

create table if not exists public.branch_members (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  branch_id uuid not null,
  user_id uuid not null references auth.users(id),
  role text,
  status text not null default 'active' check (status in ('active','suspended','removed')),
  updated_at timestamptz not null default now(),
  foreign key (branch_id, business_id) references public.branches (id, business_id),
  unique (branch_id, user_id)
);

create table if not exists public.product_stock_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  branch_id uuid not null,
  product_id uuid not null references public.products(id) on delete cascade,
  movement_type text not null,
  quantity double precision not null,
  reference_type text,
  reference_id text,
  notes text,
  movement_date timestamptz not null default now(),
  created_at timestamptz not null default now(),
  foreign key (branch_id, business_id) references public.branches (id, business_id)
);
create index if not exists ix_psm_branch_product on public.product_stock_movements (branch_id, product_id);

create table if not exists public.stock_transfers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  from_branch_id uuid not null,
  to_branch_id uuid not null,
  status text not null default 'in_transit' check (status in ('in_transit','received','cancelled')),
  notes text,
  created_by text,
  received_by text,
  shipped_at timestamptz,
  received_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (from_branch_id, business_id) references public.branches (id, business_id),
  foreign key (to_branch_id, business_id) references public.branches (id, business_id),
  check (from_branch_id <> to_branch_id)
);

create table if not exists public.stock_transfer_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  transfer_id uuid not null references public.stock_transfers(id) on delete cascade,
  item_type text not null check (item_type in ('supply','product')),
  item_id uuid not null,
  item_name text not null,
  unit text not null default '',
  quantity double precision not null check (quantity > 0),
  received_quantity double precision
);

-- 3. RLS for the new tables ---------------------------------------------------
alter table public.branches enable row level security;
alter table public.branch_members enable row level security;
alter table public.product_stock_movements enable row level security;
alter table public.stock_transfers enable row level security;
alter table public.stock_transfer_items enable row level security;

do $$
declare t text;
begin
  -- everyone in the business can read
  foreach t in array array['branches','branch_members','product_stock_movements','stock_transfers','stock_transfer_items'] loop
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.bos_is_member(business_id))', t || '_read', t);
    execute format('drop policy if exists %I on public.%I', t || '_write', t);
  end loop;
end $$;

-- branches + assignments: owner / manager
create policy branches_write on public.branches for all to authenticated
  using (public.bos_role_in(business_id, array['owner','manager']))
  with check (public.bos_role_in(business_id, array['owner','manager']));
create policy branch_members_write on public.branch_members for all to authenticated
  using (public.bos_role_in(business_id, array['owner','manager']))
  with check (public.bos_role_in(business_id, array['owner','manager']));

-- stock movements: any active member (sales deduct stock). Tighten later per branch.
create policy product_stock_movements_write on public.product_stock_movements for all to authenticated
  using (public.bos_is_member(business_id))
  with check (public.bos_is_member(business_id));

-- transfers: owner / manager / inventory
create policy stock_transfers_write on public.stock_transfers for all to authenticated
  using (public.bos_role_in(business_id, array['owner','manager','inventory']))
  with check (public.bos_role_in(business_id, array['owner','manager','inventory']));
create policy stock_transfer_items_write on public.stock_transfer_items for all to authenticated
  using (public.bos_role_in(business_id, array['owner','manager','inventory']))
  with check (public.bos_role_in(business_id, array['owner','manager','inventory']));

-- 4. One "Main Branch" per existing business (id MUST match the app) ---------
insert into public.branches (id, business_id, name, code, is_headquarters)
select extensions.uuid_generate_v5(extensions.uuid_ns_url(), 'bos:branches:branch_main_' || b.id::text),
       b.id, 'Main Branch', 'MAIN', true
from public.businesses b
on conflict do nothing;

update public.branches br
set cash_account_id = a.id
from public.accounts a
where br.is_headquarters
  and br.cash_account_id is null
  and a.business_id = br.business_id
  and a.id = extensions.uuid_generate_v5(extensions.uuid_ns_url(), 'bos:accounts:acc_cash_' || br.business_id::text);

-- 5. Fill-in trigger: old app builds send no branch_id -> use the main branch ---
create or replace function public.fill_branch_id() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_table_name = 'inventory_movements' and new.business_id is null then
    select s.business_id into new.business_id from public.supplies s where s.id = new.supply_id;
  end if;
  if new.branch_id is null then
    select b.id into new.branch_id from public.branches b
    where b.business_id = new.business_id and b.is_headquarters limit 1;
  end if;
  return new;
end $$;

-- 6. branch_id columns ---------------------------------------------------------
do $$
declare t text;
begin
  -- shared finance tables: NULL = company-wide
  foreach t in array array['pos_sessions','pos_sales','pos_tables','inventory_movements',
      'journal_entries','income_transactions','expenses','shopping_carts','audit_logs',
      'schedule_shifts','attendance_records'] loop
    execute format('alter table public.%I add column if not exists branch_id uuid', t);
    execute format('alter table public.%I drop constraint if exists %I', t, t || '_branch_fk');
    execute format('alter table public.%I add constraint %I foreign key (branch_id, business_id) references public.branches (id, business_id)', t, t || '_branch_fk');
  end loop;

  -- operational tables: backfill to the main branch + auto-fill for old clients
  foreach t in array array['pos_sessions','pos_sales','pos_tables','inventory_movements',
      'shopping_carts','schedule_shifts','attendance_records'] loop
    execute format('update public.%I x set branch_id = b.id from public.branches b where b.business_id = x.business_id and b.is_headquarters and x.branch_id is null', t);
    execute format('drop trigger if exists a0_fill_branch on public.%I', t);
    execute format('create trigger a0_fill_branch before insert on public.%I for each row execute function public.fill_branch_id()', t);
  end loop;
end $$;

-- one open shift PER BRANCH
create unique index if not exists ux_pos_sessions_one_open
  on public.pos_sessions (branch_id) where status = 'open';

-- 7. Opening balances so SUM(movements) == today's stock (ids match the app) -----
insert into public.inventory_movements
  (id, business_id, supply_id, movement_type, unit, quantity, reference_type, notes, branch_id)
select extensions.uuid_generate_v5(extensions.uuid_ns_url(), 'bos:inventory_movements:opening_' || s.id::text),
       s.business_id, s.id, 'opening_balance', s.stock_unit,
       s.current_stock - coalesce((select sum(m.quantity) from public.inventory_movements m where m.supply_id = s.id), 0),
       'migration', 'Opening balance when branches were enabled', hq.id
from public.supplies s
join public.branches hq on hq.business_id = s.business_id and hq.is_headquarters
where abs(s.current_stock - coalesce((select sum(m.quantity) from public.inventory_movements m where m.supply_id = s.id), 0)) > 0.000001
on conflict (id) do nothing;

insert into public.product_stock_movements
  (id, business_id, branch_id, product_id, movement_type, quantity, reference_type, notes)
select extensions.uuid_generate_v5(extensions.uuid_ns_url(), 'bos:product_stock_movements:opening_' || p.id::text),
       p.business_id, hq.id, p.id, 'opening_balance', p.current_stock,
       'migration', 'Opening balance when branches were enabled'
from public.products p
join public.branches hq on hq.business_id = p.business_id and hq.is_headquarters
where p.tracking_type = 'stocked' and p.current_stock <> 0
on conflict (id) do nothing;

-- 8. Put the new tables on the change feed by cloning the trigger of `customers` --
do $$
declare def text; t text;
begin
  select pg_get_triggerdef(tg.oid) into def
  from pg_trigger tg
  where tg.tgrelid = 'public.customers'::regclass
    and not tg.tgisinternal
    and pg_get_triggerdef(tg.oid) ilike '%sync%'
  limit 1;

  if def is null then
    raise exception 'No sync-feed trigger found on public.customers. Nothing was changed. Send me the output of information_schema.triggers.';
  end if;
  if def ~ 'EXECUTE (FUNCTION|PROCEDURE) [^(]+\(\s*[^)\s]' then
    raise exception 'The feed trigger passes arguments (%). Nothing was changed. Send me this definition.', def;
  end if;

  raise notice 'Cloning feed trigger: %', def;
  foreach t in array array['branches','branch_members','product_stock_movements','stock_transfers','stock_transfer_items'] loop
    -- customers_sync_change ON public.customers -> <t>_sync_change ON public.<t>
    execute replace(def, 'customers', t);
  end loop;
end $$;

-- 9. create_business_with_owner now also creates the Main Branch --------------
create or replace function public.create_business_with_owner(
  p_name text,
  p_business_type text default null,
  p_industry text default null,
  p_currency_code text default 'PHP',
  p_timezone text default 'Asia/Manila',
  p_id uuid default null
) returns uuid
language plpgsql security definer set search_path to '' as $function$
declare
  v_business_id uuid;
  v_user_id uuid := (select auth.uid());
  v_owner uuid;
begin
  if v_user_id is null then raise exception 'not authenticated'; end if;
  if not public.is_current_device_session_active() then
    raise exception 'device authorization required';
  end if;
  if btrim(p_name) = '' then raise exception 'business name is required'; end if;

  if p_id is not null then
    select owner_user_id into v_owner from public.businesses where id = p_id;
    if found then
      if v_owner <> v_user_id then raise exception 'business id already in use'; end if;
      insert into public.business_memberships (business_id, user_id, role)
      select p_id, v_user_id, 'owner'
      where not exists (select 1 from public.business_memberships
                        where business_id = p_id and user_id = v_user_id and status = 'active');
      insert into public.branches (id, business_id, name, code, is_headquarters, cash_account_id)
      values (extensions.uuid_generate_v5(extensions.uuid_ns_url(), 'bos:branches:branch_main_' || p_id::text),
              p_id, 'Main Branch', 'MAIN', true,
              extensions.uuid_generate_v5(extensions.uuid_ns_url(), 'bos:accounts:acc_cash_' || p_id::text))
      on conflict do nothing;
      return p_id;
    end if;
  end if;

  insert into public.businesses (id, owner_user_id, name, business_type, industry, business_category,
                                 currency_code, timezone)
  values (coalesce(p_id, gen_random_uuid()), v_user_id, btrim(p_name), p_business_type, p_industry,
          p_industry, coalesce(p_currency_code, 'PHP'), coalesce(p_timezone, 'Asia/Manila'))
  returning id into v_business_id;

  insert into public.business_memberships (business_id, user_id, role)
  values (v_business_id, v_user_id, 'owner');

  insert into public.branches (id, business_id, name, code, is_headquarters, cash_account_id)
  values (extensions.uuid_generate_v5(extensions.uuid_ns_url(), 'bos:branches:branch_main_' || v_business_id::text),
          v_business_id, 'Main Branch', 'MAIN', true,
          extensions.uuid_generate_v5(extensions.uuid_ns_url(), 'bos:accounts:acc_cash_' || v_business_id::text))
  on conflict do nothing;

  return v_business_id;
end;
$function$;

commit;

-- ============================================================================
-- VERIFY (run separately afterwards)
-- select count(*) from public.businesses;                       -- N
-- select count(*) from public.branches where is_headquarters;   -- must equal N
-- select count(*) from public.pos_sessions where branch_id is null;  -- 0
-- select tgname from pg_trigger where tgrelid = 'public.branches'::regclass and not tgisinternal;
-- ============================================================================