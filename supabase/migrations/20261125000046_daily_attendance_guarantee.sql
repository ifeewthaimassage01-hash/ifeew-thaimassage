-- =============================================================================
-- 046 — เลิกใช้ "กะ" ทำงานแบบรายวัน (ตามที่ผู้ใช้ขอ)
--   * เข้าใช้งานครั้งแรกของวัน = เช็คชื่อเข้างาน (attendance_clock CLOCK_IN — หน้า login เรียกอยู่แล้ว)
--   * ประกันมือ: หมอประจำที่มียอดประกัน + เช็คชื่อเข้างานวันนั้น = ได้ประกันมือ (ไม่ดูตารางกะ / ไม่ต้องลงเวลาออก)
--       - ได้ทันทีตอนเช็คชื่อ (trigger) เป็น "ยอดขั้นต่ำ": เงินเติม = ยอดประกัน − ค่ามือที่ทำได้วันนั้น (ไม่ติดลบ)
--         ระหว่างวันยอดเติมลดลงตามค่ามือที่ทำได้ (sync คิดวันนี้ด้วย — เดิมคิดเฉพาะวันที่จบแล้ว)
--       - นับเป็นค่าแรงหมอ (commissions kind GUARANTEE) → อยู่ในต้นทุนค่ามือของวันนั้นในรายงาน/แดชบอร์ด
--       - เจ้าของร้านยังให้/ไม่ให้เป็นรายวันได้ (guarantee_overrides) เหมือนเดิม
--   * สถานะ "พร้อมทำงาน" ของหมอ (หน้าคิว/มอบหมาย) = เช็คชื่อเข้างานวันนี้ที่สาขานี้แล้ว (แทนการมีกะ)
--   * กะลิ้นชักเงินสด (pos_sessions): ระบบเปิด/ปิดเองอยู่แล้ว (migration 031/034) ไม่มีหน้าจอให้จัดการ
-- =============================================================================

-- -----------------------------------------------------------------------------
-- คำนวณประกันมือของหมอ/สาขา/วัน (แทนที่ 023)
--   has_shift / attended = เช็คชื่อเข้างานวันนั้นที่สาขานั้น (คงชื่อคอลัมน์ไว้ให้รายงานเดิมใช้ได้)
-- -----------------------------------------------------------------------------
create or replace function private.compute_guarantee(p_employee_id uuid, p_branch_id uuid, p_date date)
returns table (rate numeric, earned numeric, has_shift boolean, attended boolean, override_grant boolean,
               qualified boolean, topup numeric)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  e public.employees;
begin
  select * into e from public.employees where id = p_employee_id;

  select r.daily_amount into rate from public.employee_guarantee_rates r
   where r.employee_id = e.id and r.status = 'ACTIVE'
     and r.effective_from <= p_date and (r.effective_to is null or r.effective_to > p_date);
  rate := case when e.employment_type = 'REGULAR' then coalesce(rate, 0) else 0 end;

  select coalesce(sum(private.assignment_fee(a.id)), 0) into earned
    from public.service_assignments a
    join public.queue_items q on q.id = a.queue_item_id
   where a.employee_id = e.id and a.branch_id = p_branch_id and q.queue_date = p_date
     and a.status = 'COMPLETED' and q.status = 'COMPLETED'
     and not exists (select 1 from public.commissions c where c.service_assignment_id = a.id and c.status = 'VOID');

  attended := exists (select 1 from public.staff_attendances
                       where employee_id = e.id and business_date = p_date and branch_id = p_branch_id);
  has_shift := attended;

  select o.grant_guarantee into override_grant from public.guarantee_overrides o
   where o.employee_id = e.id and o.business_date = p_date and o.branch_id = p_branch_id;

  qualified := rate > 0 and coalesce(override_grant, attended);
  topup := case when qualified then greatest(rate - earned, 0) else 0 end;
  return next;
end;
$$;

revoke all on function private.compute_guarantee(uuid, uuid, date) from public;

-- -----------------------------------------------------------------------------
-- ทำให้แถวประกันมือของหมอ/สาขา/วัน ตรงกับ compute_guarantee (idempotent)
-- -----------------------------------------------------------------------------
create or replace function private.sync_guarantee_day(p_company_id uuid, p_employee_id uuid, p_branch_id uuid, p_date date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := private.company_local_date(p_company_id);
  r       record;
  c       public.commissions;
  v_paid  numeric;
  v_delta numeric;
begin
  if private.period_locked(p_company_id, p_date) then
    return;
  end if;

  select * into r from private.compute_guarantee(p_employee_id, p_branch_id, p_date);
  select * into c from public.commissions
   where kind = 'GUARANTEE' and employee_id = p_employee_id and branch_id = p_branch_id and business_date = p_date
   for update;

  if c.id is null then
    if r.topup > 0 then
      insert into public.commissions (company_id, branch_id, employee_id, business_date, kind, base_amount, amount)
      values (p_company_id, p_branch_id, p_employee_id, p_date, 'GUARANTEE', r.rate, r.topup);
    end if;
  elsif c.status = 'ACCRUED' then
    if c.amount <> r.topup or c.base_amount <> r.rate then
      update public.commissions set amount = r.topup, base_amount = r.rate where id = c.id;
    end if;
  elsif c.status = 'VOID' then
    if r.topup > 0 then
      update public.commissions set status = 'ACCRUED', amount = r.topup, base_amount = r.rate, void_reason = null
       where id = c.id;
    end if;
  else
    -- จ่ายไปแล้ว: ปรับส่วนต่างในรอบถัดไป
    select c.amount + coalesce(sum(x.amount), 0) into v_paid
      from public.commission_adjustments x where x.commission_id = c.id and x.source = 'GUARANTEE_RECALC';
    v_delta := r.topup - v_paid;
    if v_delta <> 0 then
      insert into public.commission_adjustments (company_id, branch_id, employee_id, business_date, amount, source,
                                                 commission_id, reason)
      values (p_company_id, p_branch_id, p_employee_id, v_today, v_delta, 'GUARANTEE_RECALC', c.id,
              'ปรับเงินประกันมือวันที่ ' || to_char(p_date, 'DD/MM/YYYY'));
    end if;
  end if;
end;
$$;

revoke all on function private.sync_guarantee_day(uuid, uuid, uuid, date) from public;

-- -----------------------------------------------------------------------------
-- sync ค่ามือ (แทนที่ 033): ข้อ 1–2 เหมือนเดิม · ข้อ 3 ประกันมือ คิดจากการเช็คชื่อ และรวมวันนี้
-- -----------------------------------------------------------------------------
create or replace function private.sync_commissions_core(p_company_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today  date := private.company_local_date(p_company_id);
  r        record;
  g        record;
begin
  -- 1) ค่ามือบริการที่ถึงเกณฑ์ (จบ + Invoice จ่ายครบ ไม่ถูกคืนเงินเต็มจำนวน) และยังไม่มีแถว
  insert into public.commissions (company_id, branch_id, employee_id, business_date, kind, service_assignment_id,
                                  base_amount, share_ratio, amount)
  select a.company_id, a.branch_id, a.employee_id, q.queue_date, 'SERVICE', a.id, i.therapist_fee,
         case when i.therapist_fee > 0 then round(private.assignment_fee(a.id) / i.therapist_fee, 6) end,
         private.assignment_fee(a.id)
    from public.service_assignments a
    join public.queue_items q on q.id = a.queue_item_id
    join public.service_order_items i on i.id = q.service_order_item_id
   where a.company_id = p_company_id and a.status = 'COMPLETED' and q.status = 'COMPLETED'
     and a.employee_id is not null   -- (033) หมอวิ่งแบบกรอกชื่อไม่มีค่ามือในระบบ
     and not private.period_locked(p_company_id, q.queue_date)
     and not exists (select 1 from public.commissions x where x.service_assignment_id = a.id)
     and exists (select 1 from public.invoice_items ii join public.invoices iv on iv.id = ii.invoice_id
                  where ii.service_order_item_id = i.id and iv.status = 'PAID' and iv.refunded_amount < iv.total);

  -- 2) ค่ามือบริการที่ไม่ถึงเกณฑ์แล้ว (Void / คืนเงินเต็มจำนวน)
  for r in
    select c2.* from public.commissions c2
      join public.service_assignments a on a.id = c2.service_assignment_id
      join public.queue_items q on q.id = a.queue_item_id
     where c2.company_id = p_company_id and c2.kind = 'SERVICE' and c2.status <> 'VOID'
       and not exists (select 1 from public.invoice_items ii join public.invoices iv on iv.id = ii.invoice_id
                        where ii.service_order_item_id = q.service_order_item_id
                          and iv.status = 'PAID' and iv.refunded_amount < iv.total)
       and not exists (select 1 from public.commission_adjustments x
                        where x.commission_id = c2.id and x.source = 'VOID_REVERSAL')
     for update of c2
  loop
    if r.status = 'ACCRUED' then
      update public.commissions set status = 'VOID', payout_id = null, void_reason = 'Invoice ถูก Void/คืนเงินเต็มจำนวน'
       where id = r.id;
    else
      insert into public.commission_adjustments (company_id, branch_id, employee_id, business_date, amount, source,
                                                 commission_id, reason)
      values (r.company_id, r.branch_id, r.employee_id, v_today, -r.amount, 'VOID_REVERSAL', r.id,
              'กลับรายการค่ามือ (Invoice ถูก Void/คืนเงินเต็มจำนวนหลังจ่ายแล้ว)');
    end if;
  end loop;

  -- 3) ประกันมือ: วันที่หมอประจำเช็คชื่อเข้างาน (รวมวันนี้) + แถวประกันมือเดิม ย้อนหลังไม่เกิน 62 วัน
  for g in
    select a.employee_id, a.branch_id, a.business_date as d
      from public.staff_attendances a
      join public.employees e on e.id = a.employee_id and e.employment_type = 'REGULAR'
     where a.company_id = p_company_id and a.business_date >= v_today - 62
       and exists (select 1 from public.employee_guarantee_rates gr where gr.employee_id = a.employee_id and gr.status = 'ACTIVE')
    union
    select o.employee_id, o.branch_id, o.business_date
      from public.guarantee_overrides o
     where o.company_id = p_company_id and o.business_date >= v_today - 62
    union
    select c3.employee_id, c3.branch_id, c3.business_date
      from public.commissions c3
     where c3.company_id = p_company_id and c3.kind = 'GUARANTEE' and c3.status <> 'VOID'
       and c3.business_date >= v_today - 62
  loop
    perform private.sync_guarantee_day(p_company_id, g.employee_id, g.branch_id, g.d);
  end loop;
end;
$$;

revoke all on function private.sync_commissions_core(uuid) from public;

-- -----------------------------------------------------------------------------
-- เช็คชื่อเข้างาน → ได้ประกันมือของวันนั้นทันที
-- -----------------------------------------------------------------------------
create or replace function private.tg_attendance_guarantee()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- คิวเดียวกับ sync ค่ามือ (กันสร้างแถวประกันมือซ้ำพร้อมกัน)
  perform pg_advisory_xact_lock(hashtextextended('sync-commissions:' || new.company_id::text, 0));
  perform private.sync_guarantee_day(new.company_id, new.employee_id, new.branch_id, new.business_date);
  return new;
end;
$$;

drop trigger if exists staff_attendances_guarantee on public.staff_attendances;
create trigger staff_attendances_guarantee
  after insert on public.staff_attendances
  for each row execute function private.tg_attendance_guarantee();

-- -----------------------------------------------------------------------------
-- มอบหมายหมอ (แทนที่ 020): "พร้อมทำงาน" = เช็คชื่อเข้างานวันนี้ที่สาขานี้แล้ว
--   ยังไม่เช็คชื่อ → ถามยืนยันก่อน (hint OFF_SHIFT เดิม หน้าคิวรองรับอยู่แล้ว)
-- -----------------------------------------------------------------------------
create or replace function private.assert_therapist_available(
  p_company_id         uuid,
  p_branch_id          uuid,
  p_employee_id        uuid,
  p_confirm_off_shift  boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  e          public.employees;
  v_on_duty  boolean;
begin
  -- ล็อกแถวพนักงาน กันมอบหมายหมอคนเดียวกันพร้อมกันสองคิว
  select * into e from public.employees where id = p_employee_id and company_id = p_company_id for update;
  if e.id is null or e.status <> 'ACTIVE' or not private.is_active_staff_of_branch(e.user_id, p_branch_id) then
    raise exception 'พนักงานคนนี้ไม่ได้ประจำสาขานี้ หรือไม่ได้อยู่ในสถานะใช้งาน' using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.service_assignments
              where employee_id = e.id and status in ('ASSIGNED', 'ACCEPTED', 'IN_SERVICE')) then
    raise exception '% มีคิวที่รับไว้หรือกำลังให้บริการอยู่', e.nickname using errcode = 'check_violation';
  end if;

  v_on_duty := exists (
    select 1 from public.staff_attendances a
     where a.employee_id = e.id and a.branch_id = p_branch_id
       and a.business_date = (select w.business_date from private.branch_window_at(p_branch_id, now()) w));
  if not v_on_duty and not coalesce(p_confirm_off_shift, false) then
    raise exception '% ยังไม่ได้เช็คชื่อเข้างานวันนี้ ยืนยันเพื่อมอบหมายต่อ', e.nickname using errcode = 'P0001', hint = 'OFF_SHIFT';
  end if;
  return v_on_duty;
end;
$$;

revoke all on function private.assert_therapist_available(uuid, uuid, uuid, boolean) from public;

-- -----------------------------------------------------------------------------
-- กระดานคิว (แทนที่ 020): therapists.on_shift = เช็คชื่อเข้างานวันนี้ที่สาขานี้แล้ว
-- -----------------------------------------------------------------------------
create or replace function public.pos_board(p_branch_id uuid, p_date date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_today date;
  v_date  date;
begin
  perform private.require_branch_access(p_branch_id);
  select business_date into v_today from private.branch_window_at(p_branch_id, now());
  v_date := coalesce(p_date, v_today);

  return jsonb_build_object(
    'business_date', v_date,
    'is_today', v_date = v_today,
    'session', (
      select jsonb_build_object('session_id', s.id, 'opened_at', s.opened_at, 'opening_cash', s.opening_cash,
                                'opened_by_name', p.display_name, 'business_date', s.business_date)
        from public.pos_sessions s left join public.profiles p on p.id = s.opened_by
       where s.branch_id = p_branch_id and s.status = 'OPEN'),
    'orders', coalesce((
      select jsonb_agg(private.pos_order_view(o.id) order by o.created_at)
        from public.service_orders o
       where o.branch_id = p_branch_id and o.business_date = v_date), '[]'::jsonb),
    'therapists', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employee_id', e.id, 'nickname', e.nickname, 'user_id', e.user_id, 'photo_path', e.photo_path,
        'on_shift', exists (
          select 1 from public.staff_attendances a
           where a.employee_id = e.id and a.branch_id = p_branch_id and a.business_date = v_today),
        'busy_queue_number', (
          select q.queue_number from public.service_assignments a join public.queue_items q on q.id = a.queue_item_id
           where a.employee_id = e.id and a.status in ('ASSIGNED', 'ACCEPTED', 'IN_SERVICE')),
        'busy_status', (
          select a.status from public.service_assignments a
           where a.employee_id = e.id and a.status in ('ASSIGNED', 'ACCEPTED', 'IN_SERVICE'))
      ) order by e.nickname)
        from public.employees e
        join public.branches br on br.id = p_branch_id and br.company_id = e.company_id
       where e.status = 'ACTIVE' and private.is_active_staff_of_branch(e.user_id, p_branch_id)), '[]'::jsonb)
  );
end;
$$;
