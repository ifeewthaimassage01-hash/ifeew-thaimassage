// POST /functions/v1/owner-pin-login
// body: { company_code, pin }
// เจ้าของร้าน login ด้วย PIN อย่างเดียว (ไม่ต้องใช้เครื่องที่ผูก) — ตามที่ผู้ใช้เลือก (migration 029)
// 1) Rate limit ต่อ IP และต่อบริษัท (กันการเดา PIN จากภายนอก)
// 2) owner_verify_pin ตรวจ PIN (+ นับครั้งผิด/ล็อก + audit)
// 3) ผ่านแล้วออก Supabase session ของเจ้าของร้าน (magic link ที่ verify ฝั่ง server — ไม่ส่งอีเมล)
import { adminClient, clientIp, json, preflight, publicClient, rateLimit } from '../_shared/http.ts'

const PIN_RE = /^[0-9]{6}$/
const CODE_RE = /^[A-Za-z0-9]{2,10}$/

Deno.serve(async (req) => {
  const early = preflight(req)
  if (early) return early

  let body: { company_code?: unknown; pin?: unknown }
  try {
    body = await req.json()
  } catch {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }
  const companyCode = typeof body.company_code === 'string' ? body.company_code.toUpperCase() : ''
  const pin = typeof body.pin === 'string' ? body.pin : ''
  if (!CODE_RE.test(companyCode) || !PIN_RE.test(pin)) return json(req, 400, { error_code: 'INVALID_BODY' })

  try {
    const admin = adminClient()
    const ip = clientIp(req)
    const allowed =
      (await rateLimit(admin, `owner-pin:ip:${ip}`, 10, 900)) &&
      (await rateLimit(admin, `owner-pin:company:${companyCode}`, 30, 900))
    if (!allowed) return json(req, 429, { error_code: 'RATE_LIMITED' })

    const { data: verdict, error: verifyErr } = await admin.rpc('owner_verify_pin', {
      p_company_code: companyCode,
      p_pin: pin,
      p_client_ip: ip,
    })
    if (verifyErr) throw verifyErr
    if (!verdict?.ok) {
      const code = verdict?.error_code ?? 'INVALID_CREDENTIALS'
      return json(req, code === 'PIN_LOCKED' ? 423 : 401, {
        error_code: code,
        locked_until: verdict?.locked_until ?? null,
        attempts_left: verdict?.attempts_left ?? null,
      })
    }

    const { data: userRes, error: userErr } = await admin.auth.admin.getUserById(verdict.user_id)
    if (userErr || !userRes.user?.email) throw userErr ?? new Error('owner has no email')
    const { data: link, error: linkErr } = await admin.auth.admin.generateLink({ type: 'magiclink', email: userRes.user.email })
    if (linkErr) throw linkErr
    const { data: otp, error: otpErr } = await publicClient().auth.verifyOtp({
      type: 'email',
      token_hash: link.properties.hashed_token,
    })
    if (otpErr || !otp.session) throw otpErr ?? new Error('no session issued')

    return json(req, 200, {
      session: {
        access_token: otp.session.access_token,
        refresh_token: otp.session.refresh_token,
        expires_at: otp.session.expires_at,
      },
      user_id: verdict.user_id,
      company_id: verdict.company_id,
      idle_lock_minutes: verdict.idle_lock_minutes,
    })
  } catch (e) {
    console.error('owner-pin-login', e)
    return json(req, 500, { error_code: 'INTERNAL_ERROR' })
  }
})
