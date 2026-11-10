#!/usr/bin/env node
// ย้ายรูปบริการ/รูปสาขาเดิม (Supabase Storage) ไป Cloudinary แล้วอัปเดต image_path เป็น "cloudinary:<public_id>"
//
// ใช้:  node tools/cloudinary/migrate-images.mjs            (dry-run: แสดงรายการที่จะย้ายเท่านั้น)
//       node tools/cloudinary/migrate-images.mjs --apply    (ย้ายจริง)
//
// ต้องตั้ง env ก่อน (อย่า commit ค่าเหล่านี้):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//   CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET
//
// ปลอดภัยที่จะรันซ้ำ: ข้ามแถวที่เป็น "cloudinary:" แล้ว · ไฟล์เดิมใน Supabase ไม่ถูกลบ
import { createHash } from 'node:crypto'

const APPLY = process.argv.includes('--apply')
const env = (k) => {
  const v = process.env[k]
  if (!v) {
    console.error(`ยังไม่ได้ตั้ง ${k}`)
    process.exit(1)
  }
  return v
}
const SUPABASE_URL = env('SUPABASE_URL').replace(/\/$/, '')
const SERVICE_KEY = env('SUPABASE_SERVICE_ROLE_KEY')
const CLOUD = env('CLOUDINARY_CLOUD_NAME')
const API_KEY = env('CLOUDINARY_API_KEY')
const API_SECRET = env('CLOUDINARY_API_SECRET')

const TARGETS = [
  { table: 'services', kind: 'service', bucket: 'service-images' },
  { table: 'branches', kind: 'branch', bucket: 'branch-images' },
]
const rest = (path, init = {}) =>
  fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, 'Content-Type': 'application/json', ...init.headers },
  })

async function uploadFromUrl(sourceUrl, folder, publicId) {
  const params = { folder, overwrite: 'false', public_id: publicId, timestamp: String(Math.floor(Date.now() / 1000)) }
  const toSign = Object.keys(params).sort().map((k) => `${k}=${params[k]}`).join('&')
  const signature = createHash('sha1').update(toSign + API_SECRET).digest('hex')
  const form = new FormData()
  form.append('file', sourceUrl) // Cloudinary ดึงรูปจาก URL เอง
  form.append('api_key', API_KEY)
  form.append('signature', signature)
  for (const [k, v] of Object.entries(params)) form.append(k, v)
  const res = await fetch(`https://api.cloudinary.com/v1_1/${CLOUD}/image/upload`, { method: 'POST', body: form })
  const out = await res.json()
  if (!res.ok || !out.public_id) throw new Error(out.error?.message ?? `HTTP ${res.status}`)
  return out.public_id
}

let moved = 0
let failed = 0
for (const t of TARGETS) {
  const res = await rest(`${t.table}?select=id,company_id,image_path&image_path=not.is.null&image_path=not.like.cloudinary:*`)
  if (!res.ok) {
    console.error(`อ่าน ${t.table} ไม่สำเร็จ: ${res.status} ${await res.text()}`)
    process.exit(1)
  }
  const rows = await res.json()
  console.log(`\n${t.table}: ${rows.length} รูปที่ยังอยู่ใน Supabase`)
  for (const r of rows) {
    const source = `${SUPABASE_URL}/storage/v1/object/public/${t.bucket}/${r.image_path}`
    const folder = `ifeew/${r.company_id}/${t.kind}s/${r.id}`
    const publicId = `migrated-${r.image_path.split('/').pop().replace(/\.[^.]+$/, '')}`
    if (!APPLY) {
      console.log(`  [dry-run] ${r.id}  ${r.image_path}  →  ${folder}/${publicId}`)
      continue
    }
    try {
      const id = await uploadFromUrl(source, folder, publicId)
      const upd = await rest(`${t.table}?id=eq.${r.id}`, {
        method: 'PATCH',
        headers: { Prefer: 'return=minimal' },
        body: JSON.stringify({ image_path: `cloudinary:${id}` }),
      })
      if (!upd.ok) throw new Error(`อัปเดต DB ไม่สำเร็จ: ${upd.status} ${await upd.text()}`)
      console.log(`  ✓ ${r.id}  →  cloudinary:${id}`)
      moved++
    } catch (e) {
      console.error(`  ✗ ${r.id}  ${r.image_path}: ${e.message}`)
      failed++
    }
  }
}
console.log(APPLY ? `\nเสร็จ: ย้ายแล้ว ${moved} · ไม่สำเร็จ ${failed}` : '\nนี่คือ dry-run — เพิ่ม --apply เพื่อย้ายจริง')
process.exit(failed ? 1 : 0)
