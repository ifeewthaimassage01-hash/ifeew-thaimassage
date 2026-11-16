-- 080 — Statement ของร้าน (เจ้าของร้าน · ดาวน์โหลดเป็น PDF ในหน้า /reports/statement)
--   public.shop_statement(company, branch|null, from, to) → รายการเงินเข้า/ออกเรียงตามเวลา
--   นับแบบเดียวกับรายงานการเงิน (private.daily_finance):
--     เข้า: รับชำระ (เงินสด/โอน/QR/หักมัดจำ) · มัดจำที่ริบ
--     ออก: คืนเงินลูกค้า · รายจ่าย · ค่าแรงหมอ (รวมเป็นรายวันต่อสาขา: ค่ามือ+การันตี+ปรับ+หมอวิ่ง)
--   ทิปไม่นับ (เป็นเงินของหมอ ผ่านร้านแล้วจ่ายออก) · ทุกสาขา = รวมรายจ่าย/ปรับค่าแรงส่วนกลางด้วย

create or replace function public.shop_statement(p_company_id uuid, p_branch_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then
    raise exception 'ช่วงวันที่ต้องไม่เกิน 1 ปี' using errcode = 'invalid_parameter_value';
  end if;
  if p_branch_id is not null and not exists (
    select 1 from public.branches b where b.id = p_branch_id and b.company_id = p_company_id) then
    raise exception 'ไม่พบสาขา' using errcode = 'invalid_parameter_value';
  end if;
  perform private.sync_commissions(p_company_id);

  with tx as (
    -- รับชำระ
    select coalesce(s.business_date, iv.business_date) as d, p.received_at as at, p.branch_id,
           case p.method when 'CASH' then 'รับเงินสด' when 'BANK_TRANSFER' then 'รับเงินโอน'
                         when 'QR' then 'รับเงิน QR' else 'หักมัดจำที่จองไว้' end as title,
           concat_ws(' · ', coalesce(iv.receipt_number, iv.invoice_number),
                     nullif(trim(concat_ws(' ', c.first_name, c.last_name)), '')) as detail,
           p.amount as amount_in, 0::numeric as amount_out
      from public.payments p
      join public.invoices iv on iv.id = p.invoice_id
      left join public.pos_sessions s on s.id = p.pos_session_id
      left join public.customers c on c.id = iv.customer_id and c.anonymized_at is null
     where p.company_id = p_company_id and p.status = 'SUCCESS'
       and (p_branch_id is null or p.branch_id = p_branch_id)
       and coalesce(s.business_date, iv.business_date) between p_from and p_to
    union all
    -- คืนเงินลูกค้า
    select coalesce(s.business_date, private.company_local_date(p_company_id, r.refunded_at)), r.refunded_at, r.branch_id,
           case r.method when 'CASH' then 'คืนเงินสด' else 'คืนเงินโอน' end,
           concat_ws(' · ', coalesce(iv.receipt_number, iv.invoice_number), r.reason),
           0, r.amount
      from public.payment_refunds r
      join public.invoices iv on iv.id = r.invoice_id
      left join public.pos_sessions s on s.id = r.pos_session_id
     where r.company_id = p_company_id
       and (p_branch_id is null or r.branch_id = p_branch_id)
       and coalesce(s.business_date, private.company_local_date(p_company_id, r.refunded_at)) between p_from and p_to
    union all
    -- มัดจำที่ริบ (ลูกค้าไม่มา/ยกเลิกเกินกำหนด)
    select private.company_local_date(p_company_id, b.starts_at), b.starts_at, dep.branch_id,
           'ริบมัดจำ', b.booking_code, dep.amount, 0
      from public.booking_deposits dep
      join public.bookings b on b.id = dep.booking_id
     where dep.company_id = p_company_id and dep.status = 'VERIFIED' and dep.refund_status = 'FORFEITED'
       and (p_branch_id is null or dep.branch_id = p_branch_id)
       and private.company_local_date(p_company_id, b.starts_at) between p_from and p_to
    union all
    -- รายจ่าย (ส่วนกลาง = ไม่มีสาขา แสดงเมื่อดูทุกสาขา)
    select e.occurred_on, e.created_at, e.branch_id,
           case when e.branch_id is null then 'รายจ่ายส่วนกลาง'
                when e.payment_source = 'CASH_DRAWER' then 'รายจ่าย (เงินในลิ้นชัก)' else 'รายจ่าย' end,
           e.note, 0, e.amount
      from public.expenses e
     where e.company_id = p_company_id and e.status = 'RECORDED'
       and (case when p_branch_id is null then true else e.branch_id = p_branch_id end)
       and e.occurred_on between p_from and p_to
    union all
    -- ค่าแรงหมอ รายวันต่อสาขา (สิ้นวัน)
    select w.d, null, w.branch_id, 'ค่าแรงหมอ',
           case when w.people > 0 then w.people || ' คน' end,
           case when w.amount < 0 then -w.amount else 0 end,
           case when w.amount > 0 then w.amount else 0 end
      from (
        select z.d, z.branch_id, sum(z.amount) as amount, count(distinct z.who) as people
          from (
            select c.business_date as d, c.branch_id, c.amount, c.employee_id::text as who
              from public.commissions c
             where c.company_id = p_company_id and c.status <> 'VOID'
               and c.business_date between p_from and p_to
            union all
            select a.business_date, a.branch_id, a.amount, a.employee_id::text
              from public.commission_adjustments a
             where a.company_id = p_company_id and a.business_date between p_from and p_to
               and (case when p_branch_id is null then true else a.branch_id = p_branch_id end)
            union all
            -- หมอวิ่ง (ไม่ใช่พนักงานในระบบ) ค่ามือตามรายการบริการ
            select q.queue_date, q.branch_id, i.therapist_fee, 'walkin:' || la.freelance_name
              from public.queue_items q
              join public.service_order_items i on i.id = q.service_order_item_id
              join public.service_orders so on so.id = i.service_order_id and so.status <> 'CANCELLED'
              join lateral (
                select sa.freelance_name from public.service_assignments sa
                 where sa.queue_item_id = q.id and sa.status <> 'CANCELLED' order by sa.assigned_at desc limit 1) la
                on la.freelance_name is not null
             where q.company_id = p_company_id and q.status = 'COMPLETED'
               and q.queue_date between p_from and p_to and coalesce(i.therapist_fee, 0) > 0
          ) z
         where p_branch_id is null or z.branch_id = p_branch_id
         group by z.d, z.branch_id
      ) w
     where w.amount <> 0
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'date', tx.d,
           'time', case when tx.at is null then null
                        else to_char(tx.at at time zone coalesce(cs.timezone, 'Asia/Bangkok'), 'HH24:MI') end,
           'branch', b.name, 'branch_code', b.code,
           'title', tx.title, 'detail', nullif(tx.detail, ''),
           'in', round(tx.amount_in, 2), 'out', round(tx.amount_out, 2))
           order by tx.d, tx.at nulls last, tx.title), '[]'::jsonb)
    into v_rows
    from tx
    left join public.branches b on b.id = tx.branch_id
    left join public.company_settings cs on cs.company_id = p_company_id;

  return jsonb_build_object(
    'company', (select jsonb_build_object('name', c.name, 'legal_name', c.legal_name, 'tax_id', c.tax_id)
                  from public.companies c where c.id = p_company_id),
    'branch', (select jsonb_build_object('name', b.name, 'code', b.code, 'address', b.address, 'phone', b.phone)
                 from public.branches b where b.id = p_branch_id),
    'from', p_from, 'to', p_to,
    'generated_at', now(),
    'rows', v_rows
  );
end;
$$;
revoke all on function public.shop_statement(uuid, uuid, date, date) from public, anon;
grant execute on function public.shop_statement(uuid, uuid, date, date) to authenticated;
