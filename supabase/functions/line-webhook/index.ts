// POST /functions/v1/line-webhook?c=<company_id>   (LINE Platform เรียก — Webhook URL ต่อบริษัท ดูได้ในแอปพนักงาน /settings/line)
// ไม่ใช้ JWT: ยืนยันด้วย x-line-signature (HMAC ของ Channel secret ที่ตั้งไว้ในหน้าเว็บ) แทน
// - บอทถูกเชิญเข้ากลุ่ม (join)           → ตอบวิธีเชื่อมกลุ่ม
// - ในกลุ่มพิมพ์ "เชื่อมร้าน ABC123"      → line_link_group (รหัสจากแอปพนักงาน /settings/line)
// - พิมพ์ "ยกเลิกเชื่อมร้าน" / บอทออกจากกลุ่ม → เลิกส่งแจ้งเตือนเข้ากลุ่มนี้
// การตอบกลับ (reply) ฟรี ไม่นับโควตา · ตอบ 200 เสมอเมื่อลายเซ็นถูก (LINE จะไม่ส่งซ้ำ)
import { adminClient, rateLimit, UUID_RE } from '../_shared/http.ts'
import { lineGroupName, lineReply, lineSecret, lineSignatureOk } from '../_shared/line.ts'

interface LineEvent {
  type: string
  replyToken?: string
  source?: { type: string; groupId?: string; userId?: string }
  message?: { type: string; text?: string }
}

const LINK_RE = /^(?:เชื่อมร้าน|link)\s*([A-Za-z2-9]{6})$/i
const UNLINK_RE = /^(?:ยกเลิกเชื่อมร้าน|unlink)$/i

const EVENT_LABELS: Record<string, string> = {
  NEW_BOOKING: 'มีการจองใหม่',
  DEPOSIT_SLIP: 'ลูกค้าส่งสลิปมัดจำ',
  BOOKING_CANCELLED: 'ลูกค้ายกเลิกการจอง',
  WALK_IN: 'รับลูกค้าหน้าร้าน',
  SERVICE_DONE: 'บริการเสร็จ',
}

const ok = () => new Response('ok', { status: 200 })

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response(null, { status: 405 })
  const companyId = new URL(req.url).searchParams.get('c') ?? ''
  if (!UUID_RE.test(companyId)) return new Response(null, { status: 404 })

  const raw = await req.text()
  const admin = adminClient()
  const cfg = await lineSecret(admin, { companyId }).catch((e) => {
    console.error('line-webhook config', e)
    return null
  })
  if (!cfg?.channel_secret || !(await lineSignatureOk(cfg.channel_secret, raw, req.headers.get('x-line-signature')))) {
    return new Response(null, { status: 401 })
  }
  const token = cfg.access_token ?? ''

  let events: LineEvent[] = []
  try {
    events = ((JSON.parse(raw) as { events?: LineEvent[] }).events ?? []).slice(0, 50)
  } catch {
    return ok()
  }
  if (!token) return ok()

  for (const ev of events) {
    try {
      const groupId = ev.source?.type === 'group' ? ev.source.groupId ?? '' : ''
      const reply = (text: string) => lineReply(token, ev.replyToken ?? '', text)

      if (ev.type === 'join' && groupId) {
        await reply(
          'สวัสดีครับ 🙏\nเชื่อมกลุ่มนี้กับระบบร้านเพื่อรับแจ้งเตือน:\n1. เจ้าของร้านเปิดแอปพนักงาน → LINE OA → สร้างรหัส\n2. พิมพ์ในกลุ่มนี้ว่า  เชื่อมร้าน รหัส  เช่น  เชื่อมร้าน ABC123',
        )
        continue
      }

      if (ev.type === 'leave' && groupId) {
        await admin.rpc('line_group_left', { p_group_id: groupId })
        continue
      }

      if (ev.type !== 'message' || ev.message?.type !== 'text' || !groupId) continue
      const text = (ev.message.text ?? '').trim()

      if (UNLINK_RE.test(text)) {
        await admin.rpc('line_group_left', { p_group_id: groupId })
        await reply('เลิกส่งแจ้งเตือนเข้ากลุ่มนี้แล้ว')
        continue
      }

      const m = LINK_RE.exec(text)
      if (!m) continue
      if (!(await rateLimit(admin, `line-link:${groupId}`, 10, 600))) {
        await reply('ลองหลายครั้งเกินไป กรุณารอ 10 นาทีแล้วลองใหม่')
        continue
      }
      const name = await lineGroupName(token, groupId)
      const { data, error } = await admin.rpc('line_link_group', {
        p_company_id: companyId,
        p_code: m[1]!.toUpperCase(),
        p_group_id: groupId,
        p_group_name: name ?? '',
      })
      if (error) throw error
      const linked = data as { company_name: string; branch_name: string | null; events: string[] | null } | null
      const events = (linked?.events ?? []).map((e) => EVENT_LABELS[e] ?? e)
      await reply(
        linked
          ? `✅ เชื่อมกลุ่มนี้กับ ${linked.company_name}${linked.branch_name ? ` (สาขา${linked.branch_name})` : ' (ทุกสาขา)'} แล้ว` +
              (events.length ? `\nจะแจ้งเตือนเมื่อ: ${events.join(' · ')}` : '\nตอนนี้ยังไม่ได้เลือกเหตุการณ์ที่จะแจ้งเตือน (ตั้งได้ในแอปพนักงาน)')
          : 'รหัสไม่ถูกต้องหรือหมดอายุแล้ว (ใช้ได้ 30 นาที ครั้งเดียว) กรุณาสร้างรหัสใหม่ในแอปพนักงาน',
      )
    } catch (e) {
      console.error('line-webhook event', ev.type, e)
    }
  }
  return ok()
})
