-- =============================================================================
-- 028 — เจ้าของร้าน login ด้วย PIN 6 หลักเหมือนพนักงาน (ตามที่ผู้ใช้เลือก — เปลี่ยนจากสเปกข้อ 2)
--   * OWNER ไม่บังคับ MFA (TOTP) อีกต่อไป: เป็น OWNER ด้วยบทบาทเพียงอย่างเดียว
--   * งานเสี่ยงสูงไม่ขอยืนยันตัวตนซ้ำ (require_owner_step_up ตรวจแค่ว่าเป็น OWNER)
--   * OWNER ตั้ง PIN ของตัวเองได้ และ login ด้วย PIN บนเครื่องสาขาที่ผูกแล้ว (ทุกสาขาของบริษัท)
--     PIN ใช้กฎเดียวกับพนักงาน: 6 หลัก ห้ามเลขซ้ำ/เรียง, กดผิดหลายครั้งถูกล็อกชั่วคราว
--   * Login ด้วยอีเมล + รหัสผ่านยังใช้ได้ (สำรอง เช่น ใช้นอกร้าน/ยังไม่มีเครื่องที่ผูก)
-- ความเสี่ยงที่ยอมรับ: ใครเห็น PIN ของเจ้าของร้านจะเข้าถึงข้อมูลการเงินทั้งหมดจากเครื่องที่ผูกไว้
-- =============================================================================

-- OWNER = บทบาท OWNER ที่ ACTIVE (ไม่ต้อง aal2)
create or replace function private.is_company_owner(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.company_memberships cm
     where cm.company_id = p_company_id
       and cm.user_id = auth.uid()
       and cm.role = 'OWNER'
       and cm.status = 'ACTIVE'
       and cm.effective_from <= now()
       and (cm.effective_to is null or cm.effective_to > now())
  );
$$;

-- งานเสี่ยงสูง: ต้องเป็น OWNER (ไม่ขอยืนยันตัวตนซ้ำแล้ว)
create or replace function private.require_owner_step_up(p_company_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_company_id is null or not private.is_company_owner(p_company_id) then
    raise exception 'ไม่มีสิทธิ์ดำเนินการ' using errcode = 'insufficient_privilege';
  end if;
end;
$$;

-- OWNER ที่ใช้งานอยู่ของบริษัท (ใช้ตอน login ด้วย PIN)
create or replace function private.is_active_owner_of_company(p_user_id uuid, p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.company_memberships cm
     where cm.company_id = p_company_id and cm.user_id = p_user_id and cm.role = 'OWNER' and cm.status = 'ACTIVE'
       and cm.effective_from <= now() and (cm.effective_to is null or cm.effective_to > now()));
$$;

revoke all on function private.is_active_owner_of_company(uuid, uuid) from public;

-- (แทนที่ 008) ไม่บังคับ MFA สำหรับ OWNER
create or replace function public.my_access()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'user_id', auth.uid(),
    'aal', private.current_aal(),
    'companies', coalesce((
      select jsonb_agg(jsonb_build_object(
        'company_id', c.id,
        'company_code', c.code,
        'company_name', c.name,
        'role', cm.role,
        'owner_mfa_required', false,
        'branches', coalesce((
          select jsonb_agg(jsonb_build_object('branch_id', b.id, 'code', b.code, 'name', b.name)
                           order by b.sort_order, b.name)
            from public.branches b
           where b.company_id = c.id
             and b.is_active
             and private.has_branch_access(b.id)
        ), '[]'::jsonb)
      ) order by c.name)
        from public.company_memberships cm
        join public.companies c on c.id = cm.company_id
       where cm.user_id = auth.uid()
         and cm.status = 'ACTIVE'
         and cm.effective_from <= now()
         and (cm.effective_to is null or cm.effective_to > now())
         and c.is_active
    ), '[]'::jsonb)
  );
$$;

-- -----------------------------------------------------------------------------
-- OWNER ตั้ง/เปลี่ยน PIN ของตัวเอง
-- -----------------------------------------------------------------------------
create or replace function public.set_my_owner_pin(p_company_id uuid, p_pin text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  perform private.assert_valid_pin(p_pin);

  insert into public.staff_pins (company_id, user_id, pin_hash)
  values (p_company_id, auth.uid(), extensions.crypt(p_pin, extensions.gen_salt('bf', 10)))
  on conflict (company_id, user_id) do update
    set pin_hash = excluded.pin_hash, failed_attempts = 0, locked_until = null, pin_updated_at = now();

  perform private.write_audit(
    p_action => 'OWNER_PIN_SET', p_company_id => p_company_id, p_table_name => 'staff_pins'
  );
end;
$$;

revoke all on function public.set_my_owner_pin(uuid, text) from public, anon;
grant execute on function public.set_my_owner_pin(uuid, text) to authenticated;

create or replace function public.my_owner_pin_status(p_company_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('has_pin', sp.user_id is not null, 'pin_updated_at', sp.pin_updated_at)
    from (select 1) x
    left join public.staff_pins sp on sp.company_id = p_company_id and sp.user_id = auth.uid()
   where private.is_company_owner(p_company_id);
$$;

revoke all on function public.my_owner_pin_status(uuid) from public, anon;
grant execute on function public.my_owner_pin_status(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- (แทนที่ 014) รายชื่อบนเครื่องสาขา: พนักงานของสาขา + เจ้าของร้าน (ถ้าตั้ง PIN แล้ว)
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
      select jsonb_agg(x.j order by x.is_owner desc, x.name)
        from (
          select jsonb_build_object(
                   'user_id', e.user_id, 'display_name', e.nickname, 'photo_path', e.photo_path,
                   'locked', sp.locked_until is not null and sp.locked_until > now(), 'is_owner', false) as j,
                 false as is_owner, e.nickname as name
            from public.staff_pins sp
            join public.employees e on e.company_id = sp.company_id and e.user_id = sp.user_id
           where sp.company_id = d.company_id
             and private.is_active_staff_of_branch(sp.user_id, d.branch_id)
          union all
          select jsonb_build_object(
                   'user_id', sp.user_id, 'display_name', coalesce(nullif(p.display_name, ''), 'เจ้าของร้าน'),
                   'photo_path', null, 'locked', sp.locked_until is not null and sp.locked_until > now(), 'is_owner', true),
                 true, coalesce(p.display_name, '')
            from public.staff_pins sp
            left join public.profiles p on p.id = sp.user_id
           where sp.company_id = d.company_id
             and private.is_active_owner_of_company(sp.user_id, d.company_id)
        ) x
    ), '[]'::jsonb)
  )
  into v_result
  from public.branches b
  join public.company_settings s on s.company_id = b.company_id
  where b.id = d.branch_id;

  return v_result;
end;
$$;

-- -----------------------------------------------------------------------------
-- (แทนที่ 009) ตรวจ PIN บนเครื่องสาขา: พนักงานของสาขา หรือ OWNER ของบริษัท
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

  if not (private.is_active_staff_of_branch(p_user_id, d.branch_id)
          or private.is_active_owner_of_company(p_user_id, d.company_id)) then
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
