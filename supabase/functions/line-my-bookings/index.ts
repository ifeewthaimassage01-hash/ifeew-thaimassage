// POST /functions/v1/line-my-bookings   (ไม่ต้อง login Supabase — ยืนยันตัวตนด้วย LINE แทน)
// body: { company_code, id_token }   (id_token = LIFF ID token ของลูกค้า)
// -> { bookings: BookingView[] (มี tracking_token อายุ 30 นาที), profile: { first_name, last_name, phone } | null }
// 1) Rate limit ต่อ IP  2) ยืนยัน ID token กับ LINE (Channel ID ของ LINE Login ที่ร้านตั้งไว้)  3) line_my_bookings
// แสดงเฉพาะการจองที่ผูกกับ LINE คนนี้แล้ว (migration 076)
import { adminClient, clientIp, json, preflight, rateLimit } from '../_shared/http.ts'
import { lineSecret, lineVerifyIdToken } from '../_shared/line.ts'

const CODE_RE = /^[A-Za-z0-9]{2,10}$/

Deno.serve(async (req) => {
  const early = preflight(req)
  if (early) return early

  let body: { company_code?: unknown; id_token?: unknown }
  try {
    body = await req.json()
  } catch {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }
  const companyCode = typeof body.company_code === 'string' ? body.company_code.toUpperCase() : ''
  const idToken = typeof body.id_token === 'string' ? body.id_token : ''
  if (!CODE_RE.test(companyCode) || !idToken || idToken.length > 4096) return json(req, 400, { error_code: 'INVALID_BODY' })

  try {
    const admin = adminClient()
    if (!(await rateLimit(admin, `line-my-bookings:ip:${clientIp(req)}`, 30, 600))) {
      return json(req, 429, { error_code: 'RATE_LIMITED' })
    }
    const cfg = await lineSecret(admin, { companyCode })
    if (!cfg?.login_channel_id) {
      return json(req, 400, { error_code: 'LINE_DISABLED', message: 'ร้านยังไม่ได้เปิดใช้การเข้าสู่ระบบด้วย LINE' })
    }
    const userId = await lineVerifyIdToken(cfg.login_channel_id, idToken)
    if (!userId) {
      return json(req, 401, { error_code: 'LINE_TOKEN_INVALID', message: 'การเข้าสู่ระบบด้วย LINE หมดอายุ กรุณาเข้าสู่ระบบอีกครั้ง' })
    }
    const { data, error } = await admin.rpc('line_my_bookings', { p_company_code: companyCode, p_line_user_id: userId })
    if (error) throw error
    return json(req, 200, data ?? { bookings: [], profile: null })
  } catch (e) {
    console.error('line-my-bookings', e)
    return json(req, 500, { error_code: 'INTERNAL_ERROR' })
  }
})
