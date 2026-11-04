-- ตรวจการเงินส่วนกลาง: ประกันมือ (ลงเวลา/OWNER ให้), คอมมิชชัน (sync, Void กลับรายการ, ปรับเอง),
-- รอบจ่าย (ยอดติดลบยกไป), ปิดยอดรายวัน, ล็อก/เปิดงวด, รายงาน, แดชบอร์ด, รายจ่ายผิดปกติ, สิทธิ์
begin;
create extension if not exists pgtap with schema extensions;

select plan(41);

-- (migration 028) งานเจ้าของร้านไม่ขอยืนยันตัวตนซ้ำแล้ว — ตรวจว่า STAFF ทำไม่ได้แทน
create or replace function pg_temp.denied_for_staff(p_sql text) returns boolean language plpgsql as $f$
declare
  v_old text := current_setting('request.jwt.claims', true);
begin
  perform set_config('request.jwt.claims',
    '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1"}', true);
  begin
    execute p_sql;
  exception when insufficient_privilege then
    perform set_config('request.jwt.claims', coalesce(v_old, ''), true);
    return true;
  end;
  perform set_config('request.jwt.claims', coalesce(v_old, ''), true);
  return false;
end;
$f$;

-- เวลาเปิดร้านครอบตอนนี้ / กะวันนี้ของหมอทั้งสอง
update public.branch_holidays set is_active = false;
update public.branch_opening_hours
   set is_closed = false,
       opens_at = case when extract(hour from now() at time zone 'Asia/Bangkok') < 1 then time '00:00'
                       else date_trunc('minute', (now() at time zone 'Asia/Bangkok') - interval '1 hour')::time end,
       closes_at = case when extract(hour from now() at time zone 'Asia/Bangkok') < 1 then time '23:59'
                       else date_trunc('minute', (now() at time zone 'Asia/Bangkok') - interval '61 minutes')::time end;
update public.employee_schedules set status = 'CANCELLED'
 where branch_id = '30000000-0000-4000-8000-000000000001' and status = 'SCHEDULED';
insert into public.employee_schedules (company_id, branch_id, employee_id, starts_at, ends_at)
select '20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', e,
       greatest(now() - interval '30 minutes', ((now() at time zone 'Asia/Bangkok')::date + time '00:00') at time zone 'Asia/Bangkok'),
       now() + interval '8 hours'
  from unnest(array['40000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000004']::uuid[]) e;
insert into storage.objects (bucket_id, name) values
  ('expense-photos', '20000000-0000-4000-8000-000000000001/hq/big.jpg'),
  ('expense-photos', '20000000-0000-4000-8000-000000000001/hq/old.jpg');

create temporary table t (k text primary key, v text) on commit drop;
grant all on t to authenticated, anon, service_role;
insert into t select 'thai60', o.id::text from public.branch_service_options o
  join public.branch_services bs on bs.id = o.branch_service_id
 where bs.branch_id = '30000000-0000-4000-8000-000000000001'
   and bs.service_id = '51000000-0000-4000-8000-000000000001' and o.duration_minutes = 60;
insert into t select 'bd', business_date::text
  from private.branch_window_at('30000000-0000-4000-8000-000000000001', now());
insert into t select 'today', private.company_local_date('20000000-0000-4000-8000-000000000001')::text;
create or replace function pg_temp.v(p_key text) returns text language sql as $$ select v from t where k = p_key $$;
create or replace function pg_temp.j(p_key text) returns jsonb language sql as $$ select v::jsonb from t where k = p_key $$;
create or replace function pg_temp.put(p_key text, p_val text) returns text language sql as $$
  insert into t values (p_key, p_val) on conflict (k) do update set v = excluded.v returning v
$$;
create or replace function pg_temp.as_user(p_sub text, p_aal text default 'aal1') returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_sub, 'role', 'authenticated', 'aal', p_aal)::text, true)::text;
  select null::void;
$$;
create or replace function pg_temp.owner_step_up() returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', '10000000-0000-4000-8000-000000000001', 'role', 'authenticated', 'aal', 'aal2',
    'amr', json_build_array(json_build_object('method', 'totp', 'timestamp', extract(epoch from now())::bigint))
  )::text, true)::text;
  select null::void;
$$;
create or replace function pg_temp.yd() returns date language sql as $$ select pg_temp.v('bd')::date - 1 $$;

-- เครื่องสาขา (OWNER) สำหรับลงเวลาด้วย PIN
select pg_temp.as_user('10000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;
select pg_temp.put('device', public.pair_branch_device('30000000-0000-4000-8000-000000000001', 'iPad ลงเวลา') ->> 'device_token');
reset role;

-- ---------------------------------------------------------------------------
-- ยอดประกันมือ
-- ---------------------------------------------------------------------------
select pg_temp.as_user('10000000-0000-4000-8000-000000000002');
set local role authenticated;
select throws_ok($$select public.set_employee_guarantee('40000000-0000-4000-8000-000000000002', 500, current_date + 1, 'ทดสอบ')$$,
  '42501', null, 'STAFF ตั้งประกันมือไม่ได้');
reset role;
select pg_temp.as_user('10000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;
select ok(pg_temp.denied_for_staff(format($$select public.set_employee_guarantee('40000000-0000-4000-8000-000000000002', 500, %L, 'เริ่มประกัน')$$, pg_temp.v('bd'))), 'STAFF ทำไม่ได้ (ตั้งประกันมือต้องยืนยันตัวตนซ้ำ)');
reset role;
select pg_temp.owner_step_up();
set local role authenticated;
select throws_ok(format($$select public.set_employee_guarantee('40000000-0000-4000-8000-000000000002', 500, %L, 'ย้อนหลัง')$$, pg_temp.yd()),
  '22023', null, 'ตั้งประกันมือย้อนหลังไม่ได้');
select lives_ok(format($$select public.set_employee_guarantee('40000000-0000-4000-8000-000000000002', 500, %L, 'หมอประจำ')$$, pg_temp.v('bd')),
  'OWNER ตั้งประกันมือนภา 500 บาท/วัน');
reset role;
-- ดาวมีประกัน 400 บาท ตั้งแต่ต้นปี (ข้อมูลเดิม) และมีกะ + ลงเวลาครบเมื่อวาน
insert into public.employee_guarantee_rates (company_id, employee_id, daily_amount, effective_from, reason)
values ('20000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000004', 400, '2026-01-01', 'ข้อมูลเดิม');
-- กะเมื่อวาน: 30 นาทีหลังเวลาเปิดของวันทำการเมื่อวาน (ไม่ขึ้นกับเวลาที่รัน test)
insert into t select 'yshift', (((pg_temp.yd() + o.opens_at) at time zone 'Asia/Bangkok') + interval '30 minutes')::text
  from public.branch_opening_hours o where o.branch_id = '30000000-0000-4000-8000-000000000001' limit 1;
insert into public.employee_schedules (company_id, branch_id, employee_id, starts_at, ends_at)
values ('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000004',
        pg_temp.v('yshift')::timestamptz, pg_temp.v('yshift')::timestamptz + interval '6 hours');
insert into public.staff_attendances (company_id, branch_id, employee_id, business_date, clock_in_at, clock_out_at)
values ('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000004',
        pg_temp.yd(), pg_temp.v('yshift')::timestamptz - interval '5 minutes', pg_temp.v('yshift')::timestamptz + interval '6 hours 5 minutes');

-- ---------------------------------------------------------------------------
-- ลงเวลา
-- ---------------------------------------------------------------------------
select pg_temp.as_user('10000000-0000-4000-8000-000000000002');   -- นภา
set local role authenticated;
select ok(public.attendance_clock('30000000-0000-4000-8000-000000000001', 'CLOCK_IN') ->> 'clock_in_at' is not null, 'นภาลงเวลาเข้างาน');
select throws_ok($$select public.attendance_clock('30000000-0000-4000-8000-000000000001', 'CLOCK_IN')$$,
  '23514', null, 'ลงเวลาเข้าซ้ำในวันเดียวกันไม่ได้');
reset role;
set local role service_role;
select is((public.device_attendance_action(pg_temp.v('device'), '10000000-0000-4000-8000-000000000007', 'CLOCK_IN')) ->> 'nickname',
  'ดาว', 'ดาวลงเวลาเข้าด้วย PIN บนเครื่องสาขา');
reset role;
select is((select clock_in_by from public.staff_attendances where employee_id = '40000000-0000-4000-8000-000000000004'
            and business_date = pg_temp.v('bd')::date), '10000000-0000-4000-8000-000000000007'::uuid,
  'บันทึกว่าดาวเป็นผู้ลงเวลา');

-- ---------------------------------------------------------------------------
-- งานของนภาวันนี้: Walk-in → จบ → Invoice → จ่ายครบ
-- ---------------------------------------------------------------------------
select pg_temp.as_user('10000000-0000-4000-8000-000000000002');
set local role authenticated;
select public.pos_open_session('30000000-0000-4000-8000-000000000001', 500, null);
select pg_temp.put('o1', public.pos_create_walkin('30000000-0000-4000-8000-000000000001', null,
  (public.pos_available_starts('30000000-0000-4000-8000-000000000001', array[pg_temp.v('thai60')::uuid]) -> 0 ->> 'starts_at')::timestamptz,
  array[pg_temp.v('thai60')::uuid], null, 'p8-walkin-00000000001')::text);
select pg_temp.put('q1', pg_temp.j('o1') -> 'items' -> 0 ->> 'queue_id');
select public.queue_call(pg_temp.v('q1')::uuid, '40000000-0000-4000-8000-000000000002');
select public.queue_accept(pg_temp.v('q1')::uuid);
select public.queue_start(pg_temp.v('q1')::uuid);
select public.queue_complete(pg_temp.v('q1')::uuid);
select pg_temp.put('i1', public.pos_issue_invoice(
  (public.pos_create_invoice((pg_temp.j('o1') ->> 'order_id')::uuid) ->> 'invoice_id')::uuid)::text);
select public.pos_record_payment((pg_temp.j('i1') ->> 'invoice_id')::uuid, 'CASH', 300, null, null, 0, null, 'p8-pay-0000000000001');
select throws_ok(format($$select public.commission_summary('20000000-0000-4000-8000-000000000001', null, %L, %L)$$, pg_temp.v('bd'), pg_temp.v('bd')),
  '42501', null, 'STAFF ดูสรุปค่ามือไม่ได้');
reset role;

-- ---------------------------------------------------------------------------
-- คอมมิชชัน + รายงาน
-- ---------------------------------------------------------------------------
select pg_temp.as_user('10000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;
select pg_temp.put('cs', public.commission_summary('20000000-0000-4000-8000-000000000001', null, pg_temp.yd(), pg_temp.v('bd')::date)::text);
select ok((select (x ->> 'service')::numeric = 120 and (x ->> 'unpaid')::numeric = 120
             from jsonb_array_elements(pg_temp.j('cs') -> 'employees') x where x ->> 'nickname' = 'นภา'),
  'บริการจบ + จ่ายครบ = ค่ามือนภา 120 บาท (ค้างจ่าย)');
select ok((select (x ->> 'guarantee')::numeric = 400
             from jsonb_array_elements(pg_temp.j('cs') -> 'employees') x where x ->> 'nickname' = 'ดาว'),
  'ดาวมีกะและลงเวลาครบเมื่อวาน ไม่มีงาน = เติมประกันมือ 400 บาทอัตโนมัติ');
select pg_temp.put('fr', public.finance_report('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001',
  pg_temp.v('bd')::date, pg_temp.v('bd')::date, 'DAY')::text);
select ok((pg_temp.j('fr') -> 'rows' -> 0 ->> 'net_revenue')::numeric = 300
  and (pg_temp.j('fr') -> 'rows' -> 0 ->> 'commission_cost')::numeric = 120
  and (pg_temp.j('fr') -> 'rows' -> 0 ->> 'gross_profit')::numeric = 180,
  'รายงานวันนี้: รายรับ 300 − ค่ามือ 120 = กำไรเบื้องต้น 180');
reset role;

-- ประกันมือของนภาวันนี้ (ยังไม่ลงเวลาออก = ไม่ครบกะ)
select ok((select not g.qualified and g.rate = 500 and g.earned = 120
             from private.compute_guarantee('40000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001',
                                            pg_temp.v('bd')::date) g),
  'ยังไม่ลงเวลาออก (ไม่ครบกะ) = ไม่ได้ประกันมือ');
select pg_temp.as_user('10000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;
select public.set_guarantee_override('40000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001',
  pg_temp.v('bd')::date, true, 'ร้านให้กลับก่อนเพราะลูกค้าน้อย');
reset role;
select is((select g.topup from private.compute_guarantee('40000000-0000-4000-8000-000000000002',
            '30000000-0000-4000-8000-000000000001', pg_temp.v('bd')::date) g), 380::numeric,
  'OWNER ให้ประกันวันนี้ = เติม 500 − 120 = 380 บาท');

-- ---------------------------------------------------------------------------
-- รอบจ่าย
-- ---------------------------------------------------------------------------
update public.commissions set business_date = pg_temp.yd() where kind = 'SERVICE';   -- ย้ายงานเป็นของเมื่อวานเพื่อเข้ารอบจ่าย
select pg_temp.as_user('10000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;
select throws_ok(format($$select public.create_commission_payout('20000000-0000-4000-8000-000000000001', %L)$$, pg_temp.v('today')),
  '22023', null, 'สร้างรอบจ่ายได้ถึงเมื่อวานเท่านั้น');
select pg_temp.put('p1', public.create_commission_payout('20000000-0000-4000-8000-000000000001', pg_temp.yd())::text);
select ok((pg_temp.j('p1') ->> 'total')::numeric = 520 and jsonb_array_length(pg_temp.j('p1') -> 'items') = 2,
  'รอบจ่าย: นภา 120 + ดาว (ประกันมือ) 400 = 520');
select throws_ok(format($$select public.create_commission_payout('20000000-0000-4000-8000-000000000001', %L)$$, pg_temp.yd()),
  '23514', null, 'มีร่างรอบจ่ายค้างอยู่ สร้างซ้ำไม่ได้');
select ok(pg_temp.denied_for_staff(format($$select public.confirm_commission_payout(%L, 'BANK_TRANSFER', 'TRX123', null)$$, pg_temp.j('p1') ->> 'payout_id')), 'STAFF ทำไม่ได้ (ยืนยันจ่ายต้องยืนยันตัวตนซ้ำ)');
reset role;
select pg_temp.owner_step_up();
set local role authenticated;
select throws_ok(format($$select public.confirm_commission_payout(%L, 'BANK_TRANSFER', '', null)$$, pg_temp.j('p1') ->> 'payout_id'),
  '22023', null, 'โอนต้องมีเลขอ้างอิง');
select is(public.confirm_commission_payout((pg_temp.j('p1') ->> 'payout_id')::uuid, 'BANK_TRANSFER', 'TRX123', 'รอบแรก') ->> 'status',
  'PAID', 'ยืนยันจ่ายค่ามือ');
reset role;
select ok(not exists (select 1 from public.commissions where payout_id = (pg_temp.j('p1') ->> 'payout_id')::uuid and status <> 'PAID'),
  'รายการในรอบจ่ายเป็น PAID ทั้งหมด');

-- หลังจ่าย: OWNER ไม่ให้ประกันเมื่อวานของดาว → ปรับคืนในรอบถัดไป
select pg_temp.as_user('10000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;
select public.set_guarantee_override('40000000-0000-4000-8000-000000000004', '30000000-0000-4000-8000-000000000001',
  pg_temp.yd(), false, 'ลงเวลาแทนกัน');
select public.commission_summary('20000000-0000-4000-8000-000000000001', null, pg_temp.yd(), pg_temp.v('bd')::date);
reset role;
select is((select sum(amount) from public.commission_adjustments
            where employee_id = '40000000-0000-4000-8000-000000000004' and source = 'GUARANTEE_RECALC'), -400::numeric,
  'เปลี่ยนผลประกันมือหลังจ่ายแล้ว = รายการปรับ −400 รอบถัดไป');

-- Void Invoice หลังจ่ายค่ามือแล้ว → กลับรายการค่ามือ
select pg_temp.owner_step_up();
set local role authenticated;
select public.pos_void_invoice((pg_temp.j('i1') ->> 'invoice_id')::uuid, 'ลูกค้าขอยกเลิก', 'p8-void-000000000001');
select public.commission_summary('20000000-0000-4000-8000-000000000001', null, pg_temp.yd(), pg_temp.v('bd')::date);
select pg_temp.put('adj', public.add_commission_adjustment('40000000-0000-4000-8000-000000000002', null, 100, 'โบนัสลูกค้าชม')::text);
reset role;
select is((select amount from public.commission_adjustments
            where employee_id = '40000000-0000-4000-8000-000000000002' and source = 'VOID_REVERSAL'), -120::numeric,
  'Void Invoice หลังจ่ายค่ามือ = รายการกลับ −120');
select pg_temp.as_user('10000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;
select pg_temp.put('p2', public.create_commission_payout('20000000-0000-4000-8000-000000000001', pg_temp.v('bd')::date - 1)::text);
reset role;
select ok(jsonb_array_length(pg_temp.j('p2') -> 'items') = 0 and (pg_temp.j('p2') ->> 'total')::numeric = 0
  and (select payout_id from public.commission_adjustments where id = pg_temp.v('adj')::uuid) is null,
  'ยอดสุทธิติดลบ (นภา −120+100, ดาว −400) ยกไปรอบถัดไป');
select pg_temp.as_user('10000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;
select lives_ok(format($$select public.cancel_commission_payout(%L)$$, pg_temp.j('p2') ->> 'payout_id'), 'ยกเลิกร่างรอบจ่ายได้');
reset role;

-- ---------------------------------------------------------------------------
-- ปิดยอดรายวัน
-- ---------------------------------------------------------------------------
select pg_temp.as_user('10000000-0000-4000-8000-000000000002');
set local role authenticated;
select throws_ok(format($$select public.submit_daily_closing('30000000-0000-4000-8000-000000000001', %L, null)$$, pg_temp.v('bd')),
  '23514', null, 'ยังมีกะเปิดอยู่ ส่งปิดยอดไม่ได้');
reset role;
select pg_temp.put('exp', (private.session_figures((select id from public.pos_sessions where status = 'OPEN'
  and branch_id = '30000000-0000-4000-8000-000000000001')) ->> 'expected_cash'));
select pg_temp.as_user('10000000-0000-4000-8000-000000000002');
set local role authenticated;
select public.pos_close_session((select id from public.pos_sessions where status = 'OPEN'
  and branch_id = '30000000-0000-4000-8000-000000000001'), pg_temp.v('exp')::numeric, null);
select pg_temp.put('dc', public.submit_daily_closing('30000000-0000-4000-8000-000000000001', pg_temp.v('bd')::date, 'ปิดยอดวันนี้')::text);
select ok((select status = 'SUBMITTED' and figures ? 'guarantee_topups' from public.branch_daily_closings where id = pg_temp.v('dc')::uuid),
  'ส่งปิดยอดรายวัน (มีสรุปเงินเติมประกันมือให้ OWNER เห็น)');
select throws_ok(format($$select public.review_daily_closing(%L, true, null, 0, null)$$, pg_temp.v('dc')),
  '42501', null, 'STAFF อนุมัติปิดยอดไม่ได้');
reset role;
select pg_temp.as_user('10000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;
select throws_ok(format($$select public.review_daily_closing(%L, true, null, -50, null)$$, pg_temp.v('dc')),
  '22023', null, 'ยอดปรับปรุงต้องมีเหตุผล');
select lives_ok(format($$select public.review_daily_closing(%L, true, 'ตรวจแล้ว', -50, 'เงินขาดตัดเป็นค่าใช้จ่าย')$$, pg_temp.v('dc')),
  'OWNER อนุมัติปิดยอดพร้อมยอดปรับปรุง');
reset role;

-- ---------------------------------------------------------------------------
-- งวดบัญชี
-- ---------------------------------------------------------------------------
select pg_temp.as_user('10000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;
select ok(pg_temp.denied_for_staff(format($$select public.lock_financial_period('20000000-0000-4000-8000-000000000001', %L)$$, pg_temp.v('bd'))), 'STAFF ทำไม่ได้ (ล็อกงวดต้องยืนยันตัวตนซ้ำ)');
reset role;
select pg_temp.owner_step_up();
set local role authenticated;
select throws_ok(format($$select public.lock_financial_period('20000000-0000-4000-8000-000000000001', %L)$$, pg_temp.v('today')),
  '22023', null, 'ล็อกเดือนที่ยังไม่จบไม่ได้');
select lives_ok(format($$select public.lock_financial_period('20000000-0000-4000-8000-000000000001', %L)$$,
                       (date_trunc('month', pg_temp.v('bd')::date) - interval '1 month')::date),
  'ล็อกงวดเดือนก่อน');
select throws_ok(format($$select public.pos_record_expense('20000000-0000-4000-8000-000000000001', null, 100, 'ย้อนหลัง',
    '20000000-0000-4000-8000-000000000001/hq/old.jpg', false, %L)$$,
    (date_trunc('month', pg_temp.v('bd')::date) - interval '1 month' + interval '3 days')::date),
  '23514', null, 'บันทึกรายจ่ายในงวดที่ล็อกไม่ได้');
select throws_ok(format($$select public.reopen_financial_period('20000000-0000-4000-8000-000000000001', %L, '')$$,
                        (date_trunc('month', pg_temp.v('bd')::date) - interval '1 month')::date),
  '22023', null, 'เปิดงวดต้องมีเหตุผล');
select lives_ok(format($$select public.reopen_financial_period('20000000-0000-4000-8000-000000000001', %L, 'แก้รายจ่ายตกหล่น')$$,
                       (date_trunc('month', pg_temp.v('bd')::date) - interval '1 month')::date),
  'OWNER เปิดงวดพร้อมเหตุผล');

-- ---------------------------------------------------------------------------
-- แดชบอร์ด / รายจ่ายผิดปกติ
-- ---------------------------------------------------------------------------
select pg_temp.put('ex', public.pos_record_expense('20000000-0000-4000-8000-000000000001', null, 6000, 'ซ่อมแอร์',
  '20000000-0000-4000-8000-000000000001/hq/big.jpg', false, null)::text);
select ok((select bool_or(x -> 'flags' ? 'LARGE') from jsonb_array_elements(
             public.abnormal_expenses('20000000-0000-4000-8000-000000000001', pg_temp.v('bd')::date, pg_temp.v('bd')::date)) x),
  'รายจ่ายผิดปกติ: ยอดสูง');
select pg_temp.put('od', public.owner_dashboard('20000000-0000-4000-8000-000000000001')::text);
select ok(pg_temp.j('od') ? 'kpis' and jsonb_array_length(pg_temp.j('od') -> 'daily') = 30
  and jsonb_array_length(pg_temp.j('od') -> 'branches') = 2 and pg_temp.j('od') -> 'actions' ? 'closings_pending',
  'แดชบอร์ด OWNER: KPI, กราฟ 30 วัน, รายสาขา, รายการที่ต้องทำ');
reset role;

-- ---------------------------------------------------------------------------
-- สิทธิ์ / มุมมองของหมอ
-- ---------------------------------------------------------------------------
select pg_temp.as_user('10000000-0000-4000-8000-000000000002');   -- นภา
set local role authenticated;
select throws_ok($$select public.owner_dashboard('20000000-0000-4000-8000-000000000001')$$, '42501', null,
  'STAFF ดูยอดรวมทุกสาขาไม่ได้');
select is((select count(*)::int from public.commissions where employee_id <> '40000000-0000-4000-8000-000000000002'), 0,
  'หมอเห็นค่ามือของตัวเองเท่านั้น');
reset role;
select pg_temp.as_user('10000000-0000-4000-8000-000000000007');   -- ดาว
set local role authenticated;
select ok((select (x ->> 'guarantee')::numeric = 400 from jsonb_array_elements(
             public.my_earnings(pg_temp.yd(), pg_temp.v('bd')::date) -> 'days') x where (x ->> 'business_date')::date = pg_temp.yd()),
  'ดาวเห็นเงินประกันมือเมื่อวานในหน้ารายได้ของตัวเอง');
reset role;

select * from finish();
rollback;
