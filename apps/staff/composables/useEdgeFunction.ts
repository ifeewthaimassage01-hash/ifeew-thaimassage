/** เรียก Edge Function ด้วย JWT ของผู้ใช้ปัจจุบัน (อ่าน session ล่าสุดทุกครั้ง เผื่อเพิ่ง step-up) */
export function useEdgeFunction() {
  const config = useRuntimeConfig()
  const supabase = useSupabaseClient()
  const baseUrl = computed(() => config.public.functionsUrl || `${config.public.supabase.url}/functions/v1`)

  async function headers(): Promise<Record<string, string>> {
    const { data } = await supabase.auth.getSession()
    if (!data.session) throw new Error('กรุณาเข้าสู่ระบบใหม่')
    return { apikey: config.public.supabase.key, Authorization: `Bearer ${data.session.access_token}` }
  }

  async function call<T>(name: string, body: Record<string, unknown>): Promise<T> {
    return await $fetch<T>(`${baseUrl.value}/${name}`, { method: 'POST', body, headers: await headers() })
  }

  /** ส่ง multipart/form-data (เช่น รูปสลิป) */
  async function callForm<T>(name: string, form: FormData): Promise<T> {
    return await $fetch<T>(`${baseUrl.value}/${name}`, { method: 'POST', body: form, headers: await headers() })
  }

  return { call, callForm }
}

/** ข้อความ error จาก Edge Function (message ไทยจาก DB ถ้ามี) */
export function edgeErrorText(e: unknown, fallback = 'ดำเนินการไม่สำเร็จ'): string {
  const data = (e as { data?: { message?: string; error_code?: string } } | null)?.data
  if (data?.message) return data.message
  if (data?.error_code === 'RATE_LIMITED') return 'ส่งคำขอถี่เกินไป กรุณารอสักครู่'
  if (data?.error_code === 'INVALID_FILE') return 'รองรับรูป JPG/PNG/WebP ไม่เกิน 5 MB'
  return errorText(e, fallback)
}
