-- Record committed business-row changes on the server instead of accepting
-- client-authored rows as verified audit evidence.

begin;

alter table public.audit_logs
  add column if not exists source text not null default 'client_reported';

alter table public.audit_logs
  drop constraint if exists audit_logs_source_chk,
  add constraint audit_logs_source_chk
    check (source in ('database', 'client_reported'));

alter table public.audit_logs enable row level security;
alter table public.audit_logs force row level security;

drop policy if exists audit_logs_insert_own on public.audit_logs;
revoke all on public.audit_logs from public, anon, authenticated;
grant select, insert on public.audit_logs to authenticated;

drop policy if exists audit_logs_insert_client_report
  on public.audit_logs;
create policy audit_logs_insert_client_report on public.audit_logs
  for insert to authenticated
  with check (
    source = 'client_reported'
    and user_id = (select auth.uid())
    and exists (
      select 1
      from public.business_memberships m
      where m.business_id = audit_logs.business_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'
    )
  );

create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;

create or replace function app_private.redact_audit_jsonb(p_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if jsonb_typeof(p_value) = 'object' then
    select coalesce(
      pg_catalog.jsonb_object_agg(
        e.key,
        case
          when pg_catalog.lower(e.key) ~
            '(password|passcode|secret|token|hash|salt|api[_]?key)'
            then '"***"'::jsonb
          else app_private.redact_audit_jsonb(e.value)
        end
      ),
      '{}'::jsonb
    )
    into v_result
    from pg_catalog.jsonb_each(p_value) as e;
    return v_result;
  elsif jsonb_typeof(p_value) = 'array' then
    select coalesce(
      pg_catalog.jsonb_agg(app_private.redact_audit_jsonb(e.value)),
      '[]'::jsonb
    )
    into v_result
    from pg_catalog.jsonb_array_elements(p_value) as e;
    return v_result;
  end if;
  return p_value;
end;
$$;

revoke all on function app_private.redact_audit_jsonb(jsonb)
  from public, anon, authenticated;

create or replace function public.capture_business_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb;
  v_old jsonb;
  v_business_id uuid;
  v_branch_id uuid;
  v_entity_id text;
  v_parent_id uuid;
  v_actor_id uuid;
  v_actor_name text;
  v_actor_role text;
  v_operation text;
  v_module text;
  v_before jsonb;
  v_after jsonb;
  v_truncated boolean := false;
begin
  if tg_op = 'DELETE' then
    v_row := pg_catalog.to_jsonb(old);
    v_old := v_row;
    v_operation := 'delete';
  else
    v_row := pg_catalog.to_jsonb(new);
    v_operation := case tg_op
      when 'INSERT' then 'create'
      else 'update'
    end;
    if tg_op = 'UPDATE' then
      v_old := pg_catalog.to_jsonb(old);
    end if;
  end if;

  v_entity_id := v_row ->> 'id';
  v_branch_id := coalesce(
    nullif(v_row ->> 'branch_id', '')::uuid,
    nullif(v_row ->> 'from_branch_id', '')::uuid,
    nullif(v_row ->> 'to_branch_id', '')::uuid
  );
  if v_branch_id is null and tg_table_name = 'stock_transfer_items' then
    select t.from_branch_id
      into v_branch_id
    from public.stock_transfers t
    where t.id = (v_row ->> 'transfer_id')::uuid;
  end if;
  if tg_table_name = 'businesses' then
    v_business_id := (v_row ->> 'id')::uuid;
  elsif v_row ? 'business_id' then
    v_business_id := (v_row ->> 'business_id')::uuid;
  elsif tg_nargs >= 2 then
    v_parent_id := (v_row ->> tg_argv[1])::uuid;
    if tg_argv[0] = 'recipes' then
      select p.business_id into v_business_id
      from public.recipes r
      join public.products p on p.id = r.product_id
      where r.id = v_parent_id;
    else
      execute pg_catalog.format(
        'select business_id from public.%I where id = $1',
        tg_argv[0]
      )
      into v_business_id
      using v_parent_id;
    end if;
  end if;

  -- A cascading delete may remove the parent first; its audit event covers it.
  if v_business_id is null or v_entity_id is null then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  v_actor_id := coalesce(
    auth.uid(),
    '00000000-0000-0000-0000-000000000000'::uuid
  );

  if v_actor_id =
    '00000000-0000-0000-0000-000000000000'::uuid then
    v_actor_name := 'Database/system';
  else
    select nullif(pg_catalog.btrim(p.display_name), '')
      into v_actor_name
    from public.profiles p
    where p.id = v_actor_id;
    select m.role into v_actor_role
    from public.business_memberships m
    where m.business_id = v_business_id
      and m.user_id = v_actor_id
      and m.status = 'active'
    limit 1;
  end if;

  v_module := case
    when tg_table_name in (
      'accounts', 'journal_entries', 'ledger_lines', 'income_transactions',
      'expenses', 'receivable_payments', 'payable_payments',
      'supplier_purchases', 'account_transfers'
    ) then 'finance'
    when tg_table_name in (
      'pos_sessions', 'pos_sales', 'pos_sale_items', 'pos_sale_payments',
      'pos_sale_tenders', 'pos_tables', 'pos_order_types',
      'shopping_carts', 'shopping_cart_items'
    ) then 'sales'
    when tg_table_name in (
      'attendance_records', 'schedule_shifts', 'leave_requests',
      'payroll_profiles', 'payroll_runs', 'payroll_items'
    ) then 'people'
    when tg_table_name in (
      'business_memberships', 'business_invites', 'branch_members',
      'custom_roles', 'role_labels', 'role_permission_overrides',
      'user_devices', 'device_sessions'
    ) then 'administration'
    when tg_table_name in (
      'supplies', 'inventory_movements', 'products', 'product_categories',
      'product_stock_movements', 'recipes', 'recipe_components',
      'supply_price_history', 'stock_transfers', 'stock_transfer_items'
    ) then 'inventory'
    else 'administration'
  end;

  if v_old is not null then
    v_before := app_private.redact_audit_jsonb(v_old);
  end if;
  if tg_op <> 'DELETE' then
    v_after := app_private.redact_audit_jsonb(v_row);
  end if;

  if pg_catalog.octet_length(coalesce(v_before::text, '')) >= 60000 then
    v_before := pg_catalog.jsonb_build_object(
      '_truncated', true,
      'id', v_entity_id
    );
    v_truncated := true;
  end if;
  if pg_catalog.octet_length(coalesce(v_after::text, '')) >= 60000 then
    v_after := pg_catalog.jsonb_build_object(
      '_truncated', true,
      'id', v_entity_id
    );
    v_truncated := true;
  end if;

  insert into public.audit_logs (
    id, business_id, branch_id, user_id, action, entity_type, entity_id,
    module, action_type, entity_label, actor_name, actor_role,
    before_json, after_json, details, source, created_at
  )
  values (
    pg_catalog.gen_random_uuid(),
    v_business_id,
    v_branch_id,
    v_actor_id,
    'database.' || tg_table_name || '_' || v_operation,
    tg_table_name,
    v_entity_id,
    v_module,
    v_operation,
    pg_catalog.left(coalesce(
      v_row ->> 'name',
      v_row ->> 'display_name',
      v_row ->> 'item_name',
      v_row ->> 'reference'
    ), 160),
    coalesce(v_actor_name, 'Unknown user'),
    v_actor_role,
    v_before,
    v_after,
    case when v_truncated
      then '{"snapshotTruncated":true}'::jsonb
      else '{"capture":"database_row_change"}'::jsonb
    end,
    'database',
    pg_catalog.clock_timestamp()
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.capture_business_audit()
  from public, anon, authenticated;

do $$
declare
  v_table record;
  v_child record;
begin
  for v_table in
    select c.table_name
    from information_schema.columns c
    where c.table_schema = 'public'
      and exists (
        select 1
        from information_schema.tables t
        where t.table_schema = 'public'
          and t.table_name = c.table_name
          and t.table_type = 'BASE TABLE'
      )
    group by c.table_name
    having bool_or(c.column_name = 'id')
       and bool_or(c.column_name = 'business_id')
       and c.table_name not in (
         'audit_logs', 'sync_changes', 'sync_mutations'
       )
  loop
    execute pg_catalog.format(
      'drop trigger if exists %I on public.%I',
      v_table.table_name || '_audit_change',
      v_table.table_name
    );
    execute pg_catalog.format(
      'create trigger %I after insert or update or delete on public.%I '
      'for each row execute function public.capture_business_audit()',
      v_table.table_name || '_audit_change',
      v_table.table_name
    );
  end loop;

  -- These business-owned child rows inherit their tenant from the parent.
  for v_child in
    select *
    from (values
      ('ledger_lines', 'journal_entries', 'journal_entry_id'),
      ('inventory_movements', 'supplies', 'supply_id'),
      ('pos_sale_items', 'pos_sales', 'sale_id'),
      ('pos_sale_payments', 'pos_sales', 'sale_id'),
      ('pos_sale_tenders', 'pos_sales', 'sale_id'),
      ('shopping_cart_items', 'shopping_carts', 'cart_id'),
      ('supply_price_history', 'supplies', 'supply_id'),
      ('recipes', 'products', 'product_id'),
      ('recipe_components', 'recipes', 'recipe_id'),
      ('payroll_items', 'payroll_runs', 'run_id')
    ) as children(table_name, parent_table, parent_key)
  loop
    if pg_catalog.to_regclass(
      'public.' || pg_catalog.quote_ident(v_child.table_name)
    ) is null then
      continue;
    end if;
    execute pg_catalog.format(
      'drop trigger if exists %I on public.%I',
      v_child.table_name || '_audit_change',
      v_child.table_name
    );
    execute pg_catalog.format(
      'create trigger %I after insert or update or delete on public.%I '
      'for each row execute function public.capture_business_audit(%L, %L)',
      v_child.table_name || '_audit_change',
      v_child.table_name,
      v_child.parent_table,
      v_child.parent_key
    );
  end loop;

  execute 'drop trigger if exists businesses_audit_change on public.businesses';
  execute 'create trigger businesses_audit_change '
    'after insert or update or delete on public.businesses '
    'for each row execute function public.capture_business_audit()';
end;
$$;

-- Keep authoritative audit rows in the existing pull feed.
drop trigger if exists audit_logs_sync_change on public.audit_logs;
create trigger audit_logs_sync_change
  after insert on public.audit_logs
  for each row execute function public.log_sync_change();

commit;