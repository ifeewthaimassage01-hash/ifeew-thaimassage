-- =============================================================================
-- Phase 1 / 009 — branch_devices และ staff_pins (Staff Login แบบเลือกชื่อ + PIN)
-- =============================================================================
-- ขั้นตอน:
--  1) OWNER (aal2) ผูกเครื่องกับสาขา -> ได้ device_token ครั้งเดียว เก็บในเครื่อง
--  2) เครื่องที่ผูกแล้วเรียก Edge Function device-staff-list เพื่อแสดงรายชื่อพนักงานสาขานั้น
--  3) พนักงานแตะชื่อ + กด PIN -> Edge Function staff-pin-login ตรวจผ่าน
--     public.device_verify_staff_pin แล้วออก Supabase session ของพนักงาน
-- DB เก็บเฉพาะ hash: device token = sha256, PIN = bcrypt

-- -----------------------------------------------------------------------------
-- branch_devices
-- -----------------------------------------------------------------------------
create table public.branch_devices (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null,
  branch_id     uuid not null,
  name          text not null check (char_length(name) between 1 and 100),
  token_hash    text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  status        text not null default 'ACTIVE' check (status in ('ACTIVE', 'REVOKED')),
  paired_by     uuid not null references public.profiles (id),
  paired_at     timestamptz not null default now(),
  last_seen_at  timestamptz,
  revoked_by    uuid references public.profiles (id),
  revoked_at    timestamptz,
  revoke_reason text check (revoke_reason is null or char_length(revoke_reason) between 3 and 500),
  created_at    timestamptz not null default now(),
  created_by    uuid references public.profiles (id),
  updated_at    timestamptz not null default now(),
  constraint branch_devices_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint branch_devices_revoked_chk check (
    (status = 'ACTIVE' and revoked_at is null)
    or (status = 'REVOKED' and revoked_at is not null and revoke_reason is not null)
  )
);

comment on table public.branch_devices is 'เครื่องประจำสาขาที่ OWNER ผูกไว้สำหรับ Staff Login ด้วย PIN';

create index branch_devices_branch_idx on public.branch_devices (branch_id, status);

create trigger branch_devices_stamp
  before insert or update on public.branch_devices
  for each row execute function private.tg_stamp();

-- -----------------------------------------------------------------------------
-- staff_pins: PIN 6 หลักของ STAFF ต่อบริษัท
-- -----------------------------------------------------------------------------
create table public.staff_pins (
  company_id       uuid not null,
  user_id          uuid not null,
  pin_hash         text not null,
  failed_attempts  integer not null default 0 check (failed_attempts >= 0),
  locked_until     timestamptz,
  pin_updated_at   timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  created_by       uuid references public.profiles (id),
  updated_at       timestamptz not null default now(),
  primary key (company_id, user_id),
  constraint staff_pins_member_fk foreign key (company_id, user_id)
    references public.company_memberships (company_id, user_id) on delete restrict
);

comment on table public.staff_pins is 'PIN (bcrypt) ของ STAFF ไม่มี Policy ให้ client เข้าถึง';

create trigger staff_pins_stamp
  before insert or update on public.staff_pins
  for each row execute function private.tg_stamp();

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function private.hash_device_token(p_token text)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(extensions.digest(p_token, 'sha256'), 'hex');
$$;

-- PIN ต้องเป็นตัวเลข 6 หลัก ห้ามเลขซ้ำทั้งหมดหรือเรียงกัน
create or replace function private.assert_valid_pin(p_pin text)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_pin is null or p_pin !~ '^[0-9]{6}$' then
    raise exception 'PIN ต้องเป็นตัวเลข 6 หลัก' using errcode = 'invalid_parameter_value';
  end if;
  if p_pin ~ '^(.)\1{5}$'
     or position(p_pin in '0123456789') > 0
     or position(p_pin in '9876543210') > 0 then
    raise exception 'PIN ง่ายเกินไป (ห้ามเลขซ้ำหรือเรียงกัน)' using errcode = 'invalid_parameter_value';
  end if;
end;
$$;

-- อุปกรณ์ที่ ACTIVE จาก token (คืน NULL ถ้าไม่พบ/ถูกยกเลิก/สาขาปิด)
create or replace function private.find_active_device(p_device_token text)
returns public.branch_devices
language sql
stable
security definer
set search_path = ''
as $$
  select d.*
    from public.branch_devices d
    join public.branches b on b.id = d.branch_id
    join public.companies c on c.id = d.company_id
   where d.token_hash = private.hash_device_token(p_device_token)
     and d.status = 'ACTIVE'
     and b.is_active
     and c.is_active;
$$;

revoke all on function private.find_active_device(text) from public;

-- STAFF ที่ทำงานสาขานี้ได้ ณ ตอนนี้
create or replace function private.is_active_staff_of_branch(p_user_id uuid, p_branch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.branch_memberships bm
      join public.company_memberships cm
        on cm.company_id = bm.company_id and cm.user_id = bm.user_id
     where bm.branch_id = p_branch_id
       and bm.user_id = p_user_id
       and bm.status = 'ACTIVE'
       and bm.effective_from <= now()
       and (bm.effective_to is null or bm.effective_to > now())
       and cm.role = 'STAFF'
       and cm.status = 'ACTIVE'
       and cm.effective_from <= now()
       and (cm.effective_to is null or cm.effective_to > now())
  );
$$;

revoke all on function private.is_active_staff_of_branch(uuid, uuid) from public;

-- -----------------------------------------------------------------------------
-- public.pair_branch_device — OWNER (aal2) เท่านั้น คืน token ครั้งเดียว
-- -----------------------------------------------------------------------------
create or replace function public.pair_branch_device(p_branch_id uuid, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid;
  v_token   text;
  v_id      uuid;
begin
  select company_id into v_company
    from public.branches where id = p_branch_id and is_active;

  if v_company is null or not private.is_company_owner(v_company) then
    raise exception 'ไม่มีสิทธิ์ผูกเครื่องกับสาขานี้' using errcode = 'insufficient_privilege';
  end if;

  if p_name is null or char_length(trim(p_name)) not between 1 and 100 then
    raise exception 'กรุณาระบุชื่อเครื่อง (ไม่เกิน 100 ตัวอักษร)' using errcode = 'invalid_parameter_value';
  end if;

  -- 256 บิตจาก CSPRNG
  v_token := 'dvc_' || encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.branch_devices (company_id, branch_id, name, token_hash, paired_by)
  values (v_company, p_branch_id, trim(p_name), private.hash_device_token(v_token), auth.uid())
  returning id into v_id;

  perform private.write_audit(
    p_action => 'DEVICE_PAIRED', p_company_id => v_company, p_branch_id => p_branch_id,
    p_table_name => 'branch_devices', p_record_id => v_id,
    p_new_values => jsonb_build_object('name', trim(p_name))
  );

  return jsonb_build_object('device_id', v_id, 'device_token', v_token);
end;
$$;

revoke all on function public.pair_branch_device(uuid, text) from public, anon;
grant execute on function public.pair_branch_device(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- public.revoke_branch_device — OWNER (aal2) ต้องมีเหตุผล
-- -----------------------------------------------------------------------------
create or replace function public.revoke_branch_device(p_device_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  d public.branch_devices;
begin
  select * into d from public.branch_devices where id = p_device_id for update;

  if d.id is null or not private.is_company_owner(d.company_id) then
    raise exception 'ไม่มีสิทธิ์ยกเลิกเครื่องนี้' using errcode = 'insufficient_privilege';
  end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาระบุเหตุผล' using errcode = 'invalid_parameter_value';
  end if;
  if d.status = 'REVOKED' then
    return;
  end if;

  update public.branch_devices
     set status = 'REVOKED', revoked_at = now(), revoked_by = auth.uid(), revoke_reason = trim(p_reason)
   where id = p_device_id;

  perform private.write_audit(
    p_action => 'DEVICE_REVOKED', p_company_id => d.company_id, p_branch_id => d.branch_id,
    p_table_name => 'branch_devices', p_record_id => d.id, p_reason => trim(p_reason)
  );
end;
$$;

revoke all on function public.revoke_branch_device(uuid, text) from public, anon;
grant execute on function public.revoke_branch_device(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- public.set_staff_pin — OWNER (aal2) ตั้ง/รีเซ็ต PIN ให้ STAFF
-- -----------------------------------------------------------------------------
create or replace function public.set_staff_pin(p_company_id uuid, p_user_id uuid, p_pin text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'ไม่มีสิทธิ์ตั้ง PIN' using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1 from public.company_memberships
     where company_id = p_company_id and user_id = p_user_id
       and role = 'STAFF' and status = 'ACTIVE'
  ) then
    raise exception 'ผู้ใช้นี้ไม่ใช่ STAFF ที่ใช้งานอยู่ของบริษัท' using errcode = 'invalid_parameter_value';
  end if;

  perform private.assert_valid_pin(p_pin);

  insert into public.staff_pins (company_id, user_id, pin_hash)
  values (p_company_id, p_user_id, extensions.crypt(p_pin, extensions.gen_salt('bf', 10)))
  on conflict (company_id, user_id) do update
    set pin_hash = excluded.pin_hash,
        failed_attempts = 0,
        locked_until = null,
        pin_updated_at = now();

  perform private.write_audit(
    p_action => 'STAFF_PIN_SET', p_company_id => p_company_id,
    p_table_name => 'staff_pins', p_metadata => jsonb_build_object('user_id', p_user_id)
  );
end;
$$;

revoke all on function public.set_staff_pin(uuid, uuid, text) from public, anon;
grant execute on function public.set_staff_pin(uuid, uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- public.change_my_pin — STAFF เปลี่ยน PIN ตัวเอง (ต้องรู้ PIN เดิม)
-- -----------------------------------------------------------------------------
create or replace function public.change_my_pin(p_company_id uuid, p_current_pin text, p_new_pin text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.staff_pins;
begin
  if auth.uid() is null or not private.is_company_member(p_company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;

  select * into p from public.staff_pins
   where company_id = p_company_id and user_id = auth.uid()
   for update;

  if p.user_id is null then
    raise exception 'ยังไม่มี PIN กรุณาติดต่อเจ้าของร้าน' using errcode = 'no_data_found';
  end if;
  if p.locked_until is not null and p.locked_until > now() then
    raise exception 'PIN ถูกล็อกชั่วคราว' using errcode = 'lock_not_available';
  end if;
  if p.pin_hash <> extensions.crypt(coalesce(p_current_pin, ''), p.pin_hash) then
    raise exception 'PIN เดิมไม่ถูกต้อง' using errcode = 'invalid_password';
  end if;

  perform private.assert_valid_pin(p_new_pin);

  update public.staff_pins
     set pin_hash = extensions.crypt(p_new_pin, extensions.gen_salt('bf', 10)),
         failed_attempts = 0, locked_until = null, pin_updated_at = now()
   where company_id = p_company_id and user_id = auth.uid();

  perform private.write_audit(
    p_action => 'STAFF_PIN_CHANGED', p_company_id => p_company_id, p_table_name => 'staff_pins'
  );
end;
$$;

revoke all on function public.change_my_pin(uuid, text, text) from public, anon;
grant execute on function public.change_my_pin(uuid, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- public.device_list_staff — service_role เท่านั้น (เรียกจาก Edge Function)
-- คืนเฉพาะ user_id + display_name ของ STAFF สาขาของเครื่อง ที่ตั้ง PIN แล้ว
-- -----------------------------------------------------------------------------
create or replace function public.device_list_staff(p_device_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  d public.branch_devices;
  v_result jsonb;
begin
  d := private.find_active_device(p_device_token);
  if d.id is null then
    return jsonb_build_object('ok', false, 'error_code', 'DEVICE_INVALID');
  end if;

  update public.branch_devices
     set last_seen_at = now()
   where id = d.id
     and (last_seen_at is null or last_seen_at < now() - interval '1 minute');

  select jsonb_build_object(
    'ok', true,
    'device', jsonb_build_object(
      'device_id', d.id,
      'device_name', d.name,
      'company_id', d.company_id,
      'branch_id', d.branch_id,
      'branch_name', b.name,
      'idle_lock_minutes', s.staff_idle_lock_minutes
    ),
    'staff', coalesce((
      select jsonb_agg(jsonb_build_object(
               'user_id', p.id,
               'display_name', p.display_name,
               'locked', sp.locked_until is not null and sp.locked_until > now()
             ) order by p.display_name)
        from public.staff_pins sp
        join public.profiles p on p.id = sp.user_id
       where sp.company_id = d.company_id
         and private.is_active_staff_of_branch(sp.user_id, d.branch_id)
    ), '[]'::jsonb)
  )
  into v_result
  from public.branches b
  join public.company_settings s on s.company_id = b.company_id
  where b.id = d.branch_id;

  return v_result;
end;
$$;

revoke all on function public.device_list_staff(text) from public, anon, authenticated;
grant execute on function public.device_list_staff(text) to service_role;

-- -----------------------------------------------------------------------------
-- public.device_verify_staff_pin — service_role เท่านั้น
-- ไม่ raise เมื่อ PIN ผิด เพื่อให้ตัวนับ failed_attempts ถูก commit
-- -----------------------------------------------------------------------------
create or replace function public.device_verify_staff_pin(
  p_device_token text,
  p_user_id      uuid,
  p_pin          text,
  p_client_ip    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  d      public.branch_devices;
  sp     public.staff_pins;
  s      public.company_settings;
  v_meta jsonb;
begin
  d := private.find_active_device(p_device_token);
  if d.id is null then
    return jsonb_build_object('ok', false, 'error_code', 'DEVICE_INVALID');
  end if;

  v_meta := jsonb_build_object('device_id', d.id, 'client_ip', p_client_ip);

  if not private.is_active_staff_of_branch(p_user_id, d.branch_id) then
    perform private.write_audit(
      p_action => 'STAFF_PIN_LOGIN_DENIED', p_company_id => d.company_id, p_branch_id => d.branch_id,
      p_metadata => v_meta || jsonb_build_object('user_id', p_user_id, 'cause', 'NOT_BRANCH_STAFF')
    );
    return jsonb_build_object('ok', false, 'error_code', 'INVALID_CREDENTIALS');
  end if;

  select * into sp from public.staff_pins
   where company_id = d.company_id and user_id = p_user_id
   for update;

  if sp.user_id is null then
    return jsonb_build_object('ok', false, 'error_code', 'INVALID_CREDENTIALS');
  end if;

  if sp.locked_until is not null and sp.locked_until > now() then
    return jsonb_build_object('ok', false, 'error_code', 'PIN_LOCKED', 'locked_until', sp.locked_until);
  end if;

  select * into s from public.company_settings where company_id = d.company_id;

  if sp.pin_hash <> extensions.crypt(coalesce(p_pin, ''), sp.pin_hash) then
    if sp.failed_attempts + 1 >= s.staff_pin_max_attempts then
      update public.staff_pins
         set failed_attempts = 0,
             locked_until = now() + make_interval(mins => s.staff_pin_lockout_minutes)
       where company_id = sp.company_id and user_id = sp.user_id
      returning * into sp;

      perform private.write_audit(
        p_action => 'STAFF_PIN_LOCKED', p_company_id => d.company_id, p_branch_id => d.branch_id,
        p_actor => p_user_id, p_metadata => v_meta
      );
      return jsonb_build_object('ok', false, 'error_code', 'PIN_LOCKED', 'locked_until', sp.locked_until);
    end if;

    update public.staff_pins
       set failed_attempts = failed_attempts + 1
     where company_id = sp.company_id and user_id = sp.user_id;

    perform private.write_audit(
      p_action => 'STAFF_PIN_LOGIN_FAILED', p_company_id => d.company_id, p_branch_id => d.branch_id,
      p_actor => p_user_id, p_metadata => v_meta
    );
    return jsonb_build_object(
      'ok', false, 'error_code', 'INVALID_CREDENTIALS',
      'attempts_left', s.staff_pin_max_attempts - (sp.failed_attempts + 1)
    );
  end if;

  update public.staff_pins
     set failed_attempts = 0, locked_until = null
   where company_id = sp.company_id and user_id = sp.user_id
     and (failed_attempts <> 0 or locked_until is not null);

  update public.branch_devices set last_seen_at = now() where id = d.id;

  perform private.write_audit(
    p_action => 'STAFF_PIN_LOGIN_SUCCESS', p_company_id => d.company_id, p_branch_id => d.branch_id,
    p_actor => p_user_id, p_metadata => v_meta
  );

  return jsonb_build_object(
    'ok', true,
    'user_id', p_user_id,
    'company_id', d.company_id,
    'branch_id', d.branch_id,
    'idle_lock_minutes', s.staff_idle_lock_minutes
  );
end;
$$;

revoke all on function public.device_verify_staff_pin(text, uuid, text, text) from public, anon, authenticated;
grant execute on function public.device_verify_staff_pin(text, uuid, text, text) to service_role;
