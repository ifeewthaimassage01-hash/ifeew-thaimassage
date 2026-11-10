-- =============================================================================
-- 041 — ปุ่ม "ล้างข้อมูลการใช้งาน" (หน้า ตั้งค่าบริษัท) — ⚠ ลบถาวร
--   - OWNER ที่ยืนยันตัวตนซ้ำ (step-up) + พิมพ์คำยืนยัน "ล้างข้อมูล"
--   - ใช้ได้เฉพาะฐานข้อมูลที่มีบริษัทเดียว (TRUNCATE ลบทั้งตาราง ไม่แยกบริษัท)
--   - เก็บ: บัญชี/รหัสผ่าน/PIN, ร้าน+สาขา, บริการ+ราคา, เตียง/อุปกรณ์, พนักงาน, ลูกค้า
--   - ลบ: การจอง มัดจำ คิว ออเดอร์ บิล รับเงิน คืนเงิน สลิป ทิป กะ รายจ่าย ปิดยอด ค่ามือ ลงเวลา
--         งวดบัญชี เลขเอกสาร audit log ฯลฯ (รายการเดียวกับ tools/reset/clear-transactions.sql)
--   - หลังล้าง บันทึก audit 1 รายการว่าใครล้างเมื่อไร
-- =============================================================================

create or replace function public.owner_clear_transactions(p_company_id uuid, p_confirm text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_owner_step_up(p_company_id);

  if coalesce(trim(p_confirm), '') <> 'ล้างข้อมูล' then
    raise exception 'กรุณาพิมพ์คำว่า "ล้างข้อมูล" เพื่อยืนยัน' using errcode = 'invalid_parameter_value';
  end if;
  if (select count(*) from public.companies) <> 1 then
    raise exception 'ฐานข้อมูลนี้มีหลายบริษัท ล้างข้อมูลจากปุ่มนี้ไม่ได้' using errcode = 'check_violation';
  end if;

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

  perform private.write_audit('CLEAR_TRANSACTIONS', p_company_id, null, null, null, null, null,
                              'ล้างข้อมูลการใช้งานทั้งหมดจากหน้าตั้งค่าบริษัท');
end;
$$;

revoke all on function public.owner_clear_transactions(uuid, text) from public, anon;
grant execute on function public.owner_clear_transactions(uuid, text) to authenticated;
