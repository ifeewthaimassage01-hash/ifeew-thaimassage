-- =============================================================================
-- 045 — สรุปการเงินของสาขาบนแดชบอร์ด (OWNER เท่านั้น)
--   รายได้       = net_revenue จาก private.daily_finance (ตัวเดียวกับรายงานการเงิน/ปิดยอด)
--   รายจ่าย      = รายจ่ายร้าน (รวมค่าน้ำมันหมอวิ่ง) + ค่ามือหมอพนักงาน + ค่าแรงหมอวิ่ง
--                  ค่าแรงหมอวิ่ง (กรอกชื่อ ไม่มีบัญชี — migration 033) ไม่อยู่ในระบบค่ามือ
--                  จึงคิดจาก therapist_fee ของรายการบริการที่หมอวิ่งทำจนเสร็จ
--   ยอดสุทธิ     = รายได้ − รายจ่ายทั้งหมด
--   ลูกค้า       = จำนวนคิวที่ให้บริการเสร็จ แยกตามประเภทหมอของการมอบหมายล่าสุด
--                  REGULAR (หมอประจำ) / FREELANCE (หมอฟรีแลนซ์ที่มีบัญชี) / WALK_IN (หมอวิ่ง กรอกชื่อ)
-- =============================================================================

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

revoke all on function public.branch_money_summary(uuid, date, date) from public, anon;
grant execute on function public.branch_money_summary(uuid, date, date) to authenticated;
