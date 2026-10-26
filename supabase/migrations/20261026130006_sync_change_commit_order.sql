-- Serialize feed sequence allocation per business until the changing
-- transaction commits. Identity sequences alone are allocation-ordered, not
-- commit-ordered, so a consumer could otherwise advance past an uncommitted
-- lower sequence and never see it.

begin;

create or replace function public.lock_sync_change_business(p_business_id uuid)
returns void
language sql
volatile
set search_path = ''
as $$
  select pg_catalog.pg_advisory_xact_lock(
    24681357,
    pg_catalog.hashtext(p_business_id::text)
  );
$$;

revoke all on function public.lock_sync_change_business(uuid)
  from public, anon, authenticated;

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

  perform public.lock_sync_change_business(v_business_id);

  insert into public.sync_changes (business_id, entity_type, entity_id, operation)
  values (v_business_id, TG_TABLE_NAME, v_entity_id, v_op);
  return coalesce(NEW, OLD);
end;
$$;

create or replace function public.log_sync_change_via_parent()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb;
  v_entity_id uuid;
  v_parent_id uuid;
  v_business_id uuid;
  v_op text;
begin
  if TG_OP = 'DELETE' then
    v_row := to_jsonb(OLD);
    v_op := 'delete';
  else
    v_row := to_jsonb(NEW);
    v_op := case TG_OP when 'INSERT' then 'create' else 'update' end;
  end if;

  v_entity_id := (v_row ->> 'id')::uuid;
  v_parent_id := (v_row ->> TG_ARGV[1])::uuid;

  execute format('select business_id from public.%I where id = $1', TG_ARGV[0])
    into v_business_id
    using v_parent_id;

  -- Cascading deletes can remove the parent first; its own feed entry covers it.
  if v_business_id is null then
    return coalesce(NEW, OLD);
  end if;

  perform public.lock_sync_change_business(v_business_id);

  insert into public.sync_changes (business_id, entity_type, entity_id, operation)
  values (v_business_id, TG_TABLE_NAME, v_entity_id, v_op);

  return coalesce(NEW, OLD);
end;
$$;

create or replace function public.log_sync_change_via_recipe()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipe_id uuid;
  v_entity_id uuid;
  v_business_id uuid;
  v_op text;
begin
  if TG_OP = 'DELETE' then
    v_recipe_id := OLD.recipe_id;
    v_entity_id := OLD.id;
    v_op := 'delete';
  else
    v_recipe_id := NEW.recipe_id;
    v_entity_id := NEW.id;
    v_op := case TG_OP when 'INSERT' then 'create' else 'update' end;
  end if;

  select p.business_id into v_business_id
  from public.recipes r
  join public.products p on p.id = r.product_id
  where r.id = v_recipe_id;

  if v_business_id is null then
    return coalesce(NEW, OLD);
  end if;

  perform public.lock_sync_change_business(v_business_id);

  insert into public.sync_changes (business_id, entity_type, entity_id, operation)
  values (v_business_id, TG_TABLE_NAME, v_entity_id, v_op);

  return coalesce(NEW, OLD);
end;
$$;

create or replace function public.log_sync_change_business()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.lock_sync_change_business(new.id);

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

commit;
