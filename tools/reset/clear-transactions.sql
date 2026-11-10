-- =============================================================================
-- ล้างข้อมูลการใช้งานทั้งหมด (รันเองใน Supabase Dashboard → SQL Editor)  ⚠ กู้คืนไม่ได้
--
-- เก็บไว้:  บัญชีทุกคน (เจ้าของร้าน/พนักงาน/ลูกค้า: auth.users, profiles, รหัสผ่าน, PIN)
--           ร้าน + สาขา (companies, company_settings, branches, เวลาทำการ, วันหยุด, บัญชีรับเงิน, เครื่องที่ผูก)
--           บริการ ราคา ประวัติราคา หมวดบริการ เตียง/อุปกรณ์
--           พนักงาน (employees, สิทธิ์สาขา, ตารางงาน, อัตราประกันมือ) · ลูกค้า + ความยินยอม PDPA
--
-- ลบทั้งหมด: การจอง มัดจำ คิว ออเดอร์ บิล รับเงิน คืนเงิน สลิป ทิป กะ/ลิ้นชัก รายจ่าย ปิดยอดรายวัน
--           ค่ามือ รอบจ่าย ประกันมือรายวัน ลงเวลา ประวัติย้ายสาขา งวดบัญชี เลขเอกสาร (เริ่มนับใหม่)
--           audit log, คำขอ PDPA, idempotency keys, rate limit
--
-- ทำงานใน transaction เดียว: TRUNCATE (ไม่ CASCADE) — ถ้าตารางที่เก็บไว้อ้างถึงตารางที่ลบ
-- Postgres จะ error แล้วไม่มีอะไรถูกลบเลย (ปลอดภัย) · TRUNCATE ไม่เรียก trigger ห้ามลบรายแถว
-- ไฟล์ในที่เก็บรูป (สลิป รูปรายจ่าย) ไม่ถูกลบ — ลบเองใน Storage / Cloudinary ถ้าต้องการ
-- =============================================================================

begin;

-- audit_logs กัน TRUNCATE ไว้ด้วย trigger — ปิดชั่วคราวใน transaction นี้
alter table public.audit_logs disable trigger audit_logs_no_truncate;

truncate table
  public.tips,
  public.payment_refunds,
  public.payments,
  public.payment_slip_checks,
  public.invoice_items,
  public.invoices,
  public.pos_cash_movements,
  public.pos_sessions,
  public.service_assignments,
  public.resource_allocations,
  public.queue_items,
  public.service_order_items,
  public.service_orders,
  public.booking_tracking_tokens,
  public.booking_deposits,
  public.booking_items,
  public.bookings,
  public.expenses,
  public.branch_daily_closings,
  public.commission_payout_items,
  public.commission_payouts,
  public.commission_adjustments,
  public.commissions,
  public.guarantee_overrides,
  public.staff_attendances,
  public.employee_transfers,
  public.financial_periods,
  public.document_sequences,
  public.customer_data_requests,
  public.idempotency_keys,
  public.rate_limit_buckets,
  public.audit_logs
  restart identity;

alter table public.audit_logs enable trigger audit_logs_no_truncate;

-- ตรวจผล: ทุกแถวควรเป็น 0
select 'bookings' t, count(*) from public.bookings
union all select 'service_orders', count(*) from public.service_orders
union all select 'invoices', count(*) from public.invoices
union all select 'payments', count(*) from public.payments
union all select 'expenses', count(*) from public.expenses
union all select 'commissions', count(*) from public.commissions;

commit;
