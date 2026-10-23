-- 0008_create_business_rpc_security_definer.sql
-- Fix: make create_business_with_owner security definer so the sanctioned
-- creation path isn't blocked by the RLS INSERT policies (which exist for
-- direct client writes, not for this atomic two-row creation). The function
-- still enforces authentication and stamps auth.uid() as the owner, so the
-- caller can never create a business owned by someone else.

create or replace function public.create_business_with_owner(
  p_name text,
  p_business_type text default null,
  p_industry text default null,
  p_currency_code text default 'PHP',
  p_timezone text default 'Asia/Manila'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if btrim(p_name) = '' then
    raise exception 'business name is required';
  end if;

  insert into public.businesses (
    owner_user_id, name, business_type, industry, currency_code, timezone
  ) values (
    auth.uid(), btrim(p_name), p_business_type, p_industry,
    coalesce(p_currency_code, 'PHP'), coalesce(p_timezone, 'Asia/Manila')
  )
  returning id into v_business_id;

  insert into public.business_memberships (business_id, user_id, role)
  values (v_business_id, auth.uid(), 'owner');

  return v_business_id;
end;
$$;
