// POST /functions/v1/booking-tracking   (ไม่ต้อง login)
// body: { token }  -> สถานะการจอง (ชื่อปิดบัง ไม่มีค่าแรง) หรือ 404
import { adminClient, clientIp, json, preflight, rateLimit } from '../_shared/http.ts'

const TOKEN_RE = /^trk_[0-9a-f]{64}$/

Deno.serve(async (req) => {
  const early = preflight(req)
  if (early) return early

  let body: { token?: unknown }
  try {
    body = await req.json()
  } catch {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }
  const token = typeof body.token === 'string' ? body.token : ''
  if (!TOKEN_RE.test(token)) return json(req, 404, { error_code: 'NOT_FOUND' })

  try {
    const admin = adminClient()
    if (!(await rateLimit(admin, `tracking:ip:${clientIp(req)}`, 60, 60))) {
      return json(req, 429, { error_code: 'RATE_LIMITED' })
    }
    const { data, error } = await admin.rpc('get_booking_by_token', { p_token: token })
    if (error) throw error
    if (!data) return json(req, 404, { error_code: 'NOT_FOUND' })
    return json(req, 200, data)
  } catch (e) {
    console.error('booking-tracking', e)
    return json(req, 500, { error_code: 'INTERNAL_ERROR' })
  }
})
