alter table if exists public.product_option_choices
  add column if not exists inventory_supply_id uuid
  references public.supplies(id) on delete set null;

notify pgrst, 'reload schema';
