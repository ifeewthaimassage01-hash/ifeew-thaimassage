-- ทิปหลายคนในบิลเดียว: หน้า checkout ระบุว่าหมอคนไหนได้ทิปเท่าไหร่
--   public.pos_invoice_therapists(invoice) → หมอที่ทำงานในบิลนี้ (ตัวเลือกในช่องทิป)
--   public.pos_record_payment_tips(... p_tips jsonb [{employee_id, amount}] ...) → รับเงิน + ทิปหลายรายการใน transaction เดียว
--   (pos_record_payment เดิมรับทิปได้คนเดียว — คงไว้ไม่เปลี่ยน)

create or replace function public.pos_invoice_therapists(p_invoice_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  iv public.invoices;
begin
  select * into iv from public.invoices where id = p_invoice_id;
  if iv.id is null then
    raise exception 'ไม่พบ Invoice' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(iv.branch_id);

  return coalesce((
    select jsonb_agg(jsonb_build_object('employee_id', x.employee_id, 'nickname', x.nickname, 'services', x.services)
                     order by x.first_at, x.nickname)
      from (
        select e.id as employee_id, e.nickname, min(a.started_at) as first_at,
               string_agg(distinct ii.description, ', ') as services
          from public.invoice_items ii
          join public.queue_items q on q.service_order_item_id = ii.service_order_item_id
          join public.service_assignments a on a.queue_item_id = q.id and a.status <> 'CANCELLED' and a.employee_id is not null
          join public.employees e on e.id = a.employee_id
         where ii.invoice_id = iv.id
         group by e.id, e.nickname
      ) x
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.pos_invoice_therapists(uuid) from public, anon;
grant execute on function public.pos_invoice_therapists(uuid) to authenticated;

-- แกนรับเงิน + ทิปหลายรายการ (ตรรกะเดียวกับ private.pos_record_payment_core ต่างแค่ทิปเป็นรายการ)
create or replace function private.pos_record_payment_core_tips(
  p_invoice_id uuid, p_method text, p_amount numeric, p_slip_check_id uuid, p_manual_reason text,
  p_tips jsonb, p_idempotency_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  iv         public.invoices;
  sc         public.payment_slip_checks;
  v_session  uuid;
  v_prev     jsonb;
  v_payment  uuid;
  v_verify   text;
  v_tips     jsonb := coalesce(p_tips, '[]'::jsonb);
  v_tip      numeric(12,2);
  t          record;
  v_result   jsonb;
  v_hash     text := private.request_hash(jsonb_build_object(
                       'i', p_invoice_id, 'm', p_method, 'a', p_amount, 's', p_slip_check_id, 't', p_tips));
begin
  select * into iv from public.invoices where id = p_invoice_id for update;
  if iv.id is null then
    raise exception 'ไม่พบ Invoice' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(iv.branch_id);

  v_prev := private.idempotency_begin('pos_record_payment', p_idempotency_key, v_hash);
  if v_prev is not null then
    return v_prev -> 'body';
  end if;

  if iv.status not in ('ISSUED', 'PARTIALLY_PAID') then
    raise exception 'Invoice นี้รับเงินไม่ได้ (ต้องออก Invoice ก่อน หรือจ่ายครบแล้ว)' using errcode = 'check_violation';
  end if;
  if p_method not in ('CASH', 'BANK_TRANSFER', 'QR') then
    raise exception 'ช่องทางชำระไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  if p_amount is null or p_amount <= 0 or round(p_amount, 2) > iv.total - iv.paid_amount then
    raise exception 'ยอดรับต้องมากกว่า 0 และไม่เกินยอดค้าง % บาท', iv.total - iv.paid_amount
      using errcode = 'invalid_parameter_value';
  end if;

  -- ตรวจรายการทิป: [{employee_id, amount}] · หมอไม่ซ้ำ · ยอดมากกว่า 0 · อยู่สาขานี้
  if jsonb_typeof(v_tips) <> 'array' or jsonb_array_length(v_tips) > 20 then
    raise exception 'รายการทิปไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_tips) x
     where (x ->> 'employee_id') is null
        or (x ->> 'employee_id') !~ '^[0-9a-fA-F-]{36}$'
        or coalesce((x ->> 'amount')::numeric, 0) <= 0
  ) then
    raise exception 'กรุณาเลือกหมอและใส่ยอดทิปให้ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  if (select count(*) from jsonb_array_elements(v_tips)) <> (select count(distinct x ->> 'employee_id') from jsonb_array_elements(v_tips) x) then
    raise exception 'หมอคนเดียวกันใส่ทิปได้ครั้งเดียวต่อการรับเงิน' using errcode = 'invalid_parameter_value';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_tips) x
     where not exists (
       select 1 from public.employees e
        where e.id = (x ->> 'employee_id')::uuid and e.company_id = iv.company_id
          and private.is_active_staff_of_branch(e.user_id, iv.branch_id))
  ) then
    raise exception 'หมอที่ได้รับทิปไม่ได้อยู่สาขานี้' using errcode = 'invalid_parameter_value';
  end if;
  select coalesce(sum(round((x ->> 'amount')::numeric, 2)), 0) into v_tip from jsonb_array_elements(v_tips) x;

  v_session := private.require_open_session(iv.branch_id);

  if p_method in ('BANK_TRANSFER', 'QR') then
    select * into sc from public.payment_slip_checks where id = p_slip_check_id;
    if sc.id is null or sc.invoice_id <> iv.id then
      raise exception 'กรุณาถ่ายรูปสลิปของ Invoice นี้' using errcode = 'invalid_parameter_value';
    end if;
    if sc.outcome = 'REJECTED' then
      raise exception 'สลิปนี้ไม่ผ่านการตรวจ: %', coalesce(sc.provider_message, '-') using errcode = 'check_violation';
    end if;
    if sc.slip_trans_ref is not null and (
         exists (select 1 from public.payments where slip_trans_ref = sc.slip_trans_ref and status = 'SUCCESS')
      or exists (select 1 from public.booking_deposits where slip_trans_ref = sc.slip_trans_ref and status <> 'REJECTED')
    ) then
      raise exception 'สลิปนี้ถูกใช้แล้ว' using errcode = 'check_violation';
    end if;
    if sc.outcome = 'VERIFIED' then
      if sc.slip_amount is distinct from round(p_amount, 2) + v_tip then
        raise exception 'ยอดในสลิป (% บาท) ไม่ตรงกับยอดรับรวมทิป', sc.slip_amount using errcode = 'check_violation';
      end if;
      v_verify := 'AUTO';
    else
      if p_manual_reason is null or char_length(trim(p_manual_reason)) < 3 then
        raise exception 'ตรวจสลิปอัตโนมัติไม่ได้ กรุณาตรวจยอดเข้าบัญชีแล้วระบุเหตุผลเพื่อยืนยันเอง'
          using errcode = 'invalid_parameter_value', hint = 'MANUAL_REQUIRED';
      end if;
      v_verify := 'MANUAL';
    end if;
  elsif p_slip_check_id is not null then
    raise exception 'รับเงินสดไม่ต้องแนบสลิป' using errcode = 'invalid_parameter_value';
  end if;

  insert into public.payments (company_id, branch_id, invoice_id, pos_session_id, method, amount, verification,
                               slip_check_id, slip_trans_ref, manual_reason, received_by)
  values (iv.company_id, iv.branch_id, iv.id, v_session, p_method, round(p_amount, 2), v_verify,
          case when p_method = 'CASH' then null else sc.id end, sc.slip_trans_ref,
          case when v_verify = 'MANUAL' then left(trim(p_manual_reason), 300) end, auth.uid())
  returning id into v_payment;

  for t in select (x ->> 'employee_id')::uuid as employee_id, round((x ->> 'amount')::numeric, 2) as amount
             from jsonb_array_elements(v_tips) x
  loop
    insert into public.tips (company_id, branch_id, invoice_id, payment_id, employee_id, pos_session_id, method, amount)
    values (iv.company_id, iv.branch_id, iv.id, v_payment, t.employee_id, v_session, p_method, t.amount);
  end loop;

  perform private.refresh_invoice(iv.id);
  v_result := private.invoice_view(iv.id);
  perform private.idempotency_complete('pos_record_payment', p_idempotency_key, 200, v_result);
  return v_result;
end;
$$;

create or replace function public.pos_record_payment_tips(
  p_invoice_id uuid, p_method text, p_amount numeric, p_slip_check_id uuid, p_manual_reason text,
  p_tips jsonb, p_idempotency_key text)
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
  return private.pos_record_payment_core_tips(p_invoice_id, p_method, p_amount, p_slip_check_id, v_reason,
                                              p_tips, p_idempotency_key);
exception when unique_violation then
  get stacked diagnostics v_constraint = constraint_name;
  if v_constraint in ('payments_trans_ref_key', 'payments_slip_check_key') then
    raise exception 'สลิปนี้ถูกใช้แล้ว' using errcode = 'check_violation';
  end if;
  raise;
end;
$$;
revoke all on function public.pos_record_payment_tips(uuid, text, numeric, uuid, text, jsonb, text) from public, anon;
grant execute on function public.pos_record_payment_tips(uuid, text, numeric, uuid, text, jsonb, text) to authenticated;
