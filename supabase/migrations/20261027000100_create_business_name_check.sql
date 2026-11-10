-- 20261027000100_create_business_name_check.sql
create or replace function public.create_business_with_owner(
  p_name text, p_business_type text default null, p_industry text default null,
  p_currency_code text default 'PHP', p_timezone text default 'Asia/Manila',
  p_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_business_id uuid;
  v_user_id uuid := (select auth.uid());
  v_owner uuid;
begin
  if v_user_id is null then raise exception 'not authenticated'; end if;
  if not public.is_current_device_session_active() then
    raise exception 'device authorization required';
  end if;
  if nullif(btrim(p_name), '') is null then
    raise exception 'business name is required';
  end if;

  if p_id is not null then
    select owner_user_id into v_owner from public.businesses where id = p_id;
    if found then
      if v_owner <> v_user_id then raise exception 'business id already in use'; end if;
      insert into public.business_memberships (business_id, user_id, role)
      select p_id, v_user_id, 'owner'
      where not exists (select 1 from public.business_memberships
                        where business_id = p_id and user_id = v_user_id and status = 'active');
      insert into public.branches (id, business_id, name, code, is_headquarters, cash_account_id)
      values (extensions.uuid_generate_v5(extensions.uuid_ns_url(), 'bos:branches:branch_main_' || p_id::text),
              p_id, 'Main Branch', 'MAIN', true,
              extensions.uuid_generate_v5(extensions.uuid_ns_url(), 'bos:accounts:acc_cash_' || p_id::text))
      on conflict do nothing;
      return p_id;
    end if;
  end if;

  insert into public.businesses (id, owner_user_id, name, business_type, industry, business_category,
                                 currency_code, timezone)
  values (coalesce(p_id, gen_random_uuid()), v_user_id, btrim(p_name), p_business_type, p_industry,
          p_industry, coalesce(p_currency_code, 'PHP'), coalesce(p_timezone, 'Asia/Manila'))
  returning id into v_business_id;

  insert into public.business_memberships (business_id, user_id, role)
  values (v_business_id, v_user_id, 'owner');

  insert into public.branches (id, business_id, name, code, is_headquarters, cash_account_id)
  values (extensions.uuid_generate_v5(extensions.uuid_ns_url(), 'bos:branches:branch_main_' || v_business_id::text),
          v_business_id, 'Main Branch', 'MAIN', true,
          extensions.uuid_generate_v5(extensions.uuid_ns_url(), 'bos:accounts:acc_cash_' || v_business_id::text))
  on conflict do nothing;

  return v_business_id;
end;
$function$;