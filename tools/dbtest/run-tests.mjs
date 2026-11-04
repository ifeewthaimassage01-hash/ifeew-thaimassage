// รัน pgTAP tests ของโปรเจกต์บน Postgres จริง (เทียบกับ PGlite)
import fs from 'node:fs'
import path from 'node:path'
import { startDb } from './db.mjs'

const root = process.argv[2]
const { server, client } = await startDb(root)
let failed = 0
try {
  const dir = path.join(root, 'supabase', 'tests', 'database')
  for (const f of fs.readdirSync(dir).sort()) {
    const sql = fs.readFileSync(path.join(dir, f), 'utf8')
      .replace(/create extension if not exists pgtap[^;]*;/i, '')
      .replace(/^\s*rollback;\s*$/m, '')
    await client.query('truncate extensions.__tap restart identity')
    try {
      await client.query(sql)
    } catch (e) {
      console.log('ERROR', f, e.message)
      failed++
      await client.query('rollback').catch(() => {})
      continue
    }
    const res = await client.query('select ok, descr, diag from extensions.__tap order by n')
    const planned = Number((sql.match(/select plan\((\d+)\)/) || [])[1])
    await client.query('rollback')
    const bad = res.rows.filter((r) => !r.ok)
    console.log(`${bad.length || res.rows.length !== planned ? 'FAIL ' : 'PASS '} ${f}: ${res.rows.length - bad.length}/${planned}`)
    for (const r of bad) console.log('      ✗', r.descr, '|', r.diag)
    if (bad.length || res.rows.length !== planned) failed++
  }
} finally {
  await client.end()
  await server.stop()
}
console.log(failed ? `\n${failed} test file(s) failed` : '\nAll test files passed (real Postgres)')
process.exit(failed ? 1 : 0)
