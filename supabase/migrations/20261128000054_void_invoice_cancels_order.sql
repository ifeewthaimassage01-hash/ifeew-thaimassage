-- ยกเลิกบิล (Void) = ยกเลิกรายการลูกค้ากลุ่มนั้นด้วย → หายจาก "ยังไม่จ่าย" (เดิม Void แล้ว Order ยังค้าง ต้องออกบิลใหม่)
-- - ยกเลิก Order เฉพาะเมื่อทุกคิวจบแล้ว (เสร็จ/ยกเลิก) · ถ้ายังมีคิวกำลังนวด/รอ = Void บิลอย่างเดียวเหมือนเดิม
-- - Order ที่ COMPLETED เปลี่ยนเป็น CANCELLED ได้เฉพาะผ่าน function นี้ (flag app.void_order)
-- - ค่ามือหมอคิดจากบิลที่ PAID อยู่แล้ว จึงไม่เกิดค่ามือ · สรุปเงินแดชบอร์ดไม่นับคิวของ Order ที่ยกเลิก

create or replace function private.tg_service_orders_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- customer_id เปลี่ยนได้ (รวมลูกค้า Phase 3) นอกนั้นห้าม
  if new.company_id <> old.company_id or new.branch_id <> old.branch_id
     or new.booking_id is distinct from old.booking_id or new.channel <> old.channel
     or new.business_date <> old.business_date then
    raise exception 'ห้ามแก้ข้อมูลหลักของ Order' using errcode = 'check_violation';
  end if;
  if new.status <> old.status and not (
       (old.status = 'OPEN' and new.status in ('COMPLETED', 'CANCELLED'))
    or (old.status = 'COMPLETED' and new.status = 'OPEN')
    or (old.status = 'COMPLETED' and new.status = 'CANCELLED'
        and coalesce(current_setting('app.void_order', true), '') = 'on')
  ) then
    raise exception 'เปลี่ยนสถานะ Order จาก % เป็น % ไม่ได้', old.status, new.status using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create or replace function public.pos_void_invoice(p_invoice_id uuid, p_reason text, p_idempotency_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  iv      public.invoices;
  v_prev  jsonb;
  v_result jsonb;
begin
  select * into iv from public.invoices where id = p_invoice_id for update;
  if iv.id is null then
    raise exception 'ไม่พบ Invoice' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(iv.branch_id);

  v_prev := private.idempotency_begin('pos_void_invoice', p_idempotency_key,
                                      private.request_hash(jsonb_build_object('i', p_invoice_id)));
  if v_prev is not null then
    return v_prev -> 'body';
  end if;

  if iv.status = 'VOID' then
    raise exception 'Invoice นี้ถูก Void แล้ว' using errcode = 'check_violation';
  end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาระบุเหตุผล' using errcode = 'invalid_parameter_value';
  end if;
  if exists (select 1 from public.payments where invoice_id = iv.id and status = 'SUCCESS' and method <> 'DEPOSIT') then
    if not private.is_company_owner(iv.company_id) then
      raise exception 'Invoice ที่รับเงินแล้ว ต้องให้เจ้าของร้านเป็นผู้ Void' using errcode = 'insufficient_privilege';
    end if;
    perform private.require_owner_step_up(iv.company_id);
    if exists (
      select 1 from public.payments p join public.pos_sessions s on s.id = p.pos_session_id
       where p.invoice_id = iv.id and p.status = 'SUCCESS' and s.status <> 'OPEN'
    ) then
      raise exception 'มีเงินที่รับในกะที่ปิดแล้ว ต้องใช้การคืนเงินแทนการ Void' using errcode = 'check_violation';
    end if;
  end if;
  if exists (select 1 from public.payment_refunds where invoice_id = iv.id) then
    raise exception 'Invoice นี้มีการคืนเงินแล้ว Void ไม่ได้' using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.tips where invoice_id = iv.id and status = 'PAID_OUT') then
    raise exception 'ทิปของ Invoice นี้จ่ายให้หมอแล้ว Void ไม่ได้' using errcode = 'check_violation';
  end if;

  perform set_config('app.audit_reason', trim(p_reason), true);
  update public.tips set status = 'VOID', voided_at = now(), void_reason = 'Void Invoice'
   where invoice_id = iv.id and status = 'RECORDED';
  update public.payments set status = 'VOID', voided_at = now(), voided_by = auth.uid(), void_reason = left(trim(p_reason), 500)
   where invoice_id = iv.id and status = 'SUCCESS';
  update public.invoices
     set status = 'VOID', voided_at = now(), voided_by = auth.uid(), void_reason = left(trim(p_reason), 500)
   where id = iv.id;

  -- ทุกคิวจบแล้ว → ยกเลิก Order ด้วย (ไม่ต้องเก็บเงินกลุ่มนี้อีก)
  if not exists (
    select 1 from public.service_order_items i join public.queue_items q on q.service_order_item_id = i.id
     where i.service_order_id = iv.service_order_id and q.status not in ('COMPLETED', 'CANCELLED')
  ) then
    perform set_config('app.void_order', 'on', true);
    update public.service_orders
       set status = 'CANCELLED', cancelled_at = now(), cancelled_by = auth.uid(),
           cancel_reason = left('ยกเลิกบิล: ' || trim(p_reason), 500)
     where id = iv.service_order_id and status in ('OPEN', 'COMPLETED');
    perform set_config('app.void_order', 'off', true);
  end if;

  v_result := private.invoice_view(iv.id);
  perform private.idempotency_complete('pos_void_invoice', p_idempotency_key, 200, v_result);
  return v_result;
end;
$$;

-- สรุปเงินแดชบอร์ด: ไม่นับคิวของ Order ที่ยกเลิกบิล (ค่าแรงหมอวิ่ง / จำนวนลูกค้า)
create or replace function public.branch_money_summary(p_branch_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company     uuid;
  v_revenue     numeric := 0;
  v_expenses    numeric := 0;
  v_commission  numeric := 0;
  v_fuel        numeric := 0;
  v_walkin_fee  numeric := 0;
  v_customers   jsonb;
begin
  select company_id into v_company from public.branches where id = p_branch_id;
  if v_company is null or not private.is_company_owner(v_company) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then
    raise exception 'ช่วงวันที่ไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  perform private.sync_commissions(v_company);

  select coalesce(sum(f.net_revenue), 0), coalesce(sum(f.expenses), 0), coalesce(sum(f.commission_cost), 0)
    into v_revenue, v_expenses, v_commission
    from private.daily_finance(v_company, p_from, p_to) f
   where f.branch_id = p_branch_id;

  select coalesce(sum(amount), 0) into v_fuel
    from public.expenses
   where branch_id = p_branch_id and status = 'RECORDED' and category = 'FREELANCE_FUEL'
     and occurred_on between p_from and p_to;

  -- คิวที่ให้บริการเสร็จในช่วงนี้ + การมอบหมายล่าสุด (เปลี่ยนหมอระหว่างบริการ = นับคนสุดท้าย)
  with done as (
    select q.id, i.therapist_fee, a.employee_id, a.freelance_name
      from public.queue_items q
      join public.service_order_items i on i.id = q.service_order_item_id
      join public.service_orders so on so.id = i.service_order_id and so.status <> 'CANCELLED'
      left join lateral (
        select sa.employee_id, sa.freelance_name
          from public.service_assignments sa
         where sa.queue_item_id = q.id and sa.status <> 'CANCELLED'
         order by sa.assigned_at desc
         limit 1) a on true
     where q.branch_id = p_branch_id and q.status = 'COMPLETED' and q.queue_date between p_from and p_to
  ), typed as (
    select d.*, case when d.freelance_name is not null then 'WALK_IN'
                     else coalesce(e.employment_type, 'REGULAR') end as kind
      from done d left join public.employees e on e.id = d.employee_id
  )
  select coalesce(sum(therapist_fee) filter (where kind = 'WALK_IN'), 0),
         jsonb_build_object(
           'total', count(*),
           'REGULAR', count(*) filter (where kind = 'REGULAR'),
           'FREELANCE', count(*) filter (where kind = 'FREELANCE'),
           'WALK_IN', count(*) filter (where kind = 'WALK_IN'))
    into v_walkin_fee, v_customers
    from typed;

  return jsonb_build_object(
    'from', p_from, 'to', p_to,
    'revenue', v_revenue,
    'expenses', v_expenses - v_fuel,            -- รายจ่ายร้านทั่วไป
    'freelance_fuel', v_fuel,                   -- ค่าน้ำมันหมอวิ่ง
    'freelance_fee', v_walkin_fee,              -- ค่าแรงหมอวิ่ง
    'commission', v_commission,                 -- ค่ามือหมอพนักงาน
    'total_expenses', v_expenses + v_commission + v_walkin_fee,
    'net', v_revenue - (v_expenses + v_commission + v_walkin_fee),
    'customers', v_customers
  );
end;
$$;
