// ตรวจความปลอดภัยของ schema (คล้าย Supabase Security Advisor) บน Postgres จริง
import { startDb } from './db.mjs'

const root = process.argv[2]
const { server, client } = await startDb(root)
let problems = 0
async function section(title, sql, { expectEmpty = true } = {}) {
  const { rows } = await client.query(sql)
  const bad = expectEmpty && rows.length > 0
  if (bad) problems++
  console.log(`${bad ? 'FAIL' : expectEmpty ? 'PASS' : 'INFO'}  ${title} (${rows.length})`)
  for (const r of rows.slice(0, 60)) console.log('      ', Object.values(r).join(' | '))
}
try {
  await section('ตาราง public ที่ไม่ได้เปิด RLS',
    `select tablename from pg_tables where schemaname = 'public' and not rowsecurity`)
  await section('SECURITY DEFINER ที่ไม่ได้ตั้ง search_path',
    `select n.nspname || '.' || p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname in ('public', 'private') and p.prosecdef
        and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')`)
  await section('Function ใน public ที่ PUBLIC เรียกได้ (ลืม revoke)',
    `select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.prokind = 'f'
        and has_function_privilege('public', p.oid, 'execute')
        and p.oid not in (select tgfoid from pg_trigger)`)
  await section('Function ใน public ที่ anon เรียกได้ (ต้องเป็น endpoint สาธารณะเท่านั้น)',
    `select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')
        and p.prorettype <> 'trigger'::regtype order by 1`, { expectEmpty: false })
  await section('ตาราง/คอลัมน์ที่ anon มีสิทธิ์เขียน',
    `select table_name, privilege_type from information_schema.role_table_grants
      where grantee = 'anon' and table_schema = 'public' and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')
      union
     select table_name || '.' || column_name, privilege_type from information_schema.column_privileges
      where grantee = 'anon' and table_schema = 'public' and privilege_type in ('INSERT', 'UPDATE')`)
  await section('ตารางที่ anon อ่านได้ (ต้องเป็นข้อมูลสาธารณะเท่านั้น)',
    `select distinct table_name from information_schema.role_table_grants
      where grantee = 'anon' and table_schema = 'public' and privilege_type = 'SELECT'
      union
     select distinct table_name from information_schema.column_privileges
      where grantee = 'anon' and table_schema = 'public' and privilege_type = 'SELECT' order by 1`, { expectEmpty: false })
  await section('Policy แบบ DELETE/ALL (ห้ามลบข้อมูลผ่าน API)',
    `select tablename, policyname from pg_policies where schemaname = 'public' and cmd in ('DELETE', 'ALL')`)
  await section('ตารางการเงินที่ authenticated มีสิทธิ์เขียนตรง (ต้องผ่าน Function เท่านั้น)',
    `select table_name, privilege_type from information_schema.role_table_grants
      where grantee = 'authenticated' and table_schema = 'public' and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
        and table_name in ('invoices', 'invoice_items', 'payments', 'payment_refunds', 'tips', 'expenses', 'pos_cash_movements',
                           'commissions', 'commission_adjustments', 'commission_payouts', 'commission_payout_items',
                           'bookings', 'booking_deposits', 'resource_allocations', 'audit_logs', 'pos_sessions',
                           'branch_daily_closings', 'financial_periods', 'staff_attendances', 'queue_items', 'service_assignments')`)
  await section('View ที่ไม่ใช่ security_invoker',
    `select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind = 'v'
        and not coalesce((select bool_or(o = 'security_invoker=true') from unnest(c.reloptions) o), false)`)
} finally {
  await client.end()
  await server.stop()
}
console.log(problems ? `\n${problems} ปัญหา` : '\nไม่พบปัญหา')
process.exitCode = problems ? 1 : 0
