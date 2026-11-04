-- ตรวจการสร้างบริษัทแรกบน Production (bootstrap_company)
begin;
create extension if not exists pgtap with schema extensions;

select plan(8);

-- ผู้ใช้ที่ถูกเชิญผ่าน Auth (จำลอง)
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
values ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000050', 'authenticated', 'authenticated',
        'newowner@example.test', '', null, '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');

create temporary table t (k text primary key, v text) on commit drop;
grant all on t to authenticated, service_role;
insert into t values ('payload', $json${
  "company": { "code": "NEWCO", "name": "ร้านนวดใหม่", "legal_name": "บริษัท นวดใหม่ จำกัด" },
  "owner_display_name": "คุณใหม่",
  "branches": [ { "code": "BKK", "name": "สาขากรุงเทพ", "phone": "02-111-1111" }, { "code": "CNX", "name": "สาขาเชียงใหม่" } ],
  "policies": [ { "type": "PRIVACY_NOTICE", "version": "1.0", "title": "นโยบายความเป็นส่วนตัว",
                  "content": "ข้อความนโยบายความเป็นส่วนตัวฉบับจริงของร้าน ยาวพอสำหรับการทดสอบระบบ ............" } ]
}$json$);

set local role authenticated;
select throws_ok($$select public.bootstrap_company((select v::jsonb from t where k = 'payload'), '10000000-0000-4000-8000-000000000050')$$,
  '42501', null, 'ผู้ใช้ทั่วไปเรียก bootstrap ไม่ได้');
reset role;

set local role service_role;
select throws_ok($$select public.bootstrap_company((select v::jsonb from t where k = 'payload'), '10000000-0000-4000-8000-000000000099')$$,
  '22023', null, 'ต้องเชิญผู้ใช้ OWNER ใน Auth ก่อน');
select throws_ok($$select public.bootstrap_company((select v::jsonb from t where k = 'payload') - 'policies', '10000000-0000-4000-8000-000000000050')$$,
  '22023', null, 'ต้องมีนโยบายความเป็นส่วนตัวฉบับจริง');
insert into t select 'cid', public.bootstrap_company((select v::jsonb from t where k = 'payload'), '10000000-0000-4000-8000-000000000050')::text;
select throws_ok($$select public.bootstrap_company((select v::jsonb from t where k = 'payload'), '10000000-0000-4000-8000-000000000001')$$,
  '23505', null, 'สร้างบริษัทรหัสซ้ำไม่ได้');
reset role;

select is((select count(*)::int from public.branches where company_id = (select v::uuid from t where k = 'cid')), 2, 'สร้างสาขาครบ');
select is((select count(*)::int from public.branch_opening_hours o join public.branches b on b.id = o.branch_id
            where b.company_id = (select v::uuid from t where k = 'cid') and o.is_closed), 14,
  'สาขาใหม่ยังปิด (ให้ OWNER ตั้งเวลาทำการเอง)');
select ok(public.get_current_policies('NEWCO') ? 'PRIVACY_NOTICE', 'นโยบายความเป็นส่วนตัวพร้อมให้ลูกค้าสมัคร');

select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000050","role":"authenticated","aal":"aal2"}', true);
set local role authenticated;
select is(public.my_access() -> 'companies' -> 0 ->> 'role', 'OWNER', 'ผู้ถูกเชิญเป็น OWNER ของบริษัทใหม่');
reset role;

select * from finish();
rollback;
