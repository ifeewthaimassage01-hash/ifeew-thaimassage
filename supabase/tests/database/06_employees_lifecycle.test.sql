-- ตรวจการสร้างพนักงาน, step-up TOTP, ย้ายสาขา และเปลี่ยนสถานะ
begin;
create extension if not exists pgtap with schema extensions;

select plan(24);

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

-- บัญชีทดสอบ: 04 = พนักงานใหม่ (อีเมลภายใน), 05 = ลูกค้า, 06 = พนักงานใหม่อีกคน
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select '00000000-0000-0000-0000-000000000000', v.id, 'authenticated', 'authenticated', v.email, '', now(),
       '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''
  from (values
    ('10000000-0000-4000-8000-000000000004'::uuid, '10000000-0000-4000-8000-000000000004@staff.ifeew.internal'),
    ('10000000-0000-4000-8000-000000000005'::uuid, 'customer@example.test'),
    ('10000000-0000-4000-8000-000000000006'::uuid, '10000000-0000-4000-8000-000000000006@staff.ifeew.internal')
  ) as v(id, email);

-- กะในอนาคตของนภา (สัปดาห์หน้า) สำหรับทดสอบการย้าย/ลาออก
insert into public.employee_schedules (company_id, branch_id, employee_id, starts_at, ends_at)
values ('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001',
        '40000000-0000-4000-8000-000000000002', now() + interval '8 days', now() + interval '8 days 8 hours');

set local role authenticated;

-- OWNER aal2 แต่ไม่มี amr totp
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}', true);
select ok(pg_temp.denied_for_staff($$select public.create_staff_member('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000004',
      '30000000-0000-4000-8000-000000000001', 'SKV-02', 'มะลิ', '2026-11-01', '482913')$$), 'STAFF ทำไม่ได้ (ไม่ได้ยืนยัน TOTP ซ้ำ สร้างพนักงานไม่ได้)');

-- amr เก่าเกิน 5 นาที
select set_config('request.jwt.claims', json_build_object(
  'sub', '10000000-0000-4000-8000-000000000001', 'role', 'authenticated', 'aal', 'aal2',
  'amr', json_build_array(json_build_object('method', 'totp', 'timestamp', extract(epoch from now())::bigint - 600))
)::text, true);
select ok(pg_temp.denied_for_staff($$select public.assert_can_manage_staff('20000000-0000-4000-8000-000000000001')$$), 'STAFF ทำไม่ได้ (TOTP เกิน 5 นาทีต้องยืนยันใหม่)');

-- amr ล่าสุด
select set_config('request.jwt.claims', json_build_object(
  'sub', '10000000-0000-4000-8000-000000000001', 'role', 'authenticated', 'aal', 'aal2',
  'amr', json_build_array(json_build_object('method', 'totp', 'timestamp', extract(epoch from now())::bigint))
)::text, true);

select set_config('test.emp4', public.create_staff_member(
  '20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000004',
  '30000000-0000-4000-8000-000000000001', 'SKV-02', 'มะลิ', '2026-11-01', '482913')::text, true);

select is(
  (select status from public.employees where id = current_setting('test.emp4')::uuid),
  'ACTIVE', 'สร้างพนักงานได้เมื่อยืนยัน TOTP ล่าสุด');
select is(
  (select display_name from public.profiles where id = '10000000-0000-4000-8000-000000000004'),
  'มะลิ', 'ชื่อเล่นซิงก์ไปเป็นชื่อที่แสดงของบัญชี');
select is(
  (select count(*)::int from public.employee_transfers
    where employee_id = current_setting('test.emp4')::uuid and from_branch_id is null),
  1, 'บันทึกประวัติเริ่มงาน');

select throws_ok(
  $$select public.create_staff_member('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000005',
      '30000000-0000-4000-8000-000000000001', 'SKV-03', 'ลูกค้า', '2026-11-01', '482913')$$,
  '22023', null, 'นำบัญชีลูกค้ามาเป็นพนักงานไม่ได้');
select throws_ok(
  $$select public.create_staff_member('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000006',
      '30000000-0000-4000-8000-000000000001', 'skv-02', 'ซ้ำ', '2026-11-01', '482913')$$,
  '23505', null, 'รหัสพนักงานซ้ำไม่ได้ (ไม่สนตัวพิมพ์)');

-- ย้ายสาขาทันที
select throws_ok(
  format($$select public.transfer_employee(%L, '30000000-0000-4000-8000-000000000001', now(), 'ทดสอบ')$$,
         current_setting('test.emp4')),
  '23514', null, 'ย้ายไปสาขาเดิมไม่ได้');
select lives_ok(
  format($$select public.transfer_employee(%L, '30000000-0000-4000-8000-000000000002', now(), 'ช่วยสาขาอารีย์')$$,
         current_setting('test.emp4')),
  'ย้ายสาขาทันทีได้');

-- ย้ายล่วงหน้าแล้วยกเลิก (นภา: กะสัปดาห์หน้าอยู่หลังวันมีผล -> ต้องโดนบล็อก)
select throws_ok(
  $$select public.transfer_employee('40000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000002',
      now() + interval '1 day', 'ย้ายล่วงหน้า')$$,
  '23514', null, 'ย้ายไม่ได้ถ้ามีกะที่สาขาเดิมหลังวันมีผล');
select lives_ok(
  $$select set_config('test.tr', public.transfer_employee('40000000-0000-4000-8000-000000000002',
      '30000000-0000-4000-8000-000000000002', now() + interval '30 days', 'ย้ายเดือนหน้า')::text, true)$$,
  'ย้ายล่วงหน้าหลังกะสุดท้ายได้');
select throws_ok(
  $$select public.transfer_employee('40000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001',
      now() + interval '40 days', 'ซ้อน')$$,
  '23514', null, 'มีการย้ายที่รอมีผลอยู่ ย้ายซ้อนไม่ได้');
select lives_ok(
  $$select public.cancel_employee_transfer(current_setting('test.tr')::uuid, 'เปลี่ยนแผน')$$,
  'ยกเลิกการย้ายที่ยังไม่มีผลได้');

-- เปลี่ยนสถานะ
select lives_ok(
  format($$select public.set_employee_status(%L, 'INACTIVE', 'พักงานชั่วคราว')$$, current_setting('test.emp4')),
  'ระงับพนักงานได้');
select throws_ok(
  format($$select public.set_employee_status(%L, 'INACTIVE', 'ซ้ำ')$$, current_setting('test.emp4')),
  '22023', null, 'ตั้งสถานะเดิมซ้ำไม่ได้');
select lives_ok(
  $$select public.set_employee_status('40000000-0000-4000-8000-000000000002', 'RESIGNED', 'ลาออก')$$,
  'บันทึกลาออกได้');
select throws_ok(
  $$select public.set_employee_status('40000000-0000-4000-8000-000000000002', 'ACTIVE', 'กลับมา')$$,
  '23514', null, 'ลาออกแล้วกลับมา ACTIVE ไม่ได้');

-- ตั้ง PIN ต้อง step-up
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}', true);
select ok(pg_temp.denied_for_staff($$select public.set_staff_pin('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000003', '975318')$$), 'STAFF ทำไม่ได้ (ตั้ง PIN ต้องยืนยัน TOTP ซ้ำ)');

-- ตรวจผลในฐานะ postgres
reset role;

select ok(
  exists (select 1 from public.branch_memberships
           where user_id = '10000000-0000-4000-8000-000000000004'
             and branch_id = '30000000-0000-4000-8000-000000000001'
             and (effective_to is not null or status = 'REVOKED'))
  and exists (select 1 from public.branch_memberships
           where user_id = '10000000-0000-4000-8000-000000000004'
             and branch_id = '30000000-0000-4000-8000-000000000002' and effective_to is null and status = 'ACTIVE'),
  'ย้ายสาขาปิดสิทธิ์เดิมและเปิดสิทธิ์ใหม่');

select ok(
  not exists (select 1 from public.staff_pins where user_id = '10000000-0000-4000-8000-000000000004')
  and (select status from public.company_memberships where user_id = '10000000-0000-4000-8000-000000000004') = 'SUSPENDED',
  'ระงับแล้วลบ PIN และ membership เป็น SUSPENDED');

select ok(
  not exists (select 1 from public.employee_schedules
    where employee_id = '40000000-0000-4000-8000-000000000002' and starts_at > now() and status <> 'CANCELLED')
  and (select status from public.company_memberships where user_id = '10000000-0000-4000-8000-000000000002') = 'REVOKED'
  and not exists (select 1 from public.branch_memberships
                   where user_id = '10000000-0000-4000-8000-000000000002' and status = 'ACTIVE'
                     and (effective_to is null or effective_to > now())),
  'ลาออกแล้วยกเลิกกะอนาคตและปิดทุกสิทธิ์');

select ok(
  (select status from public.employee_transfers where id = current_setting('test.tr')::uuid) = 'CANCELLED',
  'สถานะการย้ายเป็น CANCELLED');

select throws_ok(
  $$insert into public.company_memberships (company_id, user_id, role)
    values ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000006', 'OWNER')$$,
  '23505', null, 'มี OWNER ได้คนเดียวต่อบริษัท');

-- พนักงานที่ถูกระงับเข้าสาขาไม่ได้
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated","aal":"aal1"}', true);
set local role authenticated;
select ok(not private.has_branch_access('30000000-0000-4000-8000-000000000002'), 'พนักงานที่ถูกระงับเข้าสาขาไม่ได้');
reset role;

select * from finish();
rollback;
