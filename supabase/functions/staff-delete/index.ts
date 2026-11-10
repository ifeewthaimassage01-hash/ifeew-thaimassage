// POST /functions/v1/staff-delete   (ต้องมี JWT ของ OWNER ที่เพิ่งยืนยันตัวตนซ้ำ — step-up)
// body: { employee_id }
// 1) delete_employee ด้วย JWT ของผู้เรียก (DB ตรวจ OWNER + step-up + ห้ามลบตัวเอง/เจ้าของร้าน + ต้องไม่มีประวัติ)
// 2) purge_staff_profile (service role): ลบ profile ถ้าไม่มีอะไรอ้างถึงแล้ว
// 3) ลบบัญชี Auth — ลบ profile ได้ = ลบถาวร · ยังถูกอ้างถึง = soft delete (ล้างอีเมล/login ได้อีกไม่ได้)
import { adminClient, dbErrorResponse, json, preflight, userClient, UUID_RE } from '../_shared/http.ts'

Deno.serve(async (req) => {
  const early = preflight(req)
  if (early) return early
  if (!req.headers.get('authorization')) return json(req, 401, { error_code: 'UNAUTHORIZED' })

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }
  const employeeId = String(body.employee_id ?? '')
  if (!UUID_RE.test(employeeId)) return json(req, 400, { error_code: 'INVALID_BODY' })

  const { data: userId, error } = await userClient(req).rpc('delete_employee', { p_employee_id: employeeId })
  if (error) return dbErrorResponse(req, error)

  const admin = adminClient()
  try {
    const { data: purged, error: purgeErr } = await admin.rpc('purge_staff_profile', { p_user_id: userId })
    if (purgeErr) throw purgeErr
    const { error: delErr } = await admin.auth.admin.deleteUser(String(userId), !purged)
    if (delErr) throw delErr
    return json(req, 200, { user_id: userId, account_deleted: true, hard_deleted: !!purged })
  } catch (e) {
    // ลบพนักงาน/สิทธิ์ใน DB แล้ว (เข้าแอปไม่ได้แล้ว) แต่ลบบัญชี Auth ไม่สำเร็จ — แจ้งผู้ใช้
    console.error('staff-delete account cleanup failed', userId, e)
    return json(req, 207, { user_id: userId, account_deleted: false })
  }
})
