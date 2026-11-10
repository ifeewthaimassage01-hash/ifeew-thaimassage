// POST /functions/v1/guest-booking-lookup   (ไม่ต้อง login)
// body: { company_code, phone, turnstile_token }
// -> { bookings: BookingView[] }  แต่ละรายการมี tracking_token อายุ 30 นาที ไว้เปิด /t/<token>
// 1) Rate limit ต่อ IP และต่อเบอร์  2) Cloudflare Turnstile  3) guest_bookings_by_phone
import { adminClient, clientIp, json, preflight, rateLimit, sha256Hex, verifyTurnstile } from '../_shared/http.ts'

const CODE_RE = /^[A-Za-z0-9]{2,10}$/

Deno.serve(async (req) => {
  const early = preflight(req)
  if (early) return early

  let b: Record<string, unknown>
  try {
    b = await req.json()
  } catch {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }

  const phoneDigits = String(b.phone ?? '').replace(/[^0-9]/g, '')
  if (!CODE_RE.test(String(b.company_code ?? '')) || phoneDigits.length < 9 || phoneDigits.length > 12) {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }

  try {
    const admin = adminClient()
    const ip = clientIp(req)
    const phoneKey = (await sha256Hex(phoneDigits)).slice(0, 32)
    const allowed =
      (await rateLimit(admin, `booking-lookup:ip:${ip}`, 10, 600)) &&
      (await rateLimit(admin, `booking-lookup:phone:${phoneKey}`, 10, 3600))
    if (!allowed) return json(req, 429, { error_code: 'RATE_LIMITED' })

    if (!(await verifyTurnstile(String(b.turnstile_token ?? ''), ip))) {
      return json(req, 403, { error_code: 'CAPTCHA_FAILED' })
    }

    const { data, error } = await admin.rpc('guest_bookings_by_phone', {
      p_company_code: String(b.company_code),
      p_phone: phoneDigits,
    })
    if (error) throw error
    return json(req, 200, { bookings: data ?? [] })
  } catch (e) {
    console.error('guest-booking-lookup', e)
    return json(req, 500, { error_code: 'INTERNAL_ERROR' })
  }
})
