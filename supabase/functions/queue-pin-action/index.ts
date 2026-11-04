// POST /functions/v1/queue-pin-action   (ต้องมี JWT ของผู้ใช้ที่ login อยู่บนเครื่องสาขา)
// body: { device_token, user_id, pin, queue_id, action: 'ACCEPT' | 'START' | 'COMPLETE' }
// หมอกดรับ/เริ่ม/จบคิวของตัวเองบนเครื่องสาขาโดยไม่ต้อง logout คนหน้าร้าน
// 1) Rate limit ต่อ IP / เครื่อง / หมอ (ชุดเดียวกับ staff-pin-login)
// 2) device_verify_staff_pin ตรวจเครื่อง + สาขา + PIN (นับครั้งผิด/ล็อก + audit)
// 3) device_queue_action ทำคำสั่งในนามหมอ เฉพาะคิวที่มอบหมายให้หมอคนนั้นในสาขาของเครื่อง
import {
  adminClient,
  clientIp,
  dbErrorResponse,
  DEVICE_TOKEN_RE,
  json,
  preflight,
  rateLimit,
  sha256Hex,
  UUID_RE,
} from '../_shared/http.ts'

const PIN_RE = /^[0-9]{6}$/
const ACTIONS = new Set(['ACCEPT', 'START', 'COMPLETE'])

Deno.serve(async (req) => {
  const early = preflight(req)
  if (early) return early

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }

  const token = typeof body.device_token === 'string' ? body.device_token : ''
  const userId = typeof body.user_id === 'string' ? body.user_id : ''
  const pin = typeof body.pin === 'string' ? body.pin : ''
  const queueId = typeof body.queue_id === 'string' ? body.queue_id : ''
  const action = typeof body.action === 'string' ? body.action : ''

  if (!DEVICE_TOKEN_RE.test(token)) return json(req, 401, { error_code: 'DEVICE_INVALID' })
  if (!UUID_RE.test(userId) || !UUID_RE.test(queueId) || !PIN_RE.test(pin) || !ACTIONS.has(action)) {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }

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
      return json(req, code === 'PIN_LOCKED' ? 423 : 401, {
        error_code: code,
        locked_until: verdict?.locked_until ?? null,
        attempts_left: verdict?.attempts_left ?? null,
      })
    }

    const { data, error } = await admin.rpc('device_queue_action', {
      p_device_token: token,
      p_user_id: userId,
      p_queue_id: queueId,
      p_action: action,
    })
    if (error) {
      if (error.code === 'P0001') return json(req, 409, { error_code: 'CAPACITY_FULL', message: error.message })
      return dbErrorResponse(req, error)
    }
    return json(req, 200, data)
  } catch (e) {
    console.error('queue-pin-action', e)
    return json(req, 500, { error_code: 'INTERNAL_ERROR' })
  }
})
