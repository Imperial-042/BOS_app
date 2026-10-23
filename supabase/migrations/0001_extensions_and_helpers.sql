-- 0001_extensions_and_helpers.sql
-- Extensions and shared helpers every later migration relies on.

-- gen_random_uuid() for UUID primary keys.
create extension if not exists pgcrypto;

-- Keeps updated_at current on every UPDATE without trusting the client.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
