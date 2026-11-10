alter table public.branches
  drop constraint if exists branches_complete_address_check;

alter table public.branches
  add constraint branches_complete_address_check
  check (
    is_headquarters
    or (
      nullif(btrim(country), '') is not null
      and nullif(btrim(province_state), '') is not null
      and nullif(btrim(city), '') is not null
      and nullif(btrim(street_barangay), '') is not null
      and nullif(btrim(postal_code), '') is not null
    )
  ) not valid;

notify pgrst, 'reload schema';