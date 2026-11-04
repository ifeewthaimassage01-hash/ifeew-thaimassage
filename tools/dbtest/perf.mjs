// วัดความเร็ว Function รายงาน/แดชบอร์ด เมื่อมีข้อมูล 1 ปี (สร้างข้อมูลจำลองตรงเข้าตาราง)
//   node perf.mjs <repo-root> [ต่อวันต่อสาขา=40]
import { asUser, newPool, startDb } from './db.mjs'

const root = process.argv[2]
const perDay = Number(process.argv[3] ?? 40)
const { server, client } = await startDb(root)
const pool = newPool(5)

const COMPANY = '20000000-0000-4000-8000-000000000001'
const SKV = '30000000-0000-4000-8000-000000000001'
const OWNER = { sub: '10000000-0000-4000-8000-000000000001', role: 'authenticated', aal: 'aal2' }
const NAPA = { sub: '10000000-0000-4000-8000-000000000002', role: 'authenticated', aal: 'aal1' }

try {
  const t0 = Date.now()
  // ข้อมูลจำลอง: ข้าม trigger (ไม่ต้อง audit/ตรวจซ้ำ) เพื่อสร้างเร็ว — ใช้วัดการอ่านเท่านั้น
  await client.query(`
    set session_replication_role = replica;
    create temp table gen as
    select gen_random_uuid() as order_id, gen_random_uuid() as item_id, gen_random_uuid() as queue_id,
           gen_random_uuid() as assign_id, gen_random_uuid() as invoice_id, gen_random_uuid() as invoice_item_id,
           gen_random_uuid() as payment_id, b.id as branch_id, b.code, d::date as d, n,
           (d::date + time '10:00' + make_interval(mins => n * 10)) at time zone 'Asia/Bangkok' as started,
           row_number() over (partition by b.id, extract(year from d) order by d, n) as rn,
           case when b.code = 'SKV' then (case when n % 2 = 0 then '40000000-0000-4000-8000-000000000002'
                                               else '40000000-0000-4000-8000-000000000004' end)::uuid
                else '40000000-0000-4000-8000-000000000003'::uuid end as employee_id,
           (select o.id from public.branch_service_options o join public.branch_services bs on bs.id = o.branch_service_id
             where bs.branch_id = b.id and bs.service_id = '51000000-0000-4000-8000-000000000001' and o.duration_minutes = 60) as option_id
      from public.branches b
      cross join generate_series(current_date - 366, current_date - 1, interval '1 day') d
      cross join generate_series(1, ${perDay}) n
     where b.company_id = '${COMPANY}';
    create temp table sess as
    select gen_random_uuid() as id, branch_id, d from (select distinct branch_id, d from gen) x;

    insert into public.pos_sessions (id, company_id, branch_id, status, business_date, opened_at, opened_by, opening_cash,
      closed_at, cash_sales, transfer_sales, qr_sales, cash_tips, cash_in, cash_out, cash_refunds, expected_cash, actual_cash,
      cash_difference, review_status)
    select id, '${COMPANY}', branch_id, 'CLOSED', d, (d + time '09:00') at time zone 'Asia/Bangkok', '10000000-0000-4000-8000-000000000002', 1000,
           (d + time '23:00') at time zone 'Asia/Bangkok', 0, 0, 0, 0, 0, 0, 0, 1000, 1000, 0, 'APPROVED' from sess;
    insert into public.service_orders (id, company_id, branch_id, channel, business_date, status, completed_at)
    select order_id, '${COMPANY}', branch_id, 'WALK_IN', d, 'COMPLETED', started + interval '60 minutes' from gen;
    insert into public.service_order_items (id, company_id, branch_id, service_order_id, branch_service_option_id, service_id,
      service_name, duration_minutes, unit_price, therapist_fee, line_total)
    select item_id, '${COMPANY}', branch_id, order_id, option_id, '51000000-0000-4000-8000-000000000001', 'นวดไทย', 60, 300, 120, 300 from gen;
    insert into public.queue_items (id, company_id, branch_id, service_order_item_id, queue_date, queue_number, status,
      planned_starts_at, planned_ends_at, started_at, completed_at)
    select queue_id, '${COMPANY}', branch_id, item_id, d, n, 'COMPLETED', started, started + interval '60 minutes',
           started, started + interval '60 minutes' from gen;
    insert into public.service_assignments (id, company_id, branch_id, queue_item_id, employee_id, status, started_at, completed_at)
    select assign_id, '${COMPANY}', branch_id, queue_id, employee_id, 'COMPLETED', started, started + interval '60 minutes' from gen;
    insert into public.invoices (id, company_id, branch_id, service_order_id, business_date, invoice_number, receipt_number,
      status, subtotal, total, paid_amount, issued_at, paid_at)
    select invoice_id, '${COMPANY}', branch_id, order_id, d,
           format('INV-%s-%s-%s', code, extract(year from d), lpad(rn::text, 6, '0')),
           format('RCP-%s-%s-%s', code, extract(year from d), lpad(rn::text, 6, '0')),
           'PAID', 300, 300, 300, started + interval '61 minutes', started + interval '62 minutes' from gen;
    insert into public.invoice_items (id, company_id, branch_id, invoice_id, service_order_item_id, description, duration_minutes,
      unit_price, line_total)
    select invoice_item_id, '${COMPANY}', branch_id, invoice_id, item_id, 'นวดไทย', 60, 300, 300 from gen;
    insert into public.payments (id, company_id, branch_id, invoice_id, pos_session_id, method, amount, received_at)
    select g.payment_id, '${COMPANY}', g.branch_id, g.invoice_id, s.id, case when g.n % 3 = 0 then 'CASH' else 'CASH' end, 300,
           g.started + interval '62 minutes'
      from gen g join sess s on s.branch_id = g.branch_id and s.d = g.d;
    insert into public.expenses (company_id, branch_id, expense_scope, amount, note, photo_path, occurred_on, payment_source)
    select '${COMPANY}', branch_id, 'BRANCH', 500, 'ค่าน้ำแข็ง', 'x/y.jpg', d, 'OTHER' from sess;
    set session_replication_role = origin;
    analyze;`)
  const rows = (await client.query('select count(*)::int n from public.service_orders')).rows[0].n
  console.log(`สร้างข้อมูล ${rows} Order (${perDay}/วัน/สาขา, 1 ปี) ใน ${((Date.now() - t0) / 1000).toFixed(1)} วินาที\n`)

  const today = (await client.query(`select private.company_local_date('${COMPANY}') as d`)).rows[0].d.toISOString().slice(0, 10)
  const cases = [
    ['commission_summary (ครั้งแรก: sync ย้อน 62 วัน)', OWNER, `select public.commission_summary($1, null, $2::date - 30, $2::date)`, [COMPANY, today]],
    ['commission_summary (ครั้งถัดไป)', OWNER, `select public.commission_summary($1, null, $2::date - 30, $2::date)`, [COMPANY, today]],
    ['owner_dashboard', OWNER, `select public.owner_dashboard($1)`, [COMPANY]],
    ['finance_report 1 ปี รายเดือน', OWNER, `select public.finance_report($1, null, $2::date - 365, $2::date, 'MONTH')`, [COMPANY, today]],
    ['finance_report 1 เดือน รายวัน', OWNER, `select public.finance_report($1, null, $2::date - 30, $2::date, 'DAY')`, [COMPANY, today]],
    ['therapist_work_summary 1 เดือน', OWNER, `select public.therapist_work_summary($1, null, $2::date - 30, $2::date)`, [COMPANY, today]],
    ['attendance_report 1 สัปดาห์', OWNER, `select public.attendance_report($1, null, $2::date - 7, $2::date)`, [COMPANY, today]],
    ['pos_board (วันนี้)', NAPA, `select public.pos_board($1)`, [SKV]],
    ['staff_dashboard', NAPA, `select public.staff_dashboard($1)`, [SKV]],
    ['my_work_history 1 เดือน', NAPA, `select public.my_work_history($1::date - 30, $1::date)`, [today]],
    ['my_earnings 1 เดือน', NAPA, `select public.my_earnings($1::date - 30, $1::date)`, [today]],
    ['daily_closing_preview (เมื่อวาน)', NAPA, `select public.daily_closing_preview($1, $2::date - 1)`, [SKV, today]],
  ]
  for (const [name, claims, sql, params] of cases) {
    const t = Date.now()
    const r = await asUser(pool, claims, sql, params)
    const ms = Date.now() - t
    console.log(`${r.ok ? (ms > 2000 ? 'SLOW ' : 'OK   ') : 'ERR  '} ${String(ms).padStart(6)} ms  ${name}${r.ok ? '' : '  — ' + r.error.message}`)
  }
} finally {
  await pool.end()
  await client.end()
  await server.stop()
}
