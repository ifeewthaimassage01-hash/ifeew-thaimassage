-- =============================================================================
-- Seed สำหรับ local/dev เท่านั้น — ห้ามรันกับ staging/production
-- =============================================================================
-- บัญชีทดสอบ (ค่าทดสอบเท่านั้น):
--   OWNER : owner@ifeew.test / IfeewOwner2026   (ต้องตั้ง TOTP ครั้งแรกที่ login)
--   STAFF : นภา (สาขา SKV)  PIN 246810
--   STAFF : สมใจ (สาขา ARI) PIN 135792
--   CUSTOMER : customer@ifeew.test / IfeewCustomer2026
-- STAFF ใช้อีเมลภายใน (*.staff.ifeew.internal) ไม่มีรหัสผ่าน login ได้เฉพาะผ่าน PIN บนเครื่องที่ผูกแล้ว

-- -----------------------------------------------------------------------------
-- auth.users (trigger สร้าง profiles ให้)
-- -----------------------------------------------------------------------------
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
) values
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000001',
   'authenticated', 'authenticated', 'owner@ifeew.test',
   extensions.crypt('IfeewOwner2026', extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"display_name":"คุณฝ้าย (เจ้าของ)"}',
   now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000002',
   'authenticated', 'authenticated', '10000000-0000-4000-8000-000000000002@staff.ifeew.internal',
   extensions.crypt(encode(extensions.gen_random_bytes(32), 'hex'), extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"display_name":"นภา"}',
   now(), now(), '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000003',
   'authenticated', 'authenticated', '10000000-0000-4000-8000-000000000003@staff.ifeew.internal',
   extensions.crypt(encode(extensions.gen_random_bytes(32), 'hex'), extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"display_name":"สมใจ"}',
   now(), now(), '', '', '', '');

insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id, u.id::text, 'email',
       jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
       now(), now(), now()
  from auth.users u
 where u.id in ('10000000-0000-4000-8000-000000000001',
                '10000000-0000-4000-8000-000000000002',
                '10000000-0000-4000-8000-000000000003');

-- -----------------------------------------------------------------------------
-- บริษัทและสาขา (trigger สร้าง company_settings ให้)
-- -----------------------------------------------------------------------------
insert into public.companies (id, code, name, legal_name, created_by) values
  ('20000000-0000-4000-8000-000000000001', 'IFEEW', 'Ifeew''s Thaimassage', 'บริษัท ไอฟิ้ว ไทยมาสสาจ จำกัด',
   '10000000-0000-4000-8000-000000000001');

insert into public.branches (id, company_id, code, name, address, phone, sort_order, created_by) values
  ('30000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001',
   'SKV', 'สาขาสุขุมวิท', '123 ถนนสุขุมวิท แขวงคลองเตย เขตคลองเตย กรุงเทพฯ 10110', '02-000-0001', 1,
   '10000000-0000-4000-8000-000000000001'),
  ('30000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001',
   'ARI', 'สาขาอารีย์', '45 ซอยอารีย์ 1 แขวงสามเสนใน เขตพญาไท กรุงเทพฯ 10400', '02-000-0002', 2,
   '10000000-0000-4000-8000-000000000001');

-- -----------------------------------------------------------------------------
-- สมาชิกและสิทธิ์
-- -----------------------------------------------------------------------------
insert into public.company_memberships (company_id, user_id, role, created_by) values
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'OWNER',
   '10000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', 'STAFF',
   '10000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000003', 'STAFF',
   '10000000-0000-4000-8000-000000000001');

insert into public.branch_memberships (company_id, branch_id, user_id, effective_from, created_by) values
  ('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000002', '2026-01-01 00:00+07', '10000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000002',
   '10000000-0000-4000-8000-000000000003', '2026-01-01 00:00+07', '10000000-0000-4000-8000-000000000001');

-- -----------------------------------------------------------------------------
-- PIN ทดสอบ
-- -----------------------------------------------------------------------------
insert into public.staff_pins (company_id, user_id, pin_hash, created_by) values
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002',
   extensions.crypt('246810', extensions.gen_salt('bf', 10)), '10000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000003',
   extensions.crypt('135792', extensions.gen_salt('bf', 10)), '10000000-0000-4000-8000-000000000001');

-- -----------------------------------------------------------------------------
-- Phase 2: ข้อมูลพนักงาน ประวัติเริ่มงาน เวลาทำการ และกะตัวอย่าง
-- -----------------------------------------------------------------------------
insert into public.employees (id, company_id, user_id, employee_code, nickname, start_date, created_by) values
  ('40000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000002', 'SKV-01', 'นภา', '2026-01-05', '10000000-0000-4000-8000-000000000001'),
  ('40000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000003', 'ARI-01', 'สมใจ', '2026-03-01', '10000000-0000-4000-8000-000000000001');

insert into public.employee_transfers (company_id, employee_id, to_branch_id, to_membership_id, effective_from, reason, created_by)
select bm.company_id, e.id, bm.branch_id, bm.id, bm.effective_from, 'เริ่มงาน', '10000000-0000-4000-8000-000000000001'
  from public.branch_memberships bm
  join public.employees e on e.company_id = bm.company_id and e.user_id = bm.user_id;

-- เวลาทำการ: ทุกวัน 10:00-22:00 (ศุกร์-เสาร์ ถึง 00:30 ของวันถัดไป)
update public.branch_opening_hours
   set is_closed = false,
       opens_at = '10:00',
       closes_at = case when iso_dow in (5, 6) then '00:30'::time else '22:00'::time end;

insert into public.branch_holidays (company_id, branch_id, holiday_date, name, created_by) values
  ('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', '2026-12-31', 'วันสิ้นปี',
   '10000000-0000-4000-8000-000000000001');

-- กะตัวอย่าง จันทร์-ศุกร์ของสัปดาห์นี้ 10:00-19:00 (เวลาไทย)
insert into public.employee_schedules (company_id, branch_id, employee_id, starts_at, ends_at, created_by)
select '20000000-0000-4000-8000-000000000001', x.branch_id, x.employee_id,
       ((date_trunc('week', (now() at time zone 'Asia/Bangkok'))::date + d) + time '10:00') at time zone 'Asia/Bangkok',
       ((date_trunc('week', (now() at time zone 'Asia/Bangkok'))::date + d) + time '19:00') at time zone 'Asia/Bangkok',
       '10000000-0000-4000-8000-000000000001'
  from (values
          ('30000000-0000-4000-8000-000000000001'::uuid, '40000000-0000-4000-8000-000000000002'::uuid),
          ('30000000-0000-4000-8000-000000000002'::uuid, '40000000-0000-4000-8000-000000000003'::uuid)
       ) as x(branch_id, employee_id)
 cross join generate_series(0, 4) d;

-- -----------------------------------------------------------------------------
-- Phase 3: บริการ ราคา นโยบาย ลูกค้า
-- -----------------------------------------------------------------------------
insert into public.service_categories (id, company_id, name, sort_order) values
  ('50000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'นวดไทย', 1),
  ('50000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001', 'นวดเท้า', 2),
  ('50000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000001', 'นวดน้ำมัน', 3);

insert into public.services (id, company_id, category_id, name, name_en, description, sort_order) values
  ('51000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000001',
   'นวดไทย', 'Thai Massage', 'นวดแผนไทยแบบดั้งเดิม คลายกล้ามเนื้อทั่วร่างกาย', 1),
  ('51000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000002',
   'นวดเท้า', 'Foot Massage', 'กดจุดสะท้อนฝ่าเท้า', 2),
  ('51000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000003',
   'นวดน้ำมันอโรมา', 'Aroma Oil Massage', 'นวดผ่อนคลายด้วยน้ำมันหอมระเหย', 3);

-- ช่วงเวลา/ราคา/ค่าแรง (สาขาอารีย์ราคาสูงกว่า 50 บาท ค่าแรงเท่ากัน)
create temporary table seed_prices (service_id uuid, duration_minutes int, price numeric, therapist_fee numeric);
insert into seed_prices values
  ('51000000-0000-4000-8000-000000000001', 60, 300, 120),
  ('51000000-0000-4000-8000-000000000001', 90, 450, 180),
  ('51000000-0000-4000-8000-000000000001', 120, 550, 240),
  ('51000000-0000-4000-8000-000000000002', 30, 200, 80),
  ('51000000-0000-4000-8000-000000000002', 60, 300, 120),
  ('51000000-0000-4000-8000-000000000003', 60, 600, 240),
  ('51000000-0000-4000-8000-000000000003', 90, 850, 340);

insert into public.branch_services (company_id, branch_id, service_id, sort_order, created_by)
select '20000000-0000-4000-8000-000000000001', b.id, s.id, s.sort_order, '10000000-0000-4000-8000-000000000001'
  from public.branches b cross join public.services s
 where b.company_id = '20000000-0000-4000-8000-000000000001';

insert into public.branch_service_options (company_id, branch_service_id, duration_minutes, created_by)
select bs.company_id, bs.id, sp.duration_minutes, '10000000-0000-4000-8000-000000000001'
  from public.branch_services bs join seed_prices sp on sp.service_id = bs.service_id;

insert into public.service_price_histories
  (company_id, branch_service_option_id, price, therapist_fee, effective_from, reason, created_by)
select o.company_id, o.id, sp.price + case when b.code = 'ARI' then 50 else 0 end, sp.therapist_fee,
       '2026-01-01 00:00+07', 'ราคาเริ่มต้น', '10000000-0000-4000-8000-000000000001'
  from public.branch_service_options o
  join public.branch_services bs on bs.id = o.branch_service_id
  join public.branches b on b.id = bs.branch_id
  join seed_prices sp on sp.service_id = bs.service_id and sp.duration_minutes = o.duration_minutes;

drop table seed_prices;

-- นโยบายตัวอย่าง (เนื้อหาจริงต้องให้ผู้เชี่ยวชาญกฎหมายจัดทำ)
insert into public.privacy_policy_versions (company_id, policy_type, version, title, content, published_at) values
  ('20000000-0000-4000-8000-000000000001', 'PRIVACY_NOTICE', '1.0', 'นโยบายความเป็นส่วนตัว (ตัวอย่าง)',
   'ข้อความตัวอย่างสำหรับทดสอบระบบเท่านั้น ร้านเก็บชื่อ นามสกุล เบอร์โทร และอีเมล เพื่อใช้ในการจองและให้บริการ ...',
   '2026-01-01 00:00+07'),
  ('20000000-0000-4000-8000-000000000001', 'MARKETING', '1.0', 'การรับข่าวสารและโปรโมชัน (ตัวอย่าง)',
   'ข้อความตัวอย่าง: ยินยอมให้ร้านส่งข่าวสารและโปรโมชันทางอีเมลหรือ SMS ยกเลิกได้ทุกเมื่อ',
   '2026-01-01 00:00+07');

-- ลูกค้าสมาชิก 1 คน + Guest 2 คน (Guest คนหนึ่งเบอร์ซ้ำกับสมาชิก เพื่อทดสอบการจับคู่)
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
) values (
  '00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000010',
  'authenticated', 'authenticated', 'customer@ifeew.test',
  extensions.crypt('IfeewCustomer2026', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{"display_name":"มานี ใจดี"}', now(), now(), '', '', '', '');

insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
values (gen_random_uuid(), '10000000-0000-4000-8000-000000000010', '10000000-0000-4000-8000-000000000010', 'email',
        '{"sub":"10000000-0000-4000-8000-000000000010","email":"customer@ifeew.test","email_verified":true}', now(), now(), now());

insert into public.customers (id, company_id, auth_user_id, first_name, last_name, phone, email, created_channel) values
  ('60000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000010',
   'มานี', 'ใจดี', '0812345678', 'customer@ifeew.test', 'ONLINE'),
  ('60000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001', null,
   'มานี', '', '0812345678', null, 'STAFF'),
  ('60000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000001', null,
   'ปิติ', 'มีสุข', '0898765432', null, 'STAFF');

insert into public.customer_consents (company_id, customer_id, policy_version_id, consent_type, granted, channel)
select c.company_id, c.id, p.id, p.policy_type, true, c.created_channel
  from public.customers c
  join public.privacy_policy_versions p on p.company_id = c.company_id and p.policy_type = 'PRIVACY_NOTICE';

-- -----------------------------------------------------------------------------
-- Phase 4: ทรัพยากร บัญชีรับมัดจำ
-- -----------------------------------------------------------------------------
insert into public.resource_types (id, company_id, name, description) values
  ('70000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'เบาะนวดไทย', 'เบาะพื้นสำหรับนวดไทย'),
  ('70000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001', 'เก้าอี้นวดเท้า', 'เก้าอี้ปรับเอน'),
  ('70000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000001', 'เตียงนวดน้ำมัน', 'เตียงในห้องส่วนตัว');

-- SKV: เบาะ 4, เก้าอี้ 3, เตียง 2 | ARI: เบาะ 3, เก้าอี้ 2, เตียง 1
insert into public.branch_resources (company_id, branch_id, resource_type_id, total_quantity)
select '20000000-0000-4000-8000-000000000001', b.id, t.id,
       case b.code when 'SKV' then case t.name when 'เบาะนวดไทย' then 4 when 'เก้าอี้นวดเท้า' then 3 else 2 end
                   else case t.name when 'เบาะนวดไทย' then 3 when 'เก้าอี้นวดเท้า' then 2 else 1 end end
  from public.branches b cross join public.resource_types t;

insert into public.service_resources (company_id, service_id, resource_type_id, quantity) values
  ('20000000-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000001', '70000000-0000-4000-8000-000000000001', 1),
  ('20000000-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000002', '70000000-0000-4000-8000-000000000002', 1),
  ('20000000-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000003', '70000000-0000-4000-8000-000000000003', 1);

-- บัญชีรับมัดจำ (ค่าทดสอบ) — slipok_branch_id ต้องตั้งเป็นค่าจริงจาก SlipOK ก่อนใช้งาน
insert into public.branch_payment_accounts (company_id, branch_id, promptpay_id, account_name, bank_name, slipok_branch_id) values
  ('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', '0812345670', 'ไอฟิ้ว สาขาสุขุมวิท', 'กสิกรไทย', null),
  ('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000002', '0812345671', 'ไอฟิ้ว สาขาอารีย์', 'กสิกรไทย', null);
