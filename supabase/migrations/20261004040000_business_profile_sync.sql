-- 20261004040000_business_profile_sync.sql
--
-- Business profile edits (name, owner, category, address, starting capital...)
-- now flow through the change feed, so every device signed in with the same
-- account pulls the same profile instead of asking the owner to set it up
-- again. Also backfills the feed for rows that were uploaded before their
-- tables had triggers (the feed only records changes made after a trigger
-- exists, so a second device would otherwise never receive them).

create or replace function public.log_sync_change_business()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.sync_changes (business_id, entity_type, entity_id, operation)
  values (
    new.id,
    TG_TABLE_NAME,
    new.id,
    case TG_OP when 'INSERT' then 'create' else 'update' end
  );
  return new;
end;
$$;

revoke all on function public.log_sync_change_business()
  from public, anon, authenticated;

drop trigger if exists businesses_sync_change on public.businesses;
create trigger businesses_sync_change
  after insert or update on public.businesses
  for each row execute function public.log_sync_change_business();

-- Backfill: one 'create' feed entry per existing row that has none.
insert into public.sync_changes (business_id, entity_type, entity_id, operation)
select b.id, 'businesses', b.id, 'update'
from public.businesses b
where not exists (
  select 1 from public.sync_changes c
  where c.entity_type = 'businesses' and c.entity_id = b.id
);

do $$
declare
  t text;
  direct_tables text[] := array[
    'ledger_lines', 'product_categories', 'payment_providers',
    'pos_sessions', 'pos_sales', 'shopping_carts',
    'role_permission_overrides'
  ];
begin
  foreach t in array direct_tables loop
    execute format(
      'insert into public.sync_changes (business_id, entity_type, entity_id, operation) '
      'select r.business_id, %L, r.id, ''create'' from public.%I r '
      'where not exists (select 1 from public.sync_changes c '
      'where c.entity_type = %L and c.entity_id = r.id)',
      t, t, t);
  end loop;
end;
$$;

notify pgrst, 'reload schema';
