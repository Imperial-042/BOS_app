-- ============================================================
-- 0012 — BUSINESS PROFILE SCHEMA ALIGNMENT
-- ============================================================
-- Aligns public.businesses with the current Drift Businesses table.
-- All additions are idempotent.

alter table public.businesses
  add column if not exists legal_name text,
  add column if not exists owner_name text,
  add column if not exists manager_name text,
  add column if not exists business_type text,
  add column if not exists industry text,
  add column if not exists business_category text,
  add column if not exists description text,
  add column if not exists email text,
  add column if not exists phone text,
  add column if not exists address_country text,
  add column if not exists address_province text,
  add column if not exists address_city text,
  add column if not exists address_barangay text,
  add column if not exists address_zip_code text,
  add column if not exists starting_capital bigint default 0,
  add column if not exists starting_capital_account_id uuid,
  add column if not exists is_current boolean default false,
  add column if not exists timezone text,
  add column if not exists logo_path text,
  add column if not exists is_active boolean default true;

-- Refresh PostgREST's schema cache immediately.
notify pgrst, 'reload schema';