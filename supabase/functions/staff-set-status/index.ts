// POST /functions/v1/staff-set-status   (ต้องมี JWT ของ OWNER ที่เพิ่งยืนยัน TOTP)
// body: { employee_id, status: ACTIVE | INACTIVE | RESIGNED, reason }
// 1) set_employee_status ด้วย JWT ของผู้เรียก (DB คือแหล่งความจริง: ปิดสิทธิ์ทันทีผ่าน RLS)
// 2) ban / unban บัญชีใน Auth เพื่อตัด refresh token ของ session ที่ค้างอยู่
import { adminClient, dbErrorResponse, json, preflight, userClient, UUID_RE } from '../_shared/http.ts'

const STATUSES = new Set(['ACTIVE', 'INACTIVE', 'RESIGNED'])
const BAN_FOREVER = '876000h'

Deno.serve(async (req) => {
  const early = preflight(req)
  if (early) return early

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }

  const employeeId = String(body.employee_id ?? '')
  const status = String(body.status ?? '')
  const reason = String(body.reason ?? '').trim()
  if (!UUID_RE.test(employeeId) || !STATUSES.has(status) || reason.length < 3 || reason.length > 500) {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }

  const { data, error } = await userClient(req).rpc('set_employee_status', {
    p_employee_id: employeeId,
    p_status: status,
    p_reason: reason,
  })
  if (error) return dbErrorResponse(req, error)

  const result = data as { user_id: string; status: string }
  const { error: banErr } = await adminClient().auth.admin.updateUserById(result.user_id, {
    ban_duration: result.status === 'ACTIVE' ? 'none' : BAN_FOREVER,
  })
  if (banErr) {
    // สิทธิ์ใน DB เปลี่ยนแล้ว (RLS ปิดการเข้าถึงทันที) แจ้งให้ลองซ้ำเพื่อ sync สถานะ Auth
    console.error('staff-set-status ban sync failed', result.user_id, banErr)
    return json(req, 207, { ...result, auth_synced: false })
  }

  return json(req, 200, { ...result, auth_synced: true })
})
