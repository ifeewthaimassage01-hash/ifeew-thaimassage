-- 081 — Statement ร้าน แบบต่อบริการ (แทน 080)
--   1 บรรทัดต่อ 1 บริการที่ชำระแล้ว: "นวดไทย 2.5 ชม · หมอ แตน" รายรับ = ราคาหลังส่วนลด · รายจ่าย = ค่ามือหมอของบริการนั้น
--   บรรทัดอื่น: รายจ่าย (ชื่อ = หมายเหตุ เช่น "น้ำ") · การันตีค่ามือ / ปรับค่าแรง (รายหมอ รายวัน) · คืนเงิน · ริบมัดจำ
--   บริการนับเมื่อบิลชำระครบ (PAID) ตามวันทำการของบิล · ไม่รวมทิป

create or replace function public.shop_statement(p_company_id uuid, p_branch_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tz   text;
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
  select coalesce(s.timezone, 'Asia/Bangkok') into v_tz from public.company_settings s where s.company_id = p_company_id;
  v_tz := coalesce(v_tz, 'Asia/Bangkok');
  perform private.sync_commissions(p_company_id);

  with tx as (
    -- บริการที่ชำระแล้ว: รายรับ + ค่ามือของบริการนั้น
    select iv.business_date as d, iv.paid_at as at, ii.branch_id,
           concat_ws(' · ',
             coalesce(si.service_name, ii.description) || ' ' ||
               case when coalesce(si.duration_minutes, ii.duration_minutes) % 30 = 0
                    then trim_scale(coalesce(si.duration_minutes, ii.duration_minutes) / 60.0)::text || ' ชม'
                    else coalesce(si.duration_minutes, ii.duration_minutes)::text || ' นาที' end,
             'หมอ ' || th.names) as title,
           ii.line_total as amount_in,
           coalesce(th.fee, 0) as amount_out
      from public.invoice_items ii
      join public.invoices iv on iv.id = ii.invoice_id
      left join public.service_order_items si on si.id = ii.service_order_item_id
      left join lateral (
        select string_agg(distinct coalesce(e.nickname, sa.freelance_name), ', ') as names,
               sum(coalesce(
                 (select sum(c.amount) from public.commissions c
                   where c.service_assignment_id = sa.id and c.status <> 'VOID'),
                 case when sa.freelance_name is not null then si.therapist_fee end, 0)) as fee
          from public.queue_items q
          join public.service_assignments sa on sa.queue_item_id = q.id and sa.status <> 'CANCELLED'
          left join public.employees e on e.id = sa.employee_id
         where q.service_order_item_id = si.id
      ) th on true
     where iv.company_id = p_company_id and iv.status = 'PAID'
       and (p_branch_id is null or ii.branch_id = p_branch_id)
       and iv.business_date between p_from and p_to
    union all
    -- รายจ่าย (ส่วนกลาง = ไม่มีสาขา แสดงเมื่อดูทุกสาขา)
    select e.occurred_on, e.created_at, e.branch_id,
           e.note || case when e.branch_id is null then ' (ส่วนกลาง)' else '' end,
           0, e.amount
      from public.expenses e
     where e.company_id = p_company_id and e.status = 'RECORDED'
       and (case when p_branch_id is null then true else e.branch_id = p_branch_id end)
       and e.occurred_on between p_from and p_to
    union all
    -- การันตีค่ามือ (เติมให้ถึงขั้นต่ำ) รายหมอ รายวัน
    select c.business_date, null, c.branch_id, 'การันตีค่ามือ · หมอ ' || e.nickname, 0, sum(c.amount)
      from public.commissions c
      join public.employees e on e.id = c.employee_id
     where c.company_id = p_company_id and c.kind = 'GUARANTEE' and c.status <> 'VOID'
       and (p_branch_id is null or c.branch_id = p_branch_id)
       and c.business_date between p_from and p_to
     group by c.business_date, c.branch_id, e.nickname
    having sum(c.amount) <> 0
    union all
    -- ปรับค่าแรง (บวก = จ่ายเพิ่ม · ลบ = หักคืน)
    select a.business_date, a.created_at, a.branch_id,
           concat_ws(' · ', 'ปรับค่าแรง', 'หมอ ' || e.nickname, a.reason),
           case when a.amount < 0 then -a.amount else 0 end,
           case when a.amount > 0 then a.amount else 0 end
      from public.commission_adjustments a
      join public.employees e on e.id = a.employee_id
     where a.company_id = p_company_id and a.amount <> 0
       and (case when p_branch_id is null then true else a.branch_id = p_branch_id end)
       and a.business_date between p_from and p_to
    union all
    -- คืนเงินลูกค้า
    select coalesce(s.business_date, (r.refunded_at at time zone v_tz)::date), r.refunded_at, r.branch_id,
           concat_ws(' · ', 'คืนเงิน', coalesce(iv.receipt_number, iv.invoice_number), r.reason),
           0, r.amount
      from public.payment_refunds r
      join public.invoices iv on iv.id = r.invoice_id
      left join public.pos_sessions s on s.id = r.pos_session_id
     where r.company_id = p_company_id
       and (p_branch_id is null or r.branch_id = p_branch_id)
       and coalesce(s.business_date, (r.refunded_at at time zone v_tz)::date) between p_from and p_to
    union all
    -- มัดจำที่ริบ (ลูกค้าไม่มา/ยกเลิกเกินกำหนด)
    select (b.starts_at at time zone v_tz)::date, b.starts_at, dep.branch_id,
           'ริบมัดจำ · ' || b.booking_code, dep.amount, 0
      from public.booking_deposits dep
      join public.bookings b on b.id = dep.booking_id
     where dep.company_id = p_company_id and dep.status = 'VERIFIED' and dep.refund_status = 'FORFEITED'
       and (p_branch_id is null or dep.branch_id = p_branch_id)
       and (b.starts_at at time zone v_tz)::date between p_from and p_to
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'date', tx.d,
           -- ไม่มีเวลา (รายการรายวัน) = สิ้นวัน
           'time', coalesce(to_char(tx.at at time zone v_tz, 'HH24:MI'), '23:59'),
           'branch', b.name, 'branch_code', b.code,
           'title', tx.title,
           'in', round(tx.amount_in, 2), 'out', round(tx.amount_out, 2))
           order by tx.d, coalesce(to_char(tx.at at time zone v_tz, 'HH24:MI'), '23:59'), tx.at, tx.title), '[]'::jsonb)
    into v_rows
    from tx
    left join public.branches b on b.id = tx.branch_id
   where tx.amount_in <> 0 or tx.amount_out <> 0;

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
