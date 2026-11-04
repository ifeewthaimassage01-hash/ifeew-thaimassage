-- ตรวจการผูกเครื่องประจำสาขาและ Staff Login ด้วย PIN
begin;
create extension if not exists pgtap with schema extensions;

select plan(17);

-- -----------------------------------------------------------------------------
-- รูปแบบ PIN
-- -----------------------------------------------------------------------------
select throws_ok($$select private.assert_valid_pin('12345')$$, '22023', null, 'PIN ต้องมี 6 หลัก');
select throws_ok($$select private.assert_valid_pin('123456')$$, '22023', null, 'ห้าม PIN เรียงกัน');
select throws_ok($$select private.assert_valid_pin('999999')$$, '22023', null, 'ห้าม PIN เลขซ้ำ');
select lives_ok($$select private.assert_valid_pin('246810')$$, 'PIN ปกติผ่าน');

-- -----------------------------------------------------------------------------
-- ผูกเครื่อง: OWNER aal1 ไม่ได้, aal2 ได้
-- -----------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}', true);
set local role authenticated;
select throws_ok(
  $$select public.pair_branch_device('30000000-0000-4000-8000-000000000001', 'iPad หน้าร้าน')$$,
  '42501', null, 'OWNER ที่ยังไม่ผ่าน MFA ผูกเครื่องไม่ได้');

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
  jsonb_array_length(public.device_list_staff(current_setting('test.device_token')) -> 'staff'), 1,
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
