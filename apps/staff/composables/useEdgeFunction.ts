/** เรียก Edge Function ด้วย JWT ของผู้ใช้ปัจจุบัน (อ่าน session ล่าสุดทุกครั้ง เผื่อเพิ่ง step-up) */
export function useEdgeFunction() {
  const config = useRuntimeConfig()
  const supabase = useSupabaseClient()
  const baseUrl = computed(() => config.public.functionsUrl || `${config.public.supabase.url}/functions/v1`)

  async function call<T>(name: string, body: Record<string, unknown>): Promise<T> {
    const { data } = await supabase.auth.getSession()
    if (!data.session) throw new Error('กรุณาเข้าสู่ระบบใหม่')
    return await $fetch<T>(`${baseUrl.value}/${name}`, {
      method: 'POST',
      body,
      headers: {
        apikey: config.public.supabase.key,
        Authorization: `Bearer ${data.session.access_token}`,
      },
    })
  }

  return { call }
}
