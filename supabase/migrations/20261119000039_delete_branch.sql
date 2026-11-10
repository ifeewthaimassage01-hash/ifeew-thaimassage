-- =============================================================================
-- 039 — ลบสาขา (เฉพาะสาขาที่ยังไม่มีประวัติการใช้งาน)
--   - OWNER ที่ยืนยันตัวตนซ้ำ (step-up) เท่านั้น
--   - ลบข้อมูลตั้งค่าของสาขา แล้วลบสาขา ใน transaction เดียว
--   - ถ้ามีข้อมูลประวัติอ้างถึง (การจอง ออเดอร์ การเงิน ลงเวลา ย้ายสาขา เลขเอกสาร ฯลฯ)
--     FK แบบ restrict จะปฏิเสธ → ย้อนทุกอย่างกลับ แล้วแจ้งให้ "ปิดใช้งาน" แทน (ประวัติบัญชีต้องอยู่ครบ)
--   - ห้ามลบสาขาสุดท้ายของบริษัท
-- =============================================================================

create or replace function public.delete_branch(p_branch_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid;
begin
  select company_id into v_company from public.branches where id = p_branch_id;
  if v_company is null then
    raise exception 'ไม่พบสาขา' using errcode = 'no_data_found';
  end if;
  perform private.require_owner_step_up(v_company);

  if (select count(*) from public.branches where company_id = v_company) <= 1 then
    raise exception 'ลบสาขาสุดท้ายของร้านไม่ได้' using errcode = 'check_violation';
  end if;

  begin
    -- ข้อมูลตั้งค่าของสาขา (ลูกก่อนแม่)
    delete from public.service_price_histories
     where branch_service_option_id in (
       select o.id from public.branch_service_options o
         join public.branch_services s on s.id = o.branch_service_id
        where s.branch_id = p_branch_id);
    delete from public.branch_service_options
     where branch_service_id in (select id from public.branch_services where branch_id = p_branch_id);
    delete from public.branch_services where branch_id = p_branch_id;
    delete from public.branch_opening_hours where branch_id = p_branch_id;
    delete from public.branch_holidays where branch_id = p_branch_id;
    delete from public.branch_payment_accounts where branch_id = p_branch_id;
    delete from public.branch_resources where branch_id = p_branch_id;
    delete from public.employee_schedules where branch_id = p_branch_id;
    delete from public.branch_memberships where branch_id = p_branch_id;
    delete from public.branch_devices where branch_id = p_branch_id;

    delete from public.branches where id = p_branch_id;
  exception
    when foreign_key_violation then
      raise exception 'สาขานี้มีประวัติการใช้งานแล้ว (การจอง ออเดอร์ หรือข้อมูลการเงิน) จึงลบไม่ได้ — ใช้ "ปิดใช้งาน" แทน'
        using errcode = 'check_violation';
  end;
end;
$$;

revoke all on function public.delete_branch(uuid) from public, anon;
grant execute on function public.delete_branch(uuid) to authenticated;
