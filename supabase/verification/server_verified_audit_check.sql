-- Server-generated audit boundary checks (plain SQL; no pgTAP required).
--
-- Run against a local or throwaway database with all migrations applied:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/verification/server_verified_audit_check.sql
--
-- The transaction is rolled back. Do not run against production.

begin;

create temp table check_results (name text, ok boolean, detail text);
grant all on check_results to public;

create function pg_temp.as_session(p_user uuid, p_session uuid) returns void
language plpgsql as $$
begin
  reset role;
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', p_user,
      'session_id', p_session,
      'role', 'authenticated'
    )::text,
    true
  );
  set local role authenticated;
end
$$;

create function pg_temp.record(p_name text, p_ok boolean, p_detail text default null)
returns void language plpgsql as $$
begin
  insert into check_results values (p_name, coalesce(p_ok, false), p_detail);
end
$$;

create function pg_temp.expect_error(p_name text, p_sql text)
returns void language plpgsql as $$
declare
  v_message text;
begin
  begin
    execute p_sql;
    perform pg_temp.record(p_name, false, 'statement unexpectedly succeeded');
  exception when others then
    get stacked diagnostics v_message = message_text;
    perform pg_temp.record(p_name, true, v_message);
  end;
end
$$;

do $$
declare
  v_user constant uuid := '00000000-0000-4000-8000-0000000000a1';
  v_business constant uuid := '00000000-0000-4000-8000-0000000000b1';
  v_session constant uuid := '00000000-0000-4000-8000-00000000c001';
  v_device constant uuid := '00000000-0000-4000-8000-00000000d001';
  v_account constant uuid := '00000000-0000-4000-8000-00000000e001';
  v_count integer;
  v_audit public.audit_logs%rowtype;
  v_redacted jsonb;
begin
  insert into auth.users (id, email)
  values (v_user, 'audit-check@example.test');
  insert into public.businesses (id, owner_user_id, name)
  values (v_business, v_user, 'Audit check');
  insert into public.business_memberships (business_id, user_id, role)
  values (v_business, v_user, 'owner');

  perform pg_temp.as_session(v_user, v_session);
  perform public.register_current_device(
    v_device, 'Audit check', 'android', 'mobile', 'test'
  );

  insert into public.accounts (id, business_id, name, type)
  values (v_account, v_business, 'Original name', 'asset');
  update public.accounts set name = 'Updated name' where id = v_account;

  select count(*) into v_count
  from public.audit_logs
  where business_id = v_business
    and entity_type = 'accounts'
    and entity_id = v_account::text
    and source = 'database'
    and user_id = v_user;
  perform pg_temp.record(
    'account insert/update generated database audit rows',
    v_count = 2,
    v_count::text
  );

  select * into v_audit
  from public.audit_logs
  where business_id = v_business
    and entity_type = 'accounts'
    and entity_id = v_account::text
    and action = 'database.accounts_update';
  perform pg_temp.record(
    'audit event contains the actual before and after values',
    v_audit.before_json ->> 'name' = 'Original name'
      and v_audit.after_json ->> 'name' = 'Updated name'
      and v_audit.source = 'database',
    coalesce(v_audit.before_json::text, 'missing before/after snapshot')
  );

  perform pg_temp.expect_error(
    'authenticated client cannot claim a database-generated event',
    format(
      'insert into public.audit_logs '
      '(id, business_id, user_id, action, entity_type, created_at, source) '
      'values (gen_random_uuid(), %L, %L, %L, %L, now(), %L)',
      v_business, v_user, 'database.accounts_update', 'accounts', 'database'
    )
  );

  insert into public.audit_logs (
    id, business_id, user_id, action, entity_type, created_at, source
  )
  values (
    gen_random_uuid(), v_business, v_user, 'client.note', 'accounts', now(),
    'client_reported'
  );
  perform pg_temp.record(
    'authenticated client may submit explicitly unverified events',
    exists (
      select 1 from public.audit_logs
      where business_id = v_business
        and action = 'client.note'
        and source = 'client_reported'
    )
  );

  reset role;
  select app_private.redact_audit_jsonb(
    '{"nested":{"passwordHash":"secret","api_key":"private","safe":"visible"}}'
  ) into v_redacted;
  perform pg_temp.record(
    'sensitive nested values are redacted',
    v_redacted #>> '{nested,passwordHash}' = '***'
      and v_redacted #>> '{nested,api_key}' = '***'
      and v_redacted #>> '{nested,safe}' = 'visible',
    v_redacted::text
  );

  perform pg_temp.record(
    'audit log insert privilege is limited by source policy',
    has_table_privilege('authenticated', 'public.audit_logs', 'INSERT')
  );
end
$$;

table check_results;

do $$
begin
  if exists (select 1 from check_results where not ok) then
    raise exception 'server-verified audit checks failed';
  end if;
end
$$;

rollback;
