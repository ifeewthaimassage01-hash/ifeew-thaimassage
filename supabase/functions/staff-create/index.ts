// POST /functions/v1/staff-create   (ต้องมี JWT ของ OWNER ที่เพิ่งยืนยัน TOTP)
// body: { company_id, branch_id, employee_code, nickname, start_date (YYYY-MM-DD), pin }
// 1) ตรวจสิทธิ์ล่วงหน้า (assert_can_manage_staff) ด้วย JWT ของผู้เรียก
// 2) สร้าง auth user อีเมลภายใน + รหัสผ่านสุ่ม (ไม่มีใครรู้ login ได้เฉพาะ PIN)
// 3) create_staff_member ด้วย JWT ของผู้เรียก (Transaction เดียวใน DB)
// 4) ถ้าข้อ 3 ล้มเหลว ลบ profile + auth user ที่เพิ่งสร้าง (compensation)
import { adminClient, dbErrorResponse, json, preflight, userClient, UUID_RE } from '../_shared/http.ts'

const STAFF_EMAIL_DOMAIN = 'staff.ifeew.internal'
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/
const CODE_RE = /^[A-Za-z0-9][A-Za-z0-9_-]{0,19}$/

function randomSecret(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32))
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('') + 'Aa1'
}

Deno.serve(async (req) => {
  const early = preflight(req)
  if (early) return early

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }

  const companyId = String(body.company_id ?? '')
  const branchId = String(body.branch_id ?? '')
  const code = String(body.employee_code ?? '').trim()
  const nickname = String(body.nickname ?? '').trim()
  const startDate = String(body.start_date ?? '')
  const pin = String(body.pin ?? '')

  if (
    !UUID_RE.test(companyId) || !UUID_RE.test(branchId) || !CODE_RE.test(code) ||
    nickname.length < 1 || nickname.length > 60 || !DATE_RE.test(startDate) || !/^\d{6}$/.test(pin)
  ) {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }

  const asOwner = userClient(req)
  const admin = adminClient()

  // 1) ตรวจสิทธิ์ก่อนสร้างอะไรใน Auth
  const { error: preErr } = await asOwner.rpc('assert_can_manage_staff', { p_company_id: companyId })
  if (preErr) return dbErrorResponse(req, preErr)

  // 2) สร้างบัญชีภายใน
  const { data: created, error: createErr } = await admin.auth.admin.createUser({
    email: `${crypto.randomUUID()}@${STAFF_EMAIL_DOMAIN}`,
    password: randomSecret(),
    email_confirm: true,
    user_metadata: { display_name: nickname },
  })
  if (createErr || !created.user) {
    console.error('staff-create createUser', createErr)
    return json(req, 500, { error_code: 'INTERNAL_ERROR' })
  }
  const userId = created.user.id

  // 3) สร้างข้อมูลพนักงานทั้งหมดใน DB
  const { data: employeeId, error: dbErr } = await asOwner.rpc('create_staff_member', {
    p_company_id: companyId,
    p_user_id: userId,
    p_branch_id: branchId,
    p_employee_code: code,
    p_nickname: nickname,
    p_start_date: startDate,
    p_pin: pin,
  })

  if (dbErr) {
    // 4) ย้อนการสร้างบัญชี
    const { error: delProfileErr } = await admin.from('profiles').delete().eq('id', userId)
    const { error: delUserErr } = await admin.auth.admin.deleteUser(userId)
    if (delProfileErr || delUserErr) console.error('staff-create rollback failed', userId, delProfileErr, delUserErr)
    return dbErrorResponse(req, dbErr)
  }

  return json(req, 201, { employee_id: employeeId, user_id: userId })
})
