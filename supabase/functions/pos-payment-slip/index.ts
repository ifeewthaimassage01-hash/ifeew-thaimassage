// POST /functions/v1/pos-payment-slip   (multipart/form-data, ต้องมี JWT ของพนักงาน)
// fields: file (รูปสลิปที่พนักงานถ่าย), invoice_id, amount (ยอดที่ลูกค้าโอน)
// ขั้นตอน: ตรวจสิทธิ์สาขา (pos_invoice_slip_context) → เก็บสลิปบน Cloudinary (private/authenticated)
//          → record_payment_slip_check (แนบสลิปเป็นหลักฐาน — ไม่ตรวจสลิปอัตโนมัติ) → คืน slip_check_id
// (เดิมเก็บที่ bucket payment-slips + ตรวจด้วย SlipOK — สลิปเก่ายังเปิดดูได้ผ่าน payment-slip-url)
import { adminClient, clientIp, dbErrorResponse, json, preflight, rateLimit, userClient, UUID_RE } from '../_shared/http.ts'
import { CLOUDINARY_PREFIX, cloudinaryEnv, uploadPrivate } from '../_shared/cloudinary.ts'

const TYPES = new Set(['image/jpeg', 'image/png', 'image/webp'])
const MAX_BYTES = 5 * 1024 * 1024

interface SlipContext {
  invoice_id: string
  company_id: string
  branch_id: string
  balance: number
  user_id: string
}

Deno.serve(async (req) => {
  const early = preflight(req)
  if (early) return early
  if (!req.headers.get('authorization')) return json(req, 401, { error_code: 'UNAUTHORIZED' })

  let form: FormData
  try {
    form = await req.formData()
  } catch {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }
  const file = form.get('file')
  const invoiceId = String(form.get('invoice_id') ?? '')
  const amount = Number(form.get('amount'))
  if (!(file instanceof File) || !TYPES.has(file.type) || file.size === 0 || file.size > MAX_BYTES) {
    return json(req, 400, { error_code: 'INVALID_FILE', message: 'รองรับ JPG/PNG/WebP ไม่เกิน 5 MB' })
  }
  if (!UUID_RE.test(invoiceId) || !Number.isFinite(amount) || amount <= 0 || amount > 10_000_000) {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }

  const env = cloudinaryEnv()
  if (!env) {
    console.error('pos-payment-slip: missing CLOUDINARY_* secrets')
    return json(req, 500, { error_code: 'INTERNAL_ERROR', message: 'ยังไม่ได้ตั้งค่า Cloudinary' })
  }

  const admin = adminClient()
  try {
    if (!(await rateLimit(admin, `posslip:ip:${clientIp(req)}`, 60, 600))) {
      return json(req, 429, { error_code: 'RATE_LIMITED' })
    }

    // 1) สิทธิ์ของพนักงานต่อ Invoice นี้ (ตรวจด้วย JWT ของผู้เรียก)
    const { data, error } = await userClient(req).rpc('pos_invoice_slip_context', { p_invoice_id: invoiceId })
    if (error) return dbErrorResponse(req, error)
    const ctx = data as SlipContext | null
    if (!ctx?.invoice_id || !ctx.user_id) return json(req, 404, { error_code: 'NOT_FOUND' })

    // 2) เก็บสลิปบน Cloudinary (authenticated — เปิดได้เฉพาะ URL ที่เซ็นแล้ว)
    const publicId = await uploadPrivate(
      env,
      file,
      `ifeew/${ctx.company_id}/${ctx.branch_id}/payment-slips/${ctx.invoice_id}`,
      crypto.randomUUID(),
    )
    const path = `${CLOUDINARY_PREFIX}${publicId}`

    // 3) บันทึกการแนบสลิป (service role) — ไม่ตรวจสลิป: outcome = REVIEW, ยืนยันโดยพนักงานตอนบันทึกรับเงิน
    const { data: check, error: recErr } = await admin.rpc('record_payment_slip_check', {
      p_user_id: ctx.user_id,
      p_invoice_id: ctx.invoice_id,
      p_slip_path: path,
      p_requested_amount: Math.round(amount * 100) / 100,
      p_outcome: 'REVIEW',
      p_provider_code: null,
      p_provider_message: null,
      p_slip: {},
    })
    if (recErr) return dbErrorResponse(req, recErr)
    return json(req, 200, check)
  } catch (e) {
    console.error('pos-payment-slip', e)
    return json(req, 500, { error_code: 'INTERNAL_ERROR' })
  }
})
