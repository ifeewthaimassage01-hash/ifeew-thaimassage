-- =============================================================================
-- 044 — ลบพนักงาน + ลบบัญชี login (ผ่าน Edge Function staff-delete)
--   - delete_employee คืน user_id ของพนักงานที่ลบ (เดิม void — migration 043)
--   - purge_staff_profile (service role เท่านั้น): ลบ profiles ถ้าไม่มีอะไรอ้างถึงแล้ว
--       true  → Edge Function ลบ auth user ถาวร
--       false → ยังถูกอ้างถึง (สร้างรายการไว้ / เป็นลูกค้า / อยู่บริษัทอื่น) → Edge Function ใช้ soft delete
--               ของ Supabase Auth (ล้างอีเมล/ข้อมูล login, login ไม่ได้อีก แต่แถวยังอยู่ให้ประวัติไม่พัง)
-- =============================================================================

drop function if exists public.delete_employee(uuid);

create function public.delete_employee(p_employee_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  e public.employees;
begin
  select * into e from public.employees where id = p_employee_id;
  if e.id is null then
    raise exception 'ไม่พบพนักงาน' using errcode = 'no_data_found';
  end if;
  perform private.require_owner_step_up(e.company_id);

  if e.user_id = auth.uid() then
    raise exception 'ลบบัญชีของตัวเองไม่ได้' using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.company_memberships
              where company_id = e.company_id and user_id = e.user_id and role = 'OWNER') then
    raise exception 'ลบเจ้าของร้านไม่ได้' using errcode = 'check_violation';
  end if;

  begin
    delete from public.employee_schedules where employee_id = e.id;
    delete from public.employee_guarantee_rates where employee_id = e.id;
    delete from public.employees where id = e.id;
    delete from public.branch_memberships where company_id = e.company_id and user_id = e.user_id;
    delete from public.staff_pins where company_id = e.company_id and user_id = e.user_id;
    delete from public.company_memberships where company_id = e.company_id and user_id = e.user_id;
  exception
    when foreign_key_violation then
      raise exception 'พนักงานคนนี้มีประวัติงานแล้ว (คิว ค่ามือ ลงเวลา ทิป หรือการย้ายสาขา) จึงลบไม่ได้ — ใช้ "ปิดใช้งาน" แทน'
        using errcode = 'check_violation';
  end;
  return e.user_id;
end;
$$;

revoke all on function public.delete_employee(uuid) from public, anon;
grant execute on function public.delete_employee(uuid) to authenticated;

create or replace function public.purge_staff_profile(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- ยังเป็นพนักงาน/เจ้าของที่บริษัทใดอยู่ หรือเป็นบัญชีลูกค้า → ไม่ลบ
  if exists (select 1 from public.company_memberships where user_id = p_user_id)
     or exists (select 1 from public.employees where user_id = p_user_id)
     or exists (select 1 from public.customers where auth_user_id = p_user_id) then
    return false;
  end if;
  begin
    delete from public.profiles where id = p_user_id;
  exception
    when foreign_key_violation then
      return false;
  end;
  return true;
end;
$$;

revoke all on function public.purge_staff_profile(uuid) from public, anon, authenticated;
grant execute on function public.purge_staff_profile(uuid) to service_role;
