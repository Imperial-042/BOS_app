-- Remove the legacy 5-arg overload that made RPC calls ambiguous.
drop function if exists
  public.create_business_with_owner(text, text, text, text, text);

-- The 6-arg version was created with default grants (PUBLIC + anon).
-- Restrict it to signed-in users, matching the function it replaces.
revoke all on function
  public.create_business_with_owner(text, text, text, text, text, uuid)
  from public, anon;
grant execute on function
  public.create_business_with_owner(text, text, text, text, text, uuid)
  to authenticated;

notify pgrst, 'reload schema';