-- =============================================================================
-- Phase 9 / 024 — แก้ปัญหาที่พบจากการทดสอบทำรายการพร้อมกันบน Postgres จริง
--   1) Guest เบอร์เดียวจองพร้อมกันหลายรายการ ทะลุเพดาน guest_max_active_bookings
--      → ล็อก (advisory) ต่อ บริษัท+เบอร์ ก่อนนับ
--   2) sync ค่ามือพร้อมกัน (เปิดแดชบอร์ด/รายงาน/รอบจ่ายพร้อมกัน) ชน unique แล้ว error
--      → ล็อกต่อบริษัทให้ทำทีละรายการ
--   3) สลิปเดียวใช้กับ 2 Invoice พร้อมกัน: ข้อมูลถูกต้อง (unique) แต่ข้อความ error เป็นภาษาอังกฤษ
--      → แปลงเป็นข้อความไทย
-- วิธี: ย้ายฟังก์ชันเดิมเป็น *_core แล้วครอบด้วยฟังก์ชันชื่อเดิม (ไม่ต้องคัดลอกโค้ดเดิม)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Guest booking
-- -----------------------------------------------------------------------------
alter function public.create_guest_booking(text, uuid, timestamptz, uuid[], text, text, text, text, text, uuid, text)
  rename to create_guest_booking_core;
alter function public.create_guest_booking_core(text, uuid, timestamptz, uuid[], text, text, text, text, text, uuid, text)
  set schema private;
revoke all on function private.create_guest_booking_core(text, uuid, timestamptz, uuid[], text, text, text, text, text, uuid, text)
  from public, anon, authenticated, service_role;

create or replace function public.create_guest_booking(
  p_company_code        text,
  p_branch_id           uuid,
  p_starts_at           timestamptz,
  p_option_ids          uuid[],
  p_first_name          text,
  p_last_name           text,
  p_phone               text,
  p_email               text,
  p_note                text,
  p_privacy_version_id  uuid,
  p_idempotency_key     text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- นับ/สร้างการจองของเบอร์เดียวกันทีละรายการ (เพดานการจองค้างต่อเบอร์)
  perform pg_advisory_xact_lock(
    hashtextextended('guest-booking:' || upper(coalesce(p_company_code, '')) || ':'
                     || coalesce(private.normalize_phone(p_phone), coalesce(p_phone, '')), 0));
  return private.create_guest_booking_core(p_company_code, p_branch_id, p_starts_at, p_option_ids, p_first_name,
                                           p_last_name, p_phone, p_email, p_note, p_privacy_version_id, p_idempotency_key);
end;
$$;

revoke all on function public.create_guest_booking(text, uuid, timestamptz, uuid[], text, text, text, text, text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.create_guest_booking(text, uuid, timestamptz, uuid[], text, text, text, text, text, uuid, text)
  to service_role;

-- -----------------------------------------------------------------------------
-- 2) sync ค่ามือ: ทีละรายการต่อบริษัท
-- -----------------------------------------------------------------------------
alter function private.sync_commissions(uuid) rename to sync_commissions_core;

create or replace function private.sync_commissions(p_company_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('sync-commissions:' || p_company_id::text, 0));
  perform private.sync_commissions_core(p_company_id);
end;
$$;

revoke all on function private.sync_commissions(uuid) from public;
revoke all on function private.sync_commissions_core(uuid) from public;

-- -----------------------------------------------------------------------------
-- 3) รับเงิน: แปลง error สลิปซ้ำ (ชน unique ตอนทำพร้อมกัน) เป็นข้อความไทย
-- -----------------------------------------------------------------------------
alter function public.pos_record_payment(uuid, text, numeric, uuid, text, numeric, uuid, text)
  rename to pos_record_payment_core;
alter function public.pos_record_payment_core(uuid, text, numeric, uuid, text, numeric, uuid, text)
  set schema private;
revoke all on function private.pos_record_payment_core(uuid, text, numeric, uuid, text, numeric, uuid, text)
  from public, anon, authenticated;

create or replace function public.pos_record_payment(
  p_invoice_id       uuid,
  p_method           text,
  p_amount           numeric,
  p_slip_check_id    uuid,
  p_manual_reason    text,
  p_tip_amount       numeric,
  p_tip_employee_id  uuid,
  p_idempotency_key  text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_constraint text;
begin
  return private.pos_record_payment_core(p_invoice_id, p_method, p_amount, p_slip_check_id, p_manual_reason,
                                         p_tip_amount, p_tip_employee_id, p_idempotency_key);
exception when unique_violation then
  get stacked diagnostics v_constraint = constraint_name;
  if v_constraint in ('payments_trans_ref_key', 'payments_slip_check_key') then
    raise exception 'สลิปนี้ถูกใช้แล้ว' using errcode = 'check_violation';
  end if;
  raise;
end;
$$;

revoke all on function public.pos_record_payment(uuid, text, numeric, uuid, text, numeric, uuid, text) from public, anon;
grant execute on function public.pos_record_payment(uuid, text, numeric, uuid, text, numeric, uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 4) สร้างรอบจ่ายพร้อมกัน: ร่างได้ทีละ 1 (unique) — แปลงข้อความ error เป็นภาษาไทย
-- -----------------------------------------------------------------------------
alter function public.create_commission_payout(uuid, date) rename to create_commission_payout_core;
alter function public.create_commission_payout_core(uuid, date) set schema private;
revoke all on function private.create_commission_payout_core(uuid, date) from public, anon, authenticated;

create or replace function public.create_commission_payout(p_company_id uuid, p_period_to date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_constraint text;
begin
  return private.create_commission_payout_core(p_company_id, p_period_to);
exception when unique_violation then
  get stacked diagnostics v_constraint = constraint_name;
  if v_constraint = 'commission_payouts_one_draft' then
    raise exception 'มีรอบจ่ายที่ยังเป็นร่างอยู่ กรุณายืนยันหรือยกเลิกก่อน' using errcode = 'check_violation';
  end if;
  raise;
end;
$$;

revoke all on function public.create_commission_payout(uuid, date) from public, anon;
grant execute on function public.create_commission_payout(uuid, date) to authenticated;

-- -----------------------------------------------------------------------------
-- 5) ความเร็ว (วัดด้วยข้อมูล 1 ปี ~29,000 บริการ): การแบ่งค่ามือ (assignment_fee) ค้นการมอบหมายของคิว
--    ทุกครั้ง แต่ไม่มี index ตาม queue_item_id ทั้งตาราง → sync/รายงานรายหมอช้าแบบกำลังสอง
-- -----------------------------------------------------------------------------
create index if not exists service_assignments_queue_idx on public.service_assignments (queue_item_id);
create index if not exists queue_items_date_idx on public.queue_items (queue_date);

-- -----------------------------------------------------------------------------
-- 6) sync ค่ามือทุกชั่วโมงเบื้องหลัง (pg_cron) — ไม่ให้งานค้างสะสมจนคำขอแรกของ OWNER ช้าเกิน timeout
-- -----------------------------------------------------------------------------
create or replace function private.sync_all_commissions()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c record;
begin
  for c in select id from public.companies where is_active loop
    perform private.sync_commissions(c.id);
  end loop;
end;
$$;

revoke all on function private.sync_all_commissions() from public;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('sync-commissions', '7 * * * *', 'select private.sync_all_commissions()');
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- 7) รายจ่ายสาขาที่บันทึกหลังเที่ยงคืนขณะร้านยังเปิด: วันที่ตั้งต้น = วันทำการของสาขา (ไม่ใช่วันตามปฏิทิน)
-- -----------------------------------------------------------------------------
alter function public.pos_record_expense(uuid, uuid, numeric, text, text, boolean, date) rename to pos_record_expense_core;
alter function public.pos_record_expense_core(uuid, uuid, numeric, text, text, boolean, date) set schema private;
revoke all on function private.pos_record_expense_core(uuid, uuid, numeric, text, text, boolean, date) from public, anon, authenticated;

create or replace function public.pos_record_expense(
  p_company_id    uuid,
  p_branch_id     uuid,
  p_amount        numeric,
  p_note          text,
  p_photo_path    text,
  p_from_drawer   boolean,
  p_occurred_on   date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  return private.pos_record_expense_core(
    p_company_id, p_branch_id, p_amount, p_note, p_photo_path, p_from_drawer,
    coalesce(p_occurred_on,
             case when p_branch_id is not null
                  then (select w.business_date from private.branch_window_at(p_branch_id, now()) w) end));
end;
$$;

revoke all on function public.pos_record_expense(uuid, uuid, numeric, text, text, boolean, date) from public, anon;
grant execute on function public.pos_record_expense(uuid, uuid, numeric, text, text, boolean, date) to authenticated;
