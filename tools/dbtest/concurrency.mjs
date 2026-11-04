// ทดสอบการทำรายการพร้อมกันหลายการเชื่อมต่อบน Postgres จริง
import { asUser, newPool, startDb } from './db.mjs'

const root = process.argv[2]
const { server, client } = await startDb(root)
const pool = newPool(80)

const SKV = '30000000-0000-4000-8000-000000000001'
const COMPANY = '20000000-0000-4000-8000-000000000001'
const NAPA = { sub: '10000000-0000-4000-8000-000000000002', role: 'authenticated', aal: 'aal1' }
const OWNER = {
  sub: '10000000-0000-4000-8000-000000000001', role: 'authenticated', aal: 'aal2',
  amr: [{ method: 'totp', timestamp: Math.floor(Date.now() / 1000) }],
}
const SERVICE = { role: 'service_role' }
const E_NAPA = '40000000-0000-4000-8000-000000000002'
const E_DAO = '40000000-0000-4000-8000-000000000004'

const results = []
function check(name, pass, detail) {
  results.push({ name, pass, detail })
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`)
}
const parallel = (n, fn) => Promise.all(Array.from({ length: n }, (_, i) => fn(i)))
const errs = (rs) => rs.filter((r) => !r.ok).map((r) => r.error.message)
const summary = (list) => Object.entries(list.reduce((m, x) => ((m[x] = (m[x] ?? 0) + 1), m), {})).map(([k, v]) => `${v}× ${k}`).join(' | ')

try {
  // เปิดร้านครอบตอนนี้ + กะของหมอ
  await client.query(`
    update public.branch_holidays set is_active = false;
    update public.branch_opening_hours set is_closed = false,
      opens_at = case when extract(hour from now() at time zone 'Asia/Bangkok') < 1 then time '00:00'
                       else date_trunc('minute', (now() at time zone 'Asia/Bangkok') - interval '1 hour')::time end,
      closes_at = case when extract(hour from now() at time zone 'Asia/Bangkok') < 1 then time '23:59'
                       else date_trunc('minute', (now() at time zone 'Asia/Bangkok') - interval '61 minutes')::time end;
    update public.employee_schedules set status = 'CANCELLED' where branch_id = '${SKV}' and status = 'SCHEDULED';
    insert into public.employee_schedules (company_id, branch_id, employee_id, starts_at, ends_at)
    select '${COMPANY}', '${SKV}', e, now() - interval '30 minutes', now() + interval '10 hours'
      from unnest(array['${E_NAPA}', '${E_DAO}']::uuid[]) e;`)
  const opt = async (service, dur) => (await client.query(
    `select o.id from public.branch_service_options o join public.branch_services bs on bs.id = o.branch_service_id
      where bs.branch_id = $1 and bs.service_id = $2 and o.duration_minutes = $3`, [SKV, service, dur])).rows[0].id
  const thai60 = await opt('51000000-0000-4000-8000-000000000001', 60)
  const foot30 = await opt('51000000-0000-4000-8000-000000000002', 30)
  const bd = (await client.query(`select business_date from private.branch_window_at($1, now())`, [SKV])).rows[0].business_date
  const slot = (await client.query(
    `select (x ->> 'starts_at') as s from jsonb_array_elements(public.get_available_slots($1, $2::date, array[$3::uuid])) x
      where (x ->> 'starts_at')::timestamptz > now() + interval '3 hours' limit 1`, [SKV, bd, thai60])).rows[0].s

  // -------------------------------------------------------------------------
  // A. จองเวลาเดียวกันพร้อมกัน 30 รายการ (เบาะนวดไทย SKV มี 4)
  // -------------------------------------------------------------------------
  const a = await parallel(30, (i) => asUser(pool, NAPA,
    `select public.staff_create_booking($1, '60000000-0000-4000-8000-000000000003', $2, array[$3::uuid], null, false, $4)`,
    [SKV, slot, thai60, `race-booking-key-0000000${String(i).padStart(4,"0")}`]))
  const peak = (await client.query(
    `select coalesce(sum(quantity), 0)::int as n from public.resource_allocations
      where branch_id = $1 and resource_type_id = '70000000-0000-4000-8000-000000000001'
        and status in ('HELD', 'RESERVED', 'IN_USE') and starts_at <= $2::timestamptz and ends_at > $2::timestamptz`, [SKV, slot])).rows[0].n
  check('A. จองพร้อมกัน 30 รายการ เวลาเดียวกัน → สำเร็จ 4 (เท่าจำนวนเบาะ) ไม่เกินจำนวน',
    a.filter((r) => r.ok).length === 4 && peak === 4, `สำเร็จ ${a.filter((r) => r.ok).length}, ใช้เบาะ ${peak}/4; ${summary(errs(a))}`)

  // -------------------------------------------------------------------------
  // B. Idempotency-Key เดียวกันพร้อมกัน 20 ครั้ง → สร้างการจองครั้งเดียว
  // -------------------------------------------------------------------------
  const slot2 = (await client.query(
    `select (x ->> 'starts_at') as s from jsonb_array_elements(public.get_available_slots($1, $2::date, array[$3::uuid])) x
      where (x ->> 'starts_at')::timestamptz > now() + interval '5 hours' limit 1`, [SKV, bd, foot30])).rows[0].s
  const before = (await client.query('select count(*)::int n from public.bookings')).rows[0].n
  const b = await parallel(20, () => asUser(pool, NAPA,
    `select public.staff_create_booking($1, '60000000-0000-4000-8000-000000000003', $2, array[$3::uuid], null, false, 'same-key-000000000001') as r`,
    [SKV, slot2, foot30]))
  const after = (await client.query('select count(*)::int n from public.bookings')).rows[0].n
  const ids = new Set(b.filter((r) => r.ok).map((r) => r.rows[0].r.booking_id))
  check('B. Idempotency-Key เดียวกัน 20 ครั้งพร้อมกัน → การจองเดียว', after - before === 1 && ids.size === 1,
    `เพิ่ม ${after - before} การจอง; ตอบสำเร็จ ${b.filter((r) => r.ok).length}; ${summary(errs(b))}`)

  // -------------------------------------------------------------------------
  // C. เปิดกะพร้อมกัน 10 เครื่อง → 1 กะ
  // -------------------------------------------------------------------------
  const c = await parallel(10, () => asUser(pool, NAPA, `select public.pos_open_session($1, 1000, null)`, [SKV]))
  const open = (await client.query(`select count(*)::int n from public.pos_sessions where branch_id = $1 and status = 'OPEN'`, [SKV])).rows[0].n
  check('C. เปิดกะพร้อมกัน 10 เครื่อง → เปิดได้กะเดียว', open === 1 && c.filter((r) => r.ok).length === 1, summary(errs(c)))

  // -------------------------------------------------------------------------
  // D. Walk-in พร้อมกัน 20 รายการ → เลขคิวไม่ซ้ำ ไม่ข้าม
  // -------------------------------------------------------------------------
  const starts = (await asUser(pool, NAPA,
    `select (x ->> 'starts_at') as s from jsonb_array_elements(public.pos_available_starts($1, array[$2::uuid])) x`, [SKV, foot30])).rows.map((r) => r.s)
  // ข้ามทีละ 8 ช่อง (40 นาที) ให้เก้าอี้ว่างทุกช่อง
  const d = await parallel(20, (i) => asUser(pool, NAPA,
    `select public.pos_create_walkin($1, null, $2, array[$3::uuid], null, $4) as r`, [SKV, starts[(i % 7) * 8], foot30, `race-walkin-key-0000000${String(i).padStart(4,"0")}`]))
  const qn = (await client.query(`select queue_number from public.queue_items where branch_id = $1 order by 1`, [SKV])).rows.map((r) => r.queue_number)
  const okD = d.filter((r) => r.ok).length
  const contiguous = qn.every((n, i) => n === i + 1)
  check('D. Walk-in พร้อมกัน 20 รายการ → เลขคิวไม่ซ้ำและไม่ข้าม', contiguous && qn.length === okD,
    `สำเร็จ ${okD}, เลขคิว ${qn[0]}..${qn[qn.length - 1]} (${qn.length} ใบ); ${summary(errs(d))}`)

  // -------------------------------------------------------------------------
  // E. หมอคนเดียวถูกเรียกพร้อมกัน 10 คิว → รับได้คิวเดียว
  // -------------------------------------------------------------------------
  const queues = (await client.query(`select id from public.queue_items where branch_id = $1 and status = 'WAITING' order by queue_number limit 10`, [SKV])).rows.map((r) => r.id)
  const e = await parallel(queues.length, (i) => asUser(pool, NAPA, `select public.queue_call($1, $2)`, [queues[i], E_NAPA]))
  const active = (await client.query(`select count(*)::int n from public.service_assignments where employee_id = $1 and status in ('ASSIGNED','ACCEPTED','IN_SERVICE')`, [E_NAPA])).rows[0].n
  check('E. เรียกหมอคนเดียวพร้อมกัน 10 คิว → ได้คิวเดียว', active === 1 && e.filter((r) => r.ok).length === 1, summary(errs(e)))

  // -------------------------------------------------------------------------
  // F. รับเงิน Invoice เดียวพร้อมกัน 10 ครั้ง (คนละ key) → รับครั้งเดียว ไม่เกินยอด
  // -------------------------------------------------------------------------
  // F/G ทดสอบการเงิน ไม่ใช่ capacity: เพิ่มเก้าอี้ให้เริ่มคิวไหนก็ได้ตอนนี้
  await client.query(`update public.branch_resources set total_quantity = 50 where branch_id = $1 and resource_type_id = '70000000-0000-4000-8000-000000000002'`, [SKV])
  const q1 = (await client.query(`select queue_item_id from public.service_assignments where employee_id = $1 and status = 'ASSIGNED'`, [E_NAPA])).rows[0].queue_item_id
  const others = queues.filter((x) => x !== q1)
  for (const fn of ['queue_accept', 'queue_start']) {
    const r = await asUser(pool, NAPA, `select public.${fn}($1)`, [q1])
    if (!r.ok) throw new Error(fn + ': ' + r.error.message)
  }
  const order1 = (await client.query(`select i.service_order_id from public.queue_items q join public.service_order_items i on i.id = q.service_order_item_id where q.id = $1`, [q1])).rows[0].service_order_id
  const inv = await asUser(pool, NAPA, `select public.pos_issue_invoice((public.pos_create_invoice($1) ->> 'invoice_id')::uuid) as r`, [order1])
  if (!inv.ok) throw inv.error
  const invoiceId = inv.rows[0].r.invoice_id
  const total = Number(inv.rows[0].r.total)
  const f = await parallel(10, (i) => asUser(pool, NAPA,
    `select public.pos_record_payment($1, 'CASH', $2, null, null, 0, null, $3)`, [invoiceId, total, `race-pay-key-0000000${String(i).padStart(4,"0")}`]))
  const paid = (await client.query(`select coalesce(sum(amount), 0)::numeric n from public.payments where invoice_id = $1 and status = 'SUCCESS'`, [invoiceId])).rows[0].n
  check('F. รับเงิน Invoice เดียวพร้อมกัน 10 ครั้ง → รับครั้งเดียว ไม่เกินยอด', Number(paid) === total && f.filter((r) => r.ok).length === 1,
    `รับรวม ${paid}/${total}; ${summary(errs(f))}`)

  // -------------------------------------------------------------------------
  // G. สลิปเดียว (เลขอ้างอิงเดียว) ใช้กับ 2 Invoice พร้อมกัน → ใช้ได้ครั้งเดียว
  // -------------------------------------------------------------------------
  const invs = []
  for (const qid of others.slice(0, 2)) {
    await asUser(pool, NAPA, `update public.queue_items set status = status where false`, [])
    const other = await asUser(pool, NAPA, `select public.queue_call($1, $2)`, [qid, E_DAO])
    if (!other.ok) {
      // ดาวมีคิวแล้ว ใช้ OWNER override ไม่ได้ — ใช้คิวเดียวกับดาวรอบเดียว
    }
  }
  await asUser(pool, NAPA, `select public.queue_accept($1)`, [others[0]])
  await asUser(pool, NAPA, `select public.queue_start($1)`, [others[0]])
  await asUser(pool, NAPA, `select public.queue_complete($1)`, [q1])
  await asUser(pool, NAPA, `select public.queue_call($1, $2)`, [others[1], E_NAPA])
  await asUser(pool, NAPA, `select public.queue_accept($1)`, [others[1]])
  await asUser(pool, NAPA, `select public.queue_start($1)`, [others[1]])
  for (const qid of [others[0], others[1]]) {
    const o = (await client.query(`select i.service_order_id from public.queue_items q join public.service_order_items i on i.id = q.service_order_item_id where q.id = $1`, [qid])).rows[0].service_order_id
    const r = await asUser(pool, NAPA, `select public.pos_issue_invoice((public.pos_create_invoice($1) ->> 'invoice_id')::uuid) as r`, [o])
    invs.push(r.rows[0].r)
  }
  const checks = []
  for (const iv of invs) {
    const r = await asUser(pool, SERVICE,
      `select public.record_payment_slip_check($1, $2, $3, $4, 'VERIFIED', null, 'ok', $5::jsonb) as r`,
      [NAPA.sub, iv.invoice_id, `${COMPANY}/${SKV}/${iv.invoice_id}/s.jpg`, iv.total, JSON.stringify({ trans_ref: 'SAMESLIP001', amount: Number(iv.total) })])
    checks.push(r.rows[0].r)
  }
  const g = await parallel(2, (i) => asUser(pool, NAPA,
    `select public.pos_record_payment($1, 'QR', $2, $3, null, 0, null, $4)`, [invs[i].invoice_id, invs[i].total, checks[i].slip_check_id, `race-slip-key-0000000${String(i).padStart(4,"0")}`]))
  const used = (await client.query(`select count(*)::int n from public.payments where slip_trans_ref = 'SAMESLIP001' and status = 'SUCCESS'`)).rows[0].n
  check('G. สลิปเดียวกันใช้กับ 2 Invoice พร้อมกัน → ใช้ได้ครั้งเดียว', used === 1, `สำเร็จ ${g.filter((r) => r.ok).length}; ${summary(errs(g))}`)

  // -------------------------------------------------------------------------
  // H. กด PIN ผิดพร้อมกัน 20 ครั้ง → ล็อก PIN, ไม่มีครั้งที่ผ่าน
  // -------------------------------------------------------------------------
  const dev = await asUser(pool, OWNER, `select public.pair_branch_device($1, 'race-device') as r`, [SKV])
  const token = dev.rows[0].r.device_token
  const h = await parallel(20, () => asUser(pool, SERVICE, `select public.device_verify_staff_pin($1, $2, '999999', null) as r`, [token, NAPA.sub]))
  const verdicts = h.filter((r) => r.ok).map((r) => r.rows[0].r.error_code ?? (r.rows[0].r.ok ? 'OK' : '?'))
  const locked = (await client.query(`select locked_until > now() as l from public.staff_pins where user_id = $1`, [NAPA.sub])).rows[0].l
  const right = await asUser(pool, SERVICE, `select public.device_verify_staff_pin($1, $2, '246810', null) as r`, [token, NAPA.sub])
  check('H. กด PIN ผิดพร้อมกัน 20 ครั้ง → ถูกล็อก และ PIN ถูกก็เข้าไม่ได้ระหว่างล็อก',
    locked && !verdicts.includes('OK') && right.rows[0].r.error_code === 'PIN_LOCKED', summary(verdicts))

  // -------------------------------------------------------------------------
  // I. สร้างรอบจ่ายค่ามือพร้อมกัน 5 ครั้ง → ร่างเดียว
  // -------------------------------------------------------------------------
  const i5 = await parallel(5, () => asUser(pool, OWNER, `select public.create_commission_payout($1, $2::date - 1)`, [COMPANY, bd]))
  const drafts = (await client.query(`select count(*)::int n from public.commission_payouts where status = 'DRAFT'`)).rows[0].n
  check('I. สร้างรอบจ่ายพร้อมกัน 5 ครั้ง → ร่างเดียว', drafts === 1, summary(errs(i5)))

  // -------------------------------------------------------------------------
  // J. Guest จองพร้อมกัน 10 รายการ เบอร์เดียวกัน (จำกัด 3 การจองค้าง/เบอร์)
  // -------------------------------------------------------------------------
  const privacy = (await client.query(`select public.get_current_policies('IFEEW') -> 'PRIVACY_NOTICE' ->> 'id' as id`)).rows[0].id
  const slots = (await client.query(
    `select (x ->> 'starts_at') as s from jsonb_array_elements(public.get_available_slots($1, $2::date + 1, array[$3::uuid])) x limit 10`,
    [SKV, bd, foot30])).rows.map((r) => r.s)
  const j = await parallel(10, (i) => asUser(pool, SERVICE,
    `select public.create_guest_booking('IFEEW', $1, $2, array[$3::uuid], 'ทดสอบ', 'พร้อมกัน', '0891234567', null, null, $4, $5)`,
    [SKV, slots[i], foot30, privacy, `race-guest-key-0000000${String(i).padStart(4,"0")}`]))
  const guestActive = (await client.query(
    `select count(*)::int n from public.bookings b join public.customers c on c.id = b.customer_id
      where c.phone = '0891234567' and b.status in ('PENDING', 'CONFIRMED')`)).rows[0].n
  check('J. Guest เบอร์เดียวจองพร้อมกัน 10 รายการ → ไม่เกิน 3 การจองค้าง', guestActive <= 3,
    `การจองค้าง ${guestActive}; สำเร็จ ${j.filter((r) => r.ok).length}; ${summary(errs(j))}`)
} catch (e) {
  console.error('SCRIPT ERROR', e)
  results.push({ name: 'script', pass: false })
} finally {
  await pool.end()
  await client.end()
  await server.stop()
}
const failed = results.filter((r) => !r.pass).length
console.log(failed ? `\n${failed} scenario(s) failed` : '\nAll concurrency scenarios passed')
process.exitCode = failed ? 1 : 0
