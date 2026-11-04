// POST /functions/v1/pos-payment-slip   (multipart/form-data, ต้องมี JWT ของพนักงาน)
// fields: file (รูปสลิปที่พนักงานถ่าย), invoice_id, amount (ยอดที่ลูกค้าโอน = ยอดรับ + ทิป)
// ขั้นตอน: ตรวจสิทธิ์สาขา (pos_invoice_slip_context) → เก็บสลิป (private bucket) → SlipOK
//          → record_payment_slip_check (DB ตรวจสลิปซ้ำอีกชั้น) → คืน slip_check_id ให้ใช้ตอนบันทึกรับเงิน
// ถ้ายังไม่ตั้งค่า SlipOK หรือตรวจไม่ได้ ผล = REVIEW (พนักงานยืนยันเองพร้อมเหตุผลได้)
import { adminClient, clientIp, dbErrorResponse, json, preflight, rateLimit, userClient, UUID_RE } from '../_shared/http.ts'
import { checkSlipWithSlipOk, type SlipCheckResult } from '../_shared/slipok.ts'

const TYPES: Record<string, string> = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' }
const MAX_BYTES = 5 * 1024 * 1024

interface SlipContext {
  invoice_id: string
  company_id: string
  branch_id: string
  balance: number
  user_id: string
  slipok_branch_id: string | null
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
  if (!(file instanceof File) || !TYPES[file.type] || file.size === 0 || file.size > MAX_BYTES) {
    return json(req, 400, { error_code: 'INVALID_FILE', message: 'รองรับ JPG/PNG/WebP ไม่เกิน 5 MB' })
  }
  if (!UUID_RE.test(invoiceId) || !Number.isFinite(amount) || amount <= 0 || amount > 10_000_000) {
    return json(req, 400, { error_code: 'INVALID_BODY' })
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

    // 2) เก็บสลิป
    const path = `${ctx.company_id}/${ctx.branch_id}/${ctx.invoice_id}/${crypto.randomUUID()}.${TYPES[file.type]}`
    const { error: upErr } = await admin.storage.from('payment-slips').upload(path, file, { contentType: file.type })
    if (upErr) throw upErr

    // 3) SlipOK
    const apiKey = Deno.env.get('SLIPOK_API_KEY')
    let result: SlipCheckResult
    if (!apiKey || !ctx.slipok_branch_id) {
      result = { outcome: 'REVIEW', code: null, message: 'ระบบตรวจสลิปอัตโนมัติยังไม่ได้ตั้งค่า', slip: {} }
    } else {
      result = await checkSlipWithSlipOk({
        apiKey,
        branchId: ctx.slipok_branch_id,
        file,
        fileName: `slip.${TYPES[file.type]}`,
        amount: Math.round(amount * 100) / 100,
      })
      if (result.code === 1013) result.message = 'ยอดเงินในสลิปไม่ตรงกับยอดที่ต้องรับ'
    }

    // 4) บันทึกผลตรวจ (service role) — ข้อมูลที่ pos_record_payment เชื่อถือ
    const { data: check, error: recErr } = await admin.rpc('record_payment_slip_check', {
      p_user_id: ctx.user_id,
      p_invoice_id: ctx.invoice_id,
      p_slip_path: path,
      p_requested_amount: Math.round(amount * 100) / 100,
      p_outcome: result.outcome,
      p_provider_code: result.code,
      p_provider_message: result.message,
      p_slip: result.slip,
    })
    if (recErr) return dbErrorResponse(req, recErr)
    return json(req, 200, check)
  } catch (e) {
    console.error('pos-payment-slip', e)
    return json(req, 500, { error_code: 'INTERNAL_ERROR' })
  }
})
