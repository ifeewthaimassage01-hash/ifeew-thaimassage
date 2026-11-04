-- =============================================================================
-- Phase 8 / 023 — การเงินส่วนกลาง
--   ประกันมือหมอประจำ  : employment_type, employee_guarantee_rates, staff_attendances (ลงเวลาด้วย PIN),
--                        guarantee_overrides (OWNER ให้/ไม่ให้เป็นรายวัน)
--   คอมมิชชัน          : commissions (SERVICE ต่อการมอบหมาย / GUARANTEE ต่อหมอต่อวัน), commission_adjustments,
--                        commission_payouts + commission_payout_items (รวมทิปที่ไม่ใช่เงินสด)
--   ปิดยอดรายวัน       : branch_daily_closings (พนักงานส่ง → OWNER อนุมัติ/ปฏิเสธ)
--   งวดบัญชี           : financial_periods (ล็อกรายเดือน, เปิดใหม่ต้องมีเหตุผล + TOTP)
--   รายงาน             : แดชบอร์ด OWNER, รายงานการเงิน, คอมมิชชัน, การมาทำงาน, รายจ่ายผิดปกติ
--
-- กติกาที่ตกลงไว้
--   ค่ามือ = therapist_fee ที่ Snapshot ไว้ (คงที่ ไม่หักส่วนลด) แบ่งตามเวลาเมื่อส่งต่อหมอ
--   ค่ามือเข้ารอบจ่ายเมื่อบริการจบ + Invoice จ่ายครบ; Void หรือคืนเงินเต็มจำนวน = กลับรายการ
--   ประกันมือรายวัน: มาไม่ครบกะ (ตามเวลาลงเวลา) = ไม่ได้ประกันวันนั้น เว้นแต่ OWNER ให้พร้อมเหตุผล
--     ไม่นับทิป, คำนวณอัตโนมัติ (ไม่ต้องอนุมัติ), คำนวณใหม่จนกว่าจะจ่าย หลังจ่ายแล้วปรับในรอบถัดไป
--   รายรับนับตามเงินที่รับจริง (วันทำการที่รับ) รวมมัดจำที่หักและมัดจำที่ถูกริบ − เงินคืน ไม่รวมทิป
--   กำไรเบื้องต้น = รายรับ − รายจ่าย − ค่ามือ (รวมเงินเติมประกันมือและรายการปรับ)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ค่าตั้งค่า / ข้อมูลหลัก
-- -----------------------------------------------------------------------------
alter table public.company_settings
  add column attendance_grace_minutes integer not null default 10 check (attendance_grace_minutes between 0 and 60);
grant update (attendance_grace_minutes) on public.company_settings to authenticated;

alter table public.employees
  add column employment_type text not null default 'REGULAR' check (employment_type in ('REGULAR', 'FREELANCE'));
comment on column public.employees.employment_type is 'REGULAR = หมอประจำ (มีประกันมือได้), FREELANCE = หมอวิ่ง';
grant update (employment_type) on public.employees to authenticated;

alter table public.branches
  add column default_daily_guarantee numeric(12,2) check (default_daily_guarantee is null or default_daily_guarantee >= 0);
comment on column public.branches.default_daily_guarantee is 'ยอดประกันมือเริ่มต้นสำหรับหมอประจำใหม่ (ใช้เติมค่าในหน้าจอ)';
grant update (default_daily_guarantee) on public.branches to authenticated;

-- -----------------------------------------------------------------------------
-- ยอดประกันมือรายคน (มีประวัติ, ห้ามย้อนหลัง)
-- -----------------------------------------------------------------------------
create table public.employee_guarantee_rates (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null,
  employee_id     uuid not null,
  daily_amount    numeric(12,2) not null check (daily_amount > 0 and daily_amount <= 100000),
  effective_from  date not null,
  effective_to    date,
  status          text not null default 'ACTIVE' check (status in ('ACTIVE', 'CANCELLED')),
  reason          text not null check (char_length(trim(reason)) between 3 and 300),
  created_at      timestamptz not null default now(),
  created_by      uuid references public.profiles (id),
  updated_at      timestamptz not null default now(),
  constraint employee_guarantee_rates_employee_fk foreign key (company_id, employee_id)
    references public.employees (company_id, id) on delete restrict,
  constraint employee_guarantee_rates_period_chk check (effective_to is null or effective_to > effective_from),
  constraint employee_guarantee_rates_no_overlap exclude using gist (
    employee_id with =, daterange(effective_from, effective_to, '[)') with &&
  ) where (status = 'ACTIVE')
);

comment on table public.employee_guarantee_rates is 'ยอดประกันมือต่อวันของหมอประจำ [effective_from, effective_to) แก้ผ่าน Function';

-- -----------------------------------------------------------------------------
-- ลงเวลาเข้า/ออก (1 แถวต่อหมอต่อวันทำการ) — เข้า/ออกด้วย PIN บนเครื่องสาขา
-- -----------------------------------------------------------------------------
create table public.staff_attendances (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null,
  branch_id      uuid not null,
  employee_id    uuid not null,
  business_date  date not null,
  clock_in_at    timestamptz not null,
  clock_out_at   timestamptz,
  clock_in_by    uuid references public.profiles (id),
  clock_out_by   uuid references public.profiles (id),
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id),
  updated_at     timestamptz not null default now(),
  constraint staff_attendances_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint staff_attendances_employee_fk foreign key (company_id, employee_id)
    references public.employees (company_id, id) on delete restrict,
  constraint staff_attendances_key unique (employee_id, business_date),
  constraint staff_attendances_period_chk check (clock_out_at is null or clock_out_at > clock_in_at)
);

comment on table public.staff_attendances is 'เวลาเข้า/ออกงาน ใช้ตัดสินประกันมือ ห้าม DELETE';

-- OWNER ให้/ไม่ให้ประกันมือเป็นรายวัน (ทับผลจากการลงเวลา)
create table public.guarantee_overrides (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null,
  branch_id      uuid not null,
  employee_id    uuid not null,
  business_date  date not null,
  grant_guarantee boolean not null,
  reason         text not null check (char_length(trim(reason)) between 3 and 300),
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id),
  updated_at     timestamptz not null default now(),
  constraint guarantee_overrides_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint guarantee_overrides_employee_fk foreign key (company_id, employee_id)
    references public.employees (company_id, id) on delete restrict,
  constraint guarantee_overrides_key unique (employee_id, business_date)
);

-- -----------------------------------------------------------------------------
-- คอมมิชชัน
-- -----------------------------------------------------------------------------
create table public.commission_payouts (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references public.companies (id) on delete restrict,
  period_to    date not null,
  status       text not null default 'DRAFT' check (status in ('DRAFT', 'PAID', 'CANCELLED')),
  total        numeric(12,2) not null default 0,
  method       text check (method in ('BANK_TRANSFER', 'CASH')),
  reference    text check (reference is null or char_length(reference) <= 100),
  note         text check (note is null or char_length(note) <= 500),
  paid_at      timestamptz,
  paid_by      uuid references public.profiles (id),
  cancelled_at timestamptz,
  created_at   timestamptz not null default now(),
  created_by   uuid references public.profiles (id),
  updated_at   timestamptz not null default now(),
  constraint commission_payouts_company_id_id_key unique (company_id, id),
  constraint commission_payouts_paid_chk check ((status = 'PAID') = (paid_at is not null and method is not null)),
  constraint commission_payouts_cancel_chk check ((status = 'CANCELLED') = (cancelled_at is not null))
);

create unique index commission_payouts_one_draft on public.commission_payouts (company_id) where status = 'DRAFT';

create table public.commissions (
  id                     uuid primary key default gen_random_uuid(),
  company_id             uuid not null,
  branch_id              uuid not null,
  employee_id            uuid not null,
  business_date          date not null,
  kind                   text not null check (kind in ('SERVICE', 'GUARANTEE')),
  service_assignment_id  uuid references public.service_assignments (id) on delete restrict,
  base_amount            numeric(12,2) not null check (base_amount >= 0),
  share_ratio            numeric(7,6) check (share_ratio is null or share_ratio between 0 and 1),
  amount                 numeric(12,2) not null check (amount >= 0),
  status                 text not null default 'ACCRUED' check (status in ('ACCRUED', 'PAID', 'VOID')),
  payout_id              uuid,
  void_reason            text check (void_reason is null or char_length(void_reason) <= 300),
  created_at             timestamptz not null default now(),
  created_by             uuid references public.profiles (id),
  updated_at             timestamptz not null default now(),
  constraint commissions_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint commissions_employee_fk foreign key (company_id, employee_id)
    references public.employees (company_id, id) on delete restrict,
  constraint commissions_payout_fk foreign key (company_id, payout_id)
    references public.commission_payouts (company_id, id) on delete restrict,
  constraint commissions_kind_chk check ((kind = 'SERVICE') = (service_assignment_id is not null)),
  constraint commissions_paid_chk check (status <> 'PAID' or payout_id is not null)
);

comment on table public.commissions is
  'ค่ามือ: SERVICE ต่อการมอบหมายที่จบและจ่ายครบ / GUARANTEE เงินเติมประกันมือต่อหมอต่อวัน (สร้างโดย sync เท่านั้น)';

create unique index commissions_assignment_key on public.commissions (service_assignment_id) where kind = 'SERVICE';
create unique index commissions_guarantee_key on public.commissions (employee_id, branch_id, business_date)
  where kind = 'GUARANTEE';
create index commissions_employee_idx on public.commissions (employee_id, status);
create index commissions_date_idx on public.commissions (company_id, business_date);

create table public.commission_adjustments (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null,
  branch_id      uuid,
  employee_id    uuid not null,
  business_date  date not null,
  amount         numeric(12,2) not null check (amount <> 0),
  source         text not null check (source in ('MANUAL', 'VOID_REVERSAL', 'GUARANTEE_RECALC')),
  commission_id  uuid references public.commissions (id) on delete restrict,
  reason         text not null check (char_length(trim(reason)) between 3 and 300),
  status         text not null default 'OPEN' check (status in ('OPEN', 'PAID')),
  payout_id      uuid,
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id),
  updated_at     timestamptz not null default now(),
  constraint commission_adjustments_employee_fk foreign key (company_id, employee_id)
    references public.employees (company_id, id) on delete restrict,
  constraint commission_adjustments_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint commission_adjustments_payout_fk foreign key (company_id, payout_id)
    references public.commission_payouts (company_id, id) on delete restrict,
  constraint commission_adjustments_source_chk check (source = 'MANUAL' or commission_id is not null),
  constraint commission_adjustments_paid_chk check (status <> 'PAID' or payout_id is not null)
);

comment on table public.commission_adjustments is 'รายการปรับค่ามือ (+/−) ไม่แก้รายการเดิม เข้ารอบจ่ายถัดไป';

create unique index commission_adjustments_reversal_key on public.commission_adjustments (commission_id)
  where source = 'VOID_REVERSAL';
create index commission_adjustments_employee_idx on public.commission_adjustments (employee_id, status);

create table public.commission_payout_items (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null,
  payout_id         uuid not null,
  employee_id       uuid not null,
  service_total     numeric(12,2) not null default 0,
  guarantee_total   numeric(12,2) not null default 0,
  adjustment_total  numeric(12,2) not null default 0,
  tip_total         numeric(12,2) not null default 0,
  net_amount        numeric(12,2) not null,
  created_at        timestamptz not null default now(),
  created_by        uuid references public.profiles (id),
  updated_at        timestamptz not null default now(),
  constraint commission_payout_items_payout_fk foreign key (company_id, payout_id)
    references public.commission_payouts (company_id, id) on delete restrict,
  constraint commission_payout_items_employee_fk foreign key (company_id, employee_id)
    references public.employees (company_id, id) on delete restrict,
  constraint commission_payout_items_key unique (payout_id, employee_id),
  constraint commission_payout_items_net_chk check (net_amount = service_total + guarantee_total + adjustment_total + tip_total)
);

-- ทิปที่ไม่ใช่เงินสดจ่ายผ่านรอบจ่ายค่ามือ
alter table public.tips
  add column commission_payout_id uuid,
  add constraint tips_commission_payout_fk foreign key (company_id, commission_payout_id)
    references public.commission_payouts (company_id, id) on delete restrict;
alter table public.tips drop constraint tips_paid_out_cash_chk;
alter table public.tips
  add constraint tips_paid_out_cash_chk check (status <> 'PAID_OUT' or method = 'CASH' or commission_payout_id is not null);

-- tips_guard (แทนที่ 022): ผูก/ปลดรอบจ่ายได้ขณะยัง RECORDED
create or replace function private.tg_tips_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.company_id, new.branch_id, new.invoice_id, new.payment_id, new.employee_id, new.pos_session_id, new.method, new.amount)
     is distinct from
     (old.company_id, old.branch_id, old.invoice_id, old.payment_id, old.employee_id, old.pos_session_id, old.method, old.amount) then
    raise exception 'ห้ามแก้ทิป (ใช้ Void)' using errcode = 'check_violation';
  end if;
  if old.status <> 'RECORDED' and (new.status <> old.status or new.commission_payout_id is distinct from old.commission_payout_id) then
    raise exception 'ทิปนี้จ่ายหรือยกเลิกแล้ว' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- ปิดยอดรายวัน / งวดบัญชี
-- -----------------------------------------------------------------------------
create table public.branch_daily_closings (
  id                 uuid primary key default gen_random_uuid(),
  company_id         uuid not null,
  branch_id          uuid not null,
  business_date      date not null,
  status             text not null default 'SUBMITTED' check (status in ('SUBMITTED', 'APPROVED', 'REJECTED')),
  figures            jsonb not null,
  submit_note        text check (submit_note is null or char_length(submit_note) <= 500),
  submitted_by       uuid references public.profiles (id),
  submitted_at       timestamptz not null default now(),
  reviewed_by        uuid references public.profiles (id),
  reviewed_at        timestamptz,
  review_note        text check (review_note is null or char_length(review_note) <= 500),
  adjustment_amount  numeric(12,2) not null default 0,
  adjustment_note    text check (adjustment_note is null or char_length(adjustment_note) <= 500),
  created_at         timestamptz not null default now(),
  created_by         uuid references public.profiles (id),
  updated_at         timestamptz not null default now(),
  constraint branch_daily_closings_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint branch_daily_closings_key unique (branch_id, business_date),
  constraint branch_daily_closings_reject_chk check (status <> 'REJECTED' or review_note is not null),
  constraint branch_daily_closings_adjust_chk check (adjustment_amount = 0 or adjustment_note is not null)
);

comment on table public.branch_daily_closings is 'ปิดยอดรายวันของสาขา (แยกจากปิดกะ) ห้าม DELETE';

create table public.financial_periods (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null references public.companies (id) on delete restrict,
  period_start   date not null check (extract(day from period_start) = 1),
  status         text not null check (status in ('LOCKED', 'OPEN')),
  locked_at      timestamptz,
  locked_by      uuid references public.profiles (id),
  reopened_at    timestamptz,
  reopened_by    uuid references public.profiles (id),
  reopen_reason  text check (reopen_reason is null or char_length(reopen_reason) <= 500),
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id),
  updated_at     timestamptz not null default now(),
  constraint financial_periods_key unique (company_id, period_start),
  constraint financial_periods_reopen_chk check (status = 'LOCKED' or reopen_reason is not null)
);

comment on table public.financial_periods is 'งวดบัญชีรายเดือน (มีแถว = เคยล็อก) LOCKED = ห้ามเขียนข้อมูลการเงินที่เกิดในเดือนนั้น';

-- -----------------------------------------------------------------------------
-- stamp / audit / no delete
-- -----------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['employee_guarantee_rates', 'staff_attendances', 'guarantee_overrides', 'commission_payouts',
                           'commissions', 'commission_adjustments', 'commission_payout_items',
                           'branch_daily_closings', 'financial_periods'] loop
    execute format('create trigger %I before insert or update on public.%I for each row execute function private.tg_stamp()',
                   t || '_stamp', t);
    execute format('create trigger %I before delete on public.%I for each row execute function private.tg_no_delete()',
                   t || '_no_delete', t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function private.tg_audit()',
                   t || '_audit', t);
  end loop;
end;
$$;

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function private.company_local_date(p_company_id uuid, p_at timestamptz default now())
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select (p_at at time zone s.timezone)::date from public.company_settings s where s.company_id = p_company_id;
$$;

create or replace function private.period_locked(p_company_id uuid, p_date date)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.financial_periods
     where company_id = p_company_id and status = 'LOCKED'
       and period_start = date_trunc('month', p_date)::date);
$$;

create or replace function private.assert_period_open(p_company_id uuid, p_date date)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_date is not null and private.period_locked(p_company_id, p_date) then
    raise exception 'งวดบัญชีเดือน % ถูกล็อกแล้ว แก้ไขไม่ได้ (ต้องให้เจ้าของร้านเปิดงวด)', to_char(p_date, 'MM/YYYY')
      using errcode = 'check_violation', hint = 'PERIOD_LOCKED';
  end if;
end;
$$;

-- ป้องกันการเขียนข้อมูลการเงินที่ "เกิด" ในงวดที่ล็อก (ทุกช่องทาง ไม่ใช่แค่ Function)
create or replace function private.tg_period_lock()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_date date;
begin
  if tg_table_name = 'payments' then
    if tg_op = 'UPDATE' and new.status = old.status then
      return new;
    end if;
    if new.pos_session_id is not null then
      select business_date into v_date from public.pos_sessions where id = new.pos_session_id;
    else
      select business_date into v_date from public.invoices where id = new.invoice_id;
    end if;
  elsif tg_table_name = 'payment_refunds' then
    v_date := private.company_local_date(new.company_id, new.refunded_at);
  elsif tg_table_name = 'pos_cash_movements' then
    select business_date into v_date from public.pos_sessions where id = new.pos_session_id;
  elsif tg_table_name = 'tips' then
    if tg_op = 'UPDATE' and new.status = old.status then
      return new;
    end if;
    if tg_op = 'UPDATE' and new.status = 'PAID_OUT' then
      return new;   -- จ่ายทิปของงวดที่ล็อกได้ (เงินออกอยู่ในกะ/รอบจ่ายปัจจุบัน)
    end if;
    select business_date into v_date from public.pos_sessions where id = new.pos_session_id;
  elsif tg_table_name = 'invoices' then
    if tg_op = 'UPDATE' and new.status = old.status then
      return new;
    end if;
    v_date := new.business_date;
  elsif tg_table_name = 'expenses' then
    v_date := new.occurred_on;
  elsif tg_table_name = 'commissions' then
    if tg_op = 'UPDATE' and new.amount = old.amount and (new.status = old.status or new.status = 'PAID') then
      return new;   -- ผูก/จ่ายรอบจ่ายได้ (การจ่ายเกิดในงวดปัจจุบัน)
    end if;
    v_date := new.business_date;
  elsif tg_table_name = 'commission_adjustments' then
    if tg_op = 'UPDATE' and new.amount = old.amount then
      return new;
    end if;
    v_date := new.business_date;
  elsif tg_table_name = 'branch_daily_closings' then
    v_date := new.business_date;
  end if;
  perform private.assert_period_open(new.company_id, v_date);
  return new;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array['payments', 'payment_refunds', 'pos_cash_movements', 'tips', 'invoices', 'expenses',
                           'commissions', 'commission_adjustments', 'branch_daily_closings'] loop
    execute format('create trigger %I before insert or update on public.%I for each row execute function private.tg_period_lock()',
                   t || '_period_lock', t);
  end loop;
end;
$$;

revoke all on function private.company_local_date(uuid, timestamptz) from public;
revoke all on function private.period_locked(uuid, date) from public;
revoke all on function private.assert_period_open(uuid, date) from public;

-- -----------------------------------------------------------------------------
-- ประกันมือ: คำนวณต่อหมอ/สาขา/วัน
--   rate: ยอดประกันที่มีผลวันนั้น, earned: ค่ามือจากงานที่จบ (ไม่นับที่ถูกกลับรายการ, ไม่นับทิป)
--   qualified: มีกะ และลงเวลาเข้า-ออกครอบทุกกะของวันนั้น (เผื่อ grace) หรือ OWNER ให้
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
  e        public.employees;
  v_tz     text;
  v_grace  integer;
  att      public.staff_attendances;
  v_first  timestamptz;
  v_last   timestamptz;
begin
  select * into e from public.employees where id = p_employee_id;
  select s.timezone, s.attendance_grace_minutes into v_tz, v_grace
    from public.company_settings s where s.company_id = e.company_id;

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

  -- กะที่ "เริ่ม" ในวันทำการนั้น
  select min(s.starts_at), max(s.ends_at), count(*) > 0 into v_first, v_last, has_shift
    from public.employee_schedules s
   where s.employee_id = e.id and s.branch_id = p_branch_id and s.status = 'SCHEDULED'
     and (select w.business_date from private.branch_window_at(p_branch_id, s.starts_at) w) = p_date;

  select * into att from public.staff_attendances where employee_id = e.id and business_date = p_date and branch_id = p_branch_id;
  attended := has_shift and att.id is not null and att.clock_out_at is not null
              and att.clock_in_at <= v_first + make_interval(mins => v_grace)
              and att.clock_out_at >= v_last - make_interval(mins => v_grace);

  select o.grant_guarantee into override_grant from public.guarantee_overrides o
   where o.employee_id = e.id and o.business_date = p_date and o.branch_id = p_branch_id;

  qualified := rate > 0 and coalesce(override_grant, attended);
  topup := case when qualified then greatest(rate - earned, 0) else 0 end;
  return next;
end;
$$;

revoke all on function private.compute_guarantee(uuid, uuid, date) from public;

-- -----------------------------------------------------------------------------
-- sync: ทำให้ตารางค่ามือตรงกับข้อมูลจริง (idempotent) — เรียกก่อนรายงาน/สร้างรอบจ่าย/ปิดยอด
-- -----------------------------------------------------------------------------
create or replace function private.sync_commissions(p_company_id uuid)
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

revoke all on function private.sync_commissions(uuid) from public;

-- -----------------------------------------------------------------------------
-- ลงเวลาเข้า/ออก
-- -----------------------------------------------------------------------------
create or replace function public.attendance_clock(p_branch_id uuid, p_action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  e       public.employees;
  v_date  date;
  a       public.staff_attendances;
begin
  select emp.* into e from public.employees emp join public.branches b on b.company_id = emp.company_id
   where emp.user_id = auth.uid() and b.id = p_branch_id;
  if e.id is null or not private.is_active_staff_of_branch(e.user_id, p_branch_id) then
    raise exception 'ลงเวลาได้เฉพาะพนักงานของสาขานี้' using errcode = 'insufficient_privilege';
  end if;
  select business_date into v_date from private.branch_window_at(p_branch_id, now());
  select * into a from public.staff_attendances where employee_id = e.id and business_date = v_date for update;

  if p_action = 'CLOCK_IN' then
    if a.id is not null then
      raise exception 'ลงเวลาเข้างานวันนี้แล้ว (%)', to_char(a.clock_in_at at time zone 'Asia/Bangkok', 'HH24:MI')
        using errcode = 'check_violation';
    end if;
    insert into public.staff_attendances (company_id, branch_id, employee_id, business_date, clock_in_at, clock_in_by)
    values (e.company_id, p_branch_id, e.id, v_date, now(), auth.uid())
    returning * into a;
  elsif p_action = 'CLOCK_OUT' then
    if a.id is null then
      raise exception 'ยังไม่ได้ลงเวลาเข้างานวันนี้' using errcode = 'check_violation';
    end if;
    if a.branch_id <> p_branch_id then
      raise exception 'ลงเวลาออกที่สาขาเดียวกับที่ลงเวลาเข้า' using errcode = 'check_violation';
    end if;
    update public.staff_attendances set clock_out_at = greatest(now(), clock_in_at + interval '1 second'), clock_out_by = auth.uid()
     where id = a.id returning * into a;
  else
    raise exception 'คำสั่งไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;

  return jsonb_build_object('nickname', e.nickname, 'business_date', a.business_date,
                            'clock_in_at', a.clock_in_at, 'clock_out_at', a.clock_out_at);
end;
$$;

-- ลงเวลาด้วย PIN บนเครื่องสาขา (Edge Function queue-pin-action หลังตรวจ PIN)
create or replace function public.device_attendance_action(p_device_token text, p_user_id uuid, p_action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  d        public.branch_devices;
  v_sub    text := current_setting('request.jwt.claim.sub', true);
  v_claims text := current_setting('request.jwt.claims', true);
  v_result jsonb;
begin
  d := private.find_active_device(p_device_token);
  if d.id is null then
    raise exception 'เครื่องนี้ยังไม่ได้ผูกกับสาขา' using errcode = 'insufficient_privilege';
  end if;
  perform set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user_id, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  v_result := public.attendance_clock(d.branch_id, p_action);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  return v_result;
end;
$$;

-- สถานะลงเวลาของพนักงานสาขาวันนี้ (แสดงบนหน้าคิว)
create or replace function public.branch_attendance_today(p_branch_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_date date;
begin
  perform private.require_branch_access(p_branch_id);
  select business_date into v_date from private.branch_window_at(p_branch_id, now());
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'employee_id', e.id, 'user_id', e.user_id, 'nickname', e.nickname, 'employment_type', e.employment_type,
      'clock_in_at', a.clock_in_at, 'clock_out_at', a.clock_out_at) order by e.nickname)
      from public.employees e
      join public.branches b on b.id = p_branch_id and b.company_id = e.company_id
      left join public.staff_attendances a on a.employee_id = e.id and a.business_date = v_date
     where e.status = 'ACTIVE' and private.is_active_staff_of_branch(e.user_id, p_branch_id)), '[]'::jsonb);
end;
$$;

-- -----------------------------------------------------------------------------
-- ตั้งค่าประกันมือ (OWNER)
-- -----------------------------------------------------------------------------
create or replace function public.set_employee_guarantee(
  p_employee_id    uuid,
  p_daily_amount   numeric,       -- 0 = เลิกประกันตั้งแต่วันที่ระบุ
  p_effective_from date,
  p_reason         text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  e public.employees;
begin
  select * into e from public.employees where id = p_employee_id;
  if e.id is null then
    raise exception 'ไม่พบพนักงาน' using errcode = 'no_data_found';
  end if;
  perform private.require_owner_step_up(e.company_id);
  if p_effective_from is null or p_effective_from < private.company_local_date(e.company_id) then
    raise exception 'วันที่เริ่มต้องไม่ย้อนหลัง' using errcode = 'invalid_parameter_value';
  end if;
  if p_daily_amount is null or p_daily_amount < 0 then
    raise exception 'ยอดประกันไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาระบุเหตุผล' using errcode = 'invalid_parameter_value';
  end if;

  perform set_config('app.audit_reason', trim(p_reason), true);
  update public.employee_guarantee_rates set status = 'CANCELLED'
   where employee_id = e.id and status = 'ACTIVE' and effective_from >= p_effective_from;
  update public.employee_guarantee_rates set effective_to = p_effective_from
   where employee_id = e.id and status = 'ACTIVE' and effective_from < p_effective_from
     and (effective_to is null or effective_to > p_effective_from);
  if p_daily_amount > 0 then
    insert into public.employee_guarantee_rates (company_id, employee_id, daily_amount, effective_from, reason)
    values (e.company_id, e.id, round(p_daily_amount, 2), p_effective_from, left(trim(p_reason), 300));
  end if;
end;
$$;

create or replace function public.set_guarantee_override(
  p_employee_id uuid,
  p_branch_id   uuid,
  p_date        date,
  p_grant       boolean,       -- NULL = ลบการตัดสิน (กลับไปใช้ผลจากการลงเวลา) — บันทึกเป็นแถวใหม่ไม่ได้ จึงใช้ grant ตามเดิม
  p_reason      text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  e public.employees;
begin
  select * into e from public.employees where id = p_employee_id;
  if e.id is null or not private.is_company_owner(e.company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if p_grant is null or p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาเลือกให้/ไม่ให้ และระบุเหตุผล' using errcode = 'invalid_parameter_value';
  end if;
  perform private.assert_period_open(e.company_id, p_date);
  insert into public.guarantee_overrides (company_id, branch_id, employee_id, business_date, grant_guarantee, reason)
  values (e.company_id, p_branch_id, e.id, p_date, p_grant, left(trim(p_reason), 300))
  on conflict (employee_id, business_date)
  do update set grant_guarantee = excluded.grant_guarantee, reason = excluded.reason, branch_id = excluded.branch_id;
end;
$$;

-- สรุปการมาทำงาน/ประกันมือรายวัน (OWNER)
create or replace function public.attendance_report(p_company_id uuid, p_branch_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 62 then
    raise exception 'ช่วงวันที่ต้องไม่เกิน 62 วัน' using errcode = 'invalid_parameter_value';
  end if;
  perform private.sync_commissions(p_company_id);

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'employee_id', e.id, 'nickname', e.nickname, 'employment_type', e.employment_type,
      'branch_id', x.branch_id, 'business_date', x.d,
      'shift_start', (select min(s.starts_at) from public.employee_schedules s
                       where s.employee_id = e.id and s.branch_id = x.branch_id and s.status = 'SCHEDULED'
                         and (select w.business_date from private.branch_window_at(x.branch_id, s.starts_at) w) = x.d),
      'shift_end', (select max(s.ends_at) from public.employee_schedules s
                     where s.employee_id = e.id and s.branch_id = x.branch_id and s.status = 'SCHEDULED'
                       and (select w.business_date from private.branch_window_at(x.branch_id, s.starts_at) w) = x.d),
      'clock_in_at', a.clock_in_at, 'clock_out_at', a.clock_out_at,
      'rate', g.rate, 'earned', g.earned, 'has_shift', g.has_shift, 'attended', g.attended,
      'override_grant', g.override_grant, 'override_reason', o.reason, 'qualified', g.qualified, 'topup', g.topup
    ) order by x.d desc, e.nickname)
    from (
      select s.employee_id, s.branch_id, w.business_date as d
        from public.employee_schedules s
        cross join lateral private.branch_window_at(s.branch_id, s.starts_at) w
       where s.company_id = p_company_id and s.status = 'SCHEDULED'
         and (p_branch_id is null or s.branch_id = p_branch_id)
         and s.starts_at >= (p_from - 1)::timestamp at time zone 'UTC' and s.starts_at < (p_to + 2)::timestamp at time zone 'UTC'
      union
      select a2.employee_id, a2.branch_id, a2.business_date from public.staff_attendances a2
       where a2.company_id = p_company_id and (p_branch_id is null or a2.branch_id = p_branch_id)
         and a2.business_date between p_from and p_to
    ) x
    join public.employees e on e.id = x.employee_id
    left join public.staff_attendances a on a.employee_id = e.id and a.business_date = x.d
    left join public.guarantee_overrides o on o.employee_id = e.id and o.business_date = x.d
    cross join lateral private.compute_guarantee(e.id, x.branch_id, x.d) g
    where x.d between p_from and p_to
  ), '[]'::jsonb);
end;
$$;

-- -----------------------------------------------------------------------------
-- รอบจ่ายค่ามือ (OWNER)
-- -----------------------------------------------------------------------------
create or replace function private.refresh_payout_items(p_payout_id uuid)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  p       public.commission_payouts;
  v_total numeric;
begin
  select * into p from public.commission_payouts where id = p_payout_id for update;
  delete from public.commission_payout_items where payout_id = p.id;   -- ร่างเท่านั้น (ข้าม no_delete ด้านล่าง)
  insert into public.commission_payout_items (company_id, payout_id, employee_id, service_total, guarantee_total,
                                              adjustment_total, tip_total, net_amount)
  select p.company_id, p.id, x.employee_id, sum(x.s), sum(x.g), sum(x.a), sum(x.t), sum(x.s + x.g + x.a + x.t)
    from (
      select employee_id, case when kind = 'SERVICE' then amount else 0 end as s,
             case when kind = 'GUARANTEE' then amount else 0 end as g, 0::numeric as a, 0::numeric as t
        from public.commissions where payout_id = p.id and status <> 'VOID'
      union all
      select employee_id, 0, 0, amount, 0 from public.commission_adjustments where payout_id = p.id
      union all
      select employee_id, 0, 0, 0, amount from public.tips where commission_payout_id = p.id and status = 'RECORDED'
    ) x
   group by x.employee_id;
  select coalesce(sum(net_amount), 0) into v_total from public.commission_payout_items where payout_id = p.id;
  update public.commission_payouts set total = v_total where id = p.id;
  return v_total;
end;
$$;

-- รายการรอบจ่ายในร่างลบ/สร้างใหม่ได้ (ภายใน Function นี้เท่านั้น)
create or replace function private.tg_payout_items_no_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_setting('app.payout_refresh', true) is distinct from old.payout_id::text then
    raise exception 'ห้ามลบรายการรอบจ่าย' using errcode = 'insufficient_privilege';
  end if;
  return old;
end;
$$;

drop trigger commission_payout_items_no_delete on public.commission_payout_items;
create trigger commission_payout_items_no_delete before delete on public.commission_payout_items
  for each row execute function private.tg_payout_items_no_delete();

create or replace function private.refresh_payout(p_payout_id uuid)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  v numeric;
begin
  perform set_config('app.payout_refresh', p_payout_id::text, true);
  v := private.refresh_payout_items(p_payout_id);
  perform set_config('app.payout_refresh', '', true);
  return v;
end;
$$;

create or replace function private.payout_view(p_payout_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'payout_id', p.id, 'period_to', p.period_to, 'status', p.status, 'total', p.total, 'method', p.method,
    'reference', p.reference, 'note', p.note, 'paid_at', p.paid_at, 'created_at', p.created_at,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employee_id', i.employee_id, 'nickname', e.nickname, 'employee_code', e.employee_code,
        'service_total', i.service_total, 'guarantee_total', i.guarantee_total,
        'adjustment_total', i.adjustment_total, 'tip_total', i.tip_total, 'net_amount', i.net_amount)
        order by e.nickname)
        from public.commission_payout_items i join public.employees e on e.id = i.employee_id
       where i.payout_id = p.id), '[]'::jsonb))
  from public.commission_payouts p where p.id = p_payout_id;
$$;

create or replace function public.create_commission_payout(p_company_id uuid, p_period_to date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id  uuid;
  neg   record;
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if p_period_to is null or p_period_to >= private.company_local_date(p_company_id) then
    raise exception 'สร้างรอบจ่ายได้ถึงเมื่อวานเป็นอย่างมาก' using errcode = 'invalid_parameter_value';
  end if;
  if exists (select 1 from public.commission_payouts where company_id = p_company_id and status = 'DRAFT') then
    raise exception 'มีรอบจ่ายที่ยังเป็นร่างอยู่ กรุณายืนยันหรือยกเลิกก่อน' using errcode = 'check_violation';
  end if;
  perform private.sync_commissions(p_company_id);

  insert into public.commission_payouts (company_id, period_to) values (p_company_id, p_period_to) returning id into v_id;
  update public.commissions set payout_id = v_id
   where company_id = p_company_id and status = 'ACCRUED' and payout_id is null and business_date <= p_period_to;
  update public.commission_adjustments set payout_id = v_id
   where company_id = p_company_id and status = 'OPEN' and payout_id is null and business_date <= p_period_to;
  update public.tips t set commission_payout_id = v_id
    from public.pos_sessions s
   where s.id = t.pos_session_id and t.company_id = p_company_id and t.status = 'RECORDED'
     and t.method <> 'CASH' and t.commission_payout_id is null and s.business_date <= p_period_to;

  -- ยอดสุทธิติดลบ (หักมากกว่าได้) ยกไปรอบถัดไป
  for neg in
    select x.employee_id from (
      select employee_id, amount from public.commissions where payout_id = v_id
      union all select employee_id, amount from public.commission_adjustments where payout_id = v_id
      union all select employee_id, amount from public.tips where commission_payout_id = v_id
    ) x group by x.employee_id having sum(x.amount) < 0
  loop
    update public.commissions set payout_id = null where payout_id = v_id and employee_id = neg.employee_id;
    update public.commission_adjustments set payout_id = null where payout_id = v_id and employee_id = neg.employee_id;
    update public.tips set commission_payout_id = null where commission_payout_id = v_id and employee_id = neg.employee_id;
  end loop;

  perform private.refresh_payout(v_id);
  return private.payout_view(v_id);
end;
$$;

create or replace function public.confirm_commission_payout(p_payout_id uuid, p_method text, p_reference text, p_note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.commission_payouts;
begin
  select * into p from public.commission_payouts where id = p_payout_id for update;
  if p.id is null then
    raise exception 'ไม่พบรอบจ่าย' using errcode = 'no_data_found';
  end if;
  perform private.require_owner_step_up(p.company_id);
  if p.status <> 'DRAFT' then
    raise exception 'รอบจ่ายนี้ยืนยันหรือยกเลิกแล้ว' using errcode = 'check_violation';
  end if;
  if p_method not in ('BANK_TRANSFER', 'CASH') then
    raise exception 'กรุณาเลือกวิธีจ่าย' using errcode = 'invalid_parameter_value';
  end if;
  if p_method = 'BANK_TRANSFER' and (p_reference is null or char_length(trim(p_reference)) < 3) then
    raise exception 'กรุณาระบุเลขอ้างอิงการโอน' using errcode = 'invalid_parameter_value';
  end if;

  -- ข้อมูลอาจเปลี่ยนตั้งแต่สร้างร่าง (เช่น Void) — sync แล้วคำนวณใหม่ก่อนจ่าย
  perform private.sync_commissions(p.company_id);
  perform private.refresh_payout(p.id);

  update public.commissions set status = 'PAID' where payout_id = p.id and status = 'ACCRUED';
  update public.commission_adjustments set status = 'PAID' where payout_id = p.id and status = 'OPEN';
  update public.tips set status = 'PAID_OUT', paid_out_at = now(), paid_out_by = auth.uid()
   where commission_payout_id = p.id and status = 'RECORDED';
  update public.commission_payouts
     set status = 'PAID', method = p_method, reference = nullif(left(trim(coalesce(p_reference, '')), 100), ''),
         note = nullif(left(trim(coalesce(p_note, '')), 500), ''), paid_at = now(), paid_by = auth.uid()
   where id = p.id;
  return private.payout_view(p.id);
end;
$$;

create or replace function public.cancel_commission_payout(p_payout_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.commission_payouts;
begin
  select * into p from public.commission_payouts where id = p_payout_id for update;
  if p.id is null or not private.is_company_owner(p.company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if p.status <> 'DRAFT' then
    raise exception 'ยกเลิกได้เฉพาะรอบจ่ายที่ยังเป็นร่าง' using errcode = 'check_violation';
  end if;
  update public.commissions set payout_id = null where payout_id = p.id;
  update public.commission_adjustments set payout_id = null where payout_id = p.id;
  update public.tips set commission_payout_id = null where commission_payout_id = p.id;
  update public.commission_payouts set status = 'CANCELLED', cancelled_at = now() where id = p.id;
end;
$$;

create or replace function public.add_commission_adjustment(
  p_employee_id uuid,
  p_branch_id   uuid,
  p_amount      numeric,
  p_reason      text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  e    public.employees;
  v_id uuid;
begin
  select * into e from public.employees where id = p_employee_id;
  if e.id is null or not private.is_company_owner(e.company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if p_amount is null or p_amount = 0 or abs(p_amount) > 1000000 then
    raise exception 'จำนวนเงินไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาระบุเหตุผล' using errcode = 'invalid_parameter_value';
  end if;
  insert into public.commission_adjustments (company_id, branch_id, employee_id, business_date, amount, source, reason)
  values (e.company_id, p_branch_id, e.id, private.company_local_date(e.company_id), round(p_amount, 2), 'MANUAL',
          left(trim(p_reason), 300))
  returning id into v_id;
  return v_id;
end;
$$;

-- สรุปค่ามือรายหมอ (OWNER): ค้างจ่าย/จ่ายแล้ว ในช่วงวันที่
create or replace function public.commission_summary(p_company_id uuid, p_branch_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql
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

  return jsonb_build_object(
    'employees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employee_id', e.id, 'nickname', e.nickname, 'employee_code', e.employee_code, 'employment_type', e.employment_type,
        'service', x.service, 'guarantee', x.guarantee, 'adjustments', x.adjustments, 'unpaid', x.unpaid, 'paid', x.paid,
        'unpaid_tips', (select coalesce(sum(t.amount), 0) from public.tips t
                         where t.employee_id = e.id and t.method <> 'CASH' and t.status = 'RECORDED'))
        order by e.nickname)
        from (
          select z.employee_id, sum(z.service) as service, sum(z.guarantee) as guarantee, sum(z.adjustments) as adjustments,
                 sum(z.unpaid) as unpaid, sum(z.paid) as paid
            from (
              select employee_id,
                     case when kind = 'SERVICE' then amount else 0 end as service,
                     case when kind = 'GUARANTEE' then amount else 0 end as guarantee,
                     0::numeric as adjustments,
                     case when status = 'ACCRUED' then amount else 0 end as unpaid,
                     case when status = 'PAID' then amount else 0 end as paid
                from public.commissions
               where company_id = p_company_id and status <> 'VOID' and business_date between p_from and p_to
                 and (p_branch_id is null or branch_id = p_branch_id)
              union all
              select employee_id, 0, 0, amount,
                     case when status = 'OPEN' then amount else 0 end,
                     case when status = 'PAID' then amount else 0 end
                from public.commission_adjustments
               where company_id = p_company_id and business_date between p_from and p_to
                 and (p_branch_id is null or branch_id = p_branch_id or branch_id is null)
            ) z
           group by z.employee_id
        ) x
        join public.employees e on e.id = x.employee_id), '[]'::jsonb),
    'adjustments', coalesce((
      select jsonb_agg(jsonb_build_object('adjustment_id', a.id, 'nickname', e.nickname, 'business_date', a.business_date,
                                          'amount', a.amount, 'source', a.source, 'reason', a.reason, 'status', a.status)
                       order by a.created_at desc)
        from public.commission_adjustments a join public.employees e on e.id = a.employee_id
       where a.company_id = p_company_id and a.business_date between p_from and p_to), '[]'::jsonb),
    'payouts', coalesce((
      select jsonb_agg(private.payout_view(p.id) order by p.created_at desc)
        from public.commission_payouts p
       where p.company_id = p_company_id and p.status <> 'CANCELLED'
         and (p.status = 'DRAFT' or p.paid_at >= p_from::timestamp)), '[]'::jsonb)
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- ตัวเลขการเงินต่อสาขาต่อวันทำการ (ใช้ร่วมกัน: ปิดยอดรายวัน / รายงาน / แดชบอร์ด)
-- -----------------------------------------------------------------------------
create or replace function private.daily_finance(p_company_id uuid, p_from date, p_to date)
returns table (
  business_date date, branch_id uuid,
  cash_sales numeric, transfer_sales numeric, qr_sales numeric, deposit_applied numeric,
  refunds numeric, forfeited_deposits numeric, expenses numeric, commission_cost numeric,
  net_revenue numeric, gross_profit numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  with days as (
    select d::date as business_date, b.id as branch_id
      from generate_series(p_from, p_to, interval '1 day') d
      cross join public.branches b where b.company_id = p_company_id
  ),
  pay as (
    select coalesce(s.business_date, iv.business_date) as d, p.branch_id,
           sum(p.amount) filter (where p.method = 'CASH') as cash,
           sum(p.amount) filter (where p.method = 'BANK_TRANSFER') as transfer,
           sum(p.amount) filter (where p.method = 'QR') as qr,
           sum(p.amount) filter (where p.method = 'DEPOSIT') as deposit
      from public.payments p
      join public.invoices iv on iv.id = p.invoice_id
      left join public.pos_sessions s on s.id = p.pos_session_id
     where p.company_id = p_company_id and p.status = 'SUCCESS'
       and coalesce(s.business_date, iv.business_date) between p_from and p_to
     group by 1, 2
  ),
  rf as (
    select coalesce(s.business_date, private.company_local_date(p_company_id, r.refunded_at)) as d, r.branch_id,
           sum(r.amount) as amount
      from public.payment_refunds r left join public.pos_sessions s on s.id = r.pos_session_id
     where r.company_id = p_company_id
     group by 1, 2
  ),
  ff as (
    select private.company_local_date(p_company_id, b.starts_at) as d, dep.branch_id, sum(dep.amount) as amount
      from public.booking_deposits dep join public.bookings b on b.id = dep.booking_id
     where dep.company_id = p_company_id and dep.status = 'VERIFIED' and dep.refund_status = 'FORFEITED'
     group by 1, 2
  ),
  ex as (
    select occurred_on as d, branch_id, sum(amount) as amount from public.expenses
     where company_id = p_company_id and status = 'RECORDED' and branch_id is not null
     group by 1, 2
  ),
  cm as (
    select d, branch_id, sum(amount) as amount from (
      select business_date as d, branch_id, amount from public.commissions
       where company_id = p_company_id and status <> 'VOID'
      union all
      select business_date, branch_id, amount from public.commission_adjustments
       where company_id = p_company_id and branch_id is not null
    ) z group by 1, 2
  )
  select x.business_date, x.branch_id,
         coalesce(pay.cash, 0), coalesce(pay.transfer, 0), coalesce(pay.qr, 0), coalesce(pay.deposit, 0),
         coalesce(rf.amount, 0), coalesce(ff.amount, 0), coalesce(ex.amount, 0), coalesce(cm.amount, 0),
         coalesce(pay.cash, 0) + coalesce(pay.transfer, 0) + coalesce(pay.qr, 0) + coalesce(pay.deposit, 0)
           - coalesce(rf.amount, 0) + coalesce(ff.amount, 0),
         coalesce(pay.cash, 0) + coalesce(pay.transfer, 0) + coalesce(pay.qr, 0) + coalesce(pay.deposit, 0)
           - coalesce(rf.amount, 0) + coalesce(ff.amount, 0) - coalesce(ex.amount, 0) - coalesce(cm.amount, 0)
    from days x
    left join pay on pay.d = x.business_date and pay.branch_id = x.branch_id
    left join rf on rf.d = x.business_date and rf.branch_id = x.branch_id
    left join ff on ff.d = x.business_date and ff.branch_id = x.branch_id
    left join ex on ex.d = x.business_date and ex.branch_id = x.branch_id
    left join cm on cm.d = x.business_date and cm.branch_id = x.branch_id;
$$;

revoke all on function private.daily_finance(uuid, date, date) from public;

-- รายการที่ต้องปิดยอดของวัน (ตัวเลขทั้งหมดของสาขา)
create or replace function private.daily_closing_figures(p_branch_id uuid, p_date date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid;
  f         record;
begin
  select company_id into v_company from public.branches where id = p_branch_id;
  perform private.sync_commissions(v_company);
  select * into f from private.daily_finance(v_company, p_date, p_date) x where x.branch_id = p_branch_id;
  return jsonb_build_object(
    'cash_sales', f.cash_sales, 'transfer_sales', f.transfer_sales, 'qr_sales', f.qr_sales,
    'deposit_applied', f.deposit_applied, 'refunds', f.refunds, 'forfeited_deposits', f.forfeited_deposits,
    'expenses', f.expenses, 'net_revenue', f.net_revenue,
    'sessions', (select count(*) from public.pos_sessions where branch_id = p_branch_id and business_date = p_date),
    'open_sessions', (select count(*) from public.pos_sessions where branch_id = p_branch_id and business_date = p_date and status = 'OPEN'),
    'cash_difference', (select coalesce(sum(cash_difference), 0) from public.pos_sessions
                         where branch_id = p_branch_id and business_date = p_date and status = 'CLOSED'),
    'rejected_sessions', (select count(*) from public.pos_sessions
                           where branch_id = p_branch_id and business_date = p_date and review_status = 'REJECTED'),
    'tips', (select coalesce(sum(t.amount), 0) from public.tips t join public.pos_sessions s on s.id = t.pos_session_id
              where t.branch_id = p_branch_id and s.business_date = p_date and t.status <> 'VOID'),
    'outstanding', (select coalesce(sum(total - paid_amount), 0) from public.invoices
                     where branch_id = p_branch_id and business_date = p_date and status in ('ISSUED', 'PARTIALLY_PAID')),
    'service_commission', (select coalesce(sum(private.assignment_fee(a.id)), 0)
                             from public.service_assignments a join public.queue_items q on q.id = a.queue_item_id
                            where a.branch_id = p_branch_id and q.queue_date = p_date
                              and a.status = 'COMPLETED' and q.status = 'COMPLETED'),
    'guarantee_topups', coalesce((
      select jsonb_agg(jsonb_build_object('employee_id', e.id, 'nickname', e.nickname, 'rate', g.rate, 'earned', g.earned,
                                          'qualified', g.qualified, 'topup', g.topup) order by e.nickname)
        from public.employees e
        cross join lateral private.compute_guarantee(e.id, p_branch_id, p_date) g
       where e.company_id = v_company and e.employment_type = 'REGULAR' and g.has_shift and g.rate > 0), '[]'::jsonb)
  );
end;
$$;

revoke all on function private.daily_closing_figures(uuid, date) from public;

-- -----------------------------------------------------------------------------
-- ปิดยอดรายวัน
-- -----------------------------------------------------------------------------
create or replace function public.daily_closing_preview(p_branch_id uuid, p_date date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_branch_access(p_branch_id);
  return private.daily_closing_figures(p_branch_id, p_date) || jsonb_build_object(
    'closing', (select to_jsonb(c) - 'figures' from public.branch_daily_closings c
                 where c.branch_id = p_branch_id and c.business_date = p_date));
end;
$$;

create or replace function public.submit_daily_closing(p_branch_id uuid, p_date date, p_note text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid;
  c         public.branch_daily_closings;
  f         jsonb;
begin
  perform private.require_branch_access(p_branch_id);
  select company_id into v_company from public.branches where id = p_branch_id;
  if p_date is null or p_date > (select w.business_date from private.branch_window_at(p_branch_id, now()) w) then
    raise exception 'วันที่ไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  if exists (select 1 from public.pos_sessions where branch_id = p_branch_id and business_date = p_date and status = 'OPEN') then
    raise exception 'ยังมีกะที่เปิดอยู่ กรุณาปิดกะให้ครบก่อนส่งปิดยอด' using errcode = 'check_violation';
  end if;
  select * into c from public.branch_daily_closings where branch_id = p_branch_id and business_date = p_date for update;
  if c.id is not null and c.status <> 'REJECTED' then
    raise exception 'วันนี้ส่งปิดยอดแล้ว' using errcode = 'check_violation';
  end if;
  f := private.daily_closing_figures(p_branch_id, p_date);

  if c.id is null then
    insert into public.branch_daily_closings (company_id, branch_id, business_date, figures, submit_note, submitted_by)
    values (v_company, p_branch_id, p_date, f, nullif(left(trim(coalesce(p_note, '')), 500), ''), auth.uid())
    returning * into c;
  else
    update public.branch_daily_closings
       set status = 'SUBMITTED', figures = f, submit_note = nullif(left(trim(coalesce(p_note, '')), 500), ''),
           submitted_by = auth.uid(), submitted_at = now(), reviewed_by = null, reviewed_at = null
     where id = c.id;
  end if;
  return c.id;
end;
$$;

create or replace function public.review_daily_closing(
  p_closing_id         uuid,
  p_approve            boolean,
  p_note               text,
  p_adjustment_amount  numeric,
  p_adjustment_note    text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.branch_daily_closings;
begin
  select * into c from public.branch_daily_closings where id = p_closing_id for update;
  if c.id is null or not private.is_company_owner(c.company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if c.status <> 'SUBMITTED' then
    raise exception 'รายการนี้ไม่ได้รอตรวจ' using errcode = 'check_violation';
  end if;
  if not p_approve and (p_note is null or char_length(trim(p_note)) < 3) then
    raise exception 'กรุณาระบุเหตุผลที่ปฏิเสธ' using errcode = 'invalid_parameter_value';
  end if;
  if coalesce(p_adjustment_amount, 0) <> 0 and (p_adjustment_note is null or char_length(trim(p_adjustment_note)) < 3) then
    raise exception 'กรุณาระบุเหตุผลของยอดปรับปรุง' using errcode = 'invalid_parameter_value';
  end if;
  update public.branch_daily_closings
     set status = case when p_approve then 'APPROVED' else 'REJECTED' end,
         review_note = nullif(left(trim(coalesce(p_note, '')), 500), ''),
         reviewed_by = auth.uid(), reviewed_at = now(),
         adjustment_amount = case when p_approve then round(coalesce(p_adjustment_amount, 0), 2) else 0 end,
         adjustment_note = case when p_approve and coalesce(p_adjustment_amount, 0) <> 0
                                then left(trim(p_adjustment_note), 500) end
   where id = c.id;
end;
$$;

create or replace function public.daily_closings_list(p_company_id uuid, p_branch_id uuid, p_from date, p_to date)
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
      'closing_id', c.id, 'branch_id', c.branch_id, 'branch_name', b.name, 'business_date', c.business_date,
      'status', c.status, 'figures', c.figures, 'submit_note', c.submit_note, 'submitted_by_name', ps.display_name,
      'submitted_at', c.submitted_at, 'review_note', c.review_note, 'reviewed_at', c.reviewed_at,
      'adjustment_amount', c.adjustment_amount, 'adjustment_note', c.adjustment_note) order by c.business_date desc, b.sort_order)
      from public.branch_daily_closings c
      join public.branches b on b.id = c.branch_id
      left join public.profiles ps on ps.id = c.submitted_by
     where c.company_id = p_company_id and (p_branch_id is null or c.branch_id = p_branch_id)
       and c.business_date between p_from and p_to), '[]'::jsonb);
end;
$$;

-- -----------------------------------------------------------------------------
-- งวดบัญชี (OWNER)
-- -----------------------------------------------------------------------------
create or replace function public.lock_financial_period(p_company_id uuid, p_month date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_start date := date_trunc('month', p_month)::date;
  v_end   date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
  v_missing integer;
begin
  perform private.require_owner_step_up(p_company_id);
  if v_end >= private.company_local_date(p_company_id) then
    raise exception 'ล็อกได้เฉพาะเดือนที่จบแล้ว' using errcode = 'invalid_parameter_value';
  end if;
  if exists (select 1 from public.pos_sessions where company_id = p_company_id and status = 'OPEN'
              and business_date between v_start and v_end) then
    raise exception 'ยังมีกะที่เปิดอยู่ในเดือนนี้' using errcode = 'check_violation';
  end if;
  select count(*) into v_missing
    from (select distinct branch_id, business_date from public.pos_sessions
           where company_id = p_company_id and business_date between v_start and v_end) s
   where not exists (select 1 from public.branch_daily_closings c
                      where c.branch_id = s.branch_id and c.business_date = s.business_date and c.status = 'APPROVED');
  if v_missing > 0 then
    raise exception 'ยังมีวันที่ปิดยอดรายวันไม่ได้รับอนุมัติ % วัน', v_missing using errcode = 'check_violation';
  end if;

  perform private.sync_commissions(p_company_id);   -- บันทึกค่ามือ/ประกันมือของเดือนให้ครบก่อนล็อก
  insert into public.financial_periods (company_id, period_start, status, locked_at, locked_by)
  values (p_company_id, v_start, 'LOCKED', now(), auth.uid())
  on conflict (company_id, period_start)
  do update set status = 'LOCKED', locked_at = now(), locked_by = auth.uid();
end;
$$;

create or replace function public.reopen_financial_period(p_company_id uuid, p_month date, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_owner_step_up(p_company_id);
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาระบุเหตุผล' using errcode = 'invalid_parameter_value';
  end if;
  perform set_config('app.audit_reason', trim(p_reason), true);
  update public.financial_periods
     set status = 'OPEN', reopened_at = now(), reopened_by = auth.uid(), reopen_reason = left(trim(p_reason), 500)
   where company_id = p_company_id and period_start = date_trunc('month', p_month)::date and status = 'LOCKED';
  if not found then
    raise exception 'งวดนี้ไม่ได้ล็อกอยู่' using errcode = 'check_violation';
  end if;
end;
$$;

create or replace function public.financial_periods_list(p_company_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'period_start', m.ms, 'status', coalesce(p.status, 'OPEN'), 'locked_at', p.locked_at,
      'reopened_at', p.reopened_at, 'reopen_reason', p.reopen_reason,
      'pending_closings', (
        select count(*) from (select distinct branch_id, business_date from public.pos_sessions
                               where company_id = p_company_id
                                 and business_date between m.ms and (m.ms + interval '1 month - 1 day')::date) s
         where not exists (select 1 from public.branch_daily_closings c where c.branch_id = s.branch_id
                             and c.business_date = s.business_date and c.status = 'APPROVED'))
    ) order by m.ms desc)
      from (select (date_trunc('month', private.company_local_date(p_company_id)) - make_interval(months => g))::date as ms
              from generate_series(0, 12) g) m
      left join public.financial_periods p on p.company_id = p_company_id and p.period_start = m.ms
  ), '[]'::jsonb);
end;
$$;

-- -----------------------------------------------------------------------------
-- รายงาน (OWNER)
-- -----------------------------------------------------------------------------
create or replace function public.finance_report(
  p_company_id uuid,
  p_branch_id  uuid,
  p_from       date,
  p_to         date,
  p_group      text      -- DAY | MONTH | YEAR
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 1100 then
    raise exception 'ช่วงวันที่ไม่ถูกต้อง (ไม่เกิน 3 ปี)' using errcode = 'invalid_parameter_value';
  end if;
  if p_group not in ('DAY', 'MONTH', 'YEAR') then
    raise exception 'รูปแบบการสรุปไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  perform private.sync_commissions(p_company_id);

  return jsonb_build_object(
    'rows', coalesce((
      select jsonb_agg(r order by r ->> 'period', r ->> 'branch_name')
        from (
          select jsonb_build_object(
            'period', to_char(date_trunc(lower(p_group), f.business_date), case p_group when 'DAY' then 'YYYY-MM-DD'
                                                                                 when 'MONTH' then 'YYYY-MM' else 'YYYY' end),
            'branch_id', f.branch_id, 'branch_name', b.name,
            'cash_sales', sum(f.cash_sales), 'transfer_sales', sum(f.transfer_sales), 'qr_sales', sum(f.qr_sales),
            'deposit_applied', sum(f.deposit_applied), 'refunds', sum(f.refunds),
            'forfeited_deposits', sum(f.forfeited_deposits), 'net_revenue', sum(f.net_revenue),
            'expenses', sum(f.expenses), 'commission_cost', sum(f.commission_cost), 'gross_profit', sum(f.gross_profit)
          ) as r
            from private.daily_finance(p_company_id, p_from, p_to) f
            join public.branches b on b.id = f.branch_id
           where p_branch_id is null or f.branch_id = p_branch_id
           group by date_trunc(lower(p_group), f.business_date), f.branch_id, b.name
        ) z), '[]'::jsonb),
    -- รายจ่ายสำนักงานใหญ่ / ปรับค่ามือที่ไม่ระบุสาขา (รวมเฉพาะรายงานทุกสาขา)
    'hq_expenses', case when p_branch_id is null then (
       select coalesce(sum(amount), 0) from public.expenses
        where company_id = p_company_id and branch_id is null and status = 'RECORDED' and occurred_on between p_from and p_to)
       else 0 end,
    'hq_commission_adjustments', case when p_branch_id is null then (
       select coalesce(sum(amount), 0) from public.commission_adjustments
        where company_id = p_company_id and branch_id is null and business_date between p_from and p_to)
       else 0 end,
    'daily_adjustments', (
       select coalesce(sum(adjustment_amount), 0) from public.branch_daily_closings
        where company_id = p_company_id and status = 'APPROVED' and business_date between p_from and p_to
          and (p_branch_id is null or branch_id = p_branch_id)),
    'outstanding', (
       select coalesce(sum(total - paid_amount), 0) from public.invoices
        where company_id = p_company_id and status in ('ISSUED', 'PARTIALLY_PAID')
          and (p_branch_id is null or branch_id = p_branch_id))
  );
end;
$$;

create or replace function public.owner_dashboard(p_company_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date;
  v_m0    date;
  v_y0    date;
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  perform private.sync_commissions(p_company_id);
  v_today := private.company_local_date(p_company_id);
  v_m0 := date_trunc('month', v_today)::date;
  v_y0 := date_trunc('year', v_today)::date;

  return jsonb_build_object(
    'today', v_today,
    'kpis', (
      with f as (select * from private.daily_finance(p_company_id, (v_y0 - interval '1 year')::date, v_today))
      select jsonb_build_object(
        'today', (select jsonb_build_object('revenue', coalesce(sum(net_revenue), 0), 'expenses', coalesce(sum(expenses), 0),
                                            'profit', coalesce(sum(gross_profit), 0)) from f where business_date = v_today),
        'yesterday', (select jsonb_build_object('revenue', coalesce(sum(net_revenue), 0)) from f where business_date = v_today - 1),
        'month', (select jsonb_build_object('revenue', coalesce(sum(net_revenue), 0), 'expenses', coalesce(sum(expenses), 0),
                                            'commission', coalesce(sum(commission_cost), 0), 'profit', coalesce(sum(gross_profit), 0))
                    from f where business_date >= v_m0),
        'prev_month_same_period', (select jsonb_build_object('revenue', coalesce(sum(net_revenue), 0))
                    from f where business_date between (v_m0 - interval '1 month')::date
                                                   and (v_today - interval '1 month')::date),
        'year', (select jsonb_build_object('revenue', coalesce(sum(net_revenue), 0), 'profit', coalesce(sum(gross_profit), 0))
                   from f where business_date >= v_y0),
        'prev_year_same_period', (select jsonb_build_object('revenue', coalesce(sum(net_revenue), 0))
                   from f where business_date between (v_y0 - interval '1 year')::date and (v_today - interval '1 year')::date))),
    'hq_expenses_month', (select coalesce(sum(amount), 0) from public.expenses
                           where company_id = p_company_id and branch_id is null and status = 'RECORDED' and occurred_on >= v_m0),
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object('date', d, 'revenue', rev, 'profit', pro) order by d)
        from (select business_date as d, sum(net_revenue) as rev, sum(gross_profit) as pro
                from private.daily_finance(p_company_id, v_today - 29, v_today) group by business_date) x), '[]'::jsonb),
    'monthly', coalesce((
      select jsonb_agg(jsonb_build_object('month', to_char(m, 'YYYY-MM'), 'revenue', rev, 'profit', pro) order by m)
        from (select date_trunc('month', business_date) as m, sum(net_revenue) as rev, sum(gross_profit) as pro
                from private.daily_finance(p_company_id, (v_m0 - interval '11 months')::date, v_today)
               group by 1) x), '[]'::jsonb),
    'branches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'branch_id', b.id, 'branch_name', b.name, 'revenue', x.rev, 'expenses', x.exp, 'commission', x.com, 'profit', x.pro,
        'outstanding', (select coalesce(sum(total - paid_amount), 0) from public.invoices
                         where branch_id = b.id and status in ('ISSUED', 'PARTIALLY_PAID')),
        'customers', (select count(distinct o.customer_id) from public.service_orders o
                       where o.branch_id = b.id and o.business_date >= v_m0 and o.status <> 'CANCELLED'),
        'orders', (select count(*) from public.service_orders o
                    where o.branch_id = b.id and o.business_date >= v_m0 and o.status <> 'CANCELLED'),
        'walk_ins', (select count(*) from public.service_orders o
                      where o.branch_id = b.id and o.business_date >= v_m0 and o.status <> 'CANCELLED' and o.channel = 'WALK_IN'),
        'bookings', (select count(*) from public.bookings bk
                      where bk.branch_id = b.id and bk.starts_at >= (v_m0::timestamp at time zone 'Asia/Bangkok')
                        and bk.status not in ('CANCELLED', 'EXPIRED'))
      ) order by b.sort_order, b.name)
        from public.branches b
        join lateral (select sum(net_revenue) as rev, sum(expenses) as exp, sum(commission_cost) as com, sum(gross_profit) as pro
                        from private.daily_finance(p_company_id, v_m0, v_today) f where f.branch_id = b.id) x on true
       where b.company_id = p_company_id), '[]'::jsonb),
    'actions', jsonb_build_object(
      'sessions_pending', (select count(*) from public.pos_sessions where company_id = p_company_id and review_status = 'PENDING'),
      'closings_pending', (select count(*) from public.branch_daily_closings where company_id = p_company_id and status = 'SUBMITTED'),
      'expense_void_requests', (select count(*) from public.expenses
                                 where company_id = p_company_id and status = 'RECORDED' and void_requested_at is not null),
      'large_expenses_month', (select count(*) from public.expenses
                                where company_id = p_company_id and status = 'RECORDED' and is_large and occurred_on >= v_m0),
      'unpaid_commission', (select coalesce(sum(amount), 0) from public.commissions
                             where company_id = p_company_id and status = 'ACCRUED')
                           + (select coalesce(sum(amount), 0) from public.commission_adjustments
                               where company_id = p_company_id and status = 'OPEN'),
      'deposits_to_refund', (select count(*) from public.bookings
                              where company_id = p_company_id and deposit_status = 'REFUND_PENDING'))
  );
end;
$$;

-- รายจ่ายผิดปกติ: ยอดสูง / ยกเลิกบ่อย (≥3 ใน 7 วันต่อคน) / บันทึกนอกเวลาทำการ / ยอดซ้ำวันเดียวกัน
create or replace function public.abnormal_expenses(p_company_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then
    raise exception 'ช่วงวันที่ไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'expense_id', e.id, 'branch_name', coalesce(b.name, 'สำนักงานใหญ่'), 'occurred_on', e.occurred_on,
      'amount', e.amount, 'note', e.note, 'status', e.status, 'recorded_by_name', p.display_name, 'created_at', e.created_at,
      'flags', array_remove(array[
        case when e.is_large then 'LARGE' end,
        case when (select count(*) from public.expenses v
                    where v.recorded_by = e.recorded_by and v.status = 'VOID'
                      and v.voided_at between e.created_at - interval '7 days' and e.created_at + interval '7 days') >= 3
             then 'FREQUENT_VOID' end,
        case when e.branch_id is not null and not exists (
               select 1 from private.branch_window_at(e.branch_id, e.created_at) w
                where e.created_at >= w.opens_at and e.created_at < w.closes_at) then 'OUTSIDE_HOURS' end,
        case when exists (select 1 from public.expenses d where d.id <> e.id and d.company_id = e.company_id
                            and d.branch_id is not distinct from e.branch_id and d.occurred_on = e.occurred_on
                            and d.amount = e.amount and d.status = 'RECORDED') then 'DUPLICATE' end
      ], null)) order by e.created_at desc)
      from public.expenses e
      left join public.branches b on b.id = e.branch_id
      left join public.profiles p on p.id = e.recorded_by
     where e.company_id = p_company_id and e.occurred_on between p_from and p_to
       and (e.is_large
            or (select count(*) from public.expenses v
                 where v.recorded_by = e.recorded_by and v.status = 'VOID'
                   and v.voided_at between e.created_at - interval '7 days' and e.created_at + interval '7 days') >= 3
            or (e.branch_id is not null and not exists (
                  select 1 from private.branch_window_at(e.branch_id, e.created_at) w
                   where e.created_at >= w.opens_at and e.created_at < w.closes_at))
            or exists (select 1 from public.expenses d where d.id <> e.id and d.company_id = e.company_id
                         and d.branch_id is not distinct from e.branch_id and d.occurred_on = e.occurred_on
                         and d.amount = e.amount and d.status = 'RECORDED'))
  ), '[]'::jsonb);
end;
$$;

-- งานและรายได้ของฉัน (หมอ): ค่ามือรายวัน + เงินเติมประกันมือ + การลงเวลา + รอบจ่าย
create or replace function public.my_earnings(p_from date, p_to date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  e public.employees;
begin
  select * into e from public.employees where user_id = auth.uid() order by created_at limit 1;
  if e.id is null then
    raise exception 'ไม่พบข้อมูลพนักงาน' using errcode = 'insufficient_privilege';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 62 then
    raise exception 'ช่วงวันที่ต้องไม่เกิน 62 วัน' using errcode = 'invalid_parameter_value';
  end if;
  perform private.sync_commissions(e.company_id);
  return jsonb_build_object(
    'employment_type', e.employment_type,
    'days', coalesce((
      select jsonb_agg(jsonb_build_object(
        'business_date', x.d, 'clock_in_at', a.clock_in_at, 'clock_out_at', a.clock_out_at,
        'service', x.service, 'guarantee', x.guarantee) order by x.d desc)
        from (select business_date as d,
                     sum(amount) filter (where kind = 'SERVICE') as service,
                     sum(amount) filter (where kind = 'GUARANTEE') as guarantee
                from public.commissions
               where employee_id = e.id and status <> 'VOID' and business_date between p_from and p_to
               group by business_date) x
        left join public.staff_attendances a on a.employee_id = e.id and a.business_date = x.d), '[]'::jsonb),
    'unpaid', (select coalesce(sum(amount), 0) from public.commissions where employee_id = e.id and status = 'ACCRUED')
              + (select coalesce(sum(amount), 0) from public.commission_adjustments where employee_id = e.id and status = 'OPEN'),
    'unpaid_tips', (select coalesce(sum(amount), 0) from public.tips
                     where employee_id = e.id and method <> 'CASH' and status = 'RECORDED'),
    'payouts', coalesce((
      select jsonb_agg(jsonb_build_object('paid_at', p.paid_at, 'period_to', p.period_to, 'method', p.method,
                                          'net_amount', i.net_amount) order by p.paid_at desc)
        from public.commission_payout_items i join public.commission_payouts p on p.id = i.payout_id
       where i.employee_id = e.id and p.status = 'PAID'), '[]'::jsonb)
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Grants + RLS
-- -----------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.attendance_clock(uuid, text)',
    'public.branch_attendance_today(uuid)',
    'public.set_employee_guarantee(uuid, numeric, date, text)',
    'public.set_guarantee_override(uuid, uuid, date, boolean, text)',
    'public.attendance_report(uuid, uuid, date, date)',
    'public.create_commission_payout(uuid, date)',
    'public.confirm_commission_payout(uuid, text, text, text)',
    'public.cancel_commission_payout(uuid)',
    'public.add_commission_adjustment(uuid, uuid, numeric, text)',
    'public.commission_summary(uuid, uuid, date, date)',
    'public.daily_closing_preview(uuid, date)',
    'public.submit_daily_closing(uuid, date, text)',
    'public.review_daily_closing(uuid, boolean, text, numeric, text)',
    'public.daily_closings_list(uuid, uuid, date, date)',
    'public.lock_financial_period(uuid, date)',
    'public.reopen_financial_period(uuid, date, text)',
    'public.financial_periods_list(uuid)',
    'public.finance_report(uuid, uuid, date, date, text)',
    'public.owner_dashboard(uuid)',
    'public.abnormal_expenses(uuid, date, date)',
    'public.my_earnings(date, date)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  execute 'revoke all on function public.device_attendance_action(text, uuid, text) from public, anon, authenticated';
  execute 'grant execute on function public.device_attendance_action(text, uuid, text) to service_role';
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array['employee_guarantee_rates', 'staff_attendances', 'guarantee_overrides', 'commission_payouts',
                           'commissions', 'commission_adjustments', 'commission_payout_items',
                           'branch_daily_closings', 'financial_periods'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant all on public.%I to service_role', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end;
$$;

-- ข้อมูลเงินรายคน: OWNER เห็นทั้งบริษัท, พนักงานเห็นเฉพาะของตัวเอง
create policy employee_guarantee_rates_select on public.employee_guarantee_rates
  for select to authenticated using (
    private.is_company_owner(company_id)
    or exists (select 1 from public.employees e where e.id = employee_id and e.user_id = auth.uid()));
create policy staff_attendances_select on public.staff_attendances
  for select to authenticated using (
    private.is_company_owner(company_id) or private.has_branch_access(branch_id));
create policy guarantee_overrides_select on public.guarantee_overrides
  for select to authenticated using (
    private.is_company_owner(company_id)
    or exists (select 1 from public.employees e where e.id = employee_id and e.user_id = auth.uid()));
create policy commissions_select on public.commissions
  for select to authenticated using (
    private.is_company_owner(company_id)
    or exists (select 1 from public.employees e where e.id = employee_id and e.user_id = auth.uid()));
create policy commission_adjustments_select on public.commission_adjustments
  for select to authenticated using (
    private.is_company_owner(company_id)
    or exists (select 1 from public.employees e where e.id = employee_id and e.user_id = auth.uid()));
create policy commission_payouts_select_owner on public.commission_payouts
  for select to authenticated using (private.is_company_owner(company_id));
create policy commission_payout_items_select on public.commission_payout_items
  for select to authenticated using (
    private.is_company_owner(company_id)
    or exists (select 1 from public.employees e where e.id = employee_id and e.user_id = auth.uid()));
create policy branch_daily_closings_select on public.branch_daily_closings
  for select to authenticated using (private.is_company_owner(company_id) or private.has_branch_access(branch_id));
create policy financial_periods_select on public.financial_periods
  for select to authenticated using (private.is_company_member(company_id));
