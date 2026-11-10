import { CLOUDINARY_PREFIX, publicImageUrl } from '@ifeew/shared'

type ImageKind = 'service' | 'branch'

interface SignResponse {
  cloud_name: string
  api_key: string
  signature: string
  timestamp: string
  folder: string
  public_id: string
  allowed_formats: string
  overwrite: string
}

const BUCKET: Record<ImageKind, string> = { service: 'service-images', branch: 'branch-images' }
export const IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp']
export const IMAGE_MAX_BYTES = 5 * 1024 * 1024

/**
 * รูปบริการ/รูปสาขาบน Cloudinary
 *   upload(): ขอลายเซ็นจาก Edge Function cloudinary-sign (ตรวจว่าเป็น OWNER) แล้วอัปโหลดตรงไป Cloudinary
 *             คืนค่าที่ต้องเก็บใน image_path ("cloudinary:<public_id>") — ผู้เรียกบันทึกลง DB เอง
 *   url():    URL สำหรับแสดง (รองรับทั้งรูปบน Cloudinary และรูปเก่าใน Supabase Storage)
 */
export function useImageUpload() {
  const config = useRuntimeConfig()
  const { call } = useEdgeFunction()

  function url(kind: ImageKind, path: string | null | undefined, width = 800): string | null {
    return publicImageUrl(path, {
      supabaseUrl: config.public.supabase.url as string,
      bucket: BUCKET[kind],
      cloudName: (config.public.cloudinaryCloudName as string) || null,
      width,
    })
  }

  async function upload(kind: ImageKind, targetId: string, file: File): Promise<string> {
    if (!IMAGE_TYPES.includes(file.type) || file.size > IMAGE_MAX_BYTES) {
      throw new Error('รูปต้องเป็น JPG/PNG/WebP ขนาดไม่เกิน 5 MB')
    }
    const s = await call<SignResponse>('cloudinary-sign', { kind, target_id: targetId })
    const form = new FormData()
    form.append('file', file)
    form.append('api_key', s.api_key)
    form.append('timestamp', s.timestamp)
    form.append('signature', s.signature)
    form.append('folder', s.folder)
    form.append('public_id', s.public_id)
    form.append('allowed_formats', s.allowed_formats)
    form.append('overwrite', s.overwrite)
    const res = await fetch(`https://api.cloudinary.com/v1_1/${s.cloud_name}/image/upload`, { method: 'POST', body: form })
    const out = (await res.json().catch(() => ({}))) as { public_id?: string; error?: { message?: string } }
    if (!res.ok || !out.public_id) throw new Error(`อัปโหลดรูปไม่สำเร็จ${out.error?.message ? `: ${out.error.message}` : ''}`)
    return `${CLOUDINARY_PREFIX}${out.public_id}`
  }

  return { url, upload }
}
