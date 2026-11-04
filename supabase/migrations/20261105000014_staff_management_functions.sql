-- =============================================================================
-- Phase 2 / 014 — Function จัดการพนักงาน (ทุกตัวต้อง step-up TOTP ยกเว้น copy_schedule_week)
-- =============================================================================

-- โดเมนอีเมลภายในของบัญชี STAFF (ไม่มีกล่องจดหมายจริง login ได้เฉพาะ PIN)
create or replace function private.staff_email_domain()
returns text
language sql
immutable
set search_path = ''
as $$
  select 'staff.ifeew.internal';
$$;

-- -----------------------------------------------------------------------------
-- public.create_staff_member
-- เรียกโดย Edge Function staff-create ด้วย JWT ของ OWNER หลังสร้าง auth user แล้ว
-- สร้าง membership + สิทธิ์สาขา + employee + ประวัติเริ่มงาน + PIN ใน Transaction เดียว
-- -----------------------------------------------------------------------------
create or replace function public.create_staff_member(
  p_company_id     uuid,
  p_user_id        uuid,
  p_branch_id      uuid,
  p_employee_code  text,
  p_nickname       text,
  p_start_date     date,
  p_pin            text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email        text;
  v_bm_id        uuid;
  v_employee_id  uuid;
begin
  perform private.require_owner_step_up(p_company_id);

  if not exists (
    select 1 from public.branches where id = p_branch_id and company_id = p_company_id and is_active
  ) then
    raise exception 'ไม่พบสาขาที่เปิดใช้งานในบริษัทนี้' using errcode = 'invalid_parameter_value';
  end if;

  -- ต้องเป็นบัญชีภายในที่เพิ่งสร้าง ไม่ใช่บัญชีลูกค้าหรือบัญชีที่มีสิทธิ์อยู่แล้ว
  select email into v_email from auth.users where id = p_user_id;
  if v_email is null or v_email not like '%@' || private.staff_email_domain() then
    raise exception 'บัญชีนี้ไม่ใช่บัญชีพนักงานภายใน' using errcode = 'invalid_parameter_value';
  end if;
  if exists (select 1 from public.company_memberships where user_id = p_user_id) then
    raise exception 'บัญชีนี้ถูกใช้งานแล้ว' using errcode = 'invalid_parameter_value';
  end if;

  if p_start_date is null then
    raise exception 'กรุณาระบุวันเริ่มงาน' using errcode = 'invalid_parameter_value';
  end if;

  perform private.assert_valid_pin(p_pin);

  insert into public.company_memberships (company_id, user_id, role)
  values (p_company_id, p_user_id, 'STAFF');

  insert into public.branch_memberships (company_id, branch_id, user_id)
  values (p_company_id, p_branch_id, p_user_id)
  returning id into v_bm_id;

  insert into public.employees (company_id, user_id, employee_code, nickname, start_date)
  values (p_company_id, p_user_id, trim(p_employee_code), p_nickname, p_start_date)
  returning id into v_employee_id;

  insert into public.employee_transfers (company_id, employee_id, to_branch_id, to_membership_id, effective_from, reason)
  values (p_company_id, v_employee_id, p_branch_id, v_bm_id, now(), 'เริ่มงาน');

  insert into public.staff_pins (company_id, user_id, pin_hash)
  values (p_company_id, p_user_id, extensions.crypt(p_pin, extensions.gen_salt('bf', 10)));

  perform private.write_audit(
    p_action => 'STAFF_CREATED', p_company_id => p_company_id, p_branch_id => p_branch_id,
    p_table_name => 'employees', p_record_id => v_employee_id
  );

  return v_employee_id;
end;
$$;

revoke all on function public.create_staff_member(uuid, uuid, uuid, text, text, date, text) from public, anon;
grant execute on function public.create_staff_member(uuid, uuid, uuid, text, text, date, text) to authenticated;

-- -----------------------------------------------------------------------------
-- public.transfer_employee — ย้ายสาขาทันทีหรือล่วงหน้า
-- -----------------------------------------------------------------------------
create or replace function public.transfer_employee(
  p_employee_id     uuid,
  p_to_branch_id    uuid,
  p_effective_from  timestamptz,
  p_reason          text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_emp        public.employees;
  v_eff        timestamptz := coalesce(p_effective_from, now());
  v_current    public.branch_memberships;
  v_new_bm     uuid;
  v_shifts     integer;
  v_transfer   uuid;
begin
  select * into v_emp from public.employees where id = p_employee_id for update;
  if v_emp.id is null then
    raise exception 'ไม่พบพนักงาน' using errcode = 'no_data_found';
  end if;

  perform private.require_owner_step_up(v_emp.company_id);

  if v_emp.status = 'RESIGNED' then
    raise exception 'พนักงานลาออกแล้ว' using errcode = 'check_violation';
  end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาระบุเหตุผล' using errcode = 'invalid_parameter_value';
  end if;
  if v_eff < now() - interval '1 minute' then
    raise exception 'ห้ามย้ายสาขาย้อนหลัง' using errcode = 'invalid_parameter_value';
  end if;
  if v_eff < now() then
    v_eff := now();
  end if;
  if not exists (
    select 1 from public.branches where id = p_to_branch_id and company_id = v_emp.company_id and is_active
  ) then
    raise exception 'ไม่พบสาขาปลายทางที่เปิดใช้งาน' using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    select 1 from public.branch_memberships
     where company_id = v_emp.company_id and user_id = v_emp.user_id
       and status = 'ACTIVE' and effective_from > now()
  ) then
    raise exception 'มีการย้ายสาขาที่รอมีผลอยู่ กรุณายกเลิกก่อน' using errcode = 'check_violation';
  end if;

  select * into v_current from public.branch_memberships
   where company_id = v_emp.company_id and user_id = v_emp.user_id
     and status = 'ACTIVE'
     and effective_from <= v_eff
     and (effective_to is null or effective_to > v_eff)
   for update;

  if v_current.id is null or v_current.effective_to is not null then
    raise exception 'ไม่พบสาขาปัจจุบันของพนักงาน' using errcode = 'check_violation';
  end if;
  if v_current.branch_id = p_to_branch_id then
    raise exception 'พนักงานอยู่สาขานี้อยู่แล้ว' using errcode = 'check_violation';
  end if;

  select count(*) into v_shifts from public.employee_schedules
   where employee_id = v_emp.id and branch_id = v_current.branch_id
     and status <> 'CANCELLED' and ends_at > v_eff;
  if v_shifts > 0 then
    raise exception 'มีกะงานที่สาขาเดิมหลังวันมีผล % กะ กรุณายกเลิกหรือแก้ไขก่อน', v_shifts
      using errcode = 'check_violation';
  end if;

  if v_current.effective_from >= v_eff then
    -- สิทธิ์เดิมเริ่มพร้อมกันพอดี (ยังไม่เคยมีผล) -> เพิกถอนแทนการปิดช่วงเวลา
    update public.branch_memberships set status = 'REVOKED' where id = v_current.id;
  else
    update public.branch_memberships set effective_to = v_eff where id = v_current.id;
  end if;

  insert into public.branch_memberships (company_id, branch_id, user_id, effective_from)
  values (v_emp.company_id, p_to_branch_id, v_emp.user_id, v_eff)
  returning id into v_new_bm;

  insert into public.employee_transfers (
    company_id, employee_id, from_branch_id, to_branch_id,
    from_membership_id, to_membership_id, effective_from, reason
  ) values (
    v_emp.company_id, v_emp.id, v_current.branch_id, p_to_branch_id,
    v_current.id, v_new_bm, v_eff, trim(p_reason)
  )
  returning id into v_transfer;

  return v_transfer;
end;
$$;

revoke all on function public.transfer_employee(uuid, uuid, timestamptz, text) from public, anon;
grant execute on function public.transfer_employee(uuid, uuid, timestamptz, text) to authenticated;

-- -----------------------------------------------------------------------------
-- public.cancel_employee_transfer — ยกเลิกการย้ายที่ยังไม่มีผล
-- -----------------------------------------------------------------------------
create or replace function public.cancel_employee_transfer(p_transfer_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  t public.employee_transfers;
begin
  select * into t from public.employee_transfers where id = p_transfer_id for update;
  if t.id is null then
    raise exception 'ไม่พบรายการย้ายสาขา' using errcode = 'no_data_found';
  end if;

  perform private.require_owner_step_up(t.company_id);

  if t.status <> 'ACTIVE' or t.effective_from <= now() or t.from_membership_id is null then
    raise exception 'ยกเลิกได้เฉพาะการย้ายที่ยังไม่มีผล' using errcode = 'check_violation';
  end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาระบุเหตุผล' using errcode = 'invalid_parameter_value';
  end if;
  if exists (
    select 1 from public.employee_schedules
     where employee_id = t.employee_id and branch_id = t.to_branch_id
       and status <> 'CANCELLED' and ends_at > t.effective_from
  ) then
    raise exception 'มีกะงานที่สาขาปลายทางแล้ว กรุณายกเลิกกะก่อน' using errcode = 'check_violation';
  end if;

  update public.branch_memberships set status = 'REVOKED' where id = t.to_membership_id;
  update public.branch_memberships set effective_to = null
   where id = t.from_membership_id and effective_to = t.effective_from;

  update public.employee_transfers
     set status = 'CANCELLED', cancelled_at = now(), cancelled_by = auth.uid(), cancel_reason = trim(p_reason)
   where id = t.id;
end;
$$;

revoke all on function public.cancel_employee_transfer(uuid, text) from public, anon;
grant execute on function public.cancel_employee_transfer(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- public.set_employee_status
--   ACTIVE -> INACTIVE : ระงับ (membership SUSPENDED, ลบ PIN) คงสิทธิ์สาขาไว้
--   INACTIVE -> ACTIVE : เปิดใช้ใหม่ (ต้องตั้ง PIN ใหม่)
--   * -> RESIGNED      : ลาออก (สุดท้าย) ปิดทุกสิทธิ์ ยกเลิกการย้ายที่รอและกะในอนาคต
-- Edge Function staff-set-status จะ ban/unban บัญชีใน Auth ตามผลลัพธ์
-- -----------------------------------------------------------------------------
create or replace function public.set_employee_status(p_employee_id uuid, p_status text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_emp public.employees;
begin
  select * into v_emp from public.employees where id = p_employee_id for update;
  if v_emp.id is null then
    raise exception 'ไม่พบพนักงาน' using errcode = 'no_data_found';
  end if;

  perform private.require_owner_step_up(v_emp.company_id);

  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาระบุเหตุผล' using errcode = 'invalid_parameter_value';
  end if;
  if p_status not in ('ACTIVE', 'INACTIVE', 'RESIGNED') or p_status = v_emp.status then
    raise exception 'สถานะใหม่ไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  if v_emp.status = 'RESIGNED' then
    raise exception 'พนักงานลาออกแล้ว เปลี่ยนสถานะไม่ได้' using errcode = 'check_violation';
  end if;

  perform set_config('app.audit_reason', trim(p_reason), true);

  if p_status = 'INACTIVE' then
    update public.company_memberships set status = 'SUSPENDED'
     where company_id = v_emp.company_id and user_id = v_emp.user_id;
    delete from public.staff_pins where company_id = v_emp.company_id and user_id = v_emp.user_id;
    update public.employees set status = 'INACTIVE' where id = v_emp.id;

  elsif p_status = 'ACTIVE' then
    update public.company_memberships set status = 'ACTIVE'
     where company_id = v_emp.company_id and user_id = v_emp.user_id;
    update public.employees set status = 'ACTIVE' where id = v_emp.id;

  else -- RESIGNED
    update public.employee_schedules set status = 'CANCELLED', note = left(coalesce(note || ' | ', '') || 'ลาออก', 300)
     where employee_id = v_emp.id and status <> 'CANCELLED' and starts_at > now();

    update public.employee_transfers
       set status = 'CANCELLED', cancelled_at = now(), cancelled_by = auth.uid(), cancel_reason = 'พนักงานลาออก'
     where employee_id = v_emp.id and status = 'ACTIVE' and effective_from > now();

    update public.branch_memberships set status = 'REVOKED'
     where company_id = v_emp.company_id and user_id = v_emp.user_id
       and status = 'ACTIVE' and effective_from >= now();

    update public.branch_memberships set effective_to = now()
     where company_id = v_emp.company_id and user_id = v_emp.user_id
       and status = 'ACTIVE' and effective_from < now()
       and (effective_to is null or effective_to > now());

    update public.company_memberships
       set status = 'REVOKED',
           effective_to = greatest(now(), effective_from + interval '1 second')
     where company_id = v_emp.company_id and user_id = v_emp.user_id;

    delete from public.staff_pins where company_id = v_emp.company_id and user_id = v_emp.user_id;

    update public.employees set status = 'RESIGNED', resigned_at = now() where id = v_emp.id;
  end if;

  perform private.write_audit(
    p_action => 'EMPLOYEE_STATUS_CHANGED', p_company_id => v_emp.company_id,
    p_table_name => 'employees', p_record_id => v_emp.id,
    p_old_values => jsonb_build_object('status', v_emp.status),
    p_new_values => jsonb_build_object('status', p_status),
    p_reason => trim(p_reason)
  );

  return jsonb_build_object('employee_id', v_emp.id, 'user_id', v_emp.user_id, 'status', p_status);
end;
$$;

revoke all on function public.set_employee_status(uuid, text, text) from public, anon;
grant execute on function public.set_employee_status(uuid, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- public.set_staff_pin — (แทนที่ Phase 1) ต้อง step-up และพนักงานต้อง ACTIVE
-- -----------------------------------------------------------------------------
create or replace function public.set_staff_pin(p_company_id uuid, p_user_id uuid, p_pin text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_owner_step_up(p_company_id);

  if not exists (
    select 1
      from public.company_memberships cm
      join public.employees e on e.company_id = cm.company_id and e.user_id = cm.user_id
     where cm.company_id = p_company_id and cm.user_id = p_user_id
       and cm.role = 'STAFF' and cm.status = 'ACTIVE' and e.status = 'ACTIVE'
  ) then
    raise exception 'ผู้ใช้นี้ไม่ใช่พนักงานที่ใช้งานอยู่ของบริษัท' using errcode = 'invalid_parameter_value';
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

-- -----------------------------------------------------------------------------
-- public.copy_schedule_week — คัดลอกกะ SCHEDULED จากสัปดาห์ต้นทาง (จันทร์-อาทิตย์ เวลาไทย)
-- ข้ามกะที่ซ้อนหรือพนักงานไม่สังกัดสาขาแล้ว และรายงานจำนวน
-- -----------------------------------------------------------------------------
create or replace function public.copy_schedule_week(
  p_branch_id      uuid,
  p_source_monday  date,
  p_target_monday  date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company  uuid;
  v_tz       text;
  v_days     integer;
  v_copied   integer := 0;
  v_skipped  integer := 0;
  r          record;
begin
  select b.company_id, s.timezone into v_company, v_tz
    from public.branches b join public.company_settings s on s.company_id = b.company_id
   where b.id = p_branch_id;

  if v_company is null or not private.is_company_owner(v_company) then
    raise exception 'ไม่มีสิทธิ์จัดตารางงานสาขานี้' using errcode = 'insufficient_privilege';
  end if;
  if extract(isodow from p_source_monday) <> 1 or extract(isodow from p_target_monday) <> 1 then
    raise exception 'วันเริ่มสัปดาห์ต้องเป็นวันจันทร์' using errcode = 'invalid_parameter_value';
  end if;
  if p_source_monday = p_target_monday then
    raise exception 'สัปดาห์ต้นทางและปลายทางต้องต่างกัน' using errcode = 'invalid_parameter_value';
  end if;

  v_days := p_target_monday - p_source_monday;

  for r in
    select s.employee_id, s.starts_at, s.ends_at, s.note
      from public.employee_schedules s
     where s.branch_id = p_branch_id
       and s.status = 'SCHEDULED'
       and s.starts_at >= (p_source_monday::timestamp at time zone v_tz)
       and s.starts_at <  ((p_source_monday + 7)::timestamp at time zone v_tz)
     order by s.starts_at
  loop
    begin
      insert into public.employee_schedules (company_id, branch_id, employee_id, starts_at, ends_at, note)
      values (
        v_company, p_branch_id, r.employee_id,
        ((r.starts_at at time zone v_tz) + make_interval(days => v_days)) at time zone v_tz,
        ((r.ends_at at time zone v_tz) + make_interval(days => v_days)) at time zone v_tz,
        r.note
      );
      v_copied := v_copied + 1;
    exception
      when exclusion_violation or check_violation then
        v_skipped := v_skipped + 1;
    end;
  end loop;

  return jsonb_build_object('copied', v_copied, 'skipped', v_skipped);
end;
$$;

revoke all on function public.copy_schedule_week(uuid, date, date) from public, anon;
grant execute on function public.copy_schedule_week(uuid, date, date) to authenticated;

-- -----------------------------------------------------------------------------
-- (แทนที่ Phase 1) STAFF ที่ login ด้วย PIN ได้ต้องมีข้อมูลพนักงาน ACTIVE ด้วย
-- -----------------------------------------------------------------------------
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
      join public.employees e
        on e.company_id = cm.company_id and e.user_id = cm.user_id
     where bm.branch_id = p_branch_id
       and bm.user_id = p_user_id
       and bm.status = 'ACTIVE'
       and bm.effective_from <= now()
       and (bm.effective_to is null or bm.effective_to > now())
       and cm.role = 'STAFF'
       and cm.status = 'ACTIVE'
       and cm.effective_from <= now()
       and (cm.effective_to is null or cm.effective_to > now())
       and e.status = 'ACTIVE'
  );
$$;

-- -----------------------------------------------------------------------------
-- (แทนที่ Phase 1) device_list_staff ใช้ชื่อเล่นและรูปจาก employees
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
               'user_id', e.user_id,
               'display_name', e.nickname,
               'photo_path', e.photo_path,
               'locked', sp.locked_until is not null and sp.locked_until > now()
             ) order by e.nickname)
        from public.staff_pins sp
        join public.employees e on e.company_id = sp.company_id and e.user_id = sp.user_id
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
