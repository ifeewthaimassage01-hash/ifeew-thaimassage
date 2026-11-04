-- ตรวจการผูกเครื่องประจำสาขาและ Staff Login ด้วย PIN
begin;
create extension if not exists pgtap with schema extensions;

select plan(24);

-- -----------------------------------------------------------------------------
-- รูปแบบ PIN
-- -----------------------------------------------------------------------------
select throws_ok($$select private.assert_valid_pin('12345')$$, '22023', null, 'PIN ต้องมี 6 หลัก');
select throws_ok($$select private.assert_valid_pin('123456')$$, '22023', null, 'ห้าม PIN เรียงกัน');
select throws_ok($$select private.assert_valid_pin('999999')$$, '22023', null, 'ห้าม PIN เลขซ้ำ');
select lives_ok($$select private.assert_valid_pin('246810')$$, 'PIN ปกติผ่าน');

-- -----------------------------------------------------------------------------
-- ผูกเครื่อง: STAFF ไม่ได้, OWNER ได้
-- -----------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1"}', true);
set local role authenticated;
select throws_ok(
  $$select public.pair_branch_device('30000000-0000-4000-8000-000000000001', 'iPad หน้าร้าน')$$,
  '42501', null, 'STAFF ผูกเครื่องไม่ได้');

select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}', true);
select set_config('test.device_token',
  public.pair_branch_device('30000000-0000-4000-8000-000000000001', 'iPad หน้าร้าน') ->> 'device_token', true);
select ok(current_setting('test.device_token') ~ '^dvc_[0-9a-f]{64}$', 'OWNER aal2 ผูกเครื่องได้และได้ token');
select throws_ok($$select token_hash from public.branch_devices$$, '42501', null, 'OWNER อ่าน token_hash ไม่ได้');
reset role;

-- -----------------------------------------------------------------------------
-- รายชื่อพนักงานบนเครื่อง (service_role)
-- -----------------------------------------------------------------------------
set local role service_role;

select is(
  public.device_list_staff('dvc_invalid') ->> 'error_code', 'DEVICE_INVALID', 'token ผิดไม่ได้รายชื่อ');
select is(
  jsonb_array_length(public.device_list_staff(current_setting('test.device_token')) -> 'staff'), 2,
  'เครื่องสาขา SKV เห็นเฉพาะพนักงานสาขา SKV');

-- -----------------------------------------------------------------------------
-- ตรวจ PIN
-- -----------------------------------------------------------------------------
select is(
  public.device_verify_staff_pin(current_setting('test.device_token'),
    '10000000-0000-4000-8000-000000000003', '135792') ->> 'error_code',
  'INVALID_CREDENTIALS', 'พนักงานสาขาอื่น login บนเครื่องนี้ไม่ได้แม้ PIN ถูก');

select is(
  public.device_verify_staff_pin(current_setting('test.device_token'),
    '10000000-0000-4000-8000-000000000002', '246810') ->> 'ok',
  'true', 'PIN ถูกต้อง login ได้');

select is(
  public.device_verify_staff_pin(current_setting('test.device_token'),
    '10000000-0000-4000-8000-000000000002', '000001') ->> 'attempts_left',
  '4', 'PIN ผิดครั้งแรกเหลือ 4 ครั้ง');

select public.device_verify_staff_pin(current_setting('test.device_token'),
  '10000000-0000-4000-8000-000000000002', '000001')
  from generate_series(1, 3);

select is(
  public.device_verify_staff_pin(current_setting('test.device_token'),
    '10000000-0000-4000-8000-000000000002', '000001') ->> 'error_code',
  'PIN_LOCKED', 'ผิดครบ 5 ครั้งถูกล็อก');

select is(
  public.device_verify_staff_pin(current_setting('test.device_token'),
    '10000000-0000-4000-8000-000000000002', '246810') ->> 'error_code',
  'PIN_LOCKED', 'ระหว่างล็อก PIN ถูกก็เข้าไม่ได้');

reset role;
select ok(
  (select count(*) from public.audit_logs where action = 'STAFF_PIN_LOGIN_FAILED') >= 4
  and exists (select 1 from public.audit_logs where action = 'STAFF_PIN_LOCKED'),
  'การ login ผิดและการล็อกถูกบันทึก audit');

-- -----------------------------------------------------------------------------
-- เจ้าของร้าน login ด้วย PIN บนเครื่องสาขา (migration 028)
-- -----------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}', true);
set local role authenticated;
select lives_ok($$select public.set_my_owner_pin('20000000-0000-4000-8000-000000000001', '581472')$$,
  'OWNER ตั้ง PIN ของตัวเองได้ (ไม่ต้องใช้ MFA)');
reset role;
set local role service_role;
select ok((select bool_or((x ->> 'is_owner')::boolean) from jsonb_array_elements(
            public.device_list_staff(current_setting('test.device_token')) -> 'staff') x),
  'รายชื่อบนเครื่องสาขามีเจ้าของร้าน');
select ok((public.device_verify_staff_pin(current_setting('test.device_token'),
            '10000000-0000-4000-8000-000000000001', '581472') ->> 'ok')::boolean,
  'เจ้าของร้าน login ด้วย PIN บนเครื่องสาขาได้');
select ok((public.owner_verify_pin('IFEEW', '581472') ->> 'ok')::boolean,
  'เจ้าของร้าน login ด้วย PIN อย่างเดียว (ไม่ต้องใช้เครื่องที่ผูก)');
select is(public.owner_verify_pin('IFEEW', '111111') ->> 'error_code', 'INVALID_CREDENTIALS',
  'PIN เจ้าของร้านผิด เข้าไม่ได้');
select count(public.owner_verify_pin('IFEEW', '111111')) from generate_series(1, 4);
select is(public.owner_verify_pin('IFEEW', '581472') ->> 'error_code', 'PIN_LOCKED',
  'PIN เจ้าของร้านผิดหลายครั้ง = ล็อก (PIN ถูกก็เข้าไม่ได้)');
select is(public.owner_verify_pin('NOPE', '581472') ->> 'error_code', 'INVALID_CREDENTIALS',
  'รหัสบริษัทผิด เข้าไม่ได้');
reset role;

-- -----------------------------------------------------------------------------
-- ยกเลิกเครื่อง
-- -----------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}', true);
set local role authenticated;
select lives_ok(
  $$select public.revoke_branch_device(
      (select id from public.branch_devices where name = 'iPad หน้าร้าน'), 'เครื่องหาย')$$,
  'OWNER ยกเลิกเครื่องได้');
reset role;

set local role service_role;
select is(
  public.device_list_staff(current_setting('test.device_token')) ->> 'error_code', 'DEVICE_INVALID',
  'เครื่องที่ถูกยกเลิกใช้งานไม่ได้');
reset role;

select * from finish();
rollback;
