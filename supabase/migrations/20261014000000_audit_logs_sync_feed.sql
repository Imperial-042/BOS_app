-- 20261014000000_audit_logs_sync_feed.sql  (v2)
--
-- Registers public.audit_logs in the sync_changes feed using the SAME function
-- the other tables use (log_sync_change), so feed rows match your existing
-- format. Insert only: audit rows are append-only (update/delete are blocked).

begin;

drop trigger if exists audit_logs_sync_change on public.audit_logs;
create trigger audit_logs_sync_change
  after insert on public.audit_logs
  for each row execute function public.log_sync_change();

commit;

-- ---------------------------------------------------------------------------
-- BACKFILL (run separately, after the block above succeeds).
-- Needed so audit rows written BEFORE this trigger existed get announced.
-- If it errors with a NOT NULL column you don't set here, run
--   select pg_get_functiondef('public.log_sync_change'::regproc);
-- and add that column to both lists.
-- ---------------------------------------------------------------------------
-- insert into public.sync_changes (business_id, entity_type, entity_id, operation)
-- select a.business_id, 'audit_logs', a.id, 'create'
-- from public.audit_logs a
-- where not exists (
--   select 1 from public.sync_changes c
--   where c.entity_type = 'audit_logs' and c.entity_id::text = a.id::text
-- )
-- order by a.created_at, a.id;