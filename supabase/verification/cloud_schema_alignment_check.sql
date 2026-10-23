-- Cloud schema alignment checks (plain SQL, no pgTAP required).
--
-- Run against a LOCAL or throwaway database with every migration applied:
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/verification/cloud_schema_alignment_check.sql
--
-- Creates and rolls back its own users/businesses. Never run on production.

begin;

create temp table check_results (name text, ok boolean, detail text);
grant all on check_results to public;

create function pg_temp.as_session(p_user uuid, p_session uuid) returns void
language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user, 'session_id', p_session, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $$;

create function pg_temp.as_anon() returns void
language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', '', true);
  set local role anon;
end $$;

create function pg_temp.record(p_name text, p_ok boolean, p_detail text default null)
returns void language plpgsql as $$
begin
  insert into check_results values (p_name, coalesce(p_ok, false), p_detail);
end $$;

create function pg_temp.expect_ok(p_name text, p_sql text) returns void
language plpgsql as $$
declare v_msg text;
begin
  begin
    execute p_sql;
    perform pg_temp.record(p_name, true);
  exception when others then
    get stacked diagnostics v_msg = message_text;
    perform pg_temp.record(p_name, false, v_msg);
  end;
end $$;

create function pg_temp.expect_error(p_name text, p_sql text) returns void
language plpgsql as $$
declare v_msg text;
begin
  begin
    execute p_sql;
    perform pg_temp.record(p_name, false, 'statement unexpectedly succeeded');
  exception when others then
    get stacked diagnostics v_msg = message_text;
    perform pg_temp.record(p_name, true, v_msg);
  end;
end $$;

do $$
declare
  owner_u constant uuid := '00000000-0000-4000-8000-0000000000a1';
  staff_u constant uuid := '00000000-0000-4000-8000-0000000000a2';
  other_u constant uuid := '00000000-0000-4000-8000-0000000000a3';
  biz constant uuid := '00000000-0000-4000-8000-0000000000b1';
  biz2 constant uuid := '00000000-0000-4000-8000-0000000000b2';
  s_owner constant uuid := '00000000-0000-4000-8000-00000000c001';
  s_staff constant uuid := '00000000-0000-4000-8000-00000000c002';
  s_other constant uuid := '00000000-0000-4000-8000-00000000c003';
  d_owner constant uuid := '00000000-0000-4000-8000-0000000d0001';
  d_staff constant uuid := '00000000-0000-4000-8000-0000000d0002';
  d_other constant uuid := '00000000-0000-4000-8000-0000000d0003';
  acct constant uuid := '00000000-0000-4000-8000-0000000a0001';
  acct2 constant uuid := '00000000-0000-4000-8000-0000000a0002';
  cat constant uuid := '00000000-0000-4000-8000-0000000ca001';
  cat2 constant uuid := '00000000-0000-4000-8000-0000000ca002';
  sup constant uuid := '00000000-0000-4000-8000-00000000e001';
  prod constant uuid := '00000000-0000-4000-8000-0000000f0001';
  sess constant uuid := '00000000-0000-4000-8000-00000005e001';
  sale constant uuid := '00000000-0000-4000-8000-00000005a001';
  recipe constant uuid := '00000000-0000-4000-8000-000000000e01';
  cart constant uuid := '00000000-0000-4000-8000-0000000ca00a';
  item constant uuid := '00000000-0000-4000-8000-0000000ca00b';
  n int;
begin
  -- Fixtures as superuser.
  insert into auth.users (id, email) values
    (owner_u, 'o@example.test'), (staff_u, 's@example.test'), (other_u, 'x@example.test');
  insert into public.businesses (id, owner_user_id, name) values
    (biz, owner_u, 'Alpha'), (biz2, other_u, 'Beta');
  insert into public.business_memberships (business_id, user_id, role) values
    (biz, owner_u, 'owner'), (biz, staff_u, 'employee'), (biz2, other_u, 'owner');
  insert into public.accounts (id, business_id, name, type, is_payment_account)
    values (acct, biz, 'Cash', 'asset', true), (acct2, biz2, 'Beta cash', 'asset', true);
  insert into public.product_categories (id, business_id, name) values (cat2, biz2, 'Other biz');

  perform pg_temp.as_session(owner_u, s_owner);
  perform public.register_current_device(d_owner, 'Owner phone', 'android', 'mobile', '1');
  perform pg_temp.as_session(staff_u, s_staff);
  perform public.register_current_device(d_staff, 'Staff phone', 'android', 'mobile', '1');
  perform pg_temp.as_session(other_u, s_other);
  perform public.register_current_device(d_other, 'Other phone', 'android', 'mobile', '1');

  -- Everything the bootstrap uploads, as the owner on an active device.
  perform pg_temp.as_session(owner_u, s_owner);
  perform pg_temp.expect_ok('product category with sort_order',
    format($f$insert into public.product_categories (id, business_id, name, sort_order) values (%L, %L, 'Drinks', 2)$f$, cat, biz));
  perform pg_temp.expect_ok('supply with extended columns',
    format($f$insert into public.supplies (id, business_id, name, stock_unit, brand, unit_quantity, unit, minimum_stock, units_per_purchase, category_id, sort_order, is_sold_by_weight) values (%L, %L, 'Sugar', 'kg', 'Brand', 1, 'kg', 1, 1, %L, 1, true)$f$, sup, biz, cat));
  perform pg_temp.expect_ok('product with extended columns',
    format($f$insert into public.products (id, business_id, name, product_type, tracking_type, unit, category_id, description, is_sellable, sort_order, low_stock_threshold) values (%L, %L, 'Tea', 'finished', 'none', 'cup', %L, 'hot', true, 1, 5)$f$, prod, biz, cat));
  perform pg_temp.expect_ok('inventory movement without business_id',
    format($f$insert into public.inventory_movements (id, supply_id, movement_type, quantity, unit, reference_type, reference_id) values (gen_random_uuid(), %L, 'purchase', 5, 'kg', 'cart', 'x')$f$, sup));
  perform pg_temp.expect_ok('payment provider',
    format($f$insert into public.payment_providers (business_id, name, kind) values (%L, 'GCash', 'ewallet')$f$, biz));
  perform pg_temp.expect_ok('pos session',
    format($f$insert into public.pos_sessions (id, business_id) values (%L, %L)$f$, sess, biz));
  perform pg_temp.expect_ok('pos sale',
    format($f$insert into public.pos_sales (id, business_id, total_amount, payment_account_id, session_id) values (%L, %L, 500, %L, %L)$f$, sale, biz, acct, sess));
  perform pg_temp.expect_ok('pos sale item',
    format($f$insert into public.pos_sale_items (sale_id, product_id, product_name, unit, unit_price, quantity, line_total) values (%L, %L, 'Tea', 'cup', 250, 2, 500)$f$, sale, prod));
  perform pg_temp.expect_ok('pos sale payment',
    format($f$insert into public.pos_sale_payments (sale_id, amount_paid, paid_at) values (%L, 500, now())$f$, sale));
  perform pg_temp.expect_ok('pos sale tender',
    format($f$insert into public.pos_sale_tenders (sale_id, account_id, amount, tendered, change_given) values (%L, %L, 500, 500, 0)$f$, sale, acct));
  perform pg_temp.expect_ok('recipe',
    format($f$insert into public.recipes (id, product_id) values (%L, %L)$f$, recipe, prod));
  perform pg_temp.expect_ok('recipe component',
    format($f$insert into public.recipe_components (recipe_id, component_type, supply_id, quantity_required, unit) values (%L, 'supply', %L, 1, 'kg')$f$, recipe, sup));
  perform pg_temp.expect_ok('shopping cart',
    format($f$insert into public.shopping_carts (id, business_id, cart_date, total_amount) values (%L, %L, now(), 100)$f$, cart, biz));
  perform pg_temp.expect_ok('shopping cart item',
    format($f$insert into public.shopping_cart_items (id, cart_id, supply_id, item_name, unit_price, line_total) values (%L, %L, %L, 'Sugar', 100, 100)$f$, item, cart, sup));
  perform pg_temp.expect_ok('supply price history',
    format($f$insert into public.supply_price_history (supply_id, price, store_name, recorded_date, shopping_cart_item_id) values (%L, 100, 'Store', now(), %L)$f$, sup, item));
  perform pg_temp.expect_ok('manager sets a permission override',
    format($f$insert into public.role_permission_overrides (business_id, role, permission, granted) values (%L, 'employee', 'reports.view', true)$f$, biz));
  perform pg_temp.expect_ok('upsert by id (bootstrap style)',
    format($f$insert into public.pos_sessions (id, business_id, notes) values (%L, %L, 'again') on conflict (id) do update set notes = excluded.notes$f$, sess, biz));

  select count(*) into n from public.inventory_movements;
  perform pg_temp.record('movement business derived from supply',
    (select business_id from public.inventory_movements limit 1) = biz);

  -- Change feed covers the new tables, children included.
  reset role;
  perform pg_temp.record('change feed has entries for every new table',
    (select count(distinct entity_type) from public.sync_changes
      where business_id = biz and entity_type in (
        'product_categories','payment_providers','pos_sessions','pos_sales',
        'pos_sale_items','pos_sale_payments','pos_sale_tenders','recipes',
        'recipe_components','shopping_carts','shopping_cart_items',
        'supply_price_history','role_permission_overrides')) = 13,
    (select string_agg(distinct entity_type, ',') from public.sync_changes where business_id = biz));
  perform pg_temp.record('feed uses create/update/delete only',
    (select count(*) from public.sync_changes where operation not in ('create','update','delete')) = 0);

  -- Business profile edits reach the change feed (second devices pull them).
  perform pg_temp.as_session(owner_u, s_owner);
  perform pg_temp.expect_ok('owner saves the business profile',
    format($f$update public.businesses set owner_name = 'Maria', business_category = 'Food', starting_capital = 500000 where id = %L$f$, biz));
  reset role;
  perform pg_temp.record('profile edit is in the change feed',
    exists (select 1 from public.sync_changes
            where business_id = biz and entity_type = 'businesses' and entity_id = biz));
  perform pg_temp.as_session(staff_u, s_staff);
  update public.businesses set name = 'Hijacked' where id = biz;
  get diagnostics n = row_count;
  perform pg_temp.record('employee cannot edit the business profile', n = 0, n::text);
  -- Same-business integrity.
  perform pg_temp.as_session(owner_u, s_owner);
  perform pg_temp.expect_error('product cannot use another business category',
    format($f$update public.products set category_id = %L where id = %L$f$, cat2, prod));
  perform pg_temp.expect_error('sale cannot use another business account',
    format($f$insert into public.pos_sales (business_id, payment_account_id) values (%L, %L)$f$, biz, acct2));

  -- Role limits.
  perform pg_temp.as_session(staff_u, s_staff);
  select count(*) into n from public.pos_sales;
  perform pg_temp.record('employee can read sales', n = 1, n::text);
  perform pg_temp.expect_ok('employee can record a sale item',
    format($f$insert into public.pos_sale_items (sale_id, product_name, unit, unit_price, quantity, line_total) values (%L, 'Tea', 'cup', 250, 1, 250)$f$, sale));
  perform pg_temp.expect_error('employee cannot change permission overrides',
    format($f$insert into public.role_permission_overrides (business_id, role, permission, granted) values (%L, 'employee', 'x.y', true)$f$, biz));
  delete from public.pos_sales where id = sale;
  get diagnostics n = row_count;
  perform pg_temp.record('employee cannot delete sales', n = 0, n::text);

  -- Other business and revoked device.
  perform pg_temp.as_session(other_u, s_other);
  select count(*) into n from public.pos_sales;
  perform pg_temp.record('other business sees no sales', n = 0, n::text);
  select count(*) into n from public.pos_sale_items;
  perform pg_temp.record('other business sees no sale items', n = 0, n::text);
  select count(*) into n from public.recipe_components;
  perform pg_temp.record('other business sees no recipe components', n = 0, n::text);
  perform pg_temp.expect_error('other business cannot add items to a sale',
    format($f$insert into public.pos_sale_items (sale_id, product_name, unit, unit_price, quantity, line_total) values (%L, 'x', 'u', 1, 1, 1)$f$, sale));

  perform pg_temp.as_session(owner_u, s_owner);
  perform public.revoke_current_user_device(d_owner) where false;
  reset role;
  update public.device_sessions set status = 'revoked' where session_id = s_owner;
  perform pg_temp.as_session(owner_u, s_owner);
  select count(*) into n from public.pos_sales;
  perform pg_temp.record('revoked session sees no sales', n = 0, n::text);
  select count(*) into n from public.shopping_cart_items;
  perform pg_temp.record('revoked session sees no cart items', n = 0, n::text);
  perform pg_temp.expect_error('revoked session cannot write',
    format($f$insert into public.payment_providers (business_id, name, kind) values (%L, 'x', 'cash')$f$, biz));

  -- anon.
  perform pg_temp.as_anon();
  perform pg_temp.expect_error('anon cannot read sales', 'select * from public.pos_sales');
  perform pg_temp.expect_error('anon cannot read recipes', 'select * from public.recipes');
  reset role;
end $$;

reset role;
select name, case when ok then 'PASS' else 'FAIL' end as result, detail from check_results order by ctid;

do $$
declare n int;
begin
  select count(*) into n from check_results where not ok;
  if n > 0 then
    raise exception '% cloud schema check(s) failed', n;
  end if;
  raise notice 'All % cloud schema checks passed.', (select count(*) from check_results);
end $$;

rollback;
