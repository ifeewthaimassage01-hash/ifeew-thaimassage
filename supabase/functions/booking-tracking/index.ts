// POST /functions/v1/booking-tracking   (ไม่ต้อง login)
// body: { token }                          -> สถานะการจอง (ชื่อปิดบัง ไม่มีค่าแรง) หรือ 404
// body: { token, action: 'cancel', reason? } -> ลูกค้ายกเลิกการจองเอง (กติกาเวลาตรวจใน DB)
// body: { token, action: 'line_link', id_token } -> ผูกการจองกับ LINE ของลูกค้า (LIFF ID token) → ส่งยืนยัน + เตือนนัด
import { adminClient, clientIp, corsHeaders, json, preflight, rateLimit } from '../_shared/http.ts'
import { linePush, lineSecret, lineVerifyIdToken, type FlexData } from '../_shared/line.ts'

const TOKEN_RE = /^trk_[0-9a-f]{64}$/

Deno.serve(async (req) => {
  const early = preflight(req)
  if (early) return early

  let body: { token?: unknown; action?: unknown; reason?: unknown; id_token?: unknown }
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
    if (body.action === 'line_link') {
      if (!(await rateLimit(admin, `tracking-line:ip:${clientIp(req)}`, 10, 600))) {
        return json(req, 429, { error_code: 'RATE_LIMITED' })
      }
      const { data: st, error: stErr } = await admin.rpc('line_booking_status', { p_token: token })
      if (stErr) throw stErr
      const status = st as { company_id: string; status: string; linked: boolean } | null
      if (!status) return json(req, 404, { error_code: 'NOT_FOUND' })
      if (!['PENDING', 'CONFIRMED'].includes(status.status)) {
        return json(req, 400, { error_code: 'INVALID', message: 'การจองนี้จบไปแล้ว เชื่อม LINE ไม่ได้' })
      }
      const cfg = await lineSecret(admin, { companyId: status.company_id })
      if (!cfg?.access_token || !cfg.login_channel_id) {
        return json(req, 400, { error_code: 'INVALID', message: 'ร้านยังไม่ได้เปิดใช้การแจ้งเตือนทาง LINE' })
      }
      const userId = await lineVerifyIdToken(cfg.login_channel_id, typeof body.id_token === 'string' ? body.id_token : '')
      if (!userId) return json(req, 400, { error_code: 'INVALID', message: 'ยืนยันบัญชี LINE ไม่สำเร็จ กรุณากดเชื่อม LINE อีกครั้ง' })
      const { data: attached, error: attErr } = await admin.rpc('line_attach_booking', {
        p_token: token,
        p_line_user_id: userId,
        p_site_url: corsHeaders(req)['Access-Control-Allow-Origin'] ?? '',
      })
      if (attErr) throw attErr
      const msg = attached as { text: string; flex: FlexData | null } | null // null = ร้านปิดข้อความยืนยันไว้
      if (msg?.text) await linePush(cfg.access_token, userId, msg.text, msg.flex)
      return json(req, 200, { line_linked: true })
    }

    const { data, error } = await admin.rpc('get_booking_by_token', { p_token: token })
    if (error) throw error
    if (!data) return json(req, 404, { error_code: 'NOT_FOUND' })
    const { data: st } = await admin.rpc('line_booking_status', { p_token: token })
    return json(req, 200, { ...(data as Record<string, unknown>), line_linked: !!(st as { linked?: boolean } | null)?.linked })
  } catch (e) {
    console.error('booking-tracking', e)
    return json(req, 500, { error_code: 'INTERNAL_ERROR' })
  }
})
