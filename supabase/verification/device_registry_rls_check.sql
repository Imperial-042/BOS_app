-- Device registry authorization checks (plain SQL, no pgTAP required).
--
-- Run against a LOCAL or throwaway database that already has every
-- migration applied. It creates and removes its own users/businesses.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/verification/device_registry_rls_check.sql
--
-- Exits non-zero if any check fails. Do not run against production.

begin;

create temp table check_results (name text, ok boolean, detail text);
grant all on check_results to public;

create function pg_temp.as_session(p_user uuid, p_session uuid) returns void
language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user, 'session_id', p_session, 'role', 'authenticated')::text,
    true);
  set local role authenticated;
end $$;

create function pg_temp.as_anon() returns void
language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', '', true);
  set local role anon;
end $$;

create function pg_temp.record(p_name text, p_ok boolean, p_detail text default null)
returns void language plpgsql as $$
begin
  insert into check_results values (p_name, coalesce(p_ok, false), p_detail);
end $$;

-- Runs p_sql; passes only if it raises. The current role/claims are kept.
create function pg_temp.expect_error(p_name text, p_sql text) returns void
language plpgsql as $$
declare v_msg text;
begin
  begin
    execute p_sql;
    perform pg_temp.record(p_name, false, 'statement unexpectedly succeeded');
  exception when others then
    get stacked diagnostics v_msg = message_text;
    perform pg_temp.record(p_name, true, v_msg);
  end;
end $$;

do $$
declare
  u1 constant uuid := '00000000-0000-4000-8000-0000000000a1';
  u2 constant uuid := '00000000-0000-4000-8000-0000000000a2';
  biz constant uuid := '00000000-0000-4000-8000-0000000000b1';
  s1a constant uuid := '00000000-0000-4000-8000-00000000c1a1';
  s1b constant uuid := '00000000-0000-4000-8000-00000000c1b1';
  s1b2 constant uuid := '00000000-0000-4000-8000-00000000c1b2';
  s2 constant uuid := '00000000-0000-4000-8000-00000000c201';
  dev_a constant uuid := '00000000-0000-4000-8000-0000000d0001';
  dev_b constant uuid := '00000000-0000-4000-8000-0000000d0002';
  dev_c constant uuid := '00000000-0000-4000-8000-0000000d0003';
  r jsonb;
  n int;
  b boolean;
  nm text;
begin
  -- Fixtures (as superuser).
  insert into auth.users (id, email) values (u1, 'u1@example.test'), (u2, 'u2@example.test');
  insert into public.businesses (id, owner_user_id, name) values (biz, u1, 'Check Co');
  insert into public.business_memberships (business_id, user_id, role) values (biz, u1, 'owner');

  -- 1. Valid JWT + membership but unregistered session: no business access.
  perform pg_temp.as_session(u1, s1a);
  select count(*) into n from public.businesses;
  perform pg_temp.record('unregistered session sees no businesses', n = 0, n::text);
  select count(*) into n from public.business_memberships;
  perform pg_temp.record('unregistered session sees no own memberships', n = 0, n::text);
  select public.is_current_device_session_active() into b;
  perform pg_temp.record('unregistered session is not active', b = false);

  -- 2. Registration.
  perform pg_temp.as_session(u1, s1a);
  r := public.register_current_device(dev_a, 'Phone A', 'android', 'mobile', '1.0.0');
  perform pg_temp.record('device A registers active', r ->> 'status' = 'active', r::text);
  select count(*) into n from public.businesses;
  perform pg_temp.record('registered session sees its business', n = 1, n::text);

  perform pg_temp.as_session(u1, s1b);
  r := public.register_current_device(dev_b, 'Tablet B', 'android', 'tablet', '1.0.0');
  perform pg_temp.record('device B registers active', r ->> 'status' = 'active', r::text);

  -- 3. Re-registration must not undo a user's rename.
  perform public.rename_current_user_device(dev_b, 'Renamed B');
  r := public.register_current_device(dev_b, 'Tablet B', 'android', 'tablet', '1.0.1');
  perform pg_temp.record('re-registration keeps renamed device name',
    r ->> 'device_name' = 'Renamed B', r ->> 'device_name');

  -- 4. Clients cannot write registry tables directly.
  perform pg_temp.as_session(u1, s1a);
  perform pg_temp.expect_error('direct insert into user_devices denied',
    format($f$insert into public.user_devices (user_id, device_uuid, device_name, platform, client_type) values (%L, gen_random_uuid(), 'x', 'android', 'mobile')$f$, u1));
  perform pg_temp.expect_error('direct status update denied',
    format($f$update public.user_devices set status = 'active' where user_id = %L$f$, u1));
  perform pg_temp.expect_error('direct session insert denied',
    format($f$insert into public.device_sessions (session_id, user_device_id, user_id) select gen_random_uuid(), id, user_id from public.user_devices limit 1$f$));

  -- 5. Another account cannot see or touch these devices.
  perform pg_temp.as_session(u2, s2);
  r := public.register_current_device(dev_c, 'Other C', 'ios', 'mobile', '1.0.0');
  select count(*) into n from public.user_devices;
  perform pg_temp.record('user 2 only sees own devices', n = 1, n::text);
  perform pg_temp.expect_error('user 2 cannot revoke user 1 device',
    format($f$select public.revoke_current_user_device(%L)$f$, dev_a));
  perform pg_temp.expect_error('user 2 cannot rename user 1 device',
    format($f$select public.rename_current_user_device(%L, 'pwn')$f$, dev_a));
  select count(*) into n from public.businesses;
  perform pg_temp.record('non-member sees no businesses', n = 0, n::text);

  -- 6. A device cannot revoke itself.
  perform pg_temp.as_session(u1, s1a);
  perform pg_temp.expect_error('device cannot revoke itself',
    format($f$select public.revoke_current_user_device(%L)$f$, dev_a));

  -- 7. Revoke device B from device A.
  perform public.revoke_current_user_device(dev_b);
  select count(*) into n from public.businesses;
  perform pg_temp.record('device A still authorized after revoking B', n = 1, n::text);

  perform pg_temp.as_session(u1, s1b);
  select public.is_current_device_session_active() into b;
  perform pg_temp.record('revoked device is not active (token still valid)', b = false);
  select count(*) into n from public.businesses;
  perform pg_temp.record('revoked device sees no businesses', n = 0, n::text);
  select count(*) into n from public.business_memberships;
  perform pg_temp.record('revoked device sees no memberships', n = 0, n::text);
  select count(*) into n from public.product_categories;
  perform pg_temp.record('revoked device sees no product categories', n = 0, n::text);
  perform pg_temp.expect_error('revoked device cannot create a business',
    $f$select public.create_business_with_owner('Sneaky')$f$);
  perform pg_temp.expect_error('revoked device cannot rename devices',
    format($f$select public.rename_current_user_device(%L, 'x')$f$, dev_a));
  perform pg_temp.expect_error('revoked device cannot revoke others',
    format($f$select public.revoke_current_user_device(%L)$f$, dev_a));
  perform pg_temp.expect_error('revoked device cannot sign out others',
    $f$select public.revoke_other_device_sessions()$f$);
  r := public.register_current_device(dev_b, 'Tablet B', 'android', 'tablet', '1.0.1');
  perform pg_temp.record('registering revoked device reports revoked with metadata',
    r ->> 'status' = 'revoked' and r ->> 'platform' = 'android'
    and (r ->> 'reauthentication_required')::boolean, r::text);

  -- 8. Reactivation needs a fresh session (a new JWT session id).
  perform pg_temp.expect_error('old session cannot reactivate its own device',
    format($f$select public.reactivate_current_user_device(%L)$f$, dev_b));
  perform pg_temp.as_session(u1, s1b2);
  r := public.reactivate_current_user_device(dev_b);
  perform pg_temp.record('fresh session reactivates device', r ->> 'status' = 'active', r::text);
  select count(*) into n from public.businesses;
  perform pg_temp.record('reactivated session has access', n = 1, n::text);
  perform pg_temp.as_session(u1, s1b);
  select public.is_current_device_session_active() into b;
  perform pg_temp.record('previously revoked session stays dead', b = false);

  -- 9. Sign out other sessions keeps the caller.
  perform pg_temp.as_session(u1, s1a);
  perform public.revoke_other_device_sessions();
  select public.is_current_device_session_active() into b;
  perform pg_temp.record('caller stays active after signing out others', b = true);
  perform pg_temp.as_session(u1, s1b2);
  select public.is_current_device_session_active() into b;
  perform pg_temp.record('other sessions are revoked', b = false);

  -- 10. Ending a session deactivates it.
  perform pg_temp.as_session(u1, s1a);
  perform public.end_current_device_session();
  select public.is_current_device_session_active() into b;
  perform pg_temp.record('ended session is inactive', b = false);

  -- 11. anon cannot call the device functions.
  perform pg_temp.as_anon();
  perform pg_temp.expect_error('anon cannot register devices',
    format($f$select public.register_current_device(%L, 'x', 'android', 'mobile')$f$, dev_a));
  perform pg_temp.expect_error('anon cannot read devices',
    $f$select * from public.user_devices$f$);
  perform pg_temp.expect_error('anon cannot revoke other sessions',
    $f$select public.revoke_other_device_sessions()$f$);

  reset role;
end $$;

reset role;
select name, case when ok then 'PASS' else 'FAIL' end as result, detail from check_results order by ctid;

do $$
declare n int;
begin
  select count(*) into n from check_results where not ok;
  if n > 0 then
    raise exception '% device registry check(s) failed', n;
  end if;
  raise notice 'All % device registry checks passed.', (select count(*) from check_results);
end $$;

rollback;
