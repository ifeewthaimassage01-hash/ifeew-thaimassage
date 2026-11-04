// POST /functions/v1/customer-erasure   (ต้องมี JWT ของ OWNER ที่เพิ่งยืนยัน TOTP)
// body: { request_id, approve: boolean, note? }
// 1) process_data_deletion ด้วย JWT ของผู้เรียก (anonymize ใน DB ใน Transaction เดียว)
// 2) ถ้าอนุมัติและลูกค้ามีบัญชี: เปลี่ยนอีเมลเป็นค่าที่ไม่ระบุตัวตน ล้าง metadata และ ban บัญชี Auth
import { adminClient, dbErrorResponse, json, preflight, userClient, UUID_RE } from '../_shared/http.ts'

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

  const requestId = String(body.request_id ?? '')
  const approve = body.approve === true
  const note = typeof body.note === 'string' ? body.note.trim() : ''
  if (!UUID_RE.test(requestId) || typeof body.approve !== 'boolean' || note.length > 1000) {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }

  const { data, error } = await userClient(req).rpc('process_data_deletion', {
    p_request_id: requestId,
    p_approve: approve,
    p_note: note || null,
  })
  if (error) return dbErrorResponse(req, error)

  const result = data as { request_id: string; approved: boolean; auth_user_id: string | null }
  if (!result.approved || !result.auth_user_id) return json(req, 200, { ...result, auth_synced: true })

  const uid = result.auth_user_id
  const { error: authErr } = await adminClient().auth.admin.updateUserById(uid, {
    email: `${uid}@deleted.ifeew.internal`,
    phone: '',
    user_metadata: {},
    ban_duration: BAN_FOREVER,
  })
  if (authErr) {
    // ข้อมูลใน DB ถูก anonymize แล้ว แต่ข้อมูลใน Auth ยังไม่ถูกล้าง ต้องดำเนินการซ้ำ
    console.error('customer-erasure auth sync failed', uid, authErr)
    return json(req, 207, { ...result, auth_synced: false })
  }

  return json(req, 200, { ...result, auth_synced: true })
})
