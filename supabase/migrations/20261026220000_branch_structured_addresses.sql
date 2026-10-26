alter table public.branches
  add column if not exists country text,
  add column if not exists province_state text,
  add column if not exists street_barangay text,
  add column if not exists postal_code text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'branches_complete_address_check'
      and conrelid = 'public.branches'::regclass
  ) then
    alter table public.branches
      add constraint branches_complete_address_check
      check (
        nullif(btrim(country), '') is not null
        and nullif(btrim(province_state), '') is not null
        and nullif(btrim(city), '') is not null
        and nullif(btrim(street_barangay), '') is not null
        and nullif(btrim(postal_code), '') is not null
      ) not valid;
  end if;
end;
$$;

notify pgrst, 'reload schema';