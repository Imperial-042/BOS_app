-- Installation registry and BOS session correlation.
-- The installation UUID is not a hardware identifier and is not an
-- authorization credential. Auth user + JWT session_id remain authoritative.

create table public.user_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  device_uuid uuid not null,
  device_name text not null check (
    char_length(btrim(device_name)) between 1 and 80
  ),
  platform text not null check (platform in (
    'android', 'ios', 'windows', 'macos', 'linux', 'web', 'fuchsia', 'unknown'
  )),
  client_type text not null check (client_type in (
    'mobile', 'tablet', 'desktop', 'web', 'pos',
    'warehouse_terminal', 'admin_terminal'
  )),
  app_version text,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  last_sync_at timestamptz,
  status text not null default 'active' check (
    status in ('active', 'revoked', 'blocked')
  ),
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, device_uuid),
  unique (id, user_id)
);

create index user_devices_user_last_seen_idx
  on public.user_devices (user_id, last_seen_at desc);
create index user_devices_device_uuid_idx
  on public.user_devices (device_uuid);
create index user_devices_status_idx
  on public.user_devices (status);

create trigger user_devices_set_updated_at
  before update on public.user_devices
  for each row execute function public.set_updated_at();

create table public.device_sessions (
  session_id uuid primary key,
  user_device_id uuid not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  status text not null default 'active' check (
    status in ('active', 'ended', 'revoked')
  ),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  ended_at timestamptz,
  revoked_at timestamptz,
  foreign key (user_device_id, user_id)
    references public.user_devices (id, user_id) on delete cascade
);

create index device_sessions_user_device_status_idx
  on public.device_sessions (user_device_id, status);
create index device_sessions_user_status_idx
  on public.device_sessions (user_id, status);

alter table public.user_devices enable row level security;
alter table public.device_sessions enable row level security;

create policy user_devices_select_own
  on public.user_devices for select to authenticated
  using ((select auth.uid()) = user_id);

create policy device_sessions_select_own
  on public.device_sessions for select to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.user_devices, public.device_sessions
  from anon, authenticated;
grant select on public.user_devices, public.device_sessions to authenticated;

-- This helper intentionally checks the session_id from the signed JWT against
-- server-recorded session state. A client-supplied device UUID alone cannot
-- authorize a session. Revoking a device therefore blocks Data API access
-- through RLS even until the JWT itself expires.
create or replace function public.is_current_device_session_active()
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.device_sessions ds
    join public.user_devices d on d.id = ds.user_device_id
    where ds.session_id = (auth.jwt() ->> 'session_id')::uuid
      and ds.user_id = (select auth.uid())
      and ds.status = 'active'
      and d.status = 'active'
  );
$$;

revoke all on function public.is_current_device_session_active()
  from public, anon;
grant execute on function public.is_current_device_session_active()
  to authenticated;

-- Registration always derives the account and Supabase session from the JWT.
-- A revoked device or previously revoked session is never silently restored.
create or replace function public.register_current_device(
  p_device_uuid uuid,
  p_device_name text,
  p_platform text,
  p_client_type text,
  p_app_version text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_session_id uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
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
    user_id, device_uuid, device_name, platform, client_type, app_version
  ) values (
    v_user_id, p_device_uuid, btrim(p_device_name), p_platform,
    p_client_type, nullif(btrim(p_app_version), '')
  )
  on conflict (user_id, device_uuid) do update
    set platform = excluded.platform,
        client_type = excluded.client_type,
        app_version = excluded.app_version,
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

create or replace function public.rename_current_user_device(
  p_device_uuid uuid,
  p_device_name text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'authenticated user required';
  end if;
  if not public.is_current_device_session_active() then
    raise exception 'device authorization required';
  end if;
  if p_device_name is null
     or char_length(btrim(p_device_name)) not between 1 and 80 then
    raise exception 'device name must be between 1 and 80 characters';
  end if;

  update public.user_devices
  set device_name = btrim(p_device_name)
  where user_id = (select auth.uid())
    and device_uuid = p_device_uuid;

  if not found then
    raise exception 'device not found';
  end if;
end;
$$;

create or replace function public.revoke_current_user_device(
  p_device_uuid uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_session_id uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  v_device_id uuid;
begin
  if v_user_id is null or v_session_id is null then
    raise exception 'authenticated session required';
  end if;
  if not public.is_current_device_session_active() then
    raise exception 'device authorization required';
  end if;

  select id into v_device_id
  from public.user_devices
  where user_id = v_user_id and device_uuid = p_device_uuid;
  if v_device_id is null then
    raise exception 'device not found';
  end if;
  if exists (
    select 1 from public.device_sessions
    where session_id = v_session_id and user_device_id = v_device_id
  ) then
    raise exception 'use sign out to leave the current device';
  end if;

  update public.user_devices
  set status = 'revoked', revoked_at = now()
  where id = v_device_id;
  update public.device_sessions
  set status = 'revoked', revoked_at = now()
  where user_device_id = v_device_id and status = 'active';
end;
$$;

-- Reactivation is an explicit action on the same installation after a fresh
-- Supabase login. The prior session must not be reusable.
create or replace function public.reactivate_current_user_device(
  p_device_uuid uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_session_id uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  v_device public.user_devices%rowtype;
begin
  if v_user_id is null or v_session_id is null then
    raise exception 'authenticated session required';
  end if;
  if exists (
    select 1 from public.device_sessions where session_id = v_session_id
  ) then
    raise exception 'sign in again before reactivating this device';
  end if;

  update public.user_devices
  set status = 'active', revoked_at = null, last_seen_at = now()
  where user_id = v_user_id
    and device_uuid = p_device_uuid
    and status = 'revoked'
  returning * into v_device;

  if not found then
    raise exception 'revoked device not found';
  end if;

  insert into public.device_sessions (
    session_id, user_device_id, user_id
  ) values (
    v_session_id, v_device.id, v_user_id
  );

  return jsonb_build_object(
    'id', v_device.id,
    'device_uuid', v_device.device_uuid,
    'device_name', v_device.device_name,
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

create or replace function public.revoke_other_device_sessions()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_session_id uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
begin
  if v_user_id is null or v_session_id is null then
    raise exception 'authenticated session required';
  end if;
  if not public.is_current_device_session_active() then
    raise exception 'device authorization required';
  end if;

  update public.device_sessions
  set status = 'revoked', revoked_at = now()
  where user_id = v_user_id
    and session_id <> v_session_id
    and status = 'active';
end;
$$;

create or replace function public.end_current_device_session()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_session_id uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
begin
  if v_user_id is null or v_session_id is null then
    raise exception 'authenticated session required';
  end if;

  update public.device_sessions
  set status = 'ended', ended_at = now()
  where session_id = v_session_id and user_id = v_user_id
    and status = 'active';
end;
$$;

create or replace function public.touch_current_device_sync()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_session_id uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
begin
  if v_user_id is null or v_session_id is null
     or not public.is_current_device_session_active() then
    raise exception 'device authorization required';
  end if;

  update public.user_devices d
  set last_sync_at = now()
  from public.device_sessions ds
  where ds.session_id = v_session_id
    and ds.user_id = v_user_id
    and ds.user_device_id = d.id;
end;
$$;

revoke all on function public.register_current_device(uuid, text, text, text, text),
  public.rename_current_user_device(uuid, text),
  public.revoke_current_user_device(uuid),
  public.reactivate_current_user_device(uuid),
  public.revoke_other_device_sessions(),
  public.end_current_device_session(),
  public.touch_current_device_sync()
  from public, anon;
grant execute on function
  public.register_current_device(uuid, text, text, text, text),
  public.rename_current_user_device(uuid, text),
  public.revoke_current_user_device(uuid),
  public.reactivate_current_user_device(uuid),
  public.revoke_other_device_sessions(),
  public.end_current_device_session(),
  public.touch_current_device_sync()
  to authenticated;

revoke all on function public.is_business_member(uuid),
  public.business_role(uuid),
  public.is_business_manager(uuid),
  public.create_business_with_owner(text, text, text, text, text),
  public.redeem_invite_code(text)
  from public, anon;
grant execute on function public.is_business_member(uuid),
  public.business_role(uuid),
  public.is_business_manager(uuid),
  public.create_business_with_owner(text, text, text, text, text),
  public.redeem_invite_code(text)
  to authenticated;

-- Add device authorization to the shared membership boundary. This blocks
-- business RLS, sync, and storage access for revoked/unknown sessions.
create or replace function public.is_business_member(p_business_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select public.is_current_device_session_active() and exists (
    select 1
    from public.business_memberships m
    where m.business_id = p_business_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
  );
$$;

create or replace function public.business_role(p_business_id uuid)
returns text
language sql
security definer
stable
set search_path = ''
as $$
  select m.role
  from public.business_memberships m
  where m.business_id = p_business_id
    and m.user_id = (select auth.uid())
    and m.status = 'active'
    and public.is_current_device_session_active()
  limit 1;
$$;

create or replace function public.is_business_manager(p_business_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select public.is_current_device_session_active()
    and public.business_role(p_business_id) in ('owner', 'manager');
$$;

drop policy if exists memberships_select_member
  on public.business_memberships;
create policy memberships_select_member on public.business_memberships
  for select to authenticated using (
    public.is_current_device_session_active()
    and (
      public.is_business_member(business_id)
      or user_id = (select auth.uid())
    )
  );

drop policy if exists businesses_insert_authenticated on public.businesses;
create policy businesses_insert_authenticated on public.businesses
  for insert to authenticated
  with check (
    (select auth.uid()) = owner_user_id
    and public.is_current_device_session_active()
  );

drop policy if exists memberships_insert_manage on public.business_memberships;
create policy memberships_insert_manage on public.business_memberships
  for insert to authenticated
  with check (
    public.is_current_device_session_active()
    and (
      public.is_business_manager(business_id)
      or user_id = (select auth.uid())
    )
  );

-- product_categories has bespoke policies rather than the shared membership
-- helper; include the same device-session check explicitly.
drop policy if exists product_categories_select on public.product_categories;
create policy product_categories_select on public.product_categories
  for select to authenticated using (
    public.is_current_device_session_active()
    and exists (
      select 1 from public.business_memberships bm
      where bm.business_id = product_categories.business_id
        and bm.user_id = (select auth.uid()) and bm.status = 'active'
    )
  );

drop policy if exists product_categories_insert on public.product_categories;
create policy product_categories_insert on public.product_categories
  for insert to authenticated with check (
    public.is_current_device_session_active()
    and exists (
      select 1 from public.business_memberships bm
      where bm.business_id = product_categories.business_id
        and bm.user_id = (select auth.uid()) and bm.status = 'active'
    )
  );

drop policy if exists product_categories_update on public.product_categories;
create policy product_categories_update on public.product_categories
  for update to authenticated using (
    public.is_current_device_session_active()
    and exists (
      select 1 from public.business_memberships bm
      where bm.business_id = product_categories.business_id
        and bm.user_id = (select auth.uid()) and bm.status = 'active'
    )
  ) with check (
    public.is_current_device_session_active()
    and exists (
      select 1 from public.business_memberships bm
      where bm.business_id = product_categories.business_id
        and bm.user_id = (select auth.uid()) and bm.status = 'active'
    )
  );

drop policy if exists product_categories_delete on public.product_categories;
create policy product_categories_delete on public.product_categories
  for delete to authenticated using (
    public.is_current_device_session_active()
    and exists (
      select 1 from public.business_memberships bm
      where bm.business_id = product_categories.business_id
        and bm.user_id = (select auth.uid()) and bm.status = 'active'
    )
  );

-- Security-definer business/invite creation functions must use the same
-- device boundary because they do not rely solely on RLS.
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
set search_path = ''
as $$
declare
  v_business_id uuid;
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception 'not authenticated';
  end if;
  if not public.is_current_device_session_active() then
    raise exception 'device authorization required';
  end if;
  if btrim(p_name) = '' then
    raise exception 'business name is required';
  end if;

  insert into public.businesses (
    owner_user_id, name, business_type, industry, currency_code, timezone
  ) values (
    v_user_id, btrim(p_name), p_business_type, p_industry,
    coalesce(p_currency_code, 'PHP'), coalesce(p_timezone, 'Asia/Manila')
  )
  returning id into v_business_id;

  insert into public.business_memberships (business_id, user_id, role)
  values (v_business_id, v_user_id, 'owner');

  return v_business_id;
end;
$$;

create or replace function public.redeem_invite_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invite public.business_invites%rowtype;
  v_membership_id uuid;
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception 'not authenticated';
  end if;
  if not public.is_current_device_session_active() then
    raise exception 'device authorization required';
  end if;

  select * into v_invite
  from public.business_invites
  where code = upper(btrim(p_code)) and status = 'pending'
  limit 1;
  if not found then
    raise exception 'invalid or used invite code';
  end if;

  update public.business_invites
  set status = 'used', used_by_user_id = v_user_id, used_at = now()
  where id = v_invite.id and status = 'pending';
  if not found then
    raise exception 'invalid or used invite code';
  end if;

  insert into public.business_memberships (business_id, user_id, role, status)
  values (v_invite.business_id, v_user_id, v_invite.role, 'active')
  on conflict (business_id, user_id) do update
    set role = excluded.role, status = 'active', updated_at = now()
  returning id into v_membership_id;

  return v_membership_id;
end;
$$;

notify pgrst, 'reload schema';