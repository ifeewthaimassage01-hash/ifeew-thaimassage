-- ตรวจเวลาทำการและวันหยุดสาขา
begin;
create extension if not exists pgtap with schema extensions;

select plan(11);

select is(
  (select count(*)::int from public.branch_opening_hours where branch_id = '30000000-0000-4000-8000-000000000001'),
  7, 'สาขามีเวลาทำการครบ 7 วัน');

-- OWNER (aal2)
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}', true);
set local role authenticated;

insert into public.branches (company_id, code, name)
values ('20000000-0000-4000-8000-000000000001', 'TST', 'สาขาทดสอบ');

select is(
  (select count(*)::int from public.branch_opening_hours
    where branch_id = (select id from public.branches where code = 'TST') and is_closed),
  7, 'สาขาใหม่ได้เวลาทำการ 7 วันแบบปิดไว้ก่อน');

select lives_ok(
  $$update public.branch_opening_hours set opens_at = '09:00', closes_at = '21:00'
     where branch_id = '30000000-0000-4000-8000-000000000001' and iso_dow = 1$$,
  'OWNER แก้เวลาทำการได้');

select throws_ok(
  $$update public.branch_opening_hours set is_closed = false, opens_at = null
     where branch_id = (select id from public.branches where code = 'TST') and iso_dow = 1$$,
  '23514', null, 'เปิดทำการต้องระบุเวลาเปิดและปิด');

select lives_ok(
  $$insert into public.branch_holidays (company_id, branch_id, holiday_date, name)
    values ('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', '2027-01-01', 'ปีใหม่')$$,
  'OWNER เพิ่มวันหยุดได้');

select throws_ok(
  $$insert into public.branch_holidays (company_id, branch_id, holiday_date, name)
    values ('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', '2027-01-01', 'ซ้ำ')$$,
  '23505', null, 'วันหยุดที่ใช้งานอยู่ซ้ำวันไม่ได้');

update public.branch_holidays set is_active = false where holiday_date = '2027-01-01';
select lives_ok(
  $$insert into public.branch_holidays (company_id, branch_id, holiday_date, name, is_closed, opens_at, closes_at)
    values ('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001',
            '2027-01-01', 'ปีใหม่ (เปิดครึ่งวัน)', false, '12:00', '18:00')$$,
  'ปิดวันหยุดเดิมแล้วเพิ่มใหม่ได้');

update public.branches set is_active = false where id = (select id from public.branches where code = 'TST');

-- STAFF แก้ไม่ได้
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1"}', true);
update public.branch_opening_hours set opens_at = '06:00'
 where branch_id = '30000000-0000-4000-8000-000000000001' and iso_dow = 1;
reset role;
select is(
  (select opens_at from public.branch_opening_hours
    where branch_id = '30000000-0000-4000-8000-000000000001' and iso_dow = 1),
  '09:00'::time, 'STAFF แก้เวลาทำการไม่ได้');

-- anon
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select is(
  (select count(*)::int from public.branch_opening_hours where branch_id = '30000000-0000-4000-8000-000000000001'),
  7, 'ลูกค้าเห็นเวลาทำการของสาขาที่เปิดอยู่');
select is(
  (select count(*)::int from public.branch_opening_hours where branch_id = (select id from public.branches where code = 'TST')),
  0, 'ลูกค้าไม่เห็นเวลาทำการของสาขาที่ปิด');
select is(
  (select count(*)::int from public.branch_holidays where holiday_date = '2027-01-01'),
  1, 'ลูกค้าเห็นเฉพาะวันหยุดที่ใช้งานอยู่');
reset role;

select * from finish();
rollback;
