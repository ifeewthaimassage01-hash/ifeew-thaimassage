-- =============================================================================
-- 034 — เอาระบบลิ้นชัก/กะออกจากการใช้งาน (ตามที่ผู้ใช้ขอ)
--   ผู้ใช้ไม่เห็น “กะ” อีกต่อไป: ไม่มีเปิด/ปิดกะ ไม่มีนับเงิน ไม่มีเงินเข้า/ออกลิ้นชัก ไม่มีตรวจกะ
--   ตาราง pos_sessions ยังอยู่เป็นกลไกภายใน (การรับเงิน/ทิป/คืนเงินสดผูกกับกะด้วย FK/constraint เดิม):
--     * กะเปิดอัตโนมัติเมื่อมีรายการเงิน (031) — 1 กะต่อสาขาต่อวันทำการ
--     * กะของวันก่อนที่ยังเปิดค้าง → ปิดอัตโนมัติเมื่อมีรายการเงินของวันใหม่
--     * ส่งปิดยอดรายวัน / ล็อกงวด → ปิดกะที่ค้างของช่วงนั้นอัตโนมัติก่อน (ไม่ต้องให้พนักงานปิดกะ)
--   ปิดอัตโนมัติ = ถือว่าเงินสดตรงกับยอดในระบบ (ผลต่าง 0) และอนุมัติให้เลย
--   การตรวจเงินสดย้ายไปอยู่ที่การปิดยอดรายวัน (เจ้าของร้านตรวจ/ปรับยอดได้เหมือนเดิม)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ปิดกะอัตโนมัติ (ไม่นับเงิน): ยอดที่นับได้ = ยอดในระบบ, อนุมัติทันที
-- -----------------------------------------------------------------------------
create or replace function private.auto_close_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  s        public.pos_sessions;
  f        jsonb;
  v_expect numeric(12,2);
  v_actual numeric(12,2);
begin
  select * into s from public.pos_sessions where id = p_session_id for update;
  if s.id is null or s.status <> 'OPEN' then
    return;
  end if;
  f := private.session_figures(s.id);
  v_expect := (f ->> 'expected_cash')::numeric;
  v_actual := least(greatest(v_expect, 0), 10000000);   -- actual_cash ต้องอยู่ในช่วง 0–10 ล้าน

  update public.pos_sessions
     set status = 'CLOSED', closed_at = now(), closed_by = auth.uid(),
         cash_sales = (f ->> 'cash_sales')::numeric, transfer_sales = (f ->> 'transfer_sales')::numeric,
         qr_sales = (f ->> 'qr_sales')::numeric, cash_tips = (f ->> 'cash_tips')::numeric,
         cash_in = (f ->> 'cash_in')::numeric, cash_out = (f ->> 'cash_out')::numeric,
         cash_refunds = (f ->> 'cash_refunds')::numeric, expected_cash = v_expect,
         actual_cash = v_actual, cash_difference = v_actual - v_expect,
         close_note = 'ปิดอัตโนมัติ (ไม่ใช้ระบบลิ้นชัก)',
         review_status = 'APPROVED', reviewed_at = now()
   where id = s.id;
end;
$$;

revoke all on function private.auto_close_session(uuid) from public;

-- ปิดกะที่เปิดค้างของสาขา ถึงวันทำการที่ระบุ (null = ทุกวัน)
create or replace function private.auto_close_sessions(p_company_id uuid, p_branch_id uuid, p_to_date date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  for v_id in
    select id from public.pos_sessions
     where company_id = p_company_id and status = 'OPEN'
       and (p_branch_id is null or branch_id = p_branch_id)
       and (p_to_date is null or business_date <= p_to_date)
     order by opened_at
  loop
    perform private.auto_close_session(v_id);
  end loop;
end;
$$;

revoke all on function private.auto_close_sessions(uuid, uuid, date) from public;

-- -----------------------------------------------------------------------------
-- (แทนที่ 031) กะของรายการเงิน: ใช้กะวันนี้ / ปิดกะวันก่อนที่ค้าง / เปิดใหม่อัตโนมัติ
-- -----------------------------------------------------------------------------
create or replace function private.require_open_session(p_branch_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id      uuid;
  v_sdate   date;
  v_company uuid;
  v_date    date;
begin
  if auth.uid() is null then
    raise exception 'ไม่มีผู้ใช้' using errcode = 'insufficient_privilege';
  end if;

  -- ล็อกสาขาก่อน กันสองเครื่องเปิด/ปิดกะพร้อมกัน (unique index pos_sessions_one_open เป็นชั้นสุดท้าย)
  select company_id into v_company from public.branches where id = p_branch_id and is_active for update;
  if v_company is null then
    raise exception 'สาขาไม่เปิดใช้งาน' using errcode = 'invalid_parameter_value';
  end if;
  select business_date into v_date from private.branch_window_at(p_branch_id, now());

  select id, business_date into v_id, v_sdate from public.pos_sessions
   where branch_id = p_branch_id and status = 'OPEN' for update;
  if v_id is not null and v_sdate >= v_date then
    return v_id;
  end if;
  if v_id is not null then
    perform private.auto_close_session(v_id);   -- กะของวันก่อนที่ค้าง
  end if;

  insert into public.pos_sessions (company_id, branch_id, business_date, opened_by, opening_cash, opening_note)
  values (v_company, p_branch_id, v_date, auth.uid(), 0, 'เปิดอัตโนมัติ')
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function private.require_open_session(uuid) from public;

-- -----------------------------------------------------------------------------
-- ส่งปิดยอดรายวัน: ปิดกะที่ค้างของวันนั้นให้ก่อน (เดิมบังคับให้พนักงานปิดกะ)
-- -----------------------------------------------------------------------------
alter function public.submit_daily_closing(uuid, date, text) rename to submit_daily_closing_core;
alter function public.submit_daily_closing_core(uuid, date, text) set schema private;
revoke all on function private.submit_daily_closing_core(uuid, date, text) from public, anon, authenticated;

create or replace function public.submit_daily_closing(p_branch_id uuid, p_date date, p_note text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid;
begin
  perform private.require_branch_access(p_branch_id);
  select company_id into v_company from public.branches where id = p_branch_id;
  if v_company is not null and p_date is not null then
    perform private.auto_close_sessions(v_company, p_branch_id, p_date);
  end if;
  return private.submit_daily_closing_core(p_branch_id, p_date, p_note);
end;
$$;

revoke all on function public.submit_daily_closing(uuid, date, text) from public, anon;
grant execute on function public.submit_daily_closing(uuid, date, text) to authenticated;

-- -----------------------------------------------------------------------------
-- ล็อกงวด: ปิดกะที่ค้างในเดือนนั้นให้ก่อน
-- -----------------------------------------------------------------------------
alter function public.lock_financial_period(uuid, date) rename to lock_financial_period_core;
alter function public.lock_financial_period_core(uuid, date) set schema private;
revoke all on function private.lock_financial_period_core(uuid, date) from public, anon, authenticated;

create or replace function public.lock_financial_period(p_company_id uuid, p_month date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_owner_step_up(p_company_id);
  if p_month is not null then
    perform private.auto_close_sessions(
      p_company_id, null, (date_trunc('month', p_month) + interval '1 month - 1 day')::date);
  end if;
  perform private.lock_financial_period_core(p_company_id, p_month);
end;
$$;

revoke all on function public.lock_financial_period(uuid, date) from public, anon;
grant execute on function public.lock_financial_period(uuid, date) to authenticated;

-- -----------------------------------------------------------------------------
-- กะเดิมที่ปิดแล้วแต่รอตรวจ → อนุมัติให้ (ไม่มีหน้าตรวจกะแล้ว)
-- -----------------------------------------------------------------------------
update public.pos_sessions
   set review_status = 'APPROVED', reviewed_at = now(),
       review_note = 'อนุมัติอัตโนมัติ (เลิกใช้ระบบลิ้นชัก)'
 where status = 'CLOSED' and review_status = 'PENDING';
