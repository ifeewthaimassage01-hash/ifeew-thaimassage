// POST /functions/v1/branch-staff-list
// body: { company_code, branch_id? }
// หน้า login (ไม่ต้องใช้เครื่องที่ผูก — migration 030)
//   ไม่ส่ง branch_id → { branches }
//   ส่ง branch_id    → { branches, branch, staff } (รูปพนักงานเป็น signed URL อายุ 1 ชม.)
import { adminClient, clientIp, json, preflight, rateLimit, UUID_RE } from '../_shared/http.ts'

const CODE_RE = /^[A-Za-z0-9]{2,10}$/

Deno.serve(async (req) => {
  const early = preflight(req)
  if (early) return early

  let body: { company_code?: unknown; branch_id?: unknown }
  try {
    body = await req.json()
  } catch {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }
  const companyCode = typeof body.company_code === 'string' ? body.company_code.toUpperCase() : ''
  const branchId = typeof body.branch_id === 'string' && body.branch_id ? body.branch_id : null
  if (!CODE_RE.test(companyCode) || (branchId && !UUID_RE.test(branchId))) {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }

  try {
    const admin = adminClient()
    const ip = clientIp(req)
    if (!(await rateLimit(admin, `branch-list:ip:${ip}`, 60, 60))) return json(req, 429, { error_code: 'RATE_LIMITED' })

    const { data: branches, error: brErr } = await admin.rpc('login_list_branches', { p_company_code: companyCode })
    if (brErr) throw brErr
    if (!branchId) return json(req, 200, { branches: branches ?? [] })

    const { data, error } = await admin.rpc('login_list_branch_staff', { p_company_code: companyCode, p_branch_id: branchId })
    if (error) throw error
    if (!data?.ok) return json(req, 404, { error_code: data?.error_code ?? 'BRANCH_INVALID' })

    type StaffRow = { user_id: string; display_name: string; photo_path: string | null; locked: boolean }
    const staff = (data.staff ?? []) as StaffRow[]
    const paths = staff.map((s) => s.photo_path).filter((p): p is string => !!p)
    const urls = new Map<string, string>()
    if (paths.length) {
      const { data: signed, error: signErr } = await admin.storage.from('employee-photos').createSignedUrls(paths, 3600)
      if (signErr) console.error('branch-staff-list sign', signErr)
      for (const s of signed ?? []) if (s.path && s.signedUrl) urls.set(s.path, s.signedUrl)
    }

    return json(req, 200, {
      branches: branches ?? [],
      branch: data.branch,
      staff: staff.map(({ photo_path, ...s }) => ({ ...s, photo_url: photo_path ? urls.get(photo_path) ?? null : null })),
    })
  } catch (e) {
    console.error('branch-staff-list', e)
    return json(req, 500, { error_code: 'INTERNAL_ERROR' })
  }
})
