-- =============================================================================
-- 047 — แก้ลบพนักงานไม่ได้: "ห้ามลบ employee_guarantee_rates (ใช้สถานะแทน)"
--   ยอดประกันมือเป็นข้อมูลตั้งค่า (มี trigger กันลบเพื่อเก็บประวัติ) — พนักงานที่ยังไม่เคยทำงานควรลบได้
--   delete_employee (แทนที่ 044):
--     - เคยเช็คชื่อเข้างาน / มีค่ามือ / ประกันมือรายวัน / ย้ายสาขา ฯลฯ = มีประวัติ → แจ้งให้ปิดใช้งานแทน (เหมือนเดิม)
--     - ยอดประกันมือ: ปิด trigger กันลบชั่วคราวเฉพาะใน transaction นี้แล้วลบ (trigger audit ยังบันทึกการลบ)
-- =============================================================================

create or replace function public.delete_employee(p_employee_id uuid)
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
  -- ตารางประวัติที่ห้ามลบ (ตรวจก่อน ให้ได้ข้อความที่เข้าใจง่าย)
  if exists (select 1 from public.staff_attendances where employee_id = e.id)
     or exists (select 1 from public.guarantee_overrides where employee_id = e.id)
     or exists (select 1 from public.commissions where employee_id = e.id)
     or exists (select 1 from public.commission_adjustments where employee_id = e.id) then
    raise exception 'พนักงานคนนี้เคยเข้างานหรือมีค่ามือแล้ว จึงลบไม่ได้ — ใช้ "เปลี่ยนสถานะ" เป็นลาออกแทน'
      using errcode = 'check_violation';
  end if;

  begin
    delete from public.employee_schedules where employee_id = e.id;

    alter table public.employee_guarantee_rates disable trigger employee_guarantee_rates_no_delete;
    delete from public.employee_guarantee_rates where employee_id = e.id;
    alter table public.employee_guarantee_rates enable trigger employee_guarantee_rates_no_delete;

    delete from public.employees where id = e.id;
    delete from public.branch_memberships where company_id = e.company_id and user_id = e.user_id;
    delete from public.staff_pins where company_id = e.company_id and user_id = e.user_id;
    delete from public.company_memberships where company_id = e.company_id and user_id = e.user_id;
  exception
    when foreign_key_violation then
      raise exception 'พนักงานคนนี้มีประวัติงานแล้ว (คิว ค่ามือ ลงเวลา ทิป หรือการย้ายสาขา) จึงลบไม่ได้ — ใช้ "เปลี่ยนสถานะ" เป็นลาออกแทน'
        using errcode = 'check_violation';
  end;
  return e.user_id;
end;
$$;

revoke all on function public.delete_employee(uuid) from public, anon;
grant execute on function public.delete_employee(uuid) to authenticated;
