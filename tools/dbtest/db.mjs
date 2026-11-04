// เปิด PostgreSQL จริง (embedded) + โหลด bootstrap/migrations/seed ของโปรเจกต์
import EmbeddedPostgres from 'embedded-postgres'
import pg from 'pg'
import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'

export const PORT = 54329
const read = (p) => fs.readFileSync(p, 'utf8')

export async function startDb(root, { reset = true } = {}) {
  const dir = path.join(os.tmpdir(), 'ifeew-realpg-data')
  if (reset && fs.existsSync(dir)) fs.rmSync(dir, { recursive: true, force: true })
  const server = new EmbeddedPostgres({ databaseDir: dir, user: 'postgres', password: 'postgres', port: PORT, persistent: false, initdbFlags: ['--encoding=UTF8', '--locale=C'], onLog: () => {} })
  if (reset || !fs.existsSync(dir)) await server.initialise()
  await server.start()
  const admin = new pg.Client({ host: '127.0.0.1', port: PORT, user: 'postgres', password: 'postgres', database: 'postgres' })
  await admin.connect()
  if (reset) {
    await admin.query('drop database if exists ifeew')
    await admin.query("create database ifeew encoding 'UTF8' template template0")
  }
  await admin.end()
  const client = newClient()
  await client.connect()
  if (reset) {
    // bootstrap ของ PGlite ใช้ได้กับ Postgres จริง (roles/auth/storage stubs + pgTAP shim)
    await client.query(read(new URL('./bootstrap.sql', import.meta.url)))
    await client.query('alter database ifeew set search_path = "$user", public, extensions')
    await client.query('set search_path = "$user", public, extensions')
    const sb = path.join(root, 'supabase')
    for (const f of fs.readdirSync(path.join(sb, 'migrations')).sort()) {
      try {
        await client.query(read(path.join(sb, 'migrations', f)))
      } catch (e) {
        throw new Error(`migration ${f}: ${e.message}`)
      }
    }
    await client.query(read(path.join(sb, 'seed.sql')))
  }
  return { server, client }
}

export function newClient() {
  return new pg.Client({ host: '127.0.0.1', port: PORT, user: 'postgres', password: 'postgres', database: 'ifeew' })
}

export function newPool(max = 60) {
  return new pg.Pool({ host: '127.0.0.1', port: PORT, user: 'postgres', password: 'postgres', database: 'ifeew', max })
}

/** รันฟังก์ชันใน transaction ในนามผู้ใช้ (เหมือน PostgREST: role authenticated + jwt claims) */
export async function asUser(pool, claims, sql, params = []) {
  const c = await pool.connect()
  try {
    await c.query('begin')
    await c.query("select set_config('request.jwt.claims', $1, true)", [JSON.stringify(claims)])
    await c.query(`set local role ${claims.role === 'service_role' ? 'service_role' : 'authenticated'}`)
    const r = await c.query(sql, params)
    await c.query('commit')
    return { ok: true, rows: r.rows }
  } catch (e) {
    await c.query('rollback').catch(() => {})
    return { ok: false, error: e }
  } finally {
    c.release()
  }
}
