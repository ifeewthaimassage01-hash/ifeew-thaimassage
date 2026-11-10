-- =============================================================================
-- 040 — สลิปรับเงินหน้าร้าน: เก็บบน Cloudinary + ไม่ตรวจสลิปตอน checkout
--   - record_payment_slip_check รับ path แบบ "cloudinary:ifeew/<company>/<branch>/payment-slips/..."
--     (path เดิม "<company>/<branch>/..." ของ bucket payment-slips ยังใช้ได้)
--   - pos_record_payment: โอน/QR ที่แนบสลิปแล้ว ไม่ต้องกรอกเหตุผลยืนยันเอง
--     (บันทึก verification = MANUAL พร้อมเหตุผลมาตรฐาน — ยังต้องแนบสลิปของ Invoice นี้ และสลิปที่ REJECTED ใช้ไม่ได้เหมือนเดิม)
-- =============================================================================

create or replace function public.record_payment_slip_check(
  p_user_id           uuid,
  p_invoice_id        uuid,
  p_slip_path         text,
  p_requested_amount  numeric,
  p_outcome           text,
  p_provider_code     integer,
  p_provider_message  text,
  p_slip              jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  iv        public.invoices;
  v_ref     text := nullif(p_slip ->> 'trans_ref', '');
  v_amount  numeric := (p_slip ->> 'amount')::numeric;
  v_outcome text := p_outcome;
  v_message text := p_provider_message;
  v_rel     text := p_slip_path;
  v_id      uuid;
begin
  select * into iv from public.invoices where id = p_invoice_id;
  if iv.id is null or p_outcome not in ('VERIFIED', 'REJECTED', 'REVIEW') then
    raise exception 'ข้อมูลไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  -- Cloudinary: cloudinary:ifeew/<company>/<branch>/... · Supabase Storage เดิม: <company>/<branch>/...
  if p_slip_path like 'cloudinary:ifeew/%' then
    v_rel := substr(p_slip_path, char_length('cloudinary:ifeew/') + 1);
  end if;
  if split_part(v_rel, '/', 1) <> iv.company_id::text or split_part(v_rel, '/', 2) <> iv.branch_id::text then
    raise exception 'ตำแหน่งสลิปไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  -- ตรวจซ้ำฝั่ง DB: สลิปที่ถูกใช้แล้ว (รับเงิน/มัดจำ) ใช้ไม่ได้
  if v_outcome = 'VERIFIED' and v_ref is not null and (
       exists (select 1 from public.payments where slip_trans_ref = v_ref and status = 'SUCCESS')
    or exists (select 1 from public.booking_deposits where slip_trans_ref = v_ref and status <> 'REJECTED')
  ) then
    v_outcome := 'REJECTED';
    v_message := 'สลิปนี้ถูกใช้แล้ว';
  elsif v_outcome = 'VERIFIED' and v_ref is null then
    v_outcome := 'REVIEW';
    v_message := 'ไม่พบเลขอ้างอิงสลิป';
  end if;

  insert into public.payment_slip_checks (company_id, branch_id, invoice_id, slip_path, requested_amount, outcome,
                                          provider_code, provider_message, slip_trans_ref, slip_amount, slip_trans_at,
                                          slip_sender_name, slip_receiver_name, checked_by)
  values (iv.company_id, iv.branch_id, iv.id, p_slip_path, p_requested_amount, v_outcome, p_provider_code,
          left(v_message, 300), case when v_outcome = 'VERIFIED' then v_ref end, v_amount,
          (p_slip ->> 'trans_at')::timestamptz, left(p_slip ->> 'sender_name', 100), left(p_slip ->> 'receiver_name', 100),
          p_user_id)
  returning id into v_id;

  return jsonb_build_object('slip_check_id', v_id, 'outcome', v_outcome, 'message', v_message,
                            'slip_amount', v_amount, 'slip_path', p_slip_path);
end;
$$;

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
  v_reason     text := nullif(trim(coalesce(p_manual_reason, '')), '');
begin
  -- ไม่ตรวจสลิปอัตโนมัติ: โอน/QR ที่แนบสลิปแล้วใช้เหตุผลมาตรฐาน (core ยังบังคับว่าต้องมีสลิปของ Invoice นี้)
  if p_method in ('BANK_TRANSFER', 'QR') and v_reason is null then
    v_reason := 'แนบสลิป (ไม่ได้ตรวจอัตโนมัติ)';
  end if;
  return private.pos_record_payment_core(p_invoice_id, p_method, p_amount, p_slip_check_id, v_reason,
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
