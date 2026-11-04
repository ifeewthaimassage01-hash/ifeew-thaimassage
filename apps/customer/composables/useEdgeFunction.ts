/** เรียก Edge Function (แนบ JWT ของสมาชิกถ้า login อยู่) */
export function useEdgeFunction() {
  const config = useRuntimeConfig()
  const supabase = useSupabaseClient()
  const baseUrl = computed(() => (config.public.functionsUrl as string) || `${config.public.supabase.url}/functions/v1`)

  async function headers(withAuth: boolean): Promise<Record<string, string>> {
    const h: Record<string, string> = { apikey: config.public.supabase.key as string }
    if (withAuth) {
      const { data } = await supabase.auth.getSession()
      if (data.session) h.Authorization = `Bearer ${data.session.access_token}`
    }
    return h
  }

  async function call<T>(name: string, body: Record<string, unknown> | FormData, withAuth = false): Promise<T> {
    return await $fetch<T>(`${baseUrl.value}/${name}`, { method: 'POST', body, headers: await headers(withAuth) })
  }

  return { call }
}

/** ข้อความ error ที่แสดงลูกค้าได้ */
export function edgeErrorText(e: unknown, fallback = 'ทำรายการไม่สำเร็จ กรุณาลองใหม่'): string {
  const err = e as { data?: { error_code?: string; message?: string }; message?: string } | null
  const code = err?.data?.error_code
  const map: Record<string, string> = {
    CAPTCHA_FAILED: 'ยืนยันว่าไม่ใช่บอทไม่สำเร็จ กรุณาลองใหม่',
    RATE_LIMITED: 'ทำรายการบ่อยเกินไป กรุณารอสักครู่',
    CAPACITY_FULL: 'ช่วงเวลานี้เต็มแล้ว กรุณาเลือกเวลาอื่น',
    NOT_FOUND: 'ไม่พบการจอง หรือลิงก์หมดอายุแล้ว',
    INVALID_FILE: 'รองรับไฟล์รูป JPG/PNG/WebP ไม่เกิน 5 MB',
  }
  if (code && map[code]) return map[code]
  return err?.data?.message ?? fallback
}
