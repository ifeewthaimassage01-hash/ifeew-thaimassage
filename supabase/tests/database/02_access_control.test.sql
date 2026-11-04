-- ตรวจ RLS ตาม role: anon, STAFF, OWNER (aal1 / aal2)
-- ใช้ข้อมูลจาก seed.sql
begin;
create extension if not exists pgtap with schema extensions;

select plan(20);

-- -----------------------------------------------------------------------------
-- anon
-- -----------------------------------------------------------------------------
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select is((select count(*)::int from public.branches), 2, 'anon เห็นสาขาที่เปิดอยู่ 2 สาขา');
select throws_ok($$select * from public.companies$$, '42501', null, 'anon อ่าน companies ไม่ได้');
select throws_ok($$select * from public.profiles$$, '42501', null, 'anon อ่าน profiles ไม่ได้');
select throws_ok($$select created_by from public.branches$$, '42501', null, 'anon อ่านคอลัมน์ที่ไม่ได้ grant ไม่ได้');

reset role;

-- -----------------------------------------------------------------------------
-- STAFF นภา (สาขา SKV)
-- -----------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1"}', true);
set local role authenticated;

select ok(private.has_branch_access('30000000-0000-4000-8000-000000000001'), 'STAFF เข้าถึงสาขาของตัวเอง');
select ok(not private.has_branch_access('30000000-0000-4000-8000-000000000002'), 'STAFF เข้าถึงสาขาอื่นไม่ได้');
select is((select count(*)::int from public.company_memberships), 1, 'STAFF เห็นเฉพาะ membership ของตัวเอง');
select is((select count(*)::int from public.audit_logs), 0, 'STAFF อ่าน audit_logs ไม่ได้');
select throws_ok($$select * from public.staff_pins$$, '42501', null, 'STAFF อ่าน staff_pins ไม่ได้');
select throws_ok(
  $$insert into public.audit_logs (action) values ('HACK')$$, '42501', null,
  'STAFF เขียน audit_logs ตรงไม่ได้');
select throws_ok(
  $$select public.pair_branch_device('30000000-0000-4000-8000-000000000001', 'x')$$, '42501', null,
  'STAFF ผูกเครื่องไม่ได้');

update public.branches set name = 'ถูกแก้โดย STAFF' where code = 'SKV';
reset role;
select is((select name from public.branches where code = 'SKV'), 'สาขาสุขุมวิท', 'STAFF แก้ข้อมูลสาขาไม่ได้');

-- -----------------------------------------------------------------------------
-- OWNER ที่ไม่ได้ยืนยัน MFA (aal1) — ตั้งแต่ migration 028 ไม่บังคับ MFA
-- -----------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}', true);
set local role authenticated;

select ok(private.is_company_owner('20000000-0000-4000-8000-000000000001'), 'OWNER ได้สิทธิ์เจ้าของโดยไม่ต้องผ่าน MFA');
select is((select count(*)::int from public.company_memberships), 4, 'OWNER (aal1) เห็น membership ทั้งบริษัท');
select ok(
  not (public.my_access() -> 'companies' -> 0 ->> 'owner_mfa_required')::boolean,
  'my_access ไม่บังคับ MFA สำหรับ OWNER');

-- -----------------------------------------------------------------------------
-- OWNER ผ่าน MFA (aal2)
-- -----------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}', true);

select ok(private.is_company_owner('20000000-0000-4000-8000-000000000001'), 'OWNER aal2 ได้สิทธิ์เจ้าของ');
select is((select count(*)::int from public.company_memberships), 4, 'OWNER เห็น membership ทั้งบริษัท');
select ok((select count(*) from public.audit_logs) > 0, 'OWNER อ่าน audit_logs ได้');

update public.branches set name = 'สาขาสุขุมวิท 22' where code = 'SKV';
select is((select name from public.branches where code = 'SKV'), 'สาขาสุขุมวิท 22', 'OWNER แก้ข้อมูลสาขาได้');

reset role;
select ok(
  exists (select 1 from public.audit_logs
           where table_name = 'branches' and action = 'UPDATE'
             and actor_user_id = '10000000-0000-4000-8000-000000000001'
             and old_values ->> 'name' = 'สาขาสุขุมวิท'
             and new_values ->> 'name' = 'สาขาสุขุมวิท 22'),
  'การแก้ไขสาขาถูกบันทึก audit พร้อม old/new');

select * from finish();
rollback;
