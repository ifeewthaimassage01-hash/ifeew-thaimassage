// LINE Messaging API + LINE Login (LIFF) helper
// ค่าทั้งหมดตั้งจากแอปพนักงาน (/settings/line) → private.line_settings + Supabase Vault
// อ่านด้วย public.line_secret (service_role เท่านั้น)
import type { SupabaseClient } from 'npm:@supabase/supabase-js@2'
import { buildLineMessage, type FlexData } from './lineFlex.ts'

export type { FlexData } from './lineFlex.ts'
export type { FlexSummary } from './lineFlex.ts'
export { noticeMessage, sampleStaffMessage, summaryMessage } from './lineFlex.ts'
type LineMessage = Record<string, unknown>

const API = 'https://api.line.me'

export interface LineSecret {
  company_id: string
  access_token: string | null
  channel_secret: string | null
  login_channel_id: string | null
  confirm_enabled: boolean
  webhook_url: string
}

export async function lineSecret(
  admin: SupabaseClient,
  by: { companyId?: string; companyCode?: string },
): Promise<LineSecret | null> {
  const { data, error } = await admin.rpc('line_secret', {
    p_company_id: by.companyId ?? null,
    p_company_code: by.companyCode ?? null,
  })
  if (error) throw error
  return (data as LineSecret | null) ?? null
}

async function lineFetch(token: string, path: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(`${API}${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', ...(init.headers ?? {}) },
  })
}

async function pushOnce(token: string, to: string, message: Record<string, unknown>): Promise<number> {
  const res = await lineFetch(token, '/v2/bot/message/push', {
    method: 'POST',
    body: JSON.stringify({ to, messages: [message] }),
  })
  if (!res.ok) console.error('line push', message.type, res.status, await res.text().catch(() => ''))
  return res.status
}

/**
 * ส่ง push message (นับโควตาของ LINE OA) · คืน HTTP status
 * flex = ข้อมูลการ์ด (ดู lineFlex.ts) → ส่งเป็นการ์ด · LINE ไม่รับการ์ด (400) → ส่งข้อความธรรมดาแทนอัตโนมัติ
 */
export async function linePush(token: string, to: string, text: string, flex?: FlexData | null): Promise<number> {
  const message = buildLineMessage(text, flex)
  const status = await pushOnce(token, to, message)
  if (status === 400 && message.type === 'flex') return await pushOnce(token, to, { type: 'text', text: text.slice(0, 5000) })
  return status
}

/** ตอบกลับข้อความ (ฟรี ไม่นับโควตา) ด้วย replyToken จาก webhook */
export async function lineReply(token: string, replyToken: string, message: string | LineMessage): Promise<void> {
  if (!replyToken) return
  const msg: LineMessage = typeof message === 'string' ? { type: 'text', text: message.slice(0, 5000) } : message
  const res = await lineFetch(token, '/v2/bot/message/reply', {
    method: 'POST',
    body: JSON.stringify({ replyToken, messages: [msg] }),
  })
  if (res.ok) return
  console.error('line reply', msg.type, res.status, await res.text().catch(() => ''))
  // การ์ดไม่ผ่าน → ส่งข้อความธรรมดาแทน (replyToken ยังใช้ได้เพราะครั้งแรกไม่สำเร็จ)
  if (res.status === 400 && msg.type === 'flex') {
    await lineFetch(token, '/v2/bot/message/reply', {
      method: 'POST',
      body: JSON.stringify({ replyToken, messages: [{ type: 'text', text: String(msg.altText ?? '').slice(0, 5000) || ' ' }] }),
    })
  }
}

/** ส่ง push ข้อความสำเร็จรูป (เช่น การ์ดจาก noticeMessage) · การ์ดไม่ผ่าน → ส่ง altText เป็นข้อความธรรมดา */
export async function linePushMessage(token: string, to: string, message: LineMessage): Promise<number> {
  const status = await pushOnce(token, to, message)
  if (status === 400 && message.type === 'flex') return await pushOnce(token, to, { type: 'text', text: String(message.altText ?? '').slice(0, 5000) || ' ' })
  return status
}

/** ชื่อที่แสดงของผู้ใช้ที่เป็นเพื่อนกับ OA (null = ดึงไม่ได้) */
export async function lineUserName(token: string, userId: string): Promise<string | null> {
  const res = await lineFetch(token, `/v2/bot/profile/${encodeURIComponent(userId)}`)
  if (!res.ok) return null
  return ((await res.json()) as { displayName?: string }).displayName ?? null
}

export async function lineGroupName(token: string, groupId: string): Promise<string | null> {
  const res = await lineFetch(token, `/v2/bot/group/${encodeURIComponent(groupId)}/summary`)
  if (!res.ok) return null
  return ((await res.json()) as { groupName?: string }).groupName ?? null
}

/** GET แบบคืน JSON หรือ null (ใช้ในหน้าตั้งค่า) */
export async function lineGet<T>(token: string, path: string): Promise<{ status: number; data: T | null }> {
  const res = await lineFetch(token, path)
  return { status: res.status, data: res.ok ? ((await res.json()) as T) : null }
}

export async function lineSend<T>(
  token: string,
  method: 'POST' | 'PUT',
  path: string,
  body: unknown,
): Promise<{ status: number; data: T | null }> {
  const res = await lineFetch(token, path, { method, body: JSON.stringify(body) })
  const text = await res.text()
  let data: T | null = null
  try {
    data = text ? (JSON.parse(text) as T) : null
  } catch {
    data = null
  }
  return { status: res.status, data }
}

/** ตรวจลายเซ็น webhook: base64(HMAC-SHA256(channel secret, raw body)) */
export async function lineSignatureOk(secret: string | null, rawBody: string, signature: string | null): Promise<boolean> {
  if (!secret || !signature) return false
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, [
    'sign',
  ])
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody)))
  const expected = btoa(String.fromCharCode(...mac))
  if (expected.length !== signature.length) return false
  let diff = 0
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ signature.charCodeAt(i)
  return diff === 0
}

/** ยืนยัน LIFF ID token กับ LINE → LINE user ID (sub) หรือ null */
export async function lineVerifyIdToken(loginChannelId: string | null, idToken: string): Promise<string | null> {
  if (!loginChannelId || !idToken || idToken.length > 4000) return null
  const res = await fetch(`${API}/oauth2/v2.1/verify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ id_token: idToken, client_id: loginChannelId }),
  })
  if (!res.ok) {
    console.warn('line verify id token', res.status)
    return null
  }
  const sub = ((await res.json()) as { sub?: string }).sub ?? ''
  return /^U[0-9a-f]{32}$/.test(sub) ? sub : null
}
