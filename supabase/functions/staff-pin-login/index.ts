// POST /functions/v1/staff-pin-login
// body: { device_token, user_id, pin }
// 1) Rate limit ต่อ IP / เครื่อง / พนักงาน
// 2) public.device_verify_staff_pin ตรวจเครื่อง + สิทธิ์สาขา + PIN (+ นับครั้งผิด/ล็อก + audit)
// 3) ผ่านแล้วออก Supabase session ของพนักงานด้วย magic link ที่ verify ฝั่ง server (ไม่ส่งอีเมล)
import {
  adminClient,
  clientIp,
  DEVICE_TOKEN_RE,
  json,
  preflight,
  publicClient,
  rateLimit,
  sha256Hex,
  UUID_RE,
} from '../_shared/http.ts'

const PIN_RE = /^[0-9]{6}$/

Deno.serve(async (req) => {
  const early = preflight(req)
  if (early) return early

  let body: { device_token?: unknown; user_id?: unknown; pin?: unknown }
  try {
    body = await req.json()
  } catch {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }

  const token = typeof body.device_token === 'string' ? body.device_token : ''
  const userId = typeof body.user_id === 'string' ? body.user_id : ''
  const pin = typeof body.pin === 'string' ? body.pin : ''

  if (!DEVICE_TOKEN_RE.test(token)) return json(req, 401, { error_code: 'DEVICE_INVALID' })
  if (!UUID_RE.test(userId) || !PIN_RE.test(pin)) return json(req, 400, { error_code: 'INVALID_BODY' })

  try {
    const admin = adminClient()
    const ip = clientIp(req)
    const deviceKey = (await sha256Hex(token)).slice(0, 32)

    const allowed =
      (await rateLimit(admin, `pin:ip:${ip}`, 30, 300)) &&
      (await rateLimit(admin, `pin:dev:${deviceKey}`, 30, 300)) &&
      (await rateLimit(admin, `pin:user:${userId}`, 10, 300))
    if (!allowed) return json(req, 429, { error_code: 'RATE_LIMITED' })

    const { data: verdict, error: verifyErr } = await admin.rpc('device_verify_staff_pin', {
      p_device_token: token,
      p_user_id: userId,
      p_pin: pin,
      p_client_ip: ip,
    })
    if (verifyErr) throw verifyErr

    if (!verdict?.ok) {
      const code = verdict?.error_code ?? 'INVALID_CREDENTIALS'
      const status = code === 'PIN_LOCKED' ? 423 : 401
      return json(req, status, {
        error_code: code,
        locked_until: verdict?.locked_until ?? null,
        attempts_left: verdict?.attempts_left ?? null,
      })
    }

    // ออก session ให้พนักงาน
    const { data: userRes, error: userErr } = await admin.auth.admin.getUserById(userId)
    if (userErr || !userRes.user?.email) throw userErr ?? new Error('staff user has no internal email')

    const { data: link, error: linkErr } = await admin.auth.admin.generateLink({
      type: 'magiclink',
      email: userRes.user.email,
    })
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
      branch_id: verdict.branch_id,
      idle_lock_minutes: verdict.idle_lock_minutes,
    })
  } catch (e) {
    console.error('staff-pin-login', e)
    return json(req, 500, { error_code: 'INTERNAL_ERROR' })
  }
})
