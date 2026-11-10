alter table public.product_option_groups
  add column if not exists is_add_on boolean not null default false;

alter table public.product_option_choices
  add column if not exists inventory_supply_id uuid
  references public.supplies(id) on delete set null;

create index if not exists product_option_groups_add_on_idx
  on public.product_option_groups (business_id, is_add_on, is_active);

notify pgrst, 'reload schema';
