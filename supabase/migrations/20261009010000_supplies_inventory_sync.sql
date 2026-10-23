-- Columns the app sends for supplies (no-ops where they already exist).
alter table public.supplies
  add column if not exists sku text,
  add column if not exists barcode text,
  add column if not exists purchase_unit text,
  add column if not exists stock_unit text not null default 'piece',
  add column if not exists current_stock double precision not null default 0,
  add column if not exists cost_per_base_unit double precision not null default 0,
  add column if not exists current_price bigint not null default 0,
  add column if not exists is_active boolean not null default true;

-- Any active member on an authorized device may add/update supplies and
-- stock movements. (Cashiers also deduct stock when they sell, so this
-- cannot be manager-only.)
drop policy if exists supplies_member_insert on public.supplies;
create policy supplies_member_insert on public.supplies
  for insert to authenticated
  with check (public.is_business_member(business_id));

drop policy if exists supplies_member_update on public.supplies;
create policy supplies_member_update on public.supplies
  for update to authenticated
  using (public.is_business_member(business_id))
  with check (public.is_business_member(business_id));

drop policy if exists inventory_movements_member_insert on public.inventory_movements;
create policy inventory_movements_member_insert on public.inventory_movements
  for insert to authenticated
  with check (public.is_business_member(business_id));

drop policy if exists inventory_movements_member_update on public.inventory_movements;
create policy inventory_movements_member_update on public.inventory_movements
  for update to authenticated
  using (public.is_business_member(business_id))
  with check (public.is_business_member(business_id));

-- Make sure supply changes reach the change feed.
do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.supplies'::regclass
      and not tgisinternal
      and tgfoid = 'public.log_sync_change()'::regprocedure
  ) then
    drop trigger if exists supplies_sync_change on public.supplies;
    create trigger supplies_sync_change
      after insert or update or delete on public.supplies
      for each row execute function public.log_sync_change();
  end if;
end $$;

notify pgrst, 'reload schema';