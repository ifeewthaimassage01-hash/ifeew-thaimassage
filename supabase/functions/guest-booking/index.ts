// POST /functions/v1/guest-booking   (ไม่ต้อง login)
// body: { company_code, branch_id, starts_at, option_ids[], first_name, last_name?, phone, email?, note?,
//         privacy_version_id, turnstile_token, idempotency_key, line_id_token? }
// 1) Rate limit ต่อ IP และต่อเบอร์  2) Cloudflare Turnstile  3) create_guest_booking (DB ตรวจทุกอย่างซ้ำ)
// 4) จองจาก LIFF (มี line_id_token): ยืนยันกับ LINE → ผูกการจองกับ LINE ของลูกค้า → ส่งข้อความยืนยัน
//    ทำเบื้องหลังหลังตอบลูกค้าแล้ว · LINE ล้มเหลวไม่ทำให้การจองล้มเหลว
import {
  adminClient,
  clientIp,
  corsHeaders,
  dbErrorResponse,
  json,
  preflight,
  rateLimit,
  sha256Hex,
  UUID_RE,
  verifyTurnstile,
} from '../_shared/http.ts'
import { linePush, lineSecret, lineVerifyIdToken } from '../_shared/line.ts'

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void } | undefined

// siteUrl = origin ของแอปลูกค้า (ผ่าน ALLOWED_ORIGINS แล้ว) ใช้ทำลิงก์ติดตามถ้ายังไม่ได้ตั้ง URL ในหน้าเว็บ
async function confirmViaLine(companyCode: string, idToken: string, trackingToken: string, siteUrl: string) {
  try {
    const admin = adminClient()
    const cfg = await lineSecret(admin, { companyCode })
    if (!cfg?.access_token) return
    const userId = await lineVerifyIdToken(cfg.login_channel_id, idToken)
    if (!userId) return
    const { data, error } = await admin.rpc('line_attach_booking', {
      p_token: trackingToken,
      p_line_user_id: userId,
      p_site_url: siteUrl,
    })
    if (error) throw error
    if (typeof data === 'string' && data) await linePush(cfg.access_token, userId, data)
  } catch (e) {
    console.error('guest-booking line confirm', e)
  }
}

const CODE_RE = /^[A-Za-z0-9]{2,10}$/
const KEY_RE = /^[A-Za-z0-9_-]{16,100}$/

Deno.serve(async (req) => {
  const early = preflight(req)
  if (early) return early

  let b: Record<string, unknown>
  try {
    b = await req.json()
  } catch {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }

  const optionIds = Array.isArray(b.option_ids) ? b.option_ids.map(String) : []
  const phoneDigits = String(b.phone ?? '').replace(/[^0-9]/g, '')
  if (
    !CODE_RE.test(String(b.company_code ?? '')) || !UUID_RE.test(String(b.branch_id ?? '')) ||
    Number.isNaN(Date.parse(String(b.starts_at ?? ''))) || optionIds.length < 1 || optionIds.length > 10 ||
    !optionIds.every((id) => UUID_RE.test(id)) || !UUID_RE.test(String(b.privacy_version_id ?? '')) ||
    !KEY_RE.test(String(b.idempotency_key ?? '')) || phoneDigits.length < 9 || phoneDigits.length > 12 ||
    String(b.first_name ?? '').trim().length < 1 || String(b.first_name).length > 100
  ) {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }

  try {
    const admin = adminClient()
    const ip = clientIp(req)
    const phoneKey = (await sha256Hex(phoneDigits)).slice(0, 32)
    const allowed =
      (await rateLimit(admin, `guest-booking:ip:${ip}`, 10, 600)) &&
      (await rateLimit(admin, `guest-booking:phone:${phoneKey}`, 5, 3600))
    if (!allowed) return json(req, 429, { error_code: 'RATE_LIMITED' })

    if (!(await verifyTurnstile(String(b.turnstile_token ?? ''), ip))) {
      return json(req, 403, { error_code: 'CAPTCHA_FAILED' })
    }

    const { data, error } = await admin.rpc('create_guest_booking', {
      p_company_code: String(b.company_code),
      p_branch_id: String(b.branch_id),
      p_starts_at: String(b.starts_at),
      p_option_ids: optionIds,
      p_first_name: String(b.first_name).trim(),
      p_last_name: String(b.last_name ?? '').trim().slice(0, 100),
      p_phone: String(b.phone),
      p_email: b.email ? String(b.email).trim().slice(0, 200) : null,
      p_note: b.note ? String(b.note).slice(0, 500) : null,
      p_privacy_version_id: String(b.privacy_version_id),
      p_idempotency_key: String(b.idempotency_key),
    })
    if (error) {
      if (error.hint === 'CAPACITY_FULL') return json(req, 409, { error_code: 'CAPACITY_FULL', message: error.message })
      return dbErrorResponse(req, error)
    }
    const lineIdToken = typeof b.line_id_token === 'string' ? b.line_id_token : ''
    const trackingToken = (data as { tracking_token?: string } | null)?.tracking_token
    if (lineIdToken && trackingToken) {
      const job = confirmViaLine(String(b.company_code), lineIdToken, trackingToken, corsHeaders(req)['Access-Control-Allow-Origin'] ?? '')
      if (typeof EdgeRuntime !== 'undefined') EdgeRuntime.waitUntil(job)
      else await job
    }
    return json(req, 201, data)
  } catch (e) {
    console.error('guest-booking', e)
    return json(req, 500, { error_code: 'INTERNAL_ERROR' })
  }
})
