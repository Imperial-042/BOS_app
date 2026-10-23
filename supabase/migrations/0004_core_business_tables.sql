-- 0004_core_business_tables.sql
-- The BOS operational schema. Every business-owned table carries an explicit
-- business_id so RLS, indexing, and sync are straightforward. Money is stored
-- in cents (bigint). Financial history uses restrictive deletes, not cascades.

-- ---------------------------------------------------------------------------
-- accounts (chart of accounts)
-- ---------------------------------------------------------------------------
create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  name text not null,
  type text not null check (type in ('asset','liability','equity','income','expense')),
  subtype text,
  is_payment_account boolean not null default false,
  starting_balance bigint not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index accounts_business_id_idx on public.accounts (business_id);
-- Composite unique index required by the same-business composite FKs below.
-- Must exist before categories (which references accounts (id, business_id)).
create unique index accounts_id_business_key on public.accounts (id, business_id);

-- ---------------------------------------------------------------------------
-- categories
-- ---------------------------------------------------------------------------
create table public.categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  name text not null,
  txn_type text not null check (txn_type in ('income','expense')),
  ledger_account_id uuid not null references public.accounts (id) on delete restrict,
  is_custom boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- A category can only post to an account in the SAME business.
  constraint categories_same_business_account
    foreign key (ledger_account_id, business_id)
    references public.accounts (id, business_id)
    on delete restrict
);
create index categories_business_id_idx on public.categories (business_id);

-- ---------------------------------------------------------------------------
-- customers / suppliers
-- ---------------------------------------------------------------------------
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  name text not null,
  phone text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index customers_business_id_idx on public.customers (business_id);
create unique index customers_id_business_key on public.customers (id, business_id);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  name text not null,
  phone text,
  address text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index suppliers_business_id_idx on public.suppliers (business_id);
create unique index suppliers_id_business_key on public.suppliers (id, business_id);

-- ---------------------------------------------------------------------------
-- journal entries + ledger lines (append-only financial history)
-- ---------------------------------------------------------------------------
create table public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  entry_date timestamptz not null,
  description text,
  source_type text not null,
  source_id uuid,
  status text not null default 'completed',
  created_at timestamptz not null default now()
);
create index journal_entries_business_id_idx on public.journal_entries (business_id);
create index journal_entries_source_idx on public.journal_entries (source_type, source_id);
-- Composite unique index required by composite FKs from ledger_lines etc.
create unique index journal_entries_id_business_key on public.journal_entries (id, business_id);

create table public.ledger_lines (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  journal_entry_id uuid not null references public.journal_entries (id) on delete restrict,
  account_id uuid not null references public.accounts (id) on delete restrict,
  debit bigint not null default 0 check (debit >= 0),
  credit bigint not null default 0 check (credit >= 0),
  check (debit = 0 or credit = 0),
  -- Both parents must live in the SAME business as the line.
  constraint ledger_lines_same_business_entry
    foreign key (journal_entry_id, business_id)
    references public.journal_entries (id, business_id)
    on delete restrict,
  constraint ledger_lines_same_business_account
    foreign key (account_id, business_id)
    references public.accounts (id, business_id)
    on delete restrict
);
create index ledger_lines_business_id_idx on public.ledger_lines (business_id);
create index ledger_lines_journal_entry_id_idx on public.ledger_lines (journal_entry_id);
create index ledger_lines_account_id_idx on public.ledger_lines (account_id);

-- ---------------------------------------------------------------------------
-- income / expense transactions
-- ---------------------------------------------------------------------------
create table public.income_transactions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  txn_date timestamptz not null,
  description text,
  category_id uuid not null,
  amount bigint not null check (amount >= 0),
  customer_id uuid,
  payment_account_id uuid,
  reference text,
  notes text,
  status text not null default 'completed',
  journal_entry_id uuid references public.journal_entries (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint income_same_business_customer
    foreign key (customer_id, business_id)
    references public.customers (id, business_id)
    on delete restrict,
  constraint income_same_business_account
    foreign key (payment_account_id, business_id)
    references public.accounts (id, business_id)
    on delete restrict,
  constraint income_same_business_entry
    foreign key (journal_entry_id, business_id)
    references public.journal_entries (id, business_id)
    on delete restrict
);
create index income_transactions_business_id_idx on public.income_transactions (business_id);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  expense_date timestamptz not null,
  description text,
  category_id uuid not null,
  amount bigint not null check (amount >= 0),
  payment_account_id uuid,
  receipt_photo_path text,
  reference text,
  notes text,
  status text not null default 'completed',
  journal_entry_id uuid references public.journal_entries (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint expenses_same_business_account
    foreign key (payment_account_id, business_id)
    references public.accounts (id, business_id)
    on delete restrict,
  constraint expenses_same_business_entry
    foreign key (journal_entry_id, business_id)
    references public.journal_entries (id, business_id)
    on delete restrict
);
create index expenses_business_id_idx on public.expenses (business_id);

-- ---------------------------------------------------------------------------
-- receivable / payable payments + purchases
-- ---------------------------------------------------------------------------
create table public.receivable_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  customer_id uuid not null,
  amount bigint not null check (amount > 0),
  payment_account_id uuid,
  is_on_credit boolean not null default false,
  status text not null default 'completed',
  payment_date timestamptz not null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint receivable_same_business_customer
    foreign key (customer_id, business_id)
    references public.customers (id, business_id)
    on delete restrict,
  constraint receivable_same_business_account
    foreign key (payment_account_id, business_id)
    references public.accounts (id, business_id)
    on delete restrict
);
create index receivable_payments_business_id_idx on public.receivable_payments (business_id);

create table public.supplier_purchases (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  supplier_id uuid not null,
  purchase_date timestamptz not null,
  amount bigint not null check (amount >= 0),
  is_on_credit boolean not null default false,
  payment_account_id uuid,
  notes text,
  status text not null default 'completed',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint purchase_same_business_supplier
    foreign key (supplier_id, business_id)
    references public.suppliers (id, business_id)
    on delete restrict,
  constraint purchase_same_business_account
    foreign key (payment_account_id, business_id)
    references public.accounts (id, business_id)
    on delete restrict
);
create index supplier_purchases_business_id_idx on public.supplier_purchases (business_id);

create table public.payable_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  supplier_id uuid not null,
  amount bigint not null check (amount > 0),
  payment_account_id uuid,
  is_on_credit boolean not null default false,
  status text not null default 'completed',
  payment_date timestamptz not null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payable_same_business_supplier
    foreign key (supplier_id, business_id)
    references public.suppliers (id, business_id)
    on delete restrict,
  constraint payable_same_business_account
    foreign key (payment_account_id, business_id)
    references public.accounts (id, business_id)
    on delete restrict
);
create index payable_payments_business_id_idx on public.payable_payments (business_id);

-- ---------------------------------------------------------------------------
-- transfers
-- ---------------------------------------------------------------------------
create table public.account_transfers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  from_account_id uuid not null,
  to_account_id uuid not null,
  amount bigint not null check (amount > 0),
  transfer_date timestamptz not null,
  notes text,
  created_at timestamptz not null default now(),
  constraint transfer_different_accounts check (from_account_id <> to_account_id),
  constraint transfer_same_business_from
    foreign key (from_account_id, business_id)
    references public.accounts (id, business_id)
    on delete restrict,
  constraint transfer_same_business_to
    foreign key (to_account_id, business_id)
    references public.accounts (id, business_id)
    on delete restrict
);
create index account_transfers_business_id_idx on public.account_transfers (business_id);

-- ---------------------------------------------------------------------------
-- inventory: supplies, movements, products
-- ---------------------------------------------------------------------------
create table public.supplies (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  name text not null,
  sku text,
  barcode text,
  stock_unit text not null default 'piece',
  purchase_unit text,
  current_stock double precision not null default 0,
  cost_per_base_unit double precision not null default 0,
  current_price bigint not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index supplies_business_id_idx on public.supplies (business_id);
create unique index supplies_id_business_key on public.supplies (id, business_id);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  supply_id uuid not null,
  movement_type text not null,
  quantity double precision not null,
  movement_date timestamptz not null default now(),
  notes text,
  created_at timestamptz not null default now(),
  constraint movement_same_business_supply
    foreign key (supply_id, business_id)
    references public.supplies (id, business_id)
    on delete restrict
);
create index inventory_movements_business_id_idx on public.inventory_movements (business_id);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete restrict,
  name text not null,
  sku text,
  barcode text,
  product_type text not null default 'finished',
  tracking_type text not null default 'recipe',
  unit text not null,
  sell_price bigint,
  current_stock double precision not null default 0,
  image_path text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index products_business_id_idx on public.products (business_id);

-- ---------------------------------------------------------------------------
-- module configuration (per-business feature switches)
-- ---------------------------------------------------------------------------
create table public.business_module_configs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete cascade,
  module_id text not null,
  enabled boolean not null default true,
  config_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index business_module_configs_business_module_key
  on public.business_module_configs (business_id, module_id);

