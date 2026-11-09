-- =============================================================================
-- 033 — คิวแบบย่อ + หมอวิ่ง (ตามที่ผู้ใช้ขอ)
--   * “เรียกคิว” = มอบหมายหมอและเริ่มบริการทันที (WAITING → IN_SERVICE ใน Transaction เดียว)
--     หน้าคิวเหลือ 3 คอลัมน์: รอเรียก / กำลังให้บริการ / เสร็จ-ยกเลิก
--   * หมอวิ่ง: กรอกชื่อ (ไม่ต้องมีบัญชีพนักงาน) — service_assignments.freelance_name
--     ค่าน้ำมัน (เฉพาะหมอวิ่ง) = รายจ่ายของร้าน หมวด FREELANCE_FUEL จ่ายจากลิ้นชัก (ไม่ต้องแนบรูป)
--     จำนวนเงินตั้งโดยเจ้าของร้าน (company_settings.freelance_fuel_amount) — หน้าคิวแค่ติ๊กว่ามีค่าน้ำมัน
-- ข้อจำกัดที่ยอมรับ: หมอวิ่งแบบกรอกชื่อไม่มีค่ามือในระบบค่าคอม (ไม่ผูกกับพนักงาน)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ค่าน้ำมันหมอวิ่ง (บาท/ครั้ง) — เจ้าของร้านตั้งที่หน้าตั้งค่าบริษัท
-- -----------------------------------------------------------------------------
-- (ทุกคำสั่งรันซ้ำได้: ฐานข้อมูลบางส่วนเคยถูกแก้ไปก่อนแล้ว)
alter table public.company_settings
  add column if not exists freelance_fuel_amount numeric(10,2) not null default 0
    check (freelance_fuel_amount between 0 and 10000);
comment on column public.company_settings.freelance_fuel_amount is 'ค่าน้ำมันหมอวิ่งต่อครั้งที่เรียกคิว (0 = ยังไม่ได้ตั้ง)';
grant update (freelance_fuel_amount) on public.company_settings to authenticated;

-- -----------------------------------------------------------------------------
-- การมอบหมาย: หมอประจำ (employee_id) หรือ หมอวิ่ง (freelance_name) อย่างใดอย่างหนึ่ง
-- -----------------------------------------------------------------------------
alter table public.service_assignments
  alter column employee_id drop not null,
  add column if not exists freelance_name text check (freelance_name is null or char_length(trim(freelance_name)) between 1 and 60),
  add column if not exists fuel_expense_id uuid references public.expenses (id) on delete restrict,
  drop constraint if exists service_assignments_who_chk;
alter table public.service_assignments
  add constraint service_assignments_who_chk check ((employee_id is null) = (freelance_name is not null));

comment on column public.service_assignments.freelance_name is 'หมอวิ่ง (กรอกชื่อ ไม่มีบัญชีพนักงาน) — employee_id เป็น NULL';
comment on column public.service_assignments.fuel_expense_id is 'รายจ่ายค่าน้ำมันหมอวิ่ง (expenses.category = FREELANCE_FUEL)';

-- -----------------------------------------------------------------------------
-- รายจ่าย: หมวด FREELANCE_FUEL ไม่ต้องแนบรูป (ระบบบันทึกเองตอนเรียกคิว)
-- -----------------------------------------------------------------------------
alter table public.expenses
  add column if not exists category text not null default 'GENERAL' check (category in ('GENERAL', 'FREELANCE_FUEL')),
  alter column photo_path drop not null,
  drop constraint if exists expenses_photo_chk;
alter table public.expenses
  add constraint expenses_photo_chk check (photo_path is not null or category = 'FREELANCE_FUEL');

comment on column public.expenses.category is 'GENERAL = รายจ่ายทั่วไป (ต้องมีรูป), FREELANCE_FUEL = ค่าน้ำมันหมอวิ่ง';

-- -----------------------------------------------------------------------------
-- (แทนที่ 021) มุมมอง Order: แสดงชื่อหมอวิ่ง
-- -----------------------------------------------------------------------------
create or replace function private.pos_order_view(p_order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'order_id', o.id,
    'channel', o.channel,
    'status', o.status,
    'business_date', o.business_date,
    'booking_id', o.booking_id,
    'booking_code', b.booking_code,
    'customer_id', o.customer_id,
    'customer_name', case when c.id is null then null else trim(c.first_name || ' ' || c.last_name) end,
    'phone_masked', private.mask_phone(c.phone),
    'note', o.note,
    'cancel_reason', o.cancel_reason,
    'created_at', o.created_at,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'item_id', i.id,
        'service_name', i.service_name,
        'duration_minutes', i.duration_minutes,
        'unit_price', i.unit_price,
        'item_status', i.status,
        'queue_id', q.id,
        'queue_number', q.queue_number,
        'queue_status', q.status,
        'follows_queue_id', q.follows_queue_id,
        'planned_starts_at', q.planned_starts_at,
        'planned_ends_at', q.planned_ends_at,
        'called_at', q.called_at,
        'started_at', q.started_at,
        'completed_at', q.completed_at,
        'cancel_reason', coalesce(q.cancel_reason, i.cancel_reason),
        'therapist', (
          select jsonb_build_object('employee_id', e.id, 'nickname', coalesce(e.nickname, a.freelance_name),
                                    'user_id', e.user_id, 'is_freelance', a.employee_id is null,
                                    'fuel_amount', fx.amount,
                                    'assignment_status', a.status, 'off_shift_confirmed', a.off_shift_confirmed,
                                    'started_at', a.started_at)
            from public.service_assignments a
            left join public.employees e on e.id = a.employee_id
            left join public.expenses fx on fx.id = a.fuel_expense_id and fx.status = 'RECORDED'
           where a.queue_item_id = q.id and a.status <> 'CANCELLED'
           order by (a.status in ('ASSIGNED', 'ACCEPTED', 'IN_SERVICE')) desc, a.completed_at desc nulls first
           limit 1),
        'handovers', coalesce((
          select jsonb_agg(jsonb_build_object('nickname', coalesce(e.nickname, a.freelance_name), 'started_at', a.started_at,
                                              'ended_at', a.completed_at, 'reason', a.handover_reason)
                           order by a.started_at)
            from public.service_assignments a left join public.employees e on e.id = a.employee_id
           where a.queue_item_id = q.id and a.handover_reason is not null), '[]'::jsonb)
      ) order by q.queue_number)
        from public.service_order_items i
        join public.queue_items q on q.service_order_item_id = i.id
       where i.service_order_id = o.id), '[]'::jsonb)
  )
  from public.service_orders o
  left join public.customers c on c.id = o.customer_id
  left join public.bookings b on b.id = o.booking_id
  where o.id = p_order_id;
$$;

-- -----------------------------------------------------------------------------
-- เรียกคิว = มอบหมาย + เริ่มบริการทันที
--   หมอประจำ: p_employee_id (ตรวจกะ/คิวค้างเหมือน queue_call)
--   หมอวิ่ง : p_freelance_name (+ p_with_fuel = บันทึกค่าน้ำมันตามที่เจ้าของร้านตั้ง เป็นรายจ่ายจากลิ้นชัก)
-- -----------------------------------------------------------------------------
-- เวอร์ชันก่อนหน้า (รับจำนวนค่าน้ำมันจากหน้าจอ) — ลบทิ้ง กัน RPC เรียกแล้วกำกวม
drop function if exists public.queue_call_start(uuid, uuid, boolean, text, numeric);

create or replace function public.queue_call_start(
  p_queue_id           uuid,
  p_employee_id        uuid default null,
  p_confirm_off_shift  boolean default false,
  p_freelance_name     text default null,
  p_with_fuel          boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  q            public.queue_items;
  v_name       text := nullif(trim(coalesce(p_freelance_name, '')), '');
  v_fuel       numeric := 0;
  v_on_shift   boolean := true;
  v_assignment uuid;
  v_session    uuid;
  v_expense    uuid;
  v_date       date;
  v_threshold  numeric;
  v_order      uuid;
begin
  select * into q from public.queue_items where id = p_queue_id for update;
  if q.id is null then
    raise exception 'ไม่พบคิว' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(q.branch_id);
  if q.status not in ('WAITING', 'CALLED', 'ACCEPTED') then
    raise exception 'คิวนี้เริ่มบริการหรือปิดไปแล้ว' using errcode = 'check_violation';
  end if;

  if (p_employee_id is null) = (v_name is null) then
    raise exception 'กรุณาเลือกหมอประจำ หรือกรอกชื่อหมอวิ่ง' using errcode = 'invalid_parameter_value';
  end if;
  if v_name is not null and char_length(v_name) > 60 then
    raise exception 'ชื่อหมอวิ่งยาวเกินไป' using errcode = 'invalid_parameter_value';
  end if;
  if coalesce(p_with_fuel, false) then
    if p_employee_id is not null then
      raise exception 'ค่าน้ำมันใช้ได้เฉพาะหมอวิ่ง' using errcode = 'invalid_parameter_value';
    end if;
    select freelance_fuel_amount into v_fuel from public.company_settings where company_id = q.company_id;
    if coalesce(v_fuel, 0) <= 0 then
      raise exception 'เจ้าของร้านยังไม่ได้ตั้งค่าน้ำมันหมอวิ่ง (เมนูตั้งค่าบริษัท)' using errcode = 'invalid_parameter_value';
    end if;
  end if;

  -- คิวที่เคยเรียกแบบเดิม (CALLED/ACCEPTED) → ยกเลิกการมอบหมายเดิมก่อน
  update public.service_assignments
     set status = 'CANCELLED', cancelled_at = now(), cancelled_by = auth.uid(), cancel_reason = 'เรียกคิวใหม่'
   where queue_item_id = q.id and status in ('ASSIGNED', 'ACCEPTED');

  if p_employee_id is not null then
    v_on_shift := private.assert_therapist_available(q.company_id, q.branch_id, p_employee_id, p_confirm_off_shift);
  end if;

  -- เลื่อนช่วงจองเตียงมาเริ่มตอนนี้ (ตรวจ capacity — เตียงไม่พอจะ error)
  perform private.shift_item_allocations_to_now(q.service_order_item_id);

  insert into public.service_assignments (company_id, branch_id, queue_item_id, employee_id, freelance_name, status,
                                          off_shift_confirmed, assigned_by, accepted_at, accepted_by, started_at)
  values (q.company_id, q.branch_id, q.id, p_employee_id, v_name, 'IN_SERVICE',
          not v_on_shift, auth.uid(), now(), auth.uid(), now())
  returning id into v_assignment;

  if q.status = 'WAITING' then
    update public.queue_items set status = 'CALLED', called_at = now(), called_by = auth.uid() where id = q.id;
  end if;
  if q.status in ('WAITING', 'CALLED') then
    update public.queue_items set status = 'ACCEPTED', accepted_at = now(), accepted_by = auth.uid() where id = q.id;
  end if;
  update public.queue_items set status = 'IN_SERVICE', started_at = now(), started_by = auth.uid() where id = q.id;

  -- ค่าน้ำมันหมอวิ่ง → รายจ่ายของร้าน จ่ายจากลิ้นชัก (กะเปิดอัตโนมัติถ้ายังไม่มี)
  if v_fuel > 0 then
    v_session := private.require_open_session(q.branch_id);
    select w.business_date into v_date from private.branch_window_at(q.branch_id, now()) w;
    select large_expense_threshold into v_threshold from public.company_settings where company_id = q.company_id;

    insert into public.expenses (company_id, branch_id, expense_scope, category, amount, note, photo_path, occurred_on,
                                 payment_source, pos_session_id, is_large, recorded_by)
    values (q.company_id, q.branch_id, 'BRANCH', 'FREELANCE_FUEL', v_fuel,
            left(format('ค่าน้ำมันหมอวิ่ง: %s (คิว %s)', v_name, lpad(q.queue_number::text, 3, '0')), 500),
            null, v_date, 'CASH_DRAWER', v_session, v_fuel > v_threshold, auth.uid())
    returning id into v_expense;

    insert into public.pos_cash_movements (company_id, branch_id, pos_session_id, movement_type, category, amount, reason, expense_id)
    values (q.company_id, q.branch_id, v_session, 'CASH_OUT', 'EXPENSE', v_fuel,
            left(format('ค่าน้ำมันหมอวิ่ง: %s', v_name), 500), v_expense);

    update public.service_assignments set fuel_expense_id = v_expense where id = v_assignment;
  end if;

  select i.service_order_id into v_order from public.service_order_items i where i.id = q.service_order_item_id;
  return private.pos_order_view(v_order);
end;
$$;

revoke all on function public.queue_call_start(uuid, uuid, boolean, text, boolean) from public, anon;
grant execute on function public.queue_call_start(uuid, uuid, boolean, text, boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- (แทนที่ 022) รายการรายจ่าย: เพิ่ม category
-- -----------------------------------------------------------------------------
create or replace function public.expenses_list(p_company_id uuid, p_branch_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_branch_id is null then
    if not private.is_company_owner(p_company_id) then
      raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
    end if;
  else
    perform private.require_branch_access(p_branch_id);
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 92 then
    raise exception 'ช่วงวันที่ต้องไม่เกิน 92 วัน' using errcode = 'invalid_parameter_value';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'expense_id', e.id, 'amount', e.amount, 'note', e.note, 'photo_path', e.photo_path, 'occurred_on', e.occurred_on,
      'payment_source', e.payment_source, 'is_large', e.is_large, 'status', e.status, 'category', e.category,
      'recorded_by_name', pr.display_name, 'created_at', e.created_at,
      'session_open', s.status = 'OPEN',
      'void_requested_at', e.void_requested_at, 'void_request_reason', e.void_request_reason,
      'void_reason', e.void_reason) order by e.created_at desc)
      from public.expenses e
      left join public.profiles pr on pr.id = e.recorded_by
      left join public.pos_sessions s on s.id = e.pos_session_id
     where e.company_id = p_company_id
       and (case when p_branch_id is null then e.branch_id is null else e.branch_id = p_branch_id end)
       and e.occurred_on between p_from and p_to
  ), '[]'::jsonb);
end;
$$;

-- -----------------------------------------------------------------------------
-- (แทนที่ 023/024) sync ค่ามือ: ข้ามการมอบหมายหมอวิ่งแบบกรอกชื่อ (employee_id เป็น NULL)
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
  c        public.commissions;
  v_paid   numeric;
  v_delta  numeric;
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

  -- 3) เงินเติมประกันมือ: วันที่จบแล้ว (ก่อนวันนี้) ย้อนหลังไม่เกิน 62 วัน ในงวดที่ยังไม่ล็อก
  for g in
    select distinct s.employee_id, s.branch_id, w.business_date as d
      from public.employee_schedules s
      join public.employees e on e.id = s.employee_id and e.employment_type = 'REGULAR'
      cross join lateral private.branch_window_at(s.branch_id, s.starts_at) w
     where s.company_id = p_company_id and s.status = 'SCHEDULED'
       and s.starts_at >= now() - interval '63 days' and s.starts_at < now()
       and exists (select 1 from public.employee_guarantee_rates gr where gr.employee_id = s.employee_id and gr.status = 'ACTIVE')
    union
    select c3.employee_id, c3.branch_id, c3.business_date
      from public.commissions c3
     where c3.company_id = p_company_id and c3.kind = 'GUARANTEE' and c3.status <> 'VOID'
       and c3.business_date >= v_today - 62
  loop
    continue when g.d >= (select w.business_date from private.branch_window_at(g.branch_id, now()) w)
               or private.period_locked(p_company_id, g.d);

    select * into r from private.compute_guarantee(g.employee_id, g.branch_id, g.d);
    select * into c from public.commissions
     where kind = 'GUARANTEE' and employee_id = g.employee_id and branch_id = g.branch_id and business_date = g.d
     for update;

    if c.id is null then
      if r.topup > 0 then
        insert into public.commissions (company_id, branch_id, employee_id, business_date, kind, base_amount, amount)
        values (p_company_id, g.branch_id, g.employee_id, g.d, 'GUARANTEE', r.rate, r.topup);
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
        values (p_company_id, g.branch_id, g.employee_id, v_today, v_delta, 'GUARANTEE_RECALC', c.id,
                'ปรับเงินประกันมือวันที่ ' || to_char(g.d, 'DD/MM/YYYY'));
      end if;
    end if;
  end loop;
end;
$$;


revoke all on function private.sync_commissions_core(uuid) from public;
