// POST /functions/v1/line-webhook?c=<company_id>   (LINE Platform เรียก — Webhook URL ต่อบริษัท ดูได้ในแอปพนักงาน /settings/line)
// ไม่ใช้ JWT: ยืนยันด้วย x-line-signature (HMAC ของ Channel secret ที่ตั้งไว้ในหน้าเว็บ) แทน
// - บอทถูกเชิญเข้ากลุ่ม (join)           → ตอบวิธีเชื่อมกลุ่ม
// - ในกลุ่มพิมพ์ "เชื่อมร้าน ABC123"      → line_link_group (รหัสจากแอปพนักงาน /settings/line)
// - พิมพ์ "ยกเลิกเชื่อมร้าน" / บอทออกจากกลุ่ม → เลิกส่งแจ้งเตือนเข้ากลุ่มนี้
// การตอบกลับ (reply) ฟรี ไม่นับโควตา · ตอบ 200 เสมอเมื่อลายเซ็นถูก (LINE จะไม่ส่งซ้ำ)
import { adminClient, rateLimit, UUID_RE } from '../_shared/http.ts'
import {
  type FlexSummary,
  lineGroupName,
  lineReply,
  lineSecret,
  lineSignatureOk,
  lineUserName,
  noticeMessage,
  summaryMessage,
} from '../_shared/line.ts'

interface LineEvent {
  type: string
  replyToken?: string
  source?: { type: string; groupId?: string; userId?: string }
  message?: { type: string; text?: string }
}

const LINK_RE = /^(?:เชื่อมร้าน|link)\s*([A-Za-z2-9]{6})$/i
const UNLINK_RE = /^(?:ยกเลิกเชื่อมร้าน|unlink)$/i
// แชท 1:1 ของเจ้าของร้าน (สรุปประจำวัน — migration 077)
const OWNER_LINK_RE = /^(?:เชื่อมเจ้าของ|owner)\s*([A-Za-z2-9]{6})$/i
const SUMMARY_RE = /^(?:สรุป|สรุปวันนี้|summary)$/i
const OWNER_UNLINK_RE = /^(?:เลิกรับสรุป|stop summary)$/i

const EVENT_LABELS: Record<string, string> = {
  NEW_BOOKING: 'จองใหม่ (ไม่ต้องมัดจำ)',
  DEPOSIT_SLIP: 'สลิปมัดจำรอตรวจ',
  DEPOSIT_REVIEWED: 'ตรวจสลิปแล้ว',
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
      // ตอบกลับเป็นการ์ด (การตอบกลับไม่นับโควตา) · การ์ดไม่ผ่าน → lineReply ส่งข้อความธรรมดาแทน
      const reply = (m: Parameters<typeof lineReply>[2]) => lineReply(token, ev.replyToken ?? '', m)

      if (ev.type === 'join' && groupId) {
        await reply(
          noticeMessage('สวัสดีครับ เชื่อมกลุ่มนี้กับระบบร้าน: สร้างรหัสในแอปพนักงาน แล้วพิมพ์ เชื่อมร้าน รหัส', {
            title: 'สวัสดีครับ 🙏',
            sub: 'เชื่อมกลุ่มนี้เพื่อรับแจ้งเตือนจากร้าน',
            lines: ['1. เจ้าของร้านเปิดแอปพนักงาน → LINE OA → สร้างรหัส', '2. พิมพ์ในกลุ่มนี้ว่า “เชื่อมร้าน รหัส”', 'เช่น เชื่อมร้าน ABC123'],
          }),
        )
        continue
      }

      if (ev.type === 'leave' && groupId) {
        await admin.rpc('line_group_left', { p_group_id: groupId })
        continue
      }

      // แชท 1:1 กับ OA: เจ้าของร้านผูก LINE รับสรุปรายวัน / ขอสรุปวันนี้ / เลิกรับสรุป (migration 077)
      const userId = ev.source?.type === 'user' ? ev.source.userId ?? '' : ''
      if (ev.type === 'message' && ev.message?.type === 'text' && userId) {
        const t = (ev.message.text ?? '').trim()
        const own = OWNER_LINK_RE.exec(t)
        if (own) {
          if (!(await rateLimit(admin, `line-owner:${userId}`, 10, 600))) {
            await reply(noticeMessage('ลองหลายครั้งเกินไป กรุณารอ 10 นาทีแล้วลองใหม่', { title: 'ลองหลายครั้งเกินไป', tone: 'pending', lines: ['กรุณารอ 10 นาทีแล้วลองใหม่'] }))
            continue
          }
          const name = await lineUserName(token, userId)
          const { data, error } = await admin.rpc('line_link_owner', {
            p_company_id: companyId, p_code: own[1]!.toUpperCase(), p_line_user_id: userId, p_name: name ?? '',
          })
          if (error) throw error
          const linked = data as { company_name: string; summary_time: string } | null
          await reply(
            linked
              ? noticeMessage(`✅ เชื่อม LINE ของเจ้าของร้าน ${linked.company_name} แล้ว`, {
                  title: '✅ เชื่อมแล้ว',
                  sub: linked.company_name,
                  tone: 'success',
                  lines: [`จะส่งสรุปประจำวันมาที่แชทนี้ทุกวัน เวลา ${linked.summary_time} น.`, 'พิมพ์ “สรุป” เพื่อดูสรุปของวันนี้ได้ทุกเมื่อ', 'เปลี่ยนเวลาได้ในแอปพนักงาน → LINE OA'],
                })
              : noticeMessage('รหัสไม่ถูกต้องหรือหมดอายุแล้ว กรุณาสร้างรหัสใหม่ในแอปพนักงาน', {
                  title: 'รหัสไม่ถูกต้อง',
                  tone: 'danger',
                  lines: ['รหัสไม่ถูกต้องหรือหมดอายุแล้ว (ใช้ได้ 30 นาที ครั้งเดียว)', 'สร้างรหัสใหม่ในแอปพนักงาน → LINE OA'],
                }),
          )
          continue
        }
        if (SUMMARY_RE.test(t)) {
          const { data, error } = await admin.rpc('line_owner_summary_now', { p_company_id: companyId, p_line_user_id: userId })
          if (error) throw error
          if (data) {
            const s = data as FlexSummary & { link?: string | null }
            await reply(summaryMessage(s, s.link ?? null))
          }
          continue // ไม่ใช่เจ้าของที่ผูกไว้ = เงียบ (ไม่เปิดเผยข้อมูลร้าน)
        }
        if (OWNER_UNLINK_RE.test(t)) {
          const { data, error } = await admin.rpc('line_unlink_owner_by_line', { p_company_id: companyId, p_line_user_id: userId })
          if (error) throw error
          if (data) {
            await reply(noticeMessage('เลิกส่งสรุปประจำวันมาที่แชทนี้แล้ว', {
              title: 'เลิกรับสรุปแล้ว', tone: 'beige', lines: ['จะไม่ส่งสรุปประจำวันมาที่แชทนี้อีก', 'เชื่อมใหม่ได้ด้วยรหัสจากแอปพนักงาน'],
            }))
          }
          continue
        }
        continue
      }

      if (ev.type !== 'message' || ev.message?.type !== 'text' || !groupId) continue
      const text = (ev.message.text ?? '').trim()

      if (UNLINK_RE.test(text)) {
        await admin.rpc('line_group_left', { p_group_id: groupId })
        await reply(
          noticeMessage('เลิกส่งแจ้งเตือนเข้ากลุ่มนี้แล้ว', {
            title: 'เลิกส่งแจ้งเตือนแล้ว',
            tone: 'beige',
            lines: ['กลุ่มนี้จะไม่ได้รับแจ้งเตือนจากร้านอีก', 'เชื่อมใหม่ได้ด้วยรหัสจากแอปพนักงาน'],
          }),
        )
        continue
      }

      const m = LINK_RE.exec(text)
      if (!m) continue
      if (!(await rateLimit(admin, `line-link:${groupId}`, 10, 600))) {
        await reply(
          noticeMessage('ลองหลายครั้งเกินไป กรุณารอ 10 นาทีแล้วลองใหม่', { title: 'ลองหลายครั้งเกินไป', tone: 'pending', lines: ['กรุณารอ 10 นาทีแล้วลองใหม่'] }),
        )
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
      if (linked) {
        const where = linked.branch_name ? `${linked.branch_name.startsWith('สาขา') ? '' : 'สาขา'}${linked.branch_name}` : 'ทุกสาขา'
        await reply(
          noticeMessage(`✅ เชื่อมกลุ่มนี้กับ ${linked.company_name} (${where}) แล้ว`, {
            title: '✅ เชื่อมกลุ่มแล้ว',
            sub: `${linked.company_name} · ${where}`,
            tone: 'success',
            lines: events.length
              ? ['จะแจ้งเตือนในกลุ่มนี้เมื่อ', ...events.map((e) => `• ${e}`)]
              : ['ยังไม่ได้เลือกเหตุการณ์ที่จะแจ้งเตือน', 'ตั้งได้ในแอปพนักงาน → LINE OA'],
          }),
        )
      } else {
        await reply(
          noticeMessage('รหัสไม่ถูกต้องหรือหมดอายุแล้ว กรุณาสร้างรหัสใหม่ในแอปพนักงาน', {
            title: 'รหัสไม่ถูกต้อง',
            tone: 'danger',
            lines: ['รหัสไม่ถูกต้องหรือหมดอายุแล้ว (ใช้ได้ 30 นาที ครั้งเดียว)', 'กรุณาสร้างรหัสใหม่ในแอปพนักงาน'],
          }),
        )
      }
    } catch (e) {
      console.error('line-webhook event', ev.type, e)
    }
  }
  return ok()
})
