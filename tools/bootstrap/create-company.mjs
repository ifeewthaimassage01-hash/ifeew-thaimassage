// สร้างบริษัทแรก + เชิญ OWNER บน Supabase (Production/Staging) — รันครั้งเดียว
//
//   SUPABASE_URL=https://xxxx.supabase.co \
//   SUPABASE_SECRET_KEY=<secret / service_role key> \
//   STAFF_APP_URL=https://ifeew-staff.vercel.app \
//   node create-company.mjs company.json
//
// ขั้นตอน
//   1) เชิญอีเมล OWNER ผ่าน Supabase Auth (OWNER ตั้งรหัสผ่านเองจากอีเมล → หน้า /set-password → ผูก TOTP)
//      ถ้าอีเมลนี้มีบัญชีอยู่แล้ว ใช้บัญชีเดิม (ไม่ส่งอีเมลใหม่)
//   2) bootstrap_company: บริษัท, OWNER membership, สาขา (ยังปิดทำการ), นโยบายความเป็นส่วนตัว
// สคริปต์ไม่มี/ไม่พิมพ์รหัสผ่านใดๆ — key อ่านจาก environment เท่านั้น ห้าม commit ไฟล์ที่มี key
import { createClient } from '@supabase/supabase-js'
import fs from 'node:fs'

const url = process.env.SUPABASE_URL
const key = process.env.SUPABASE_SECRET_KEY ?? process.env.SUPABASE_SERVICE_ROLE_KEY
const staffUrl = process.env.STAFF_APP_URL
const file = process.argv[2]

if (!url || !key || !staffUrl || !file) {
  console.error('ต้องกำหนด SUPABASE_URL, SUPABASE_SECRET_KEY, STAFF_APP_URL และไฟล์ company.json')
  process.exit(1)
}

const payload = JSON.parse(fs.readFileSync(file, 'utf8'))
const email = String(payload.owner_email ?? '').trim().toLowerCase()
if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
  console.error('owner_email ไม่ถูกต้อง')
  process.exit(1)
}
if (!payload.policies?.some((p) => p.type === 'PRIVACY_NOTICE' && String(p.content ?? '').length >= 50)) {
  console.error('ต้องมีนโยบายความเป็นส่วนตัว (PRIVACY_NOTICE) ฉบับจริงใน company.json')
  process.exit(1)
}

const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })

async function findUserByEmail(target) {
  for (let page = 1; page <= 50; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 200 })
    if (error) throw error
    const hit = data.users.find((u) => (u.email ?? '').toLowerCase() === target)
    if (hit) return hit
    if (data.users.length < 200) return null
  }
  return null
}

let user = await findUserByEmail(email)
if (user) {
  console.log(`ใช้บัญชีเดิมของ ${email}`)
} else {
  const { data, error } = await admin.auth.admin.inviteUserByEmail(email, {
    redirectTo: `${staffUrl.replace(/\/$/, '')}/set-password`,
    data: { display_name: payload.owner_display_name ?? '' },
  })
  if (error) {
    console.error('เชิญ OWNER ไม่สำเร็จ:', error.message)
    process.exit(1)
  }
  user = data.user
  console.log(`ส่งอีเมลเชิญไปที่ ${email} แล้ว`)
}

const { data: companyId, error } = await admin.rpc('bootstrap_company', { p_payload: payload, p_owner_user_id: user.id })
if (error) {
  console.error('สร้างบริษัทไม่สำเร็จ:', error.message)
  process.exit(1)
}

console.log(`สร้างบริษัท ${payload.company.code} แล้ว (company_id ${companyId})`)
console.log(`
ขั้นต่อไปสำหรับ OWNER
  1. เปิดอีเมลเชิญ → ตั้งรหัสผ่าน → ผูกแอป Authenticator
  2. เมนู “สาขา”: ตั้งเวลาทำการ/วันหยุด (สาขาใหม่ยังปิดอยู่)
  3. เมนู “บริการและราคา”, “เตียงและอุปกรณ์” (รวมบัญชี PromptPay + SlipOK Branch ID), “พนักงาน”
  4. เมนู “ตั้งค่าเครื่อง”: ผูกแท็บเล็ตหน้าร้านแต่ละสาขา
  5. ตั้ง NUXT_PUBLIC_COMPANY_CODE=${payload.company.code} ใน Customer App`)
