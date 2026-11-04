-- ตรวจบริการ ช่วงเวลา ราคา ค่าแรง และประวัติราคา
begin;
create extension if not exists pgtap with schema extensions;

select plan(20);

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

-- ---------------------------------------------------------------------------
-- anon: แคตตาล็อกสาธารณะ
-- ---------------------------------------------------------------------------
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select is(
  (select array_agg(duration_minutes::text || '=' || price::int::text order by duration_minutes)
     from public.v_public_branch_services
    where branch_id = '30000000-0000-4000-8000-000000000001' and service_id = '51000000-0000-4000-8000-000000000001'),
  array['60=300', '90=450', '120=550'], 'ลูกค้าเห็นนวดไทย 3 ช่วงเวลาพร้อมราคา');
select is(
  (select price from public.v_public_branch_services
    where branch_id = '30000000-0000-4000-8000-000000000002' and service_id = '51000000-0000-4000-8000-000000000001'
      and duration_minutes = 60),
  350.00::numeric, 'ราคาแยกตามสาขา');
select throws_ok(
  $$select therapist_fee from public.service_price_histories$$, '42501', null, 'ลูกค้าไม่เห็นค่าแรง');
reset role;

-- ---------------------------------------------------------------------------
-- STAFF ไม่เห็นค่าแรง และตั้งราคาไม่ได้
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1"}', true);
set local role authenticated;
select throws_ok(
  $$select therapist_fee from public.service_price_histories$$, '42501', null, 'STAFF ไม่เห็นค่าแรง');
select throws_ok(
  $$select public.owner_service_pricing('30000000-0000-4000-8000-000000000001')$$, '42501', null, 'STAFF เรียกดูราคา+ค่าแรงไม่ได้');
select throws_ok(
  $$select public.save_branch_service_pricing(array['30000000-0000-4000-8000-000000000001']::uuid[],
      '51000000-0000-4000-8000-000000000001', '[{"duration_minutes":60,"price":1,"therapist_fee":0}]', null, 'x')$$,
  '42501', null, 'STAFF ตั้งราคาไม่ได้');
reset role;

-- ---------------------------------------------------------------------------
-- OWNER
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}', true);
set local role authenticated;

select is(
  (select (o ->> 'therapist_fee')::numeric
     from jsonb_array_elements(public.owner_service_pricing('30000000-0000-4000-8000-000000000001')) bs,
          jsonb_array_elements(bs -> 'options') x,
          lateral (select x -> 'current' as o) c
    where bs ->> 'service_id' = '51000000-0000-4000-8000-000000000001' and (x ->> 'duration_minutes')::int = 90),
  180.00::numeric, 'OWNER เห็นค่าแรงช่วง 90 นาที');

select ok(pg_temp.denied_for_staff($$select public.save_branch_service_pricing(array['30000000-0000-4000-8000-000000000001']::uuid[],
      '51000000-0000-4000-8000-000000000001',
      '[{"duration_minutes":60,"price":320,"therapist_fee":130},{"duration_minutes":90,"price":450,"therapist_fee":180},{"duration_minutes":120,"price":550,"therapist_fee":240}]',
      null, 'ปรับราคา')$$), 'STAFF ทำไม่ได้ (แก้ราคาเดิมต้องยืนยัน TOTP ซ้ำ)');

-- step-up
select set_config('request.jwt.claims', json_build_object(
  'sub', '10000000-0000-4000-8000-000000000001', 'role', 'authenticated', 'aal', 'aal2',
  'amr', json_build_array(json_build_object('method', 'totp', 'timestamp', extract(epoch from now())::bigint))
)::text, true);

select throws_ok(
  $$select public.save_branch_service_pricing(array['30000000-0000-4000-8000-000000000001']::uuid[],
      '51000000-0000-4000-8000-000000000001', '[{"duration_minutes":60,"price":100,"therapist_fee":150}]', null, 'ผิด')$$,
  '22023', null, 'ค่าแรงมากกว่าราคาไม่ได้');
select throws_ok(
  $$select public.save_branch_service_pricing(array['30000000-0000-4000-8000-000000000001']::uuid[],
      '51000000-0000-4000-8000-000000000001',
      '[{"duration_minutes":60,"price":300,"therapist_fee":120},{"duration_minutes":60,"price":300,"therapist_fee":120}]', null, 'ซ้ำ')$$,
  '22023', null, 'ช่วงเวลาซ้ำไม่ได้');
select throws_ok(
  $$select public.save_branch_service_pricing(array['30000000-0000-4000-8000-000000000001']::uuid[],
      '51000000-0000-4000-8000-000000000001', '[{"duration_minutes":60,"price":300,"therapist_fee":120}]',
      now() - interval '1 day', 'ย้อนหลัง')$$,
  '22023', null, 'ห้ามเปลี่ยนราคาย้อนหลัง');

-- แก้ 60 นาที, ปิด 120 นาที, เพิ่ม 180 นาที
select is(
  public.save_branch_service_pricing(array['30000000-0000-4000-8000-000000000001']::uuid[],
    '51000000-0000-4000-8000-000000000001',
    '[{"duration_minutes":60,"price":320,"therapist_fee":130},{"duration_minutes":90,"price":450,"therapist_fee":180},{"duration_minutes":180,"price":800,"therapist_fee":320}]',
    null, 'ปรับราคาประจำปี') ->> 'changed',
  '3', 'บันทึกราคาทั้งบริการในครั้งเดียว (แก้ 1 ปิด 1 เพิ่ม 1)');

-- ใช้ราคาเดียวกันทุกสาขา (สาขาอารีย์เคยมีราคา -> ต้อง step-up ซึ่งมีแล้ว)
select lives_ok(
  $$select public.save_branch_service_pricing(
      array['30000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000002']::uuid[],
      '51000000-0000-4000-8000-000000000002', '[{"duration_minutes":60,"price":320,"therapist_fee":130}]',
      null, 'ราคาเดียวกันทุกสาขา')$$,
  'บันทึกราคาให้หลายสาขาพร้อมกันได้');

-- ตั้งราคาล่วงหน้า แล้วยกเลิก
select lives_ok(
  $$select public.save_branch_service_pricing(array['30000000-0000-4000-8000-000000000001']::uuid[],
      '51000000-0000-4000-8000-000000000003', '[{"duration_minutes":60,"price":650,"therapist_fee":260},{"duration_minutes":90,"price":850,"therapist_fee":340}]',
      now() + interval '7 days', 'ปรับราคาเดือนหน้า')$$,
  'ตั้งราคาล่วงหน้าได้');
select throws_ok(
  $$select public.save_branch_service_pricing(array['30000000-0000-4000-8000-000000000001']::uuid[],
      '51000000-0000-4000-8000-000000000003', '[{"duration_minutes":60,"price":700,"therapist_fee":260},{"duration_minutes":90,"price":850,"therapist_fee":340}]',
      now() + interval '14 days', 'ซ้อน')$$,
  '23514', null, 'มีราคาล่วงหน้าค้างอยู่ ตั้งซ้อนไม่ได้');

reset role;

-- ลูกค้าเห็นผลถูกต้อง
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select is(
  (select array_agg(duration_minutes::text || '=' || price::int::text order by duration_minutes)
     from public.v_public_branch_services
    where branch_id = '30000000-0000-4000-8000-000000000001' and service_id = '51000000-0000-4000-8000-000000000001'),
  array['60=320', '90=450', '180=800'], 'ลูกค้าเห็นช่วงเวลาและราคาใหม่ ไม่เห็นช่วงที่ปิด');
select is(
  (select price from public.v_public_branch_services
    where branch_id = '30000000-0000-4000-8000-000000000001' and service_id = '51000000-0000-4000-8000-000000000003'
      and duration_minutes = 60),
  600.00::numeric, 'ลูกค้าไม่เห็นราคาที่ตั้งล่วงหน้า');
reset role;

-- ยกเลิกราคาล่วงหน้า
select set_config('request.jwt.claims', json_build_object(
  'sub', '10000000-0000-4000-8000-000000000001', 'role', 'authenticated', 'aal', 'aal2',
  'amr', json_build_array(json_build_object('method', 'totp', 'timestamp', extract(epoch from now())::bigint))
)::text, true);
set local role authenticated;
select lives_ok(
  $$select public.cancel_scheduled_price(
      (select p.id from public.service_price_histories p
         join public.branch_service_options o on o.id = p.branch_service_option_id
         join public.branch_services bs on bs.id = o.branch_service_id
        where bs.branch_id = '30000000-0000-4000-8000-000000000001'
          and bs.service_id = '51000000-0000-4000-8000-000000000003'
          and o.duration_minutes = 60 and p.effective_from > now() and p.status = 'ACTIVE'),
      'เลื่อนการปรับราคา')$$,
  'ยกเลิกราคาล่วงหน้าได้');
select throws_ok(
  $$update public.branch_service_options set duration_minutes = 75$$, '42501', null, 'แก้นาทีของช่วงเวลาตรงไม่ได้');
reset role;

select ok(
  (select count(*) = 1 and bool_and(p.effective_to is null)
     from public.service_price_histories p
     join public.branch_service_options o on o.id = p.branch_service_option_id
     join public.branch_services bs on bs.id = o.branch_service_id
    where bs.branch_id = '30000000-0000-4000-8000-000000000001'
      and bs.service_id = '51000000-0000-4000-8000-000000000003'
      and o.duration_minutes = 60 and p.status = 'ACTIVE'),
  'ยกเลิกแล้วราคาเดิมกลับมาไม่มีวันสิ้นสุด');

select * from finish();
rollback;
