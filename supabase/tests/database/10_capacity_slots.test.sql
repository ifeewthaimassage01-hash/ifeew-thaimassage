-- ตรวจ capacity ทรัพยากร, เวลาว่าง และการกันจองเกิน (SKV มีเบาะนวดไทย 4 ที่)
begin;
create extension if not exists pgtap with schema extensions;

select plan(13);

-- วันทดสอบ = อีก 2 วัน (เวลาไทย) 14:00
create temporary table t (k text primary key, v text) on commit drop;
grant all on t to authenticated, anon, service_role;
insert into t values ('d', ((now() at time zone 'Asia/Bangkok')::date + 2)::text);
insert into t select 'thai60', o.id::text from public.branch_service_options o
  join public.branch_services bs on bs.id = o.branch_service_id
 where bs.branch_id = '30000000-0000-4000-8000-000000000001'
   and bs.service_id = '51000000-0000-4000-8000-000000000001' and o.duration_minutes = 60;
insert into t select 'foot60', o.id::text from public.branch_service_options o
  join public.branch_services bs on bs.id = o.branch_service_id
 where bs.branch_id = '30000000-0000-4000-8000-000000000001'
   and bs.service_id = '51000000-0000-4000-8000-000000000002' and o.duration_minutes = 60;
create or replace function pg_temp.ts(p_time text) returns timestamptz language sql as $$
  select ((select v from t where k = 'd')::date + p_time::time) at time zone 'Asia/Bangkok'
$$;
create or replace function pg_temp.opt(p_key text) returns uuid language sql as $$
  select v::uuid from t where k = p_key
$$;
create or replace function pg_temp.slot_times(p_options uuid[]) returns text[] language sql as $$
  select coalesce(array_agg(x ->> 'time'), '{}')
    from jsonb_array_elements(public.get_available_slots('30000000-0000-4000-8000-000000000001',
                                                         (select v from t where k = 'd')::date, p_options)) x
$$;

-- anon เห็นเวลาว่าง
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select ok('14:00' = any (pg_temp.slot_times(array[pg_temp.opt('thai60')])), 'ลูกค้าเห็นเวลา 14:00 ว่าง');
select is((pg_temp.slot_times(array[pg_temp.opt('thai60')]))[1], '10:00', 'ช่องแรกตรงเวลาเปิดร้าน');
reset role;

-- STAFF นภา จองนวดไทย 14:00 ให้ลูกค้า 4 ครั้ง (ไม่เก็บมัดจำ = ยืนยันทันที)
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1"}', true);
set local role authenticated;

select lives_ok(
  $$select public.staff_create_booking('30000000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000003',
      pg_temp.ts('14:00'), array[pg_temp.opt('thai60')], null, false, gen_random_uuid()::text)
    from generate_series(1, 4)$$,
  'จองเบาะนวดไทยครบ 4 ที่ได้');
select throws_ok(
  $$select public.staff_create_booking('30000000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000003',
      pg_temp.ts('14:00'), array[pg_temp.opt('thai60')], null, false, gen_random_uuid()::text)$$,
  'P0001', null, 'ที่ที่ 5 จองไม่ได้ (เต็ม)');
select ok(
  not ('14:00' = any (pg_temp.slot_times(array[pg_temp.opt('thai60')])))
  and not ('15:00' = any (pg_temp.slot_times(array[pg_temp.opt('thai60')])))
  and ('15:30' = any (pg_temp.slot_times(array[pg_temp.opt('thai60')]))),
  'เวลาที่ทับซ้อน (รวมเวลาเผื่อ 10 นาที) ไม่แสดง เวลาถัดไปแสดง');
select lives_ok(
  $$select public.staff_create_booking('30000000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000003',
      pg_temp.ts('14:00'), array[pg_temp.opt('foot60')], null, false, gen_random_uuid()::text)$$,
  'บริการที่ใช้ทรัพยากรอื่น (เก้าอี้นวดเท้า) ยังจองได้');
select throws_ok(
  $$select public.staff_create_booking('30000000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000003',
      pg_temp.ts('14:10'), array[pg_temp.opt('foot60')], null, false, gen_random_uuid()::text)$$,
  '22023', null, 'เวลาเริ่มต้องตรงช่วง 30 นาที');
select throws_ok(
  $$select public.staff_create_booking('30000000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000003',
      pg_temp.ts('09:00'), array[pg_temp.opt('foot60')], null, false, gen_random_uuid()::text)$$,
  '22023', null, 'นอกเวลาทำการจองไม่ได้');
reset role;

-- ป้องกันชั้นสุดท้าย: insert allocation ตรงเกินจำนวนก็ไม่ได้
select throws_ok(
  $$insert into public.resource_allocations (company_id, branch_id, resource_type_id, quantity, starts_at, ends_at, status)
    values ('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001',
            '70000000-0000-4000-8000-000000000001', 1, pg_temp.ts('14:30'), pg_temp.ts('15:00'), 'RESERVED')$$,
  'P0001', null, 'trigger กันการจัดสรรเกินจำนวน');

-- OWNER ลดจำนวนเบาะต่ำกว่าที่จองไว้ไม่ได้
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}', true);
set local role authenticated;
select throws_ok(
  $$update public.branch_resources set total_quantity = 3
     where branch_id = '30000000-0000-4000-8000-000000000001' and resource_type_id = '70000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'ลดจำนวนเบาะต่ำกว่าที่จองไว้ไม่ได้');
reset role;

-- ยกเลิก 1 รายการ -> ว่าง 1 ที่ แต่ 2 คนพร้อมกันยังไม่ได้
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1"}', true);
set local role authenticated;
select lives_ok(
  $$select public.staff_cancel_booking(
      (select b.id from public.bookings b join public.booking_items i on i.booking_id = b.id
        where i.branch_service_option_id = pg_temp.opt('thai60') and b.status = 'CONFIRMED' limit 1),
      'ลูกค้าโทรยกเลิก', false)$$,
  'ยกเลิกแล้วคืนเบาะ');
select ok(
  ('14:00' = any (pg_temp.slot_times(array[pg_temp.opt('thai60')])))
  and not ('14:00' = any (pg_temp.slot_times(array[pg_temp.opt('thai60'), pg_temp.opt('thai60')]))),
  'เหลือ 1 ที่: จอง 1 คนได้ 2 คนไม่ได้');
reset role;

-- STAFF สาขาอื่นจองให้สาขานี้ไม่ได้
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated","aal":"aal1"}', true);
set local role authenticated;
select throws_ok(
  $$select public.staff_create_booking('30000000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000003',
      pg_temp.ts('16:00'), array[pg_temp.opt('foot60')], null, false, gen_random_uuid()::text)$$,
  '42501', null, 'STAFF สาขาอื่นจองให้สาขานี้ไม่ได้');
reset role;

select * from finish();
rollback;
