// POST /functions/v1/cloudinary-sign   (ต้องมี JWT ของ OWNER — verify_jwt ค่าเริ่มต้น)
// body: { kind: 'service' | 'branch', target_id }
// -> { cloud_name, api_key, timestamp, signature, folder, public_id, allowed_formats }
// 1) image_upload_target ด้วย JWT ของผู้เรียก (สิทธิ์เดียวกับ RLS: OWNER ของบริษัทเจ้าของรายการ)
// 2) เซ็นพารามิเตอร์อัปโหลดของ Cloudinary — โฟลเดอร์/ชื่อไฟล์/นามสกุลกำหนดฝั่ง server เปลี่ยนไม่ได้
//    API secret อยู่ใน secret ของ function เท่านั้น
import { dbErrorResponse, json, preflight, userClient, UUID_RE } from '../_shared/http.ts'

const KINDS = new Set(['service', 'branch'])
const ALLOWED_FORMATS = 'jpg,jpeg,png,webp'

async function sha1Hex(value: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(value))
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

Deno.serve(async (req) => {
  const early = preflight(req)
  if (early) return early

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }
  const kind = String(body.kind ?? '')
  const targetId = String(body.target_id ?? '')
  if (!KINDS.has(kind) || !UUID_RE.test(targetId)) return json(req, 400, { error_code: 'INVALID_BODY' })

  const cloudName = Deno.env.get('CLOUDINARY_CLOUD_NAME')
  const apiKey = Deno.env.get('CLOUDINARY_API_KEY')
  const apiSecret = Deno.env.get('CLOUDINARY_API_SECRET')
  if (!cloudName || !apiKey || !apiSecret) {
    console.error('cloudinary-sign: missing CLOUDINARY_* secrets')
    return json(req, 500, { error_code: 'INTERNAL_ERROR', message: 'ยังไม่ได้ตั้งค่า Cloudinary' })
  }

  const { data: companyId, error } = await userClient(req).rpc('image_upload_target', { p_kind: kind, p_target_id: targetId })
  if (error) return dbErrorResponse(req, error)

  const timestamp = Math.floor(Date.now() / 1000)
  const params: Record<string, string> = {
    allowed_formats: ALLOWED_FORMATS,
    folder: `ifeew/${companyId}/${kind}s/${targetId}`,
    overwrite: 'false',
    public_id: String(timestamp),
    timestamp: String(timestamp),
  }
  // ลายเซ็น: key=value เรียงตามชื่อ ต่อด้วย & แล้วต่อท้ายด้วย api secret → SHA-1
  const toSign = Object.keys(params).sort().map((k) => `${k}=${params[k]}`).join('&')
  const signature = await sha1Hex(toSign + apiSecret)

  return json(req, 200, { cloud_name: cloudName, api_key: apiKey, signature, ...params })
})
