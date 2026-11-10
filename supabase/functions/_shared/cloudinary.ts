// Cloudinary ฝั่ง server (Edge Function) — ใช้ API secret ที่อยู่ใน secret ของ function เท่านั้น
//   uploadPrivate(): อัปโหลดแบบ type=authenticated (เปิดดูได้เฉพาะ URL ที่เซ็นแล้ว) — ใช้กับสลิปโอนเงิน
//   signedPrivateUrl(): URL ดูรูป authenticated (ลายเซ็นในพาธ ไม่มีวันหมดอายุ แต่เดาไม่ได้)

export const CLOUDINARY_PREFIX = 'cloudinary:'

interface CloudinaryEnv {
  cloudName: string
  apiKey: string
  apiSecret: string
}

export function cloudinaryEnv(): CloudinaryEnv | null {
  const cloudName = Deno.env.get('CLOUDINARY_CLOUD_NAME')
  const apiKey = Deno.env.get('CLOUDINARY_API_KEY')
  const apiSecret = Deno.env.get('CLOUDINARY_API_SECRET')
  return cloudName && apiKey && apiSecret ? { cloudName, apiKey, apiSecret } : null
}

async function sha1(value: string): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest('SHA-1', new TextEncoder().encode(value)))
}

const hex = (b: Uint8Array) => [...b].map((x) => x.toString(16).padStart(2, '0')).join('')
const base64Url = (b: Uint8Array) =>
  btoa(String.fromCharCode(...b)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')

/** อัปโหลดไฟล์แบบ private (authenticated) แล้วคืน public_id */
export async function uploadPrivate(env: CloudinaryEnv, file: File, folder: string, publicId: string): Promise<string> {
  const params: Record<string, string> = {
    allowed_formats: 'jpg,jpeg,png,webp',
    folder,
    overwrite: 'false',
    public_id: publicId,
    timestamp: String(Math.floor(Date.now() / 1000)),
    type: 'authenticated',
  }
  const toSign = Object.keys(params).sort().map((k) => `${k}=${params[k]}`).join('&')
  const form = new FormData()
  form.append('file', file)
  form.append('api_key', env.apiKey)
  form.append('signature', hex(await sha1(toSign + env.apiSecret)))
  for (const [k, v] of Object.entries(params)) form.append(k, v)

  const res = await fetch(`https://api.cloudinary.com/v1_1/${env.cloudName}/image/upload`, { method: 'POST', body: form })
  const out = (await res.json().catch(() => ({}))) as { public_id?: string; error?: { message?: string } }
  if (!res.ok || !out.public_id) throw new Error(`cloudinary upload failed: ${out.error?.message ?? res.status}`)
  return out.public_id
}

/** URL ดูรูป authenticated — ลายเซ็น = 8 ตัวแรกของ base64url(SHA-1("<transformation>/<public_id>" + secret)) */
export async function signedPrivateUrl(env: CloudinaryEnv, publicId: string, transformation = 'c_limit,w_1600,q_auto'): Promise<string> {
  const toSign = `${transformation}/${publicId}`
  const sig = base64Url(await sha1(toSign + env.apiSecret)).slice(0, 8)
  return `https://res.cloudinary.com/${env.cloudName}/image/authenticated/s--${sig}--/${toSign}`
}
