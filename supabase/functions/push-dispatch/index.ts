// POST /functions/v1/push-dispatch   (เรียกจาก DB ผ่าน pg_net เท่านั้น — ไม่มี CORS / ไม่ต้องมี JWT)
// body: { id }  = private.push_outbox.id (ใช้ได้ครั้งเดียว ภายใน 15 นาที)
// 1) public.push_claim(id) → ข้อความ + เครื่องผู้รับ (คนที่ทำรายการเองถูกตัดออกแล้ว)
// 2) ส่ง Web Push (VAPID) ทุกเครื่อง · เครื่องที่ยกเลิกรับแล้ว (404/410) ลบออกจาก push_subscriptions
// 3) ส่ง LINE push message ไป line_to (กลุ่มพนักงาน หรือ LINE ของลูกค้าตอนเตือนนัด)
//    กลุ่มที่บอทไม่ได้อยู่แล้ว (400) ลบออกจาก line_groups
// ENV: VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT (https://… หรือ mailto:…)
// LINE: token ของบริษัทจาก public.line_secret (ตั้งในแอปพนักงาน /settings/line · ไม่ตั้ง = ข้าม LINE)
import webpush from 'npm:web-push@3.6.7'
import { adminClient, UUID_RE } from '../_shared/http.ts'
import { linePush, lineSecret, type FlexData } from '../_shared/line.ts'

interface Claim {
  company_id: string
  title: string
  body: string
  url: string
  tag: string
  subscriptions: Array<{ endpoint: string; p256dh: string; auth: string }>
  line_to?: string[]
  line_text?: string | null
  /** ข้อมูลการ์ด Flex (migration 069) · ไม่มี = ส่งข้อความธรรมดา */
  line_flex?: FlexData | null
}

const reply = (status: number, body: unknown = {}) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

// สลิปที่ผ่านแล้ว: แนบรูปสลิปในการ์ดกลุ่ม (bucket booking-slips เป็น private → signed URL อายุ 30 วัน)
const SLIP_URL_TTL = 30 * 24 * 60 * 60
async function attachSlip(admin: ReturnType<typeof adminClient>, claim: Claim): Promise<void> {
  const f = claim.line_flex
  if (f?.kind !== 'staff' || f.event !== 'DEPOSIT_REVIEWED' || !f.review_ok) return
  const depositId = claim.tag.replace(/^deposit_reviewed-/, '')
  if (!UUID_RE.test(depositId)) return
  try {
    const { data } = await admin.from('booking_deposits').select('slip_path').eq('id', depositId).maybeSingle()
    const path = (data as { slip_path: string | null } | null)?.slip_path
    if (!path) return
    const { data: signed, error } = await admin.storage.from('booking-slips').createSignedUrl(path, SLIP_URL_TTL)
    if (error) throw error
    f.slip_url = signed?.signedUrl ?? null
  } catch (e) {
    console.error('push-dispatch slip url', (e as Error).message) // ไม่มีรูปก็ยังส่งการ์ดได้
  }
}

async function sendLine(admin: ReturnType<typeof adminClient>, claim: Claim): Promise<number> {
  const to = claim.line_to ?? []
  if (!to.length || !claim.line_text) return 0
  const token = (await lineSecret(admin, { companyId: claim.company_id }))?.access_token
  if (!token) return 0
  await attachSlip(admin, claim)
  const gone: string[] = []
  let sent = 0
  await Promise.all(
    to.map(async (target) => {
      try {
        const status = await linePush(token, target, claim.line_text!, claim.line_flex)
        if (status === 200) sent++
        else if (status === 400 && target.startsWith('C')) gone.push(target) // บอทไม่ได้อยู่ในกลุ่มนี้แล้ว
      } catch (e) {
        console.error('push-dispatch line', (e as Error).message)
      }
    }),
  )
  if (gone.length) {
    const { error } = await admin.rpc('line_remove_targets', { p_ids: gone })
    if (error) console.error('push-dispatch line cleanup', error)
  }
  return sent
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return reply(405)

  let id = ''
  try {
    id = String(((await req.json()) as { id?: unknown }).id ?? '')
  } catch {
    return reply(400)
  }
  if (!UUID_RE.test(id)) return reply(400)

  const publicKey = Deno.env.get('VAPID_PUBLIC_KEY')
  const privateKey = Deno.env.get('VAPID_PRIVATE_KEY')
  const subject = Deno.env.get('VAPID_SUBJECT')

  try {
    const admin = adminClient()
    const { data, error } = await admin.rpc('push_claim', { p_id: id })
    if (error) throw error
    const claim = data as Claim | null
    if (!claim) return reply(200, { sent: 0 }) // ใช้ไปแล้ว / หมดอายุ / ไม่มีอยู่จริง
    const lineSent = await sendLine(admin, claim)
    if (!claim.subscriptions.length) return reply(200, { sent: 0, line: lineSent })
    if (!publicKey || !privateKey || !subject) {
      console.error('push-dispatch: missing VAPID env')
      return reply(500)
    }

    webpush.setVapidDetails(subject, publicKey, privateKey)
    const payload = JSON.stringify({ title: claim.title, body: claim.body, url: claim.url, tag: claim.tag })
    const gone: string[] = []
    let sent = 0

    await Promise.all(
      claim.subscriptions.map(async (s) => {
        try {
          await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, {
            TTL: 60 * 60,
            urgency: 'high',
          })
          sent++
        } catch (e) {
          const status = (e as { statusCode?: number }).statusCode
          if (status === 404 || status === 410) gone.push(s.endpoint)
          else console.error('push-dispatch send', status, (e as Error).message)
        }
      }),
    )

    if (gone.length) {
      const { error: delErr } = await admin.rpc('push_remove_subscriptions', { p_endpoints: gone })
      if (delErr) console.error('push-dispatch cleanup', delErr)
    }
    return reply(200, { sent, removed: gone.length, line: lineSent })
  } catch (e) {
    console.error('push-dispatch', e)
    return reply(500)
  }
})
