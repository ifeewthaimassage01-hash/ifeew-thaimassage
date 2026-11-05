-- =============================================================================
-- 031 — ไม่ต้องกด “เปิดกะ” (ตามที่ผู้ใช้ขอ)
--   ทุกฟังก์ชันที่รับ/จ่ายเงินสด (ชำระเงิน, คืนเงินสด, เงินเข้า/ออกลิ้นชัก, จ่ายทิป, รายจ่ายจากลิ้นชัก)
--   เรียก private.require_open_session — เปลี่ยนให้เปิดกะให้อัตโนมัติเมื่อยังไม่มีกะเปิด
--   (เงินทอนเริ่มต้น 0 บาท) แทนการ error NO_OPEN_SESSION
--   การปิดกะ/นับเงิน และการปิดยอดรายวันยังเหมือนเดิม: ปิดกะแล้ว รายการถัดไปจะเปิดกะใหม่ให้เอง
-- ผลที่ยอมรับ: ถ้ามีเงินทอนค้างในลิ้นชักตอนเริ่ม ยอดที่ควรมีตอนปิดกะจะไม่รวมเงินนั้น
--   (ให้บันทึก “เงินเข้าลิ้นชัก” หรือใส่เหตุผลผลต่างตอนปิดกะ)
-- =============================================================================

create or replace function private.require_open_session(p_branch_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id      uuid;
  v_company uuid;
  v_date    date;
begin
  select id into v_id from public.pos_sessions where branch_id = p_branch_id and status = 'OPEN' for share;
  if v_id is not null then
    return v_id;
  end if;

  if auth.uid() is null then
    raise exception 'ยังไม่ได้เปิดกะ' using errcode = 'check_violation', hint = 'NO_OPEN_SESSION';
  end if;

  -- ล็อกสาขาแล้วตรวจซ้ำ กันสองเครื่องเปิดกะพร้อมกัน (unique index pos_sessions_one_open เป็นชั้นสุดท้าย)
  select company_id into v_company from public.branches where id = p_branch_id and is_active for update;
  if v_company is null then
    raise exception 'สาขาไม่เปิดใช้งาน' using errcode = 'invalid_parameter_value';
  end if;
  select id into v_id from public.pos_sessions where branch_id = p_branch_id and status = 'OPEN' for share;
  if v_id is not null then
    return v_id;
  end if;

  select business_date into v_date from private.branch_window_at(p_branch_id, now());
  insert into public.pos_sessions (company_id, branch_id, business_date, opened_by, opening_cash, opening_note)
  values (v_company, p_branch_id, v_date, auth.uid(), 0, 'เปิดกะอัตโนมัติ')
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function private.require_open_session(uuid) from public;
