// POST /functions/v1/line-admin   (ต้องมี JWT ของ OWNER — เรียกจากแอปพนักงาน /settings/line)
// body: { company_id, action: 'check' | 'setup_webhook' | 'test_group', group_id? }
// - check:         ตรวจ token (ชื่อบอท/basic ID) · สถานะ webhook · โควตาข้อความเดือนนี้
// - setup_webhook: ตั้ง Webhook URL ของ channel ให้อัตโนมัติ แล้วให้ LINE ยิงทดสอบ (ตรวจ Channel secret ไปในตัว)
// - test_group:    ส่งการ์ดตัวอย่างเข้ากลุ่มที่เชื่อมไว้
import { adminClient, json, preflight, userClient, UUID_RE } from '../_shared/http.ts'
import { lineGet, linePushMessage, lineSecret, lineSend, sampleStaffMessage } from '../_shared/line.ts'

Deno.serve(async (req) => {
  const early = preflight(req)
  if (early) return early

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }
  const companyId = String(body.company_id ?? '')
  const action = String(body.action ?? '')
  if (!UUID_RE.test(companyId) || !['check', 'setup_webhook', 'test_group'].includes(action)) {
    return json(req, 400, { error_code: 'INVALID_BODY' })
  }

  try {
    // สิทธิ์: line_settings_get ด้วย JWT ของผู้เรียก (เฉพาะ OWNER)
    const user = userClient(req)
    const { data: settings, error: permErr } = await user.rpc('line_settings_get', { p_company_id: companyId })
    if (permErr) return json(req, 403, { error_code: 'FORBIDDEN', message: 'เฉพาะเจ้าของร้าน' })

    const admin = adminClient()
    const cfg = await lineSecret(admin, { companyId })
    const token = cfg?.access_token
    if (!token) return json(req, 200, { configured: false })

    if (action === 'check') {
      const bot = await lineGet<{ displayName: string; basicId: string; pictureUrl?: string }>(token, '/v2/bot/info')
      if (!bot.data) {
        return json(req, 200, { configured: true, token_valid: false, status: bot.status })
      }
      await admin.rpc('line_save_bot_info', {
        p_company_id: companyId,
        p_bot_name: bot.data.displayName,
        p_basic_id: bot.data.basicId,
      })
      const [webhook, quota, usage] = await Promise.all([
        lineGet<{ endpoint: string; active: boolean }>(token, '/v2/bot/channel/webhook/endpoint'),
        lineGet<{ type: string; value?: number }>(token, '/v2/bot/message/quota'),
        lineGet<{ totalUsage: number }>(token, '/v2/bot/message/quota/consumption'),
      ])
      const expected = (settings as { webhook_url?: string } | null)?.webhook_url ?? ''
      return json(req, 200, {
        configured: true,
        token_valid: true,
        bot: { name: bot.data.displayName, basic_id: bot.data.basicId, picture_url: bot.data.pictureUrl ?? null },
        webhook: webhook.data
          ? { endpoint: webhook.data.endpoint, active: webhook.data.active, matches: webhook.data.endpoint === expected }
          : null,
        quota: {
          limit: quota.data?.type === 'limited' ? quota.data.value ?? null : null,
          used: usage.data?.totalUsage ?? null,
        },
        has_channel_secret: !!cfg?.channel_secret,
      })
    }

    if (action === 'setup_webhook') {
      const endpoint = cfg!.webhook_url
      const put = await lineSend(token, 'PUT', '/v2/bot/channel/webhook/endpoint', { endpoint })
      if (put.status !== 200) {
        return json(req, 200, { ok: false, step: 'set', status: put.status, detail: put.data })
      }
      const test = await lineSend<{ success: boolean; statusCode: number; reason: string; detail: string }>(
        token,
        'POST',
        '/v2/bot/channel/webhook/test',
        { endpoint },
      )
      const webhook = await lineGet<{ endpoint: string; active: boolean }>(token, '/v2/bot/channel/webhook/endpoint')
      return json(req, 200, {
        ok: !!test.data?.success,
        step: 'test',
        test: test.data,
        active: webhook.data?.active ?? null,
      })
    }

    // test_group
    const groupId = String(body.group_id ?? '')
    const { data: groups } = await user.rpc('line_groups_list', { p_company_id: companyId })
    const group = ((groups ?? []) as Array<{ group_id: string; branch_name: string | null }>).find((g) => g.group_id === groupId)
    if (!group) {
      return json(req, 404, { error_code: 'NOT_FOUND', message: 'ไม่พบกลุ่มนี้' })
    }
    // ส่งการ์ดตัวอย่างแบบที่กลุ่มจะได้รับจริง (การ์ดไม่ผ่าน → ข้อความธรรมดา)
    const staffUrl = (settings as { staff_url?: string | null } | null)?.staff_url ?? null
    const status = await linePushMessage(token, groupId, sampleStaffMessage(group.branch_name, staffUrl))
    return json(req, 200, { ok: status === 200, status })
  } catch (e) {
    console.error('line-admin', e)
    return json(req, 500, { error_code: 'INTERNAL_ERROR' })
  }
})
