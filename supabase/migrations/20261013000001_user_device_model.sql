-- Hardware model is informational, separate from the user-editable name.
alter table public.user_devices
  add column if not exists device_model text;

alter table public.user_devices
  drop constraint if exists user_devices_device_model_len;
alter table public.user_devices
  add constraint user_devices_device_model_len
  check (device_model is null or char_length(device_model) <= 120);

-- Remove the earlier helper if it was ever applied, and the old 5-arg
-- signature (keeping both would create an ambiguous overload in PostgREST).
drop function if exists public.set_current_device_model(text, text);
drop function if exists public.register_current_device(uuid, text, text, text, text);

create or replace function public.register_current_device(
  p_device_uuid uuid,
  p_device_name text,
  p_platform text,
  p_client_type text,
  p_app_version text default null,
  p_device_model text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_session_id uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  v_model text := nullif(left(btrim(coalesce(p_device_model, '')), 120), '');
  v_device public.user_devices%rowtype;
  v_session public.device_sessions%rowtype;
begin
  if v_user_id is null or v_session_id is null then
    raise exception 'authenticated session required';
  end if;
  if p_device_uuid is null then
    raise exception 'device identifier is required';
  end if;
  if p_device_name is null
     or char_length(btrim(p_device_name)) not between 1 and 80 then
    raise exception 'device name must be between 1 and 80 characters';
  end if;
  if p_platform not in (
    'android', 'ios', 'windows', 'macos', 'linux', 'web', 'fuchsia', 'unknown'
  ) then
    raise exception 'unsupported platform';
  end if;
  if p_client_type not in (
    'mobile', 'tablet', 'desktop', 'web', 'pos',
    'warehouse_terminal', 'admin_terminal'
  ) then
    raise exception 'unsupported client type';
  end if;

  insert into public.user_devices (
    user_id, device_uuid, device_name, device_model, platform, client_type,
    app_version
  ) values (
    v_user_id, p_device_uuid, btrim(p_device_name), v_model, p_platform,
    p_client_type, nullif(btrim(p_app_version), '')
  )
  on conflict (user_id, device_uuid) do update
    set platform = excluded.platform,
        client_type = excluded.client_type,
        app_version = excluded.app_version,
        device_model = coalesce(excluded.device_model,
                                public.user_devices.device_model),
        last_seen_at = case
          when public.user_devices.last_seen_at < now() - interval '5 minutes'
            then now()
          else public.user_devices.last_seen_at
        end
  returning * into v_device;

  if v_device.status <> 'active' then
    return jsonb_build_object(
      'id', v_device.id,
      'device_uuid', v_device.device_uuid,
      'device_name', v_device.device_name,
      'device_model', v_device.device_model,
      'platform', v_device.platform,
      'client_type', v_device.client_type,
      'app_version', v_device.app_version,
      'status', v_device.status,
      'reauthentication_required', exists (
        select 1 from public.device_sessions
        where session_id = v_session_id
      ),
      'first_seen_at', v_device.first_seen_at,
      'last_seen_at', v_device.last_seen_at,
      'last_sync_at', v_device.last_sync_at
    );
  end if;

  insert into public.device_sessions (
    session_id, user_device_id, user_id
  ) values (
    v_session_id, v_device.id, v_user_id
  )
  on conflict (session_id) do update
    set last_seen_at = case
      when public.device_sessions.last_seen_at < now() - interval '5 minutes'
        then now()
      else public.device_sessions.last_seen_at
    end
    where public.device_sessions.user_device_id = excluded.user_device_id
      and public.device_sessions.user_id = excluded.user_id
      and public.device_sessions.status = 'active'
  returning * into v_session;

  if not found then
    raise exception
      'session is already associated or ended; sign in again to continue';
  end if;

  return jsonb_build_object(
    'id', v_device.id,
    'device_uuid', v_device.device_uuid,
    'device_name', v_device.device_name,
    'device_model', v_device.device_model,
    'platform', v_device.platform,
    'client_type', v_device.client_type,
    'app_version', v_device.app_version,
    'status', v_device.status,
    'first_seen_at', v_device.first_seen_at,
    'last_seen_at', v_device.last_seen_at,
    'last_sync_at', v_device.last_sync_at
  );
end;
$$;

revoke all on function
  public.register_current_device(uuid, text, text, text, text, text)
  from public, anon;
grant execute on function
  public.register_current_device(uuid, text, text, text, text, text)
  to authenticated;

notify pgrst, 'reload schema';