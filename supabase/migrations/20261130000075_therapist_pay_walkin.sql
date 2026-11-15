-- ค่าแรงหมอ: รวมหมอวิ่ง (หมอนอกที่ไม่มีบัญชีพนักงาน — service_assignments.freelance_name) ด้วย
--   ค่าแรงหมอวิ่ง = ค่ามือเต็มของคิวที่หมอวิ่งเป็นคนสุดท้าย (สูตรเดียวกับ "ค่าแรงหมอวิ่ง" ใน branch_money_summary)
--   ทุกแถวมี kind: 'REGULAR' (หมอประจำ) / 'WALK_IN' (หมอวิ่ง — employee_id = null)

create or replace function public.therapist_work_summary(p_company_id uuid, p_branch_id uuid, p_from date, p_to date)
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
       where a.company_id = p_company_id and a.employee_id is not null
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
    regular as (
      select ids.employee_id, e.employee_code, e.nickname, 'REGULAR'::text as kind,
             coalesce(w.services, 0) as services, coalesce(w.worked_minutes, 0) as worked_minutes,
             coalesce(w.off_shift_count, 0) as off_shift_count, coalesce(w.handover_count, 0) as handover_count,
             coalesce(cm.fee, 0) as fee, coalesce(cm.guarantee, 0) as guarantee,
             coalesce(adj.amount, 0) as adjustments, coalesce(tp.tips, 0) as tips
        from ids
        join public.employees e on e.id = ids.employee_id
        left join work w on w.employee_id = ids.employee_id
        left join cm on cm.employee_id = ids.employee_id
        left join adj on adj.employee_id = ids.employee_id
        left join tp on tp.employee_id = ids.employee_id
    ),
    -- หมอวิ่ง: คิวที่เสร็จ (ออเดอร์ไม่ถูกยกเลิก) ที่หมอคนสุดท้ายเป็นหมอวิ่ง
    walkin as (
      select null::uuid as employee_id, null::text as employee_code, la.freelance_name as nickname, 'WALK_IN'::text as kind,
             count(*) as services,
             coalesce(round(sum(extract(epoch from (la.completed_at - la.started_at))) / 60), 0)::int as worked_minutes,
             0::bigint as off_shift_count, 0::bigint as handover_count,
             coalesce(sum(i.therapist_fee), 0) as fee, 0::numeric as guarantee, 0::numeric as adjustments, 0::numeric as tips
        from public.queue_items q
        join public.service_order_items i on i.id = q.service_order_item_id
        join public.service_orders so on so.id = i.service_order_id and so.status <> 'CANCELLED'
        join lateral (
          select sa.freelance_name, sa.started_at, sa.completed_at
            from public.service_assignments sa
           where sa.queue_item_id = q.id and sa.status <> 'CANCELLED'
           order by sa.assigned_at desc
           limit 1) la on true
       where q.company_id = p_company_id
         and (p_branch_id is null or q.branch_id = p_branch_id)
         and q.status = 'COMPLETED' and q.queue_date between p_from and p_to
         and la.freelance_name is not null
       group by la.freelance_name
    ),
    x as (select * from regular union all select * from walkin)
    select jsonb_agg(jsonb_build_object(
      'employee_id', x.employee_id,
      'employee_code', x.employee_code,
      'nickname', x.nickname,
      'kind', x.kind,
      'services', x.services,
      'worked_minutes', x.worked_minutes,
      'off_shift_count', x.off_shift_count,
      'handover_count', x.handover_count,
      'fee_estimate', x.fee,
      'guarantee', x.guarantee,
      'adjustments', x.adjustments,
      'tips', x.tips,
      'pay_total', x.fee + x.guarantee + x.adjustments + x.tips
    ) order by x.fee + x.guarantee + x.adjustments + x.tips desc, x.nickname)
    from x
  ), '[]'::jsonb);
end;
$$;
