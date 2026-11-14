// POST /functions/v1/booking-tracking   (ไม่ต้อง login)
// body: { token }                          -> สถานะการจอง (ชื่อปิดบัง ไม่มีค่าแรง) หรือ 404
// body: { token, action: 'cancel', reason? } -> ลูกค้ายกเลิกการจองเอง (กติกาเวลาตรวจใน DB)
import { adminClient, clientIp, json, preflight, rateLimit } from '../_shared/http.ts'

const TOKEN_RE = /^trk_[0-9a-f]{64}$/

Deno.serve(async (req) => {
  const early = preflight(req)
  if (early) return early

  let body: { token?: unknown; action?: unknown; reason?: unknown }
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
    if (body.action === 'cancel') {
      if (!(await rateLimit(admin, `tracking-cancel:ip:${clientIp(req)}`, 10, 600))) {
        return json(req, 429, { error_code: 'RATE_LIMITED' })
      }
      const reason = typeof body.reason === 'string' ? body.reason.slice(0, 500) : ''
      const { data, error } = await admin.rpc('cancel_booking_by_token', { p_token: token, p_reason: reason || null })
      if (error) {
        if (error.code === 'P0002') return json(req, 404, { error_code: 'NOT_FOUND' })
        if (error.code === '23514') return json(req, 400, { error_code: 'INVALID', message: error.message })
        throw error
      }
      return json(req, 200, data)
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
