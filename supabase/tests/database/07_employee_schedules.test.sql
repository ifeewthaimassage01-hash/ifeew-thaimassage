-- ตรวจตารางกะงาน
begin;
create extension if not exists pgtap with schema extensions;

select plan(15);

-- จันทร์ของสัปดาห์หน้า (เวลาไทย)
select set_config('test.mon',
  ((date_trunc('week', now() at time zone 'Asia/Bangkok'))::date + 7)::text, true);

create temporary table t_ts (k text primary key, v timestamptz) on commit drop;
grant all on t_ts to authenticated;
insert into t_ts values
  ('mon10', (current_setting('test.mon')::date + time '10:00') at time zone 'Asia/Bangkok'),
  ('mon18', (current_setting('test.mon')::date + time '18:00') at time zone 'Asia/Bangkok'),
  ('mon19', (current_setting('test.mon')::date + time '19:00') at time zone 'Asia/Bangkok'),
  ('mon22', (current_setting('test.mon')::date + time '22:00') at time zone 'Asia/Bangkok'),
  ('tue20', (current_setting('test.mon')::date + 1 + time '20:00') at time zone 'Asia/Bangkok'),
  ('wed02', (current_setting('test.mon')::date + 2 + time '02:00') at time zone 'Asia/Bangkok'),
  ('wed03', (current_setting('test.mon')::date + 2 + time '03:00') at time zone 'Asia/Bangkok');

select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}', true);
set local role authenticated;

select lives_ok(
  $$insert into public.employee_schedules (company_id, branch_id, employee_id, starts_at, ends_at)
    select '20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001',
           '40000000-0000-4000-8000-000000000002', (select v from t_ts where k = 'mon10'), (select v from t_ts where k = 'mon19')$$,
  'OWNER เพิ่มกะได้');

select throws_ok(
  $$insert into public.employee_schedules (company_id, branch_id, employee_id, starts_at, ends_at)
    select '20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001',
           '40000000-0000-4000-8000-000000000002', (select v from t_ts where k = 'mon18'), (select v from t_ts where k = 'mon22')$$,
  '23P01', null, 'กะซ้อนเวลากันไม่ได้');

select throws_ok(
  $$insert into public.employee_schedules (company_id, branch_id, employee_id, starts_at, ends_at)
    select '20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000002',
           '40000000-0000-4000-8000-000000000002', (select v from t_ts where k = 'tue20'), (select v from t_ts where k = 'wed02')$$,
  '23514', null, 'จัดกะที่สาขาที่ไม่ได้สังกัดไม่ได้');

select throws_ok(
  $$insert into public.employee_schedules (company_id, branch_id, employee_id, starts_at, ends_at)
    select '20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001',
           '40000000-0000-4000-8000-000000000002', (select v from t_ts where k = 'mon22'), (select v from t_ts where k = 'mon22') + interval '17 hours'$$,
  '23514', null, 'กะยาวเกิน 16 ชั่วโมงไม่ได้');

select lives_ok(
  $$insert into public.employee_schedules (company_id, branch_id, employee_id, starts_at, ends_at)
    select '20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001',
           '40000000-0000-4000-8000-000000000002', (select v from t_ts where k = 'tue20'), (select v from t_ts where k = 'wed02')$$,
  'กะข้ามเที่ยงคืนได้');

select lives_ok(
  $$update public.employee_schedules set status = 'LEAVE' where starts_at = (select v from t_ts where k = 'mon10')$$,
  'เปลี่ยนกะเป็นลาได้');
select throws_ok(
  $$update public.employee_schedules set ends_at = (select v from t_ts where k = 'mon18')
     where starts_at = (select v from t_ts where k = 'mon10')$$,
  '23514', null, 'แก้เวลากะที่เป็นลาไม่ได้');
select lives_ok(
  $$update public.employee_schedules set status = 'CANCELLED' where starts_at = (select v from t_ts where k = 'mon10')$$,
  'ยกเลิกกะได้');
select throws_ok(
  $$update public.employee_schedules set status = 'SCHEDULED' where starts_at = (select v from t_ts where k = 'mon10')$$,
  '23514', null, 'กะที่ยกเลิกแล้วแก้ไม่ได้');

-- คัดลอกสัปดาห์หน้า -> สัปดาห์ถัดไป (เหลือกะ SCHEDULED 1 กะ คือกะข้ามคืน)
select is(
  public.copy_schedule_week('30000000-0000-4000-8000-000000000001',
    current_setting('test.mon')::date, current_setting('test.mon')::date + 7) ->> 'copied',
  '1', 'คัดลอกสัปดาห์ได้');
select is(
  public.copy_schedule_week('30000000-0000-4000-8000-000000000001',
    current_setting('test.mon')::date, current_setting('test.mon')::date + 7) ->> 'skipped',
  '1', 'คัดลอกซ้ำจะข้ามกะที่ซ้อน');
select throws_ok(
  $$select public.copy_schedule_week('30000000-0000-4000-8000-000000000001',
      current_setting('test.mon')::date + 1, current_setting('test.mon')::date + 8)$$,
  '22023', null, 'สัปดาห์ต้องเริ่มวันจันทร์');

-- STAFF นภา (SKV)
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1"}', true);

select ok(
  (select count(*) from public.employee_schedules where branch_id = '30000000-0000-4000-8000-000000000001') > 0
  and (select count(*) from public.employee_schedules where branch_id = '30000000-0000-4000-8000-000000000002') = 0,
  'STAFF เห็นกะของสาขาตัวเองเท่านั้น');
select throws_ok(
  $$insert into public.employee_schedules (company_id, branch_id, employee_id, starts_at, ends_at)
    select '20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001',
           '40000000-0000-4000-8000-000000000002', (select v from t_ts where k = 'wed03'), (select v from t_ts where k = 'wed03') + interval '4 hours'$$,
  '42501', null, 'STAFF จัดกะเองไม่ได้');
select throws_ok(
  $$select public.copy_schedule_week('30000000-0000-4000-8000-000000000001',
      current_setting('test.mon')::date, current_setting('test.mon')::date + 14)$$,
  '42501', null, 'STAFF คัดลอกตารางงานไม่ได้');

reset role;
select * from finish();
rollback;
