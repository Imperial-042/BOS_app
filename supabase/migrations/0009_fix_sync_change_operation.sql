-- 0009_fix_sync_change_operation.sql
-- Fix: PostgreSQL TG_OP returns 'INSERT', but sync_changes.operation allows
-- only 'create'/'update'/'delete'. Map INSERT -> create so the change-feed
-- trigger doesn't violate its own check constraint on every insert.

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
  elsif TG_OP = 'INSERT' then
    v_business_id := NEW.business_id;
    v_entity_id := NEW.id;
    v_op := 'create';
  else
    v_business_id := NEW.business_id;
    v_entity_id := NEW.id;
    v_op := 'update';
  end if;

  insert into public.sync_changes (business_id, entity_type, entity_id, operation)
  values (v_business_id, TG_TABLE_NAME, v_entity_id, v_op);
  return coalesce(NEW, OLD);
end;
$$;
