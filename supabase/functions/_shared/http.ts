// Helper ร่วมของ Edge Functions: CORS, JSON response, client IP, Supabase clients
import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2'

const allowedOrigins = (Deno.env.get('ALLOWED_ORIGINS') ?? '')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean)

export function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('origin') ?? ''
  const allow = allowedOrigins.includes(origin) ? origin : ''
  return {
    'Access-Control-Allow-Origin': allow,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Max-Age': '600',
    Vary: 'Origin',
  }
}

export function json(req: Request, status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  })
}

/** ตรวจ Cloudflare Turnstile (CAPTCHA) ฝั่ง server */
export async function verifyTurnstile(token: string, ip: string): Promise<boolean> {
  const secret = Deno.env.get('TURNSTILE_SECRET_KEY')
  if (!secret) throw new Error('Missing env: TURNSTILE_SECRET_KEY')
  if (!token) return false
  const form = new FormData()
  form.append('secret', secret)
  form.append('response', token)
  if (ip && ip !== 'unknown') form.append('remoteip', ip)
  const res = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', { method: 'POST', body: form })
  if (!res.ok) return false
  const data = (await res.json()) as { success?: boolean }
  return data.success === true
}

export function preflight(req: Request): Response | null {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders(req) })
  if (req.method !== 'POST') return json(req, 405, { error_code: 'METHOD_NOT_ALLOWED' })
  return null
}

export function clientIp(req: Request): string {
  const fwd = req.headers.get('x-forwarded-for')
  return (fwd?.split(',')[0] ?? req.headers.get('x-real-ip') ?? 'unknown').trim()
}

export async function sha256Hex(value: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

function requireEnv(...names: string[]): string {
  for (const n of names) {
    const v = Deno.env.get(n)
    if (v) return v
  }
  throw new Error(`Missing env: ${names.join(' | ')}`)
}

const noSession = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } }

/** Client สิทธิ์ secret/service role — ใช้ฝั่ง server เท่านั้น */
export function adminClient(): SupabaseClient {
  return createClient(
    requireEnv('SUPABASE_URL'),
    requireEnv('SUPABASE_SECRET_KEY', 'SUPABASE_SERVICE_ROLE_KEY'),
    noSession,
  )
}

/** Client สิทธิ์ publishable/anon — ใช้แลก token เป็น session */
export function publicClient(): SupabaseClient {
  return createClient(
    requireEnv('SUPABASE_URL'),
    requireEnv('SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_ANON_KEY'),
    noSession,
  )
}

/**
 * Client ที่ทำงานด้วยสิทธิ์ของผู้เรียก (ส่ง JWT ต่อให้ PostgREST)
 * DB Function จะตรวจ OWNER + step-up TOTP จาก JWT นี้เอง
 */
export function userClient(req: Request): SupabaseClient {
  const authorization = req.headers.get('authorization') ?? ''
  return createClient(
    requireEnv('SUPABASE_URL'),
    requireEnv('SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_ANON_KEY'),
    { ...noSession, global: { headers: { Authorization: authorization } } },
  )
}

/** แปลง error จาก PostgREST เป็น response (ไม่ส่งรายละเอียดภายในออกไป) */
export function dbErrorResponse(req: Request, error: { code?: string; message?: string }): Response {
  if (error.message === 'STEP_UP_REQUIRED') return json(req, 403, { error_code: 'STEP_UP_REQUIRED' })
  if (error.code === '42501') return json(req, 403, { error_code: 'FORBIDDEN', message: error.message })
  if (error.code === '23505') return json(req, 409, { error_code: 'DUPLICATE', message: 'ข้อมูลซ้ำ (เช่น รหัสพนักงาน)' })
  if (error.code && ['22023', '23514', 'P0002'].includes(error.code)) {
    return json(req, 400, { error_code: 'INVALID', message: error.message })
  }
  return json(req, 500, { error_code: 'INTERNAL_ERROR' })
}

/** fixed-window rate limit ผ่าน public.rate_limit_hit (true = ผ่าน) */
export async function rateLimit(
  admin: SupabaseClient,
  key: string,
  limit: number,
  windowSeconds: number,
): Promise<boolean> {
  const { data, error } = await admin.rpc('rate_limit_hit', {
    p_bucket_key: key,
    p_limit: limit,
    p_window_seconds: windowSeconds,
  })
  if (error) throw error
  return data === true
}

export const DEVICE_TOKEN_RE = /^dvc_[0-9a-f]{64}$/
export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
