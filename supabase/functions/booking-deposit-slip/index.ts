// POST /functions/v1/booking-deposit-slip   (multipart/form-data)
// fields: file (รูปสลิป), และอย่างใดอย่างหนึ่ง
//   - token            : Tracking Token (Guest / ลิงก์ที่พนักงานส่งให้)
//   - booking_id + company_code + Authorization: Bearer <JWT สมาชิก>
// ขั้นตอน: ระบุการจอง -> เก็บสลิป (private bucket) -> SlipOK -> record_deposit_slip (DB ตรวจยอด/สลิปซ้ำซ้ำอีกชั้น)
import { adminClient, clientIp, dbErrorResponse, json, preflight, rateLimit, userClient, UUID_RE } from '../_shared/http.ts'
import { checkSlipWithSlipOk, type SlipCheckResult } from '../_shared/slipok.ts'

const TOKEN_RE = /^trk_[0-9a-f]{64}$/
const TYPES: Record<string, string> = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' }
const MAX_BYTES = 5 * 1024 * 1024

interface PaymentContext {
  booking_id: string
  company_id: string
  branch_id: string
  amount: number
}

Deno.serve(async (req) => {
  const early = preflight(req)
  if (early) return early

  let form: FormData
  try {
    form = await req.formData()
  } catch {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }
  const file = form.get('file')
  if (!(file instanceof File) || !TYPES[file.type] || file.size === 0 || file.size > MAX_BYTES) {
    return json(req, 400, { error_code: 'INVALID_FILE', message: 'รองรับ JPG/PNG/WebP ไม่เกิน 5 MB' })
  }

  const admin = adminClient()
  try {
    if (!(await rateLimit(admin, `slip:ip:${clientIp(req)}`, 20, 600))) {
      return json(req, 429, { error_code: 'RATE_LIMITED' })
    }

    // 1) ระบุการจอง
    let ctx: PaymentContext | null = null
    const token = String(form.get('token') ?? '')
    if (token) {
      if (!TOKEN_RE.test(token)) return json(req, 404, { error_code: 'NOT_FOUND' })
      const { data, error } = await admin.rpc('booking_payment_context_by_token', { p_token: token })
      if (error) throw error
      ctx = data as PaymentContext | null
    } else {
      const bookingId = String(form.get('booking_id') ?? '')
      const companyCode = String(form.get('company_code') ?? '')
      if (!UUID_RE.test(bookingId) || !/^[A-Za-z0-9]{2,10}$/.test(companyCode) || !req.headers.get('authorization')) {
        return json(req, 400, { error_code: 'INVALID_BODY' })
      }
      const { data, error } = await userClient(req).rpc('my_booking_payment_context', {
        p_company_code: companyCode,
        p_booking_id: bookingId,
      })
      if (error) return dbErrorResponse(req, error)
      ctx = data as PaymentContext | null
    }
    if (!ctx?.booking_id) return json(req, 404, { error_code: 'NOT_FOUND' })

    if (!(await rateLimit(admin, `slip:booking:${ctx.booking_id}`, 10, 900))) {
      return json(req, 429, { error_code: 'RATE_LIMITED' })
    }

    // 2) เก็บสลิป
    const path = `${ctx.company_id}/${ctx.branch_id}/${ctx.booking_id}/${Date.now()}.${TYPES[file.type]}`
    const { error: upErr } = await admin.storage.from('booking-slips').upload(path, file, { contentType: file.type })
    if (upErr) throw upErr

    // 3) ตรวจกับ SlipOK (ถ้ายังไม่ได้ตั้งค่า -> ส่งให้พนักงานตรวจ)
    const { data: account } = await admin
      .from('branch_payment_accounts')
      .select('slipok_branch_id')
      .eq('branch_id', ctx.branch_id)
      .eq('is_active', true)
      .maybeSingle()
    const apiKey = Deno.env.get('SLIPOK_API_KEY')
    let result: SlipCheckResult
    if (!apiKey || !account?.slipok_branch_id) {
      result = { outcome: 'REVIEW', code: null, message: 'ระบบตรวจสลิปอัตโนมัติยังไม่ได้ตั้งค่า รอพนักงานตรวจ', slip: {} }
    } else {
      result = await checkSlipWithSlipOk({
        apiKey,
        branchId: account.slipok_branch_id,
        file,
        fileName: `slip.${TYPES[file.type]}`,
        amount: Number(ctx.amount),
      })
    }

    // 4) บันทึกผล (DB ตรวจยอดและสลิปซ้ำอีกชั้น และยืนยันการจองถ้าผ่าน)
    const { data: view, error: recErr } = await admin.rpc('record_deposit_slip', {
      p_booking_id: ctx.booking_id,
      p_slip_path: path,
      p_outcome: result.outcome,
      p_provider_code: result.code,
      p_provider_message: result.message,
      p_slip: result.slip,
    })
    if (recErr) return dbErrorResponse(req, recErr)
    return json(req, 200, view)
  } catch (e) {
    console.error('booking-deposit-slip', e)
    return json(req, 500, { error_code: 'INTERNAL_ERROR' })
  }
})
