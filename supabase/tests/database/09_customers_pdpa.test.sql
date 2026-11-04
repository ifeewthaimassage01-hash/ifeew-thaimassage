-- ตรวจลูกค้า ความยินยอม การค้นหา การจับคู่ และ PDPA
begin;
create extension if not exists pgtap with schema extensions;

select plan(27);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
) values (
  '00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000020', 'authenticated', 'authenticated',
  'new@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');

select set_config('test.privacy', public.get_current_policies('IFEEW') -> 'PRIVACY_NOTICE' ->> 'id', true);

-- ---------------------------------------------------------------------------
-- ลูกค้าใหม่สมัครสมาชิก
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000020","role":"authenticated","aal":"aal1"}', true);
set local role authenticated;

select ok(public.my_customer('IFEEW') is null, 'ยังไม่มีข้อมูลลูกค้าก่อนลงทะเบียน');
select throws_ok(
  $$select public.register_customer('IFEEW', 'สมชาย', 'ทดสอบ', '0811112222', gen_random_uuid(), false)$$,
  '22023', null, 'ต้องยอมรับนโยบายฉบับปัจจุบัน');
select throws_ok(
  $$select public.register_customer('IFEEW', 'สมชาย', 'ทดสอบ', '12345', current_setting('test.privacy')::uuid, false)$$,
  '22023', null, 'เบอร์โทรไม่ถูกต้อง');
select lives_ok(
  $$select public.register_customer('IFEEW', 'สมชาย', 'ทดสอบ', '+66 81 111 2222', current_setting('test.privacy')::uuid, false)$$,
  'ลงทะเบียนลูกค้าได้');
select is(public.my_customer('IFEEW') ->> 'phone', '0811112222', 'เบอร์ถูกแปลงเป็นรูปแบบไทย');
select is(public.my_customer('IFEEW') -> 'consents' -> 'MARKETING' ->> 'granted', 'false', 'บันทึกการไม่ยินยอมการตลาด');
select throws_ok(
  $$select public.register_customer('IFEEW', 'สมชาย', 'ซ้ำ', '0811112222', current_setting('test.privacy')::uuid, false)$$,
  '23505', null, 'ลงทะเบียนซ้ำไม่ได้');
select lives_ok($$select public.set_my_marketing_consent('IFEEW', true)$$, 'เปลี่ยนความยินยอมการตลาดได้');
select is(public.my_customer('IFEEW') -> 'consents' -> 'MARKETING' ->> 'granted', 'true', 'ความยินยอมล่าสุดมีผล');
select is((select count(*)::int from public.customers), 0, 'ลูกค้าอ่านตาราง customers ตรงไม่ได้');
select is(public.export_my_data('IFEEW') -> 'customer' ->> 'first_name', 'สมชาย', 'ส่งออกข้อมูลของตัวเองได้');
select lives_ok($$select public.request_my_data_deletion('IFEEW', 'ไม่ใช้บริการแล้ว')$$, 'ส่งคำขอลบข้อมูลได้');
select throws_ok($$select public.request_my_data_deletion('IFEEW', 'ซ้ำ')$$, '23505', null, 'มีคำขอค้างได้ครั้งละ 1');

-- ---------------------------------------------------------------------------
-- STAFF นภา
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1"}', true);

select throws_ok(
  $$select * from public.search_customers_by_phone('20000000-0000-4000-8000-000000000001', '0812')$$,
  '22023', null, 'ค้นหาด้วยเบอร์ไม่ครบไม่ได้');
select is(
  (select count(*)::int from public.search_customers_by_phone('20000000-0000-4000-8000-000000000001', '081-234-5678')),
  2, 'ค้นหาเบอร์เต็มเจอทั้งสมาชิกและ Guest');
select ok(
  (select bool_and(phone_masked = '081-xxx-5678')
     from public.search_customers_by_phone('20000000-0000-4000-8000-000000000001', '0812345678')),
  'ผลค้นหาปิดบังเบอร์');
select is((select count(*)::int from public.customers), 0, 'STAFF อ่านตาราง customers ตรงไม่ได้');
select is(public.get_customer('60000000-0000-4000-8000-000000000002') ->> 'phone', '0812345678', 'เปิดดูรายละเอียดได้');
select throws_ok(
  $$select public.create_customer('20000000-0000-4000-8000-000000000001', 'ใหม่', '', '0822223333', null, null, false)$$,
  '22023', null, 'ต้องแจ้งนโยบายก่อนเพิ่มลูกค้า');
select lives_ok(
  $$select public.create_customer('20000000-0000-4000-8000-000000000001', 'ใหม่', 'วอล์กอิน', '0822223333', null, 'แพ้น้ำมัน', true)$$,
  'พนักงานเพิ่มลูกค้า Walk-in ได้');
select throws_ok(
  $$select public.merge_customers('60000000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000002', 'ทดสอบ')$$,
  '23514', null, 'สมาชิกเป็นต้นทางการรวมไม่ได้');
select lives_ok(
  $$select public.merge_customers('60000000-0000-4000-8000-000000000002', '60000000-0000-4000-8000-000000000001', 'ลูกค้ายืนยันที่หน้าร้าน')$$,
  'รวม Guest เข้ากับสมาชิกได้');
select is(
  (select count(*)::int from public.search_customers_by_phone('20000000-0000-4000-8000-000000000001', '0812345678')),
  1, 'หลังรวมเหลือผลค้นหา 1 ราย');

select public.update_customer('60000000-0000-4000-8000-000000000001', 'แก้ชื่อ', '', '0800000000', null, 'ลูกค้าประจำ');
reset role;
select ok(
  (select first_name = 'มานี' and phone = '0812345678' and staff_note = 'ลูกค้าประจำ'
     from public.customers where id = '60000000-0000-4000-8000-000000000001'),
  'พนักงานแก้ได้เฉพาะหมายเหตุของลูกค้าสมาชิก');

-- ---------------------------------------------------------------------------
-- OWNER อนุมัติลบข้อมูล
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims', json_build_object(
  'sub', '10000000-0000-4000-8000-000000000001', 'role', 'authenticated', 'aal', 'aal2',
  'amr', json_build_array(json_build_object('method', 'totp', 'timestamp', extract(epoch from now())::bigint))
)::text, true);
set local role authenticated;
select is(
  public.process_data_deletion(
    (select id from public.customer_data_requests where status = 'PENDING' limit 1), true, null) ->> 'auth_user_id',
  '10000000-0000-4000-8000-000000000020', 'OWNER อนุมัติลบข้อมูลได้');
reset role;

select ok(
  (select status = 'ANONYMIZED' and phone is null and email is null and auth_user_id is null
     from public.customers where first_name = 'ลบข้อมูลแล้ว' and created_channel = 'ONLINE'
       and anonymized_at is not null limit 1)
  and (select display_name = '' and phone is null from public.profiles where id = '10000000-0000-4000-8000-000000000020'),
  'ข้อมูลลูกค้าและโปรไฟล์ถูก anonymize');
select ok(
  not exists (select 1 from public.audit_logs
               where coalesce(old_values::text, '') || coalesce(new_values::text, '') || metadata::text like '%0811112222%'),
  'audit log ไม่มีเบอร์โทรลูกค้า');

select * from finish();
rollback;
