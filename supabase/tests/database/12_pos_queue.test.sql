-- ตรวจ POS & คิว: เปิดกะ, Walk-in, capacity, เลขคิว, มอบหมายหมอ, เริ่ม/จบ/ยกเลิก, เช็กอินการจอง, สิทธิ์
begin;
create extension if not exists pgtap with schema extensions;

select plan(40);

-- ---------------------------------------------------------------------------
-- เตรียมเวลาให้ test ไม่ขึ้นกับเวลาที่รัน: เปิดร้านทุกวัน ตั้งแต่ 1 ชั่วโมงก่อนตอนนี้ (เกือบ 24 ชม.)
-- และกะ: นภา มีกะครอบเวลานี้, ดาว ไม่มีกะ
-- ---------------------------------------------------------------------------
update public.branch_holidays set is_active = false;
update public.branch_opening_hours
   set is_closed = false,
       opens_at = date_trunc('minute', (now() at time zone 'Asia/Bangkok') - interval '1 hour')::time,
       closes_at = date_trunc('minute', (now() at time zone 'Asia/Bangkok') - interval '61 minutes')::time;
update public.employee_schedules set status = 'CANCELLED'
 where branch_id = '30000000-0000-4000-8000-000000000001' and status = 'SCHEDULED';
insert into public.employee_schedules (company_id, branch_id, employee_id, starts_at, ends_at)
values ('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001',
        '40000000-0000-4000-8000-000000000002', now() - interval '2 hours', now() + interval '8 hours');

create temporary table t (k text primary key, v text) on commit drop;
grant all on t to authenticated, anon, service_role;
insert into t select 'thai60', o.id::text from public.branch_service_options o
  join public.branch_services bs on bs.id = o.branch_service_id
 where bs.branch_id = '30000000-0000-4000-8000-000000000001'
   and bs.service_id = '51000000-0000-4000-8000-000000000001' and o.duration_minutes = 60;
insert into t select 'foot30', o.id::text from public.branch_service_options o
  join public.branch_services bs on bs.id = o.branch_service_id
 where bs.branch_id = '30000000-0000-4000-8000-000000000001'
   and bs.service_id = '51000000-0000-4000-8000-000000000002' and o.duration_minutes = 30;
insert into t select 'bd', business_date::text
  from private.branch_window_at('30000000-0000-4000-8000-000000000001', now());
create or replace function pg_temp.v(p_key text) returns text language sql as $$ select v from t where k = p_key $$;
create or replace function pg_temp.put(p_key text, p_val text) returns text language sql as $$
  insert into t values (p_key, p_val) on conflict (k) do update set v = excluded.v returning v
$$;
-- คิวที่ n ของ Order ที่เก็บไว้ใน key
create or replace function pg_temp.q(p_key text, p_n int) returns uuid language sql as $$
  select (pg_temp.v(p_key)::jsonb -> 'items' -> p_n ->> 'queue_id')::uuid
$$;
create or replace function pg_temp.as_user(p_sub text) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_sub, 'role', 'authenticated', 'aal', 'aal1')::text, true)::text;
  select null::void;
$$;

-- ---------------------------------------------------------------------------
-- กะ POS
-- ---------------------------------------------------------------------------
select pg_temp.as_user('10000000-0000-4000-8000-000000000002');   -- นภา (SKV)
set local role authenticated;

select ok(public.pos_open_session('30000000-0000-4000-8000-000000000001', 1000, 'เงินทอน') is not null,
  'STAFF เปิดกะของสาขาตัวเองได้');
select throws_ok(
  $$select public.pos_open_session('30000000-0000-4000-8000-000000000001', 500, null)$$,
  '23514', 'สาขานี้มีกะที่เปิดอยู่แล้ว', 'เปิดกะซ้ำในสาขาเดียวกันไม่ได้');
select is((public.pos_board('30000000-0000-4000-8000-000000000001') -> 'session' ->> 'opening_cash')::numeric, 1000::numeric,
  'กระดานแสดงกะที่เปิดอยู่');

-- ---------------------------------------------------------------------------
-- Walk-in
-- ---------------------------------------------------------------------------
select pg_temp.put('slots', public.pos_available_starts('30000000-0000-4000-8000-000000000001',
  array[pg_temp.v('thai60')::uuid, pg_temp.v('thai60')::uuid])::text);
select ok(
  (pg_temp.v('slots')::jsonb -> 0 ->> 'starts_at')::timestamptz between now() and now() + interval '5 minutes',
  'ระบบเสนอเวลาว่างเร็วที่สุด (ภายใน 5 นาทีจากตอนนี้)');
select pg_temp.put('s0', pg_temp.v('slots')::jsonb -> 0 ->> 'starts_at');

select pg_temp.put('o1', public.pos_create_walkin('30000000-0000-4000-8000-000000000001',
  '60000000-0000-4000-8000-000000000003', pg_temp.v('s0')::timestamptz,
  array[pg_temp.v('thai60')::uuid, pg_temp.v('thai60')::uuid], 'มาสองคน', 'walkin-key-0000000001')::text);
select is(
  (select array_agg((x ->> 'queue_number')::int order by (x ->> 'queue_number')::int)
     from jsonb_array_elements(pg_temp.v('o1')::jsonb -> 'items') x),
  array[1, 2], 'Walk-in 2 คน ได้คิว 1 และ 2 (เริ่มนับใหม่ต่อวันทำการ)');
select ok(
  (pg_temp.v('o1')::jsonb ->> 'channel') = 'WALK_IN' and (pg_temp.v('o1')::jsonb ->> 'status') = 'OPEN'
  and (pg_temp.v('o1')::jsonb -> 'items' -> 0 ->> 'queue_status') = 'WAITING'
  and (pg_temp.v('o1')::jsonb -> 'items' -> 0 ->> 'unit_price')::numeric = 300,
  'Order ใหม่: WALK_IN, คิวรอเรียก, ราคาปัจจุบัน');
select is(
  public.pos_create_walkin('30000000-0000-4000-8000-000000000001',
    '60000000-0000-4000-8000-000000000003', pg_temp.v('s0')::timestamptz,
    array[pg_temp.v('thai60')::uuid, pg_temp.v('thai60')::uuid], 'มาสองคน', 'walkin-key-0000000001') ->> 'order_id',
  pg_temp.v('o1')::jsonb ->> 'order_id', 'Idempotency-Key เดิมได้ Order เดิม ไม่สร้างซ้ำ');
select is(
  (select count(*)::int from public.resource_allocations a
     join public.service_order_items i on i.id = a.service_order_item_id
    where i.service_order_id = (pg_temp.v('o1')::jsonb ->> 'order_id')::uuid and a.status = 'RESERVED'),
  2, 'Walk-in จองเบาะไว้ทันที (RESERVED) คนละ 1 เบาะ');

-- ลูกค้าทั่วไป (ไม่ระบุตัว) ใช้เบาะที่เหลืออีก 2
select pg_temp.put('o2', public.pos_create_walkin('30000000-0000-4000-8000-000000000001',
  null, pg_temp.v('s0')::timestamptz,
  array[pg_temp.v('thai60')::uuid, pg_temp.v('thai60')::uuid], null, 'walkin-key-0000000002')::text);
select ok((pg_temp.v('o2')::jsonb ->> 'customer_id') is null, 'Walk-in ไม่ระบุลูกค้าได้');
select throws_ok(
  format($$select public.pos_create_walkin('30000000-0000-4000-8000-000000000001', null, %L,
    array[%L::uuid], null, 'walkin-key-0000000003')$$, pg_temp.v('s0'), pg_temp.v('thai60')),
  'P0001', null, 'เบาะเต็ม (4/4) สร้าง Walk-in เวลาเดียวกันไม่ได้');
select ok(
  (public.pos_available_starts('30000000-0000-4000-8000-000000000001', array[pg_temp.v('thai60')::uuid])
     -> 0 ->> 'starts_at')::timestamptz >= pg_temp.v('s0')::timestamptz + interval '70 minutes',
  'เวลาที่ระบบเสนอถัดไป = หลังเบาะว่าง (60 นาที + เผื่อทำความสะอาด 10 นาที)');
select throws_ok(
  format($$select public.pos_create_walkin('30000000-0000-4000-8000-000000000001', null, %L,
    array[%L::uuid], null, 'walkin-key-0000000004')$$, (now() - interval '1 hour')::text, pg_temp.v('foot30')),
  '22023', null, 'เวลาเริ่มย้อนหลังไม่ได้');
select throws_ok(
  format($$select public.pos_create_walkin('30000000-0000-4000-8000-000000000001', null, %L,
    array[%L::uuid], null, 'walkin-key-0000000005')$$, (now() + interval '2 days')::text, pg_temp.v('foot30')),
  '22023', null, 'Walk-in ข้ามวันไม่ได้ (ต้องสร้างเป็นการจอง)');

-- ---------------------------------------------------------------------------
-- มอบหมายหมอ
-- ---------------------------------------------------------------------------
select throws_ok(
  format($$select public.queue_call(%L, '40000000-0000-4000-8000-000000000004')$$, pg_temp.q('o1', 0)),
  'P0001', 'ดาว ไม่มีกะในเวลานี้ ยืนยันเพื่อมอบหมายต่อ', 'หมอที่ไม่มีกะ ต้องยืนยันก่อน');
select throws_ok(
  format($$select public.queue_call(%L, '40000000-0000-4000-8000-000000000003')$$, pg_temp.q('o1', 0)),
  '23514', null, 'มอบหมายหมอสาขาอื่นไม่ได้');
select is(
  public.queue_call(pg_temp.q('o1', 0), '40000000-0000-4000-8000-000000000002') -> 'items' -> 0 -> 'therapist' ->> 'nickname',
  'นภา', 'เรียกคิว 1 ให้นภา (มีกะ)');
select throws_ok(
  format($$select public.queue_call(%L, '40000000-0000-4000-8000-000000000002')$$, pg_temp.q('o1', 1)),
  '23514', 'นภา มีคิวที่รับไว้หรือกำลังให้บริการอยู่', 'หมอ 1 คนรับได้ทีละ 1 คิว');
select is(
  public.queue_call(pg_temp.q('o1', 1), '40000000-0000-4000-8000-000000000004', true) -> 'items' -> 1 -> 'therapist' ->> 'off_shift_confirmed',
  'true', 'ยืนยันแล้วมอบหมายหมอนอกกะได้ (บันทึกว่ายืนยันนอกกะ)');
select throws_ok(
  format($$select public.queue_start(%L)$$, pg_temp.q('o1', 0)),
  '23514', null, 'ยังไม่รับคิว เริ่มบริการไม่ได้');

-- ---------------------------------------------------------------------------
-- รับ → เริ่ม → จบ
-- ---------------------------------------------------------------------------
select is(public.queue_accept(pg_temp.q('o1', 0)) -> 'items' -> 0 ->> 'queue_status', 'ACCEPTED', 'หมอรับคิว');
select is(public.queue_start(pg_temp.q('o1', 0)) -> 'items' -> 0 ->> 'queue_status', 'IN_SERVICE', 'เริ่มบริการ');
select ok(
  (select bool_and(a.status = 'IN_USE' and a.starts_at = now() and a.ends_at = now() + interval '70 minutes')
     from public.resource_allocations a join public.queue_items q on q.service_order_item_id = a.service_order_item_id
    where q.id = pg_temp.q('o1', 0)),
  'เริ่มบริการ = เบาะเป็น IN_USE และเลื่อนช่วงเวลาไปเริ่มตามเวลาจริง');
select throws_ok(
  format($$select public.queue_cancel(%L, 'ลูกค้าเปลี่ยนใจ')$$, pg_temp.q('o1', 0)),
  '23514', null, 'คิวที่เริ่มบริการแล้วยกเลิกไม่ได้');
select is(public.queue_complete(pg_temp.q('o1', 0)) -> 'items' -> 0 ->> 'queue_status', 'COMPLETED', 'จบบริการ');
select ok(
  (select bool_and(a.status = 'RELEASED')
     from public.resource_allocations a join public.queue_items q on q.service_order_item_id = a.service_order_item_id
    where q.id = pg_temp.q('o1', 0))
  and (select status from public.service_assignments where queue_item_id = pg_temp.q('o1', 0)) = 'COMPLETED',
  'จบบริการ = คืนเบาะทันที และปิดการมอบหมาย');
select is(
  public.queue_call(pg_temp.q('o2', 0), '40000000-0000-4000-8000-000000000002') -> 'items' -> 0 -> 'therapist' ->> 'nickname',
  'นภา', 'จบคิวแล้วหมอรับคิวใหม่ได้');

-- เปลี่ยนหมอก่อนเริ่มบริการต้องมีเหตุผล
select throws_ok(
  format($$select public.queue_call(%L, '40000000-0000-4000-8000-000000000002')$$, pg_temp.q('o2', 1)),
  '23514', null, 'หมอที่มีคิวค้างรับเพิ่มไม่ได้');

-- ยกเลิกรายการที่ 2 ของ Order แรก → Order จบ (มี 1 รายการเสร็จ)
select is(public.queue_cancel(pg_temp.q('o1', 1), 'ลูกค้ากลับก่อน') ->> 'status', 'COMPLETED',
  'ยกเลิกรายการที่เหลือ = Order เสร็จสิ้น');
select ok(
  not exists (select 1 from public.service_assignments where employee_id = '40000000-0000-4000-8000-000000000004'
                 and status in ('ASSIGNED', 'ACCEPTED', 'IN_SERVICE')),
  'ยกเลิกคิว = ปล่อยหมอที่ถูกเรียกไว้');

-- เพิ่มบริการ (ต่อเวลา) ใน Order ที่จบแล้ว → กลับเป็น OPEN และได้คิวใหม่
select pg_temp.put('o1b', public.pos_add_order_items((pg_temp.v('o1')::jsonb ->> 'order_id')::uuid,
  pg_temp.v('s0')::timestamptz, array[pg_temp.v('foot30')::uuid], 'add-key-000000000001')::text);
select ok(
  (pg_temp.v('o1b')::jsonb ->> 'status') = 'OPEN'
  and (pg_temp.v('o1b')::jsonb -> 'items' -> 2 ->> 'queue_number')::int = 5,
  'เพิ่มบริการได้ Order กลับเป็น OPEN และได้เลขคิวถัดไป');

-- ---------------------------------------------------------------------------
-- เช็กอินการจอง
-- ---------------------------------------------------------------------------
select pg_temp.put('b1', public.staff_create_booking('30000000-0000-4000-8000-000000000001',
  '60000000-0000-4000-8000-000000000001',
  (select (x ->> 'starts_at')::timestamptz
     from jsonb_array_elements(public.get_available_slots('30000000-0000-4000-8000-000000000001',
            pg_temp.v('bd')::date,
            array[pg_temp.v('foot30')::uuid])) x
    where (x ->> 'starts_at')::timestamptz > now() + interval '3 hours'
    limit 1),
  array[pg_temp.v('foot30')::uuid], null, false, 'booking-key-000000001') ->> 'booking_id');
select ok(
  (select bool_and(extract(minute from (x ->> 'starts_at')::timestamptz at time zone 'Asia/Bangkok')::int % 30 = 0)
     from jsonb_array_elements(public.get_available_slots('30000000-0000-4000-8000-000000000001',
            pg_temp.v('bd')::date, array[pg_temp.v('foot30')::uuid])) x),
  'เวลาจองออนไลน์ตรงช่อง :00/:30 แม้ร้านเปิดเวลาไม่ตรงช่อง');
select pg_temp.put('c1', public.pos_check_in_booking(pg_temp.v('b1')::uuid)::text);
select ok(
  (pg_temp.v('c1')::jsonb ->> 'channel') = 'STAFF'
  and (pg_temp.v('c1')::jsonb ->> 'booking_code') like 'BKG-SKV-%'
  and (pg_temp.v('c1')::jsonb -> 'items' -> 0 ->> 'queue_number')::int = 6
  and (select status from public.bookings where id = pg_temp.v('b1')::uuid) = 'CHECKED_IN',
  'เช็กอิน = สร้าง Order/คิวจากการจอง และการจองเป็น CHECKED_IN');
select ok(
  (select bool_and(a.status = 'IN_USE' and a.service_order_item_id is not null)
     from public.resource_allocations a join public.booking_items i on i.id = a.booking_item_id
    where i.booking_id = pg_temp.v('b1')::uuid),
  'เช็กอินไม่สร้าง Allocation ใหม่ แต่เปลี่ยนของเดิมเป็น IN_USE');
select throws_ok(
  format($$select public.pos_check_in_booking(%L)$$, pg_temp.v('b1')),
  '23514', 'การจองนี้เช็กอินแล้ว', 'เช็กอินซ้ำไม่ได้');
select throws_ok(
  format($$select public.queue_cancel(%L, 'ลูกค้าไม่ทำ')$$, pg_temp.q('c1', 0)),
  '23514', null, 'ยกเลิกรายการสุดท้ายของการจองที่เช็กอินแล้วไม่ได้');
reset role;

-- ---------------------------------------------------------------------------
-- สิทธิ์
-- ---------------------------------------------------------------------------
select pg_temp.as_user('10000000-0000-4000-8000-000000000003');   -- สมใจ (ARI)
set local role authenticated;
select is((select count(*)::int from public.queue_items), 0, 'STAFF สาขาอื่นไม่เห็นคิวของ SKV');
select throws_ok(
  format($$select public.queue_accept(%L)$$, pg_temp.q('o2', 0)),
  '42501', null, 'STAFF สาขาอื่นจัดการคิวของ SKV ไม่ได้');
reset role;

select pg_temp.as_user('10000000-0000-4000-8000-000000000002');
set local role authenticated;
select throws_ok($$select therapist_fee from public.service_order_items$$, '42501', null,
  'Client อ่านค่ามือหมอไม่ได้');
select throws_ok(
  $$update public.queue_items set status = 'COMPLETED'$$, '42501', null, 'แก้คิวตรงไม่ได้ (ต้องผ่าน Function)');
reset role;

select pg_temp.as_user('10000000-0000-4000-8000-000000000010');   -- ลูกค้า
set local role authenticated;
select is((select count(*)::int from public.service_orders), 0, 'ลูกค้าอ่าน service_orders ไม่ได้');
reset role;

select * from finish();
rollback;
