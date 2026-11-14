// POST /functions/v1/push-dispatch   (เรียกจาก DB ผ่าน pg_net เท่านั้น — ไม่มี CORS / ไม่ต้องมี JWT)
// body: { id }  = private.push_outbox.id (ใช้ได้ครั้งเดียว ภายใน 15 นาที)
// 1) public.push_claim(id) → ข้อความ + เครื่องผู้รับ (คนที่ทำรายการเองถูกตัดออกแล้ว)
// 2) ส่ง Web Push (VAPID) ทุกเครื่อง · เครื่องที่ยกเลิกรับแล้ว (404/410) ลบออกจาก push_subscriptions
// ENV: VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT (https://… หรือ mailto:…)
import webpush from 'npm:web-push@3.6.7'
import { adminClient, UUID_RE } from '../_shared/http.ts'

interface Claim {
  title: string
  body: string
  url: string
  tag: string
  subscriptions: Array<{ endpoint: string; p256dh: string; auth: string }>
}

const reply = (status: number, body: unknown = {}) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

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
  if (!publicKey || !privateKey || !subject) {
    console.error('push-dispatch: missing VAPID env')
    return reply(500)
  }

  try {
    const admin = adminClient()
    const { data, error } = await admin.rpc('push_claim', { p_id: id })
    if (error) throw error
    const claim = data as Claim | null
    if (!claim) return reply(200, { sent: 0 }) // ใช้ไปแล้ว / หมดอายุ / ไม่มีอยู่จริง
    if (!claim.subscriptions.length) return reply(200, { sent: 0 })

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
    return reply(200, { sent, removed: gone.length })
  } catch (e) {
    console.error('push-dispatch', e)
    return reply(500)
  }
})
