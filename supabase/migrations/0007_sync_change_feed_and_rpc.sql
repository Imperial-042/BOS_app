-- 0007_sync_change_feed_and_rpc.sql
-- Server-side change feed (for cursor-based pull) + atomic, idempotent
-- business commands for composite financial operations. The server is the
-- second validation boundary: every command re-checks membership, business
-- ownership, amounts, and idempotency before writing anything.

-- ---------------------------------------------------------------------------
-- Change feed: one row per committed change to a business-owned record.
-- `seq` is the authoritative, monotonic pull cursor (server-generated, not
-- device clock). RLS restricts reads to members of the row's business.
-- ---------------------------------------------------------------------------
create table public.sync_changes (
  seq bigint generated always as identity primary key,
  business_id uuid not null references public.businesses (id) on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  operation text not null check (operation in ('create','update','delete')),
  changed_at timestamptz not null default now()
);
create index sync_changes_business_seq_idx
  on public.sync_changes (business_id, seq);

alter table public.sync_changes enable row level security;
create policy sync_changes_select_member on public.sync_changes
  for select using (public.is_business_member(business_id));

-- Trigger helper: log a change for any business-owned row. Tables whose
-- business_id is direct call this with NEW.business_id; child tables pass the
-- parent's business_id resolved by their own trigger.
create or replace function public.log_sync_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business_id uuid;
  v_entity_id uuid;
  v_op text;
begin
  if TG_OP = 'DELETE' then
    v_business_id := OLD.business_id;
    v_entity_id := OLD.id;
    v_op := 'delete';
  else
    v_business_id := NEW.business_id;
    v_entity_id := NEW.id;
    v_op := lower(TG_OP);
  end if;

  insert into public.sync_changes (business_id, entity_type, entity_id, operation)
  values (v_business_id, TG_TABLE_NAME, v_entity_id, v_op);
  return coalesce(NEW, OLD);
end;
$$;

-- Attach the feed to the sync-relevant business-owned tables. Financial
-- history tables are append-only events — feed covers them too.
do $$
declare
  t text;
  synced text[] := array[
    'accounts','categories','customers','suppliers','journal_entries',
    'income_transactions','expenses','receivable_payments','payable_payments',
    'supplier_purchases','account_transfers','supplies','inventory_movements',
    'products','business_module_configs'
  ];
begin
  foreach t in array synced loop
    execute format(
      'create trigger %I after insert or update or delete on public.%I '
      'for each row execute function public.log_sync_change()',
      t || '_sync_change', t);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Idempotency: a server-side record of processed mutation ids so a repeated
-- upload of the same logical operation is recognized, never duplicated.
-- ---------------------------------------------------------------------------
create table public.sync_mutations (
  mutation_id uuid primary key,
  business_id uuid not null references public.businesses (id) on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  processed_at timestamptz not null default now()
);
create index sync_mutations_business_idx on public.sync_mutations (business_id);

alter table public.sync_mutations enable row level security;
create policy sync_mutations_member on public.sync_mutations
  for all using (public.is_business_member(business_id))
  with check (public.is_business_member(business_id));

-- Returns true the FIRST time this mutation id is seen; false on a duplicate
-- (already processed). Called inside each command's transaction so the check
-- and the write commit together.
create or replace function public.claim_mutation(
  p_mutation_id uuid,
  p_business_id uuid,
  p_entity_type text,
  p_entity_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.sync_mutations
    (mutation_id, business_id, entity_type, entity_id)
  values (p_mutation_id, p_business_id, p_entity_type, p_entity_id)
  on conflict (mutation_id) do nothing;
  return found;
end;
$$;

-- ---------------------------------------------------------------------------
-- record_supplier_payment: atomic, idempotent supplier payment.
--   payment record + journal entry + 2 ledger lines, one transaction.
-- ---------------------------------------------------------------------------
create or replace function public.record_supplier_payment(
  p_mutation_id uuid,
  p_payment_id uuid,
  p_business_id uuid,
  p_supplier_id uuid,
  p_amount bigint,
  p_payment_account_id uuid,
  p_payment_date timestamptz,
  p_notes text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_is_new boolean;
  v_payable uuid;
  v_entry uuid := gen_random_uuid();
  v_outstanding bigint;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if not public.is_business_member(p_business_id) then
    raise exception 'not authorized for this business';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'payment amount must be greater than zero';
  end if;

  -- Idempotency: a repeated upload of the same mutation is a no-op.
  v_is_new := public.claim_mutation(
    p_mutation_id, p_business_id, 'payable_payments', p_payment_id);
  if not v_is_new then
    return jsonb_build_object('payment_id', p_payment_id, 'duplicate', true);
  end if;

  -- Supplier must belong to this business.
  if not exists (
    select 1 from public.suppliers
    where id = p_supplier_id and business_id = p_business_id
  ) then
    raise exception 'supplier does not belong to this business';
  end if;

  -- Payment account must be a payment account in this business.
  if not exists (
    select 1 from public.accounts
    where id = p_payment_account_id and business_id = p_business_id
      and is_payment_account and is_active
  ) then
    raise exception 'invalid payment account';
  end if;

  -- Outstanding balance = credit purchases - completed payments.
  select coalesce((
    select sum(amount) from public.supplier_purchases
    where supplier_id = p_supplier_id and business_id = p_business_id
      and is_on_credit and status = 'completed'
  ), 0) - coalesce((
    select sum(amount) from public.payable_payments
    where supplier_id = p_supplier_id and business_id = p_business_id
      and status = 'completed'
  ), 0) into v_outstanding;

  if v_outstanding <= 0 then
    raise exception 'this supplier has no outstanding balance to pay';
  end if;
  if p_amount > v_outstanding then
    raise exception 'payment cannot exceed the outstanding balance';
  end if;

  -- Accounts Payable GL account for this business (seeded deterministic id
  -- maps to a lookup by name+type since cloud ids are UUIDs).
  select id into v_payable from public.accounts
  where business_id = p_business_id and type = 'liability'
    and subtype = 'trade_payable'
  order by created_at
  limit 1;
  if v_payable is null then
    raise exception 'no accounts-payable account found for this business';
  end if;

  insert into public.payable_payments (
    id, business_id, supplier_id, amount, payment_account_id,
    is_on_credit, status, payment_date, notes
  ) values (
    p_payment_id, p_business_id, p_supplier_id, p_amount,
    p_payment_account_id, false, 'completed', p_payment_date, p_notes
  );

  insert into public.journal_entries (
    id, business_id, entry_date, source_type, source_id, description
  ) values (
    v_entry, p_business_id, p_payment_date, 'payable_payment',
    p_payment_id, p_notes
  );

  insert into public.ledger_lines
    (business_id, journal_entry_id, account_id, debit, credit)
  values
    (p_business_id, v_entry, v_payable, p_amount, 0),
    (p_business_id, v_entry, p_payment_account_id, 0, p_amount);

  return jsonb_build_object(
    'payment_id', p_payment_id, 'journal_entry_id', v_entry,
    'duplicate', false
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- record_customer_payment: atomic, idempotent receivable collection.
-- ---------------------------------------------------------------------------
create or replace function public.record_customer_payment(
  p_mutation_id uuid,
  p_payment_id uuid,
  p_business_id uuid,
  p_customer_id uuid,
  p_amount bigint,
  p_payment_account_id uuid,
  p_payment_date timestamptz,
  p_notes text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_is_new boolean;
  v_receivable uuid;
  v_entry uuid := gen_random_uuid();
  v_outstanding bigint;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if not public.is_business_member(p_business_id) then
    raise exception 'not authorized for this business';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'payment amount must be greater than zero';
  end if;

  v_is_new := public.claim_mutation(
    p_mutation_id, p_business_id, 'receivable_payments', p_payment_id);
  if not v_is_new then
    return jsonb_build_object('payment_id', p_payment_id, 'duplicate', true);
  end if;

  if not exists (
    select 1 from public.customers
    where id = p_customer_id and business_id = p_business_id
  ) then
    raise exception 'customer does not belong to this business';
  end if;

  if not exists (
    select 1 from public.accounts
    where id = p_payment_account_id and business_id = p_business_id
      and is_payment_account and is_active
  ) then
    raise exception 'invalid payment account';
  end if;

  select coalesce((
    select sum(amount) from public.income_transactions
    where customer_id = p_customer_id and business_id = p_business_id
      and payment_account_id is null
  ), 0) - coalesce((
    select sum(amount) from public.receivable_payments
    where customer_id = p_customer_id and business_id = p_business_id
      and status = 'completed'
  ), 0) into v_outstanding;

  if v_outstanding <= 0 then
    raise exception 'this customer has no outstanding balance to pay';
  end if;
  if p_amount > v_outstanding then
    raise exception 'payment cannot exceed the outstanding balance';
  end if;

  select id into v_receivable from public.accounts
  where business_id = p_business_id and type = 'asset'
    and subtype = 'current_asset' and name ilike '%receivable%'
  order by created_at
  limit 1;
  if v_receivable is null then
    raise exception 'no accounts-receivable account found for this business';
  end if;

  insert into public.receivable_payments (
    id, business_id, customer_id, amount, payment_account_id,
    is_on_credit, status, payment_date, notes
  ) values (
    p_payment_id, p_business_id, p_customer_id, p_amount,
    p_payment_account_id, false, 'completed', p_payment_date, p_notes
  );

  insert into public.journal_entries (
    id, business_id, entry_date, source_type, source_id, description
  ) values (
    v_entry, p_business_id, p_payment_date, 'receivable_payment',
    p_payment_id, p_notes
  );

  insert into public.ledger_lines
    (business_id, journal_entry_id, account_id, debit, credit)
  values
    (p_business_id, v_entry, p_payment_account_id, p_amount, 0),
    (p_business_id, v_entry, v_receivable, 0, p_amount);

  return jsonb_build_object(
    'payment_id', p_payment_id, 'journal_entry_id', v_entry,
    'duplicate', false
  );
end;
$$;
