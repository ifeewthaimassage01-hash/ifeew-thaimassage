-- ตรวจโครงสร้างความปลอดภัยพื้นฐาน
begin;
create extension if not exists pgtap with schema extensions;

select plan(6);

select is(
  (select count(*)::int from pg_tables where schemaname = 'public' and not rowsecurity),
  0,
  'ทุกตารางใน public เปิด RLS'
);

select is(
  (select count(*)::int from pg_policies where schemaname = 'public' and cmd in ('DELETE', 'ALL')),
  0,
  'ไม่มี policy DELETE หรือ ALL ใน public'
);

select is(
  (select count(*)::int from pg_policies where schemaname = 'public' and tablename = 'audit_logs' and cmd <> 'SELECT'),
  0,
  'audit_logs มีเฉพาะ policy SELECT'
);

select is(
  (select count(*)::int from pg_policies where schemaname = 'public' and tablename in ('staff_pins', 'idempotency_keys', 'rate_limit_buckets')),
  0,
  'staff_pins / idempotency_keys / rate_limit_buckets ไม่มี policy ให้ client'
);

-- ทุก security definer function ใน public/private ต้องกำหนด search_path
select is(
  (select count(*)::int
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.prosecdef
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')),
  0,
  'security definer function ทุกตัวกำหนด search_path'
);

select is(
  (select count(*)::int
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('device_list_staff', 'device_verify_staff_pin', 'rate_limit_hit')
      and (has_function_privilege('anon', p.oid, 'EXECUTE')
           or has_function_privilege('authenticated', p.oid, 'EXECUTE'))),
  0,
  'function สำหรับ Edge Function เรียกได้เฉพาะ service_role'
);

select * from finish();
rollback;
