-- 20261026143016_customer_profile_phone.sql
alter table public.customer_profiles
  add column if not exists phone   text,
  add column if not exists city    text,
  add column if not exists address text;

notify pgrst, 'reload schema';