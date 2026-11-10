// POST /functions/v1/payment-slip-url   (ต้องมี JWT ของพนักงาน)
// body: { slip_path } (ค่าจาก invoice_view.payments[].slip_path) -> { url }
// เปิดดูสลิปรับเงินหน้าร้าน: อ่านแถว payment_slip_checks ด้วย JWT ของผู้เรียก (RLS = สิทธิ์สาขา)
//   - "cloudinary:<public_id>" → URL ที่เซ็นแล้วของรูป authenticated
//   - path เดิมใน bucket payment-slips → signed URL ของ Supabase Storage (5 นาที)
import { dbErrorResponse, json, preflight, userClient } from '../_shared/http.ts'
import { CLOUDINARY_PREFIX, cloudinaryEnv, signedPrivateUrl } from '../_shared/cloudinary.ts'

Deno.serve(async (req) => {
  const early = preflight(req)
  if (early) return early
  if (!req.headers.get('authorization')) return json(req, 401, { error_code: 'UNAUTHORIZED' })

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }
  const requested = String(body.slip_path ?? '')
  if (!requested || requested.length > 300) return json(req, 400, { error_code: 'INVALID_BODY' })

  const db = userClient(req)
  const { data, error } = await db.from('payment_slip_checks').select('slip_path').eq('slip_path', requested).limit(1).maybeSingle()
  if (error) return dbErrorResponse(req, error)
  const path = (data as { slip_path: string } | null)?.slip_path
  if (!path) return json(req, 404, { error_code: 'NOT_FOUND' })

  if (path.startsWith(CLOUDINARY_PREFIX)) {
    const env = cloudinaryEnv()
    if (!env) return json(req, 500, { error_code: 'INTERNAL_ERROR', message: 'ยังไม่ได้ตั้งค่า Cloudinary' })
    return json(req, 200, { url: await signedPrivateUrl(env, path.slice(CLOUDINARY_PREFIX.length)) })
  }
  const { data: signed, error: sErr } = await db.storage.from('payment-slips').createSignedUrl(path, 300)
  if (sErr || !signed?.signedUrl) return json(req, 404, { error_code: 'NOT_FOUND' })
  return json(req, 200, { url: signed.signedUrl })
})
