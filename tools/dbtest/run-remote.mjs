// รัน pgTAP tests บนฐานข้อมูล Supabase จริง (staging) โดยไม่ทิ้งข้อมูลไว้
//   DATABASE_URL=postgresql://postgres.<ref>:<password>@<pooler-host>:5432/postgres node run-remote.mjs ../..
// แต่ละไฟล์: BEGIN → pgTAP shim → seed.sql → test → อ่านผล → ROLLBACK (staging ไม่มี seed/ข้อมูลทดสอบค้าง)
// ห้ามรันกับ Production
import fs from 'node:fs'
import path from 'node:path'
import pg from 'pg'

const root = process.argv[2]
const url = process.env.DATABASE_URL
if (!url) {
  console.error('ต้องกำหนด DATABASE_URL')
  process.exit(1)
}
const read = (p) => fs.readFileSync(p, 'utf8')
const boot = read(new URL('./bootstrap.sql', import.meta.url))
const shim = boot.slice(boot.indexOf('create table extensions.__tap'), boot.indexOf('-- storage stub'))
const seed = read(path.join(root, 'supabase', 'seed.sql'))

const client = new pg.Client({ connectionString: url, ssl: { rejectUnauthorized: false } })
await client.connect()
const { rows } = await client.query('select count(*)::int n from public.companies')
if (rows[0].n > 0) {
  console.error('ฐานข้อมูลนี้มีบริษัทอยู่แล้ว — สคริปต์นี้ใช้กับ staging ที่ว่างเท่านั้น')
  process.exit(1)
}

let failed = 0
const dir = path.join(root, 'supabase', 'tests', 'database')
for (const f of fs.readdirSync(dir).sort()) {
  const sql = read(path.join(dir, f))
    .replace(/begin;/i, '')
    .replace(/create extension if not exists pgtap[^;]*;/i, '')
    .replace(/^\s*rollback;\s*$/m, '')
  try {
    await client.query('begin')
    await client.query('set local search_path = "$user", public, extensions')
    await client.query(shim)
    await client.query(seed)
    await client.query(sql)
    const res = await client.query('select ok, descr, diag from extensions.__tap order by n')
    const planned = Number((sql.match(/select plan\((\d+)\)/) || [])[1])
    const bad = res.rows.filter((r) => !r.ok)
    console.log(`${bad.length || res.rows.length !== planned ? 'FAIL ' : 'PASS '} ${f}: ${res.rows.length - bad.length}/${planned}`)
    for (const r of bad) console.log('      ✗', r.descr, '|', r.diag)
    if (bad.length || res.rows.length !== planned) failed++
  } catch (e) {
    console.log('ERROR', f, e.message)
    failed++
  } finally {
    await client.query('rollback').catch(() => {})
  }
}
await client.end()
console.log(failed ? `\n${failed} test file(s) failed` : '\nAll test files passed (Supabase)')
process.exitCode = failed ? 1 : 0
