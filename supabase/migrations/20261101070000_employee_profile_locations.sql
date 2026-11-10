alter table public.employee_profiles
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists location_accuracy_meters double precision;

notify pgrst, 'reload schema';
