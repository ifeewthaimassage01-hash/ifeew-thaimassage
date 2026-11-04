// POST /functions/v1/device-staff-list
// body: { device_token }
// คืนข้อมูลเครื่อง + รายชื่อพนักงานของสาขาที่ผูกไว้ (user_id, display_name, locked)
import {
  adminClient,
  clientIp,
  DEVICE_TOKEN_RE,
  json,
  preflight,
  rateLimit,
  sha256Hex,
} from '../_shared/http.ts'

Deno.serve(async (req) => {
  const early = preflight(req)
  if (early) return early

  let body: { device_token?: unknown }
  try {
    body = await req.json()
  } catch {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }

  const token = typeof body.device_token === 'string' ? body.device_token : ''
  if (!DEVICE_TOKEN_RE.test(token)) return json(req, 401, { error_code: 'DEVICE_INVALID' })

  try {
    const admin = adminClient()
    const ip = clientIp(req)
    const deviceKey = (await sha256Hex(token)).slice(0, 32)

    const allowed =
      (await rateLimit(admin, `staff-list:ip:${ip}`, 60, 60)) &&
      (await rateLimit(admin, `staff-list:dev:${deviceKey}`, 30, 60))
    if (!allowed) return json(req, 429, { error_code: 'RATE_LIMITED' })

    const { data, error } = await admin.rpc('device_list_staff', { p_device_token: token })
    if (error) throw error
    if (!data?.ok) return json(req, 401, { error_code: data?.error_code ?? 'DEVICE_INVALID' })

    // เครื่องยังไม่มี session จึงออก signed URL ของรูปพนักงานให้ (หมดอายุ 1 ชม.)
    type StaffRow = { user_id: string; display_name: string; photo_path: string | null; locked: boolean }
    const staff = (data.staff ?? []) as StaffRow[]
    const paths = staff.map((s) => s.photo_path).filter((p): p is string => !!p)
    const urls = new Map<string, string>()
    if (paths.length) {
      const { data: signed, error: signErr } = await admin.storage
        .from('employee-photos')
        .createSignedUrls(paths, 3600)
      if (signErr) console.error('device-staff-list sign', signErr)
      for (const s of signed ?? []) if (s.path && s.signedUrl) urls.set(s.path, s.signedUrl)
    }

    return json(req, 200, {
      device: data.device,
      staff: staff.map(({ photo_path, ...s }) => ({ ...s, photo_url: photo_path ? urls.get(photo_path) ?? null : null })),
    })
  } catch (e) {
    console.error('device-staff-list', e)
    return json(req, 500, { error_code: 'INTERNAL_ERROR' })
  }
})
