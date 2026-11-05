-- =============================================================================
-- 030 — พนักงาน login ด้วย PIN โดยเลือกสาขาจาก dropdown (ไม่ต้องใช้เครื่องที่ผูก) ตามที่ผู้ใช้ขอ
--   เรียกจาก Edge Functions branch-staff-list / staff-pin-login (service role) หลัง rate limit
--   กฎ PIN / การล็อก / audit เหมือน device_verify_staff_pin (009, 028)
-- ความเสี่ยงที่ยอมรับ: ใครรู้ URL ของระบบเห็นรายชื่อสาขา + ชื่อเล่น/รูปพนักงาน
--   และลองเดา PIN จากที่ไหนก็ได้ (ป้องกันด้วยการล็อกหลังกดผิด + rate limit)
-- =============================================================================

-- สาขาที่เปิดใช้งานของบริษัท (สำหรับ dropdown หน้า login)
create or replace function public.login_list_branches(p_company_code text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('branch_id', b.id, 'name', b.name)
                            order by b.sort_order, b.name), '[]'::jsonb)
    from public.branches b
   where b.company_id = private.company_id_by_code(p_company_code)
     and b.is_active;
$$;

revoke all on function public.login_list_branches(text) from public, anon, authenticated;
grant execute on function public.login_list_branches(text) to service_role;

-- พนักงานของสาขาที่ตั้ง PIN แล้ว (ไม่รวมเจ้าของร้าน — เจ้าของร้านใช้แท็บของตัวเอง)
create or replace function public.login_list_branch_staff(p_company_code text, p_branch_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_company uuid := private.company_id_by_code(p_company_code);
  v_branch  public.branches;
  s         public.company_settings;
begin
  select * into v_branch from public.branches
   where id = p_branch_id and company_id = v_company and is_active;
  if v_branch.id is null then
    return jsonb_build_object('ok', false, 'error_code', 'BRANCH_INVALID');
  end if;
  select * into s from public.company_settings where company_id = v_company;

  return jsonb_build_object(
    'ok', true,
    'branch', jsonb_build_object(
      'company_id', v_company, 'branch_id', v_branch.id, 'branch_name', v_branch.name,
      'idle_lock_minutes', s.staff_idle_lock_minutes),
    'staff', coalesce((
      select jsonb_agg(jsonb_build_object(
               'user_id', e.user_id, 'display_name', e.nickname, 'photo_path', e.photo_path,
               'locked', sp.locked_until is not null and sp.locked_until > now(), 'is_owner', false)
             order by e.nickname)
        from public.staff_pins sp
        join public.employees e on e.company_id = sp.company_id and e.user_id = sp.user_id
       where sp.company_id = v_company
         and private.is_active_staff_of_branch(sp.user_id, v_branch.id)
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.login_list_branch_staff(text, uuid) from public, anon, authenticated;
grant execute on function public.login_list_branch_staff(text, uuid) to service_role;

-- ตรวจ PIN พนักงานของสาขาที่เลือก
create or replace function public.branch_verify_staff_pin(
  p_company_code text,
  p_branch_id    uuid,
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
  v_company uuid := private.company_id_by_code(p_company_code);
  v_branch  uuid;
  sp        public.staff_pins;
  s         public.company_settings;
  v_meta    jsonb := jsonb_build_object('client_ip', p_client_ip, 'channel', 'BRANCH_PIN');
begin
  select id into v_branch from public.branches
   where id = p_branch_id and company_id = v_company and is_active;
  if v_branch is null then
    return jsonb_build_object('ok', false, 'error_code', 'BRANCH_INVALID');
  end if;

  if not private.is_active_staff_of_branch(p_user_id, v_branch) then
    perform private.write_audit(
      p_action => 'STAFF_PIN_LOGIN_DENIED', p_company_id => v_company, p_branch_id => v_branch,
      p_metadata => v_meta || jsonb_build_object('user_id', p_user_id, 'cause', 'NOT_BRANCH_STAFF')
    );
    return jsonb_build_object('ok', false, 'error_code', 'INVALID_CREDENTIALS');
  end if;

  select * into sp from public.staff_pins
   where company_id = v_company and user_id = p_user_id
   for update;
  if sp.user_id is null then
    return jsonb_build_object('ok', false, 'error_code', 'INVALID_CREDENTIALS');
  end if;
  if sp.locked_until is not null and sp.locked_until > now() then
    return jsonb_build_object('ok', false, 'error_code', 'PIN_LOCKED', 'locked_until', sp.locked_until);
  end if;

  select * into s from public.company_settings where company_id = v_company;

  if sp.pin_hash <> extensions.crypt(coalesce(p_pin, ''), sp.pin_hash) then
    if sp.failed_attempts + 1 >= s.staff_pin_max_attempts then
      update public.staff_pins
         set failed_attempts = 0, locked_until = now() + make_interval(mins => s.staff_pin_lockout_minutes)
       where company_id = sp.company_id and user_id = sp.user_id
      returning * into sp;
      perform private.write_audit(
        p_action => 'STAFF_PIN_LOCKED', p_company_id => v_company, p_branch_id => v_branch,
        p_actor => p_user_id, p_metadata => v_meta
      );
      return jsonb_build_object('ok', false, 'error_code', 'PIN_LOCKED', 'locked_until', sp.locked_until);
    end if;
    update public.staff_pins set failed_attempts = failed_attempts + 1
     where company_id = sp.company_id and user_id = sp.user_id;
    perform private.write_audit(
      p_action => 'STAFF_PIN_LOGIN_FAILED', p_company_id => v_company, p_branch_id => v_branch,
      p_actor => p_user_id, p_metadata => v_meta
    );
    return jsonb_build_object('ok', false, 'error_code', 'INVALID_CREDENTIALS',
                              'attempts_left', s.staff_pin_max_attempts - (sp.failed_attempts + 1));
  end if;

  update public.staff_pins set failed_attempts = 0, locked_until = null
   where company_id = sp.company_id and user_id = sp.user_id
     and (failed_attempts <> 0 or locked_until is not null);

  perform private.write_audit(
    p_action => 'STAFF_PIN_LOGIN_SUCCESS', p_company_id => v_company, p_branch_id => v_branch,
    p_actor => p_user_id, p_metadata => v_meta
  );

  return jsonb_build_object('ok', true, 'user_id', p_user_id, 'company_id', v_company,
                            'branch_id', v_branch, 'idle_lock_minutes', s.staff_idle_lock_minutes);
end;
$$;

revoke all on function public.branch_verify_staff_pin(text, uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.branch_verify_staff_pin(text, uuid, uuid, text, text) to service_role;
