-- ค่าแรงหมอ = ค่ามือ (commissions SERVICE) + เงินเติมประกันมือ (GUARANTEE) + รายการปรับ + ทิป
-- ใช้ตาราง commissions ชุดเดียวกับสรุปการเงิน (private.daily_finance) ตัวเลขจึงตรงกันทุกหน้า
-- ต้อง sync_commissions ก่อนอ่าน (เขียนข้อมูล) → ฟังก์ชันเป็น volatile

drop function if exists public.therapist_work_summary(uuid, uuid, date, date);
create function public.therapist_work_summary(p_company_id uuid, p_branch_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then
    raise exception 'ช่วงวันที่ต้องไม่เกิน 1 ปี' using errcode = 'invalid_parameter_value';
  end if;
  perform private.sync_commissions(p_company_id);

  return coalesce((
    with work as (
      select a.employee_id,
             count(distinct a.queue_item_id) as services,
             coalesce(round(sum(extract(epoch from (a.completed_at - a.started_at))) / 60), 0)::int as worked_minutes,
             count(*) filter (where a.off_shift_confirmed) as off_shift_count,
             count(*) filter (where a.handover_reason is not null) as handover_count
        from public.service_assignments a
        join public.queue_items q on q.id = a.queue_item_id
       where a.company_id = p_company_id
         and (p_branch_id is null or a.branch_id = p_branch_id)
         and a.status = 'COMPLETED' and q.status = 'COMPLETED'
         and q.queue_date between p_from and p_to
       group by a.employee_id
    ),
    cm as (
      select c.employee_id,
             sum(c.amount) filter (where c.kind = 'SERVICE') as fee,
             sum(c.amount) filter (where c.kind = 'GUARANTEE') as guarantee
        from public.commissions c
       where c.company_id = p_company_id and c.status <> 'VOID'
         and (p_branch_id is null or c.branch_id = p_branch_id)
         and c.business_date between p_from and p_to
       group by c.employee_id
    ),
    adj as (
      select j.employee_id, sum(j.amount) as amount
        from public.commission_adjustments j
       where j.company_id = p_company_id
         and (p_branch_id is null or j.branch_id = p_branch_id)
         and j.business_date between p_from and p_to
       group by j.employee_id
    ),
    tp as (
      select t.employee_id, sum(t.amount) as tips
        from public.tips t
       where t.company_id = p_company_id
         and (p_branch_id is null or t.branch_id = p_branch_id)
         and t.status <> 'VOID'
         and (t.created_at at time zone 'Asia/Bangkok')::date between p_from and p_to
       group by t.employee_id
    ),
    ids as (
      select employee_id from work union select employee_id from cm
      union select employee_id from adj union select employee_id from tp
    ),
    x as (
      select ids.employee_id,
             coalesce(w.services, 0) as services, coalesce(w.worked_minutes, 0) as worked_minutes,
             coalesce(w.off_shift_count, 0) as off_shift_count, coalesce(w.handover_count, 0) as handover_count,
             coalesce(cm.fee, 0) as fee, coalesce(cm.guarantee, 0) as guarantee,
             coalesce(adj.amount, 0) as adjustments, coalesce(tp.tips, 0) as tips
        from ids
        left join work w on w.employee_id = ids.employee_id
        left join cm on cm.employee_id = ids.employee_id
        left join adj on adj.employee_id = ids.employee_id
        left join tp on tp.employee_id = ids.employee_id
    )
    select jsonb_agg(jsonb_build_object(
      'employee_id', x.employee_id,
      'employee_code', e.employee_code,
      'nickname', e.nickname,
      'services', x.services,
      'worked_minutes', x.worked_minutes,
      'off_shift_count', x.off_shift_count,
      'handover_count', x.handover_count,
      'fee_estimate', x.fee,
      'guarantee', x.guarantee,
      'adjustments', x.adjustments,
      'tips', x.tips,
      'pay_total', x.fee + x.guarantee + x.adjustments + x.tips
    ) order by x.fee + x.guarantee + x.adjustments + x.tips desc, e.nickname)
    from x join public.employees e on e.id = x.employee_id
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.therapist_work_summary(uuid, uuid, date, date) from public, anon;
grant execute on function public.therapist_work_summary(uuid, uuid, date, date) to authenticated;

drop function if exists public.therapist_pay_daily(uuid, uuid, uuid, date, date);
create function public.therapist_pay_daily(p_company_id uuid, p_branch_id uuid, p_employee_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then
    raise exception 'ช่วงวันที่ต้องไม่เกิน 1 ปี' using errcode = 'invalid_parameter_value';
  end if;
  perform private.sync_commissions(p_company_id);

  return coalesce((
    with jobs as (
      select c.business_date as d,
             a.started_at,
             i.service_name,
             i.duration_minutes,
             c.amount as fee,
             a.handover_reason is not null as handover
        from public.commissions c
        join public.service_assignments a on a.id = c.service_assignment_id
        join public.queue_items q on q.id = a.queue_item_id
        join public.service_order_items i on i.id = q.service_order_item_id
       where c.company_id = p_company_id and c.employee_id = p_employee_id
         and c.kind = 'SERVICE' and c.status <> 'VOID'
         and (p_branch_id is null or c.branch_id = p_branch_id)
         and c.business_date between p_from and p_to
    ),
    gu as (
      select c.business_date as d, sum(c.amount) as amount, max(c.base_amount) as base
        from public.commissions c
       where c.company_id = p_company_id and c.employee_id = p_employee_id
         and c.kind = 'GUARANTEE' and c.status <> 'VOID'
         and (p_branch_id is null or c.branch_id = p_branch_id)
         and c.business_date between p_from and p_to
       group by 1
    ),
    adj as (
      select j.business_date as d, sum(j.amount) as amount
        from public.commission_adjustments j
       where j.company_id = p_company_id and j.employee_id = p_employee_id
         and (p_branch_id is null or j.branch_id = p_branch_id)
         and j.business_date between p_from and p_to
       group by 1
    ),
    tp as (
      select (t.created_at at time zone 'Asia/Bangkok')::date as d, sum(t.amount) as amount
        from public.tips t
       where t.company_id = p_company_id and t.employee_id = p_employee_id
         and (p_branch_id is null or t.branch_id = p_branch_id)
         and t.status <> 'VOID'
         and (t.created_at at time zone 'Asia/Bangkok')::date between p_from and p_to
       group by 1
    ),
    days as (select d from jobs union select d from gu union select d from adj union select d from tp),
    s as (
      select days.d,
             (select count(*) from jobs where jobs.d = days.d) as services,
             coalesce((select sum(fee) from jobs where jobs.d = days.d), 0) as fee,
             coalesce((select amount from gu where gu.d = days.d), 0) as guarantee,
             (select base from gu where gu.d = days.d) as guarantee_base,
             coalesce((select amount from adj where adj.d = days.d), 0) as adjustments,
             coalesce((select amount from tp where tp.d = days.d), 0) as tips
        from days
    )
    select jsonb_agg(jsonb_build_object(
      'date', s.d,
      'services', s.services,
      'fee', s.fee,
      'guarantee', s.guarantee,
      'guarantee_base', s.guarantee_base,
      'adjustments', s.adjustments,
      'tips', s.tips,
      'total', s.fee + s.guarantee + s.adjustments + s.tips,
      'jobs', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'time', to_char(jobs.started_at at time zone 'Asia/Bangkok', 'HH24:MI'),
                 'service_name', jobs.service_name,
                 'minutes', jobs.duration_minutes,
                 'fee', jobs.fee,
                 'handover', jobs.handover) order by jobs.started_at)
          from jobs where jobs.d = s.d), '[]'::jsonb)
    ) order by s.d desc)
    from s
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.therapist_pay_daily(uuid, uuid, uuid, date, date) from public, anon;
grant execute on function public.therapist_pay_daily(uuid, uuid, uuid, date, date) to authenticated;
