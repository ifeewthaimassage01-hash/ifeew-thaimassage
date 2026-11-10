-- =============================================================================
-- 043 — ลบข้อมูลหลัก: บริการ, หมวดหมู่บริการ, ประเภทเตียง/อุปกรณ์, พนักงาน
--   กติกาเดียวกับ delete_branch (039):
--   - OWNER ที่ยืนยันตัวตนซ้ำ (step-up) เท่านั้น
--   - ลบข้อมูลตั้งค่าที่ผูกอยู่ แล้วลบตัวหลัก ใน transaction เดียว
--   - ถ้ามีประวัติอ้างถึง (การจอง ออเดอร์ ค่ามือ ลงเวลา ฯลฯ) FK แบบ restrict จะปฏิเสธ
--     → ย้อนทุกอย่างกลับ แล้วแจ้งให้ "ปิดใช้งาน" แทน
-- =============================================================================

-- -----------------------------------------------------------------------------
-- บริการ: ลบราคา/ช่วงเวลาทุกสาขา + การผูกเตียง แล้วลบบริการ
-- -----------------------------------------------------------------------------
create or replace function public.delete_service(p_service_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid;
begin
  select company_id into v_company from public.services where id = p_service_id;
  if v_company is null then
    raise exception 'ไม่พบบริการ' using errcode = 'no_data_found';
  end if;
  perform private.require_owner_step_up(v_company);

  begin
    delete from public.service_price_histories
     where branch_service_option_id in (
       select o.id from public.branch_service_options o
         join public.branch_services s on s.id = o.branch_service_id
        where s.service_id = p_service_id);
    delete from public.branch_service_options
     where branch_service_id in (select id from public.branch_services where service_id = p_service_id);
    delete from public.branch_services where service_id = p_service_id;
    delete from public.service_resources where service_id = p_service_id;
    delete from public.services where id = p_service_id;
  exception
    when foreign_key_violation then
      raise exception 'บริการนี้มีการจองหรือออเดอร์แล้ว จึงลบไม่ได้ — ใช้ "ปิดใช้งาน" แทน'
        using errcode = 'check_violation';
  end;
end;
$$;

-- -----------------------------------------------------------------------------
-- หมวดหมู่บริการ: ลบได้เมื่อไม่มีบริการอยู่ในหมวด
-- -----------------------------------------------------------------------------
create or replace function public.delete_service_category(p_category_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid;
begin
  select company_id into v_company from public.service_categories where id = p_category_id;
  if v_company is null then
    raise exception 'ไม่พบหมวดหมู่' using errcode = 'no_data_found';
  end if;
  perform private.require_owner_step_up(v_company);

  if exists (select 1 from public.services where category_id = p_category_id) then
    raise exception 'ยังมีบริการอยู่ในหมวดนี้ — ย้ายบริการไปหมวดอื่นหรือลบบริการก่อน'
      using errcode = 'check_violation';
  end if;
  delete from public.service_categories where id = p_category_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- ประเภทเตียง/อุปกรณ์: ลบจำนวนในแต่ละสาขา + การผูกกับบริการ แล้วลบประเภท
-- -----------------------------------------------------------------------------
create or replace function public.delete_resource_type(p_resource_type_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid;
begin
  select company_id into v_company from public.resource_types where id = p_resource_type_id;
  if v_company is null then
    raise exception 'ไม่พบประเภทเตียง/อุปกรณ์' using errcode = 'no_data_found';
  end if;
  perform private.require_owner_step_up(v_company);

  begin
    delete from public.service_resources where resource_type_id = p_resource_type_id;
    delete from public.branch_resources where resource_type_id = p_resource_type_id;
    delete from public.resource_types where id = p_resource_type_id;
  exception
    when foreign_key_violation then
      raise exception 'เตียง/อุปกรณ์นี้เคยถูกใช้ในคิวแล้ว จึงลบไม่ได้ — ใช้ "ปิดใช้งาน" แทน'
        using errcode = 'check_violation';
  end;
end;
$$;

-- -----------------------------------------------------------------------------
-- พนักงาน: ลบตารางงาน อัตราประกันมือ สิทธิ์สาขา/บริษัท และ PIN แล้วลบพนักงาน
--   บัญชี login (auth/profile) ยังอยู่ แต่เข้าแอปพนักงานไม่ได้แล้วเพราะไม่มีสิทธิ์ในบริษัท
--   ห้ามลบเจ้าของร้าน และห้ามลบตัวเอง
-- -----------------------------------------------------------------------------
create or replace function public.delete_employee(p_employee_id uuid)
returns void
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
end;
$$;

revoke all on function public.delete_service(uuid) from public, anon;
revoke all on function public.delete_service_category(uuid) from public, anon;
revoke all on function public.delete_resource_type(uuid) from public, anon;
revoke all on function public.delete_employee(uuid) from public, anon;
grant execute on function public.delete_service(uuid) to authenticated;
grant execute on function public.delete_service_category(uuid) to authenticated;
grant execute on function public.delete_resource_type(uuid) to authenticated;
grant execute on function public.delete_employee(uuid) to authenticated;
