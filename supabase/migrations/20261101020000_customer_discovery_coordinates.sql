alter table public.customer_profiles
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists location_accuracy_meters double precision;

alter table public.customer_profiles
  add constraint customer_profiles_latitude_check
  check (latitude is null or latitude between -90 and 90) not valid;

alter table public.customer_profiles
  add constraint customer_profiles_longitude_check
  check (longitude is null or longitude between -180 and 180) not valid;

notify pgrst, 'reload schema';
