-- 20261013000000_audit_logs_append_only.sql
--
-- Server-side audit trail. Mirrors the local Drift table `audit_logs`
-- (column names must match exactly: the sync engine uploads `SELECT *` rows).
--
-- ASSUMPTIONS to verify against your project before applying:
--   * public.businesses(id uuid) exists (the client already syncs it).
--   * public.business_memberships(business_id, user_id, role, status) exists
--     (queried by the app: role in owner|manager|accountant|cashier|...,
--     status 'active').
--
-- NOT included (needs your existing sync_changes trigger function, which was
-- not provided): registering audit_logs in the `sync_changes` change feed so
-- OTHER devices pull these rows. See INTEGRATION_PATCHES.md, step S1.

begin;

create table if not exists public.audit_logs (
  id            uuid primary key,                  -- client event id = idempotency key
  business_id   uuid not null references public.businesses (id) on delete restrict,
  user_id       uuid not null,                     -- actor (auth.users.id); no FK so history survives user removal
  action        text not null,
  entity_type   text not null,
  entity_id     text,
  module        text,
  action_type   text,
  entity_label  text,
  actor_name    text,
  actor_role    text,
  device_id     text,
  reason        text,
  before_json   jsonb,
  after_json    jsonb,
  details       jsonb,
  created_at    timestamptz not null,              -- client event time
  received_at   timestamptz not null default now(),-- server time, not client-controlled
  constraint audit_logs_module_chk check (
    module is null or module in
      ('finance','inventory','sales','people','administration','security')),
  constraint audit_logs_action_type_chk check (
    action_type is null or action_type in
      ('create','update','delete','void','refund','adjustment',
       'permission','export','security')),
  constraint audit_logs_size_chk check (
    coalesce(octet_length(before_json::text), 0) < 65536
    and coalesce(octet_length(after_json::text), 0) < 65536
    and coalesce(octet_length(details::text), 0) < 65536)
);

create index if not exists ix_audit_logs_business_time
  on public.audit_logs (business_id, created_at desc);
create index if not exists ix_audit_logs_business_module
  on public.audit_logs (business_id, module, created_at desc);
create index if not exists ix_audit_logs_entity
  on public.audit_logs (business_id, entity_type, entity_id);
create index if not exists ix_audit_logs_business_user
  on public.audit_logs (business_id, user_id, created_at desc);

-- ---------------------------------------------------------------- privileges
alter table public.audit_logs enable row level security;
alter table public.audit_logs force row level security;

revoke all on public.audit_logs from public, anon, authenticated;
grant select, insert on public.audit_logs to authenticated;
-- No UPDATE / DELETE / TRUNCATE grant for any client role.

-- ------------------------------------------------------------------ policies
-- INSERT: only as yourself, only into a business where you are an active
-- member. Prevents forging another user's events or writing to another tenant.
drop policy if exists audit_logs_insert_own on public.audit_logs;
create policy audit_logs_insert_own on public.audit_logs
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.business_memberships m
      where m.business_id = audit_logs.business_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'
    )
  );

-- SELECT: owners and managers of that business only. (Per-business role
-- permission overrides live on the client; the server enforces this floor.)
drop policy if exists audit_logs_select_admins on public.audit_logs;
create policy audit_logs_select_admins on public.audit_logs
  for select to authenticated
  using (
    exists (
      select 1
      from public.business_memberships m
      where m.business_id = audit_logs.business_id
        and m.user_id = (select auth.uid())
        and m.status = 'active'
        and m.role in ('owner', 'manager')
    )
  );

-- No UPDATE or DELETE policies exist: with RLS forced, those are denied.

-- ------------------------------------------------- defense in depth: triggers
-- Blocks UPDATE/DELETE/TRUNCATE even for roles that bypass RLS
-- (service_role, table owner). Retention/purge must be a deliberate,
-- reviewed migration that disables this trigger explicitly.
create or replace function public.audit_logs_block_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'audit_logs is append-only (% is not allowed)', tg_op
    using errcode = '42501';
end;
$$;

drop trigger if exists audit_logs_no_update_delete on public.audit_logs;
create trigger audit_logs_no_update_delete
  before update or delete on public.audit_logs
  for each row execute function public.audit_logs_block_mutation();

drop trigger if exists audit_logs_no_truncate on public.audit_logs;
create trigger audit_logs_no_truncate
  before truncate on public.audit_logs
  for each statement execute function public.audit_logs_block_mutation();

-- received_at is always server time, whatever the client sends.
create or replace function public.audit_logs_stamp_received()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.received_at := now();
  return new;
end;
$$;

drop trigger if exists audit_logs_stamp_received on public.audit_logs;
create trigger audit_logs_stamp_received
  before insert on public.audit_logs
  for each row execute function public.audit_logs_stamp_received();

commit;