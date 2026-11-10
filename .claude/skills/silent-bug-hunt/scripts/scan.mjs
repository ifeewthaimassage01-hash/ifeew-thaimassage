#!/usr/bin/env node
// สแกนหา "บัคเงียบ" และไฟล์/โค้ดที่ไม่ได้ใช้ ใน ifeew-thaimassage (Nuxt 4 layers + Supabase + Edge Functions)
// ผลลัพธ์เป็น "ผู้ต้องสงสัย" ไม่ใช่ข้อสรุป — ต้องเปิดไฟล์ยืนยันทุกข้อก่อนรายงาน
//
// ใช้: node .claude/skills/silent-bug-hunt/scripts/scan.mjs [--root <repo>] [--only <check,...>] [--json]
// checks: swallowed-error, unchecked-supabase, write-only-state, storage-key,
//         rpc, table, edge-function, deno-env, unused-component, unused-export, unlinked-page

import fs from 'node:fs'
import path from 'node:path'

const args = process.argv.slice(2)
const argVal = (k) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : undefined }
const ROOT = path.resolve(argVal('--root') ?? process.cwd())
const ONLY = argVal('--only')?.split(',')
const AS_JSON = args.includes('--json')
const enabled = (c) => !ONLY || ONLY.includes(c)

const SKIP_DIRS = new Set(['node_modules', '.nuxt', '.output', 'dist', '.git', '.temp', '.claude', 'results'])
function walk(dir, exts, out = []) {
  if (!fs.existsSync(dir)) return out
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP_DIRS.has(e.name)) continue
    const p = path.join(dir, e.name)
    if (e.isDirectory()) walk(p, exts, out)
    else if (exts.some((x) => e.name.endsWith(x))) out.push(p)
  }
  return out
}
const rel = (p) => path.relative(ROOT, p).split(path.sep).join('/')
const cache = new Map()
const read = (p) => { if (!cache.has(p)) cache.set(p, fs.readFileSync(p, 'utf8')); return cache.get(p) }
const lineOf = (text, idx) => text.slice(0, idx).split('\n').length
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

// ---------------------------------------------------------------------------
const appFiles = [
  ...walk(path.join(ROOT, 'apps'), ['.vue', '.ts', '.mjs']),
  ...walk(path.join(ROOT, 'packages'), ['.vue', '.ts', '.mjs']),
].filter((f) => !f.endsWith('.d.ts') && !f.endsWith('database.types.ts'))
const fnFiles = walk(path.join(ROOT, 'supabase', 'functions'), ['.ts'])
const migFiles = walk(path.join(ROOT, 'supabase', 'migrations'), ['.sql']).sort()
const codeFiles = [...appFiles, ...fnFiles]
const allSql = migFiles.map(read).join('\n')

const findings = []
const add = (check, severity, file, line, msg) => findings.push({ check, severity, file: file ? rel(file) : null, line, msg })

/** ไฟล์ที่มีคำนี้ (ทั้งคำ) นอกจากไฟล์ที่ยกเว้น */
function usedElsewhere(word, exclude = () => false, files = codeFiles) {
  const re = new RegExp(`\\b${esc(word)}\\b`)
  return files.filter((f) => !exclude(f) && re.test(read(f)))
}

// ---------------------------------------------------------------------------
// 1) catch ที่กลืน error โดยไม่ทำอะไร
if (enabled('swallowed-error')) {
  const pats = [
    [/catch\s*(\([^)]*\))?\s*\{(\s|\/\/[^\n]*|\/\*[\s\S]*?\*\/)*\}/g, 'catch ว่าง (มีแต่คอมเมนต์หรือไม่มีอะไร)'],
    [/\.catch\(\s*(\(\s*\w*\s*\)|\w+)\s*=>\s*(\{\s*\}|null|undefined|void 0|false|\[\])\s*\)/g, '.catch(() => {}) ทิ้ง error'],
  ]
  for (const f of codeFiles) {
    const t = read(f)
    for (const [re, msg] of pats) for (const m of t.matchAll(re)) add('swallowed-error', 'medium', f, lineOf(t, m.index), msg)
  }
}

// 2) ผล supabase-js ที่ไม่ได้ดู error ({ data, error } ไม่ throw เอง)
if (enabled('unchecked-supabase')) {
  for (const f of appFiles) {
    const t = read(f)
    for (const m of t.matchAll(/const\s*\{([^}]*)\}\s*=\s*await\s+(supabase|admin|client)\s*\n?\s*\.(?!auth\b)/g)) {
      if (!/\berror\b/.test(m[1])) add('unchecked-supabase', 'high', f, lineOf(t, m.index), `ดึงแค่ {${m[1].trim()}} ไม่ได้เช็ก error — ถ้า RLS/RPC พังจะได้ data=null เงียบ ๆ`)
    }
    // await supabase.from(...).update/insert/delete(...) แบบไม่เก็บผล และไม่ได้ห่อด้วย must()
    for (const m of t.matchAll(/^[ \t]*await\s+supabase\s*\.(from|rpc|storage)\b[^\n]*/gm)) {
      add('unchecked-supabase', 'high', f, lineOf(t, m.index), 'await supabase... โดยไม่เก็บผล — error ถูกทิ้ง (ใช้ must() หรือเช็ก error)')
    }
  }
}

// 3) state ที่เขียนแต่ไม่เคยอ่าน (เช่น error.value = ... แต่ template ไม่แสดง)
if (enabled('write-only-state')) {
  for (const f of appFiles.filter((x) => x.endsWith('.vue') || /composables/.test(x))) {
    const t = read(f)
    for (const m of t.matchAll(/\b(?:const|let)\s+(\w+)\s*=\s*(?:ref|shallowRef|reactive|useState)\b/g)) {
      const name = m[1]
      const all = [...t.matchAll(new RegExp(`\\b${esc(name)}\\b`, 'g'))].length
      const writes = [...t.matchAll(new RegExp(`\\b${esc(name)}\\.value\\s*=(?!=)`, 'g'))].length
      const exported = new RegExp(`return\\s*\\{[^}]*\\b${esc(name)}\\b`).test(t) // composable ส่งออกไป
      if (!exported && all - 1 - writes === 0) add('write-only-state', writes ? 'high' : 'low', f, lineOf(t, m.index), `'${name}' ${writes ? `ถูกเขียน ${writes} ครั้งแต่ไม่เคยถูกอ่าน/แสดง` : 'ประกาศแล้วไม่ได้ใช้'}`)
    }
  }
}

// 4) localStorage/sessionStorage key ที่เขียนแต่ไม่อ่าน หรืออ่านแต่ไม่มีใครเขียน
if (enabled('storage-key')) {
  const sets = new Map(), gets = new Map()
  for (const f of appFiles) {
    const t = read(f)
    for (const m of t.matchAll(/(?:local|session)Storage\.(setItem|getItem|removeItem)\(\s*['"`]([^'"`]+)['"`]/g)) {
      const map = m[1] === 'getItem' ? gets : m[1] === 'setItem' ? sets : null
      if (map && !map.has(m[2])) map.set(m[2], [f, lineOf(t, m.index)])
    }
    for (const m of t.matchAll(/useLocalStorage\(\s*['"`]([^'"`]+)['"`]/g)) { sets.set(m[1], [f, 0]); gets.set(m[1], [f, 0]) }
  }
  // อ่านเฉพาะเพื่อเอามาต่อท้ายแล้วเขียนกลับ — ไม่มีหน้าไหนเอาข้อมูลไปแสดง/ใช้จริง
  for (const [k] of sets) {
    if (!gets.has(k)) continue
    const reads = [], writes = []
    const keyRe = new RegExp(`(?:local|session)Storage\\.(getItem|setItem)\\(\\s*['"\`]${esc(k)}['"\`]`, 'g')
    for (const f of appFiles) for (const m of read(f).matchAll(keyRe)) (m[1] === 'getItem' ? reads : writes).push([f, m.index])
    if (reads.every(([f, i]) => writes.some(([g, j]) => g === f && j > i && j - i < 400))) {
      const [f, i] = writes[0]
      add('storage-key', 'medium', f, lineOf(read(f), i), `'${k}' ถูกอ่านแค่ตอนจะเขียนทับตัวเอง — ไม่มีที่ไหนเอาข้อมูลไปใช้จริง`)
    }
  }
  for (const [k, [f, l]] of sets) if (!gets.has(k)) add('storage-key', 'medium', f, l, `เก็บ '${k}' ลงเครื่องแต่ไม่มีที่ไหนอ่าน`)
  for (const [k, [f, l]] of gets) if (!sets.has(k)) add('storage-key', 'medium', f, l, `อ่าน '${k}' แต่ไม่มีที่ไหนเขียน (หรือเขียนด้วยชื่อ key อื่น)`)
}

// 5) RPC: เรียกแต่ไม่มีใน migrations / public function ที่ไม่มีใครเรียก
const sqlFns = new Map() // name -> [file, line] ของครั้งล่าสุด
for (const f of migFiles) {
  // ไล่ตามลำดับคำสั่งในไฟล์ (rename แล้ว create ชื่อเดิมใหม่ในไฟล์เดียวกันเป็นเรื่องปกติ)
  const t = read(f)
  const re = /create\s+(?:or\s+replace\s+)?function\s+public\.(\w+)\s*\(|drop\s+function\s+(?:if\s+exists\s+)?public\.(\w+)|alter\s+function\s+public\.(\w+)[^;]*?(?:rename\s+to\s+(\w+)|set\s+schema\s+(\w+))/gi
  for (const m of t.matchAll(re)) {
    if (m[1]) sqlFns.set(m[1], [f, lineOf(t, m.index)])
    else if (m[2]) sqlFns.delete(m[2])
    else if (m[3]) { const v = sqlFns.get(m[3]); sqlFns.delete(m[3]); if (m[4] && v) sqlFns.set(m[4], v) }
  }
}
if (enabled('rpc')) {
  const called = new Map()
  for (const f of codeFiles) {
    const t = read(f)
    for (const m of t.matchAll(/\.rpc\(\s*['"`](\w+)['"`]/g)) if (!called.has(m[1])) called.set(m[1], [f, lineOf(t, m.index)])
  }
  for (const [n, [f, l]] of called) if (!sqlFns.has(n)) add('rpc', 'high', f, l, `เรียก rpc('${n}') แต่ไม่พบ public.${n} ใน migrations (สะกดผิด/ถูก drop/ย้าย schema?)`)
  for (const [n, [f, l]] of sqlFns) {
    if (called.has(n) || n.startsWith('tg_')) continue
    // ถูกเรียกจาก SQL อื่น (นอกจาก grant/revoke/comment) ถือว่าใช้
    const uses = [...allSql.matchAll(new RegExp(`public\\.${esc(n)}\\b`, 'g'))].length
    const meta = [...allSql.matchAll(new RegExp(`(grant|revoke|comment on|alter)[^;]*public\\.${esc(n)}\\b`, 'gi'))].length
    const defs = [...allSql.matchAll(new RegExp(`function\\s+public\\.${esc(n)}\\s*\\(`, 'gi'))].length
    if (uses - meta - defs <= 0) add('rpc', 'low', f, l, `public.${n} ไม่มีโค้ดฝั่ง app/function เรียก (อาจเป็น cron/pg_net หรือโค้ดตาย)`)
  }
}

// 6) ตาราง/วิวที่ .from('x') แต่ไม่มีใน migrations
if (enabled('table')) {
  const rels = new Set()
  for (const m of allSql.matchAll(/create\s+(?:or\s+replace\s+)?(?:table|view|materialized\s+view)\s+(?:if\s+not\s+exists\s+)?public\.(\w+)/gi)) rels.add(m[1])
  for (const m of allSql.matchAll(/alter\s+table\s+public\.(\w+)\s+rename\s+to\s+(\w+)/gi)) rels.add(m[2])
  const buckets = new Set([...allSql.matchAll(/storage\.buckets[^;]*?values\s*\(\s*'([^']+)'/gi)].map((m) => m[1]))
  for (const f of codeFiles) {
    const t = read(f)
    for (const m of t.matchAll(/(?<!storage)\.from\(\s*['"`](\w[\w-]*)['"`]/g)) {
      const before = t.slice(Math.max(0, m.index - 30), m.index)
      if (/storage\s*$/.test(before)) { if (buckets.size && !buckets.has(m[1])) add('table', 'medium', f, lineOf(t, m.index), `storage bucket '${m[1]}' ไม่พบใน migrations`); continue }
      if (!rels.has(m[1])) add('table', 'high', f, lineOf(t, m.index), `.from('${m[1]}') แต่ไม่พบ table/view public.${m[1]} ใน migrations`)
    }
  }
}

// 7) Edge Functions: เรียก vs มีโฟลเดอร์ vs config.toml
if (enabled('edge-function')) {
  const fnDir = path.join(ROOT, 'supabase', 'functions')
  const dirs = fs.existsSync(fnDir) ? fs.readdirSync(fnDir, { withFileTypes: true }).filter((d) => d.isDirectory() && !d.name.startsWith('_')).map((d) => d.name) : []
  const cfgPath = path.join(ROOT, 'supabase', 'config.toml')
  const cfg = fs.existsSync(cfgPath) ? read(cfgPath) : ''
  const called = new Map()
  for (const f of appFiles) {
    const t = read(f)
    for (const m of t.matchAll(/\b(?:\w*[cC]all\w*|invoke)(?:<[^>]*>)?\(\s*['"`]([\w-]+)['"`]/g)) if (!called.has(m[1])) called.set(m[1], [f, lineOf(t, m.index)])
  }
  for (const [n, [f, l]] of called) if (!dirs.includes(n)) add('edge-function', 'high', f, l, `เรียก function '${n}' แต่ไม่มี supabase/functions/${n}`)
  for (const d of dirs) {
    const idx = path.join(fnDir, d, 'index.ts')
    if (!called.has(d)) add('edge-function', 'medium', idx, 1, `function '${d}' ไม่มีโค้ดฝั่ง app เรียก`)
    const m = cfg.match(new RegExp(`\\[functions\\.${esc(d)}\\][^\\[]*`))
    const head = fs.existsSync(idx) ? read(idx).split('\n').slice(0, 6).join('\n') : ''
    const saysPublic = /ไม่ต้อง\s*login|no auth required|anonymous|verify_jwt\s*=\s*false/i.test(head)
    if (!m && saysPublic) add('edge-function', 'high', idx, 1, `'${d}' บอกว่าไม่ต้อง login แต่ไม่มี [functions.${d}] verify_jwt = false ใน config.toml → gateway ตอบ 401 (browser มักแจ้งเป็น CORS error)`)
    else if (!m) add('edge-function', 'info', idx, 1, `'${d}' ไม่มีใน config.toml (ใช้ verify_jwt = true ค่าเริ่มต้น) — ตรวจว่าตั้งใจให้ต้อง login`)
  }
}

// 8) Deno.env.get ที่ไม่มีใน .env.example
if (enabled('deno-env')) {
  const exPath = path.join(ROOT, 'supabase', 'functions', '.env.example')
  const ex = fs.existsSync(exPath) ? read(exPath) : null
  const builtin = /^SUPABASE_/
  if (ex !== null) {
    const seen = new Set()
    for (const f of fnFiles) {
      const t = read(f)
      for (const m of t.matchAll(/Deno\.env\.get\(\s*['"`](\w+)['"`]/g)) {
        if (seen.has(m[1]) || builtin.test(m[1])) continue
        seen.add(m[1])
        if (!new RegExp(`^\\s*#?\\s*${esc(m[1])}\\s*=`, 'm').test(ex)) add('deno-env', 'medium', f, lineOf(t, m.index), `${m[1]} ไม่อยู่ใน supabase/functions/.env.example — ลืมตั้ง secret ตอน deploy ได้ง่าย`)
      }
    }
  }
}

// 9) คอมโพเนนต์ที่ไม่มีใครใช้ (Nuxt auto-import: ui/ ใช้ชื่อไฟล์, ที่อื่นใช้ path prefix)
const pascal = (s) => s.split(/[-_/]/).filter(Boolean).map((w) => w[0].toUpperCase() + w.slice(1)).join('')
const kebab = (s) => s.replace(/([a-z0-9])([A-Z])/g, '$1-$2').toLowerCase()
if (enabled('unused-component')) {
  const roots = [
    ...['customer', 'staff'].map((a) => [path.join(ROOT, 'apps', a, 'components'), true]),
    [path.join(ROOT, 'packages', 'ui', 'components', 'ui'), false],
    [path.join(ROOT, 'packages', 'ui', 'components'), true],
  ]
  const vueFiles = appFiles.filter((f) => f.endsWith('.vue') || f.endsWith('.ts'))
  const done = new Set()
  for (const [dir, prefix] of roots) {
    for (const f of walk(dir, ['.vue'])) {
      if (done.has(f)) continue
      if (prefix && rel(f).includes('packages/ui/components/ui/')) continue
      done.add(f)
      const sub = path.relative(dir, f).replace(/\.vue$/, '').split(path.sep)
      const file = pascal(sub[sub.length - 1]), dirPre = pascal(sub.slice(0, -1).join('/'))
      const name = !prefix || !dirPre || file.startsWith(dirPre) ? file : dirPre + file // Nuxt ตัด prefix ซ้ำ
      const vendored = rel(f).includes('/components/ui/') // ชิ้นส่วน shadcn-vue ที่ติดมากับชุด ไม่ใช่โค้ดที่เขียนเอง
      const sameDir = (x) => path.dirname(x) === path.dirname(f) || x === f
      const re = new RegExp(`<(${esc(name)}|${esc(kebab(name))})[\\s/>]|\\b${esc(name)}\\b`)
      const users = vueFiles.filter((x) => !sameDir(x) && re.test(read(x)))
      if (!users.length) add('unused-component', vendored ? 'info' : 'low', f, 1, `คอมโพเนนต์ <${name}> ไม่ถูกใช้ที่ไหน (ลบได้ หรือหน้าที่ควรใช้ลืมใส่?)`)
    }
  }
}

// 10) export ใน composables/utils/shared ที่ไม่มีใครใช้
if (enabled('unused-export')) {
  const targets = appFiles.filter((f) => /\/(composables|utils)\//.test(rel(f)) || /packages\/shared\/src\/(?!database\.types)/.test(rel(f)))
  for (const f of targets) {
    const t = read(f)
    for (const m of t.matchAll(/export\s+(?:async\s+)?(?:function|const|class|type|interface|enum)\s+(\w+)/g)) {
      const name = m[1]
      const inFile = [...t.matchAll(new RegExp(`\\b${esc(name)}\\b`, 'g'))].length
      if (!usedElsewhere(name, (x) => x === f).length) add('unused-export', inFile > 1 ? 'info' : 'low', f, lineOf(t, m.index), `export '${name}' ไม่ถูกใช้นอกไฟล์${inFile > 1 ? ' (ใช้ภายในไฟล์เอง — export เกินจำเป็น)' : ' — โค้ดตาย'}`)
    }
  }
}

// 11) หน้า (pages) ที่ไม่มีลิงก์ไปถึง — เข้าได้แค่พิมพ์ URL เอง
if (enabled('unlinked-page')) {
  for (const app of ['customer', 'staff']) {
    const pdir = path.join(ROOT, 'apps', app, 'pages')
    const appCode = appFiles.filter((f) => rel(f).startsWith(`apps/${app}/`) || rel(f).startsWith('packages/'))
    for (const f of walk(pdir, ['.vue'])) {
      let route = '/' + path.relative(pdir, f).replace(/\.vue$/, '').split(path.sep).join('/')
      route = route.replace(/\/index$/, '') || '/'
      if (route === '/' || /login|mfa|set-password|register/.test(route)) continue
      const base = route.split('/[')[0] // /t/[token] -> /t
      const re = new RegExp(`['"\`]${esc(base)}(['"\`/?#$]|\\$\\{)`)
      if (!appCode.some((x) => x !== f && re.test(read(x)))) add('unlinked-page', 'low', f, 1, `หน้า ${route} ไม่มีลิงก์/navigateTo มาที่นี่`)
    }
  }
}

// ---------------------------------------------------------------------------
const order = { high: 0, medium: 1, low: 2, info: 3 }
findings.sort((a, b) => order[a.severity] - order[b.severity] || a.check.localeCompare(b.check) || (a.file ?? '').localeCompare(b.file ?? ''))
if (AS_JSON) {
  console.log(JSON.stringify(findings, null, 2))
} else {
  const by = {}
  for (const x of findings) (by[x.check] ??= []).push(x)
  console.log(`root: ${ROOT}\nผู้ต้องสงสัยทั้งหมด ${findings.length} รายการ (ต้องยืนยันทีละข้อ)\n`)
  for (const [c, xs] of Object.entries(by)) {
    console.log(`## ${c} (${xs.length})`)
    for (const x of xs) console.log(`  [${x.severity}] ${x.file ?? ''}${x.line ? ':' + x.line : ''} — ${x.msg}`)
    console.log()
  }
}
