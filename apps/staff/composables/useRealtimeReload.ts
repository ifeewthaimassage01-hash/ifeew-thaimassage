/**
 * โหลดข้อมูลใหม่เมื่อตารางใน Supabase Realtime เปลี่ยน (เครื่องอื่นบันทึก / ลูกค้าทำรายการ)
 * - sources: ตาราง + filter ที่จะฟัง (คืน null = ยังไม่พร้อม เช่น ยังไม่รู้สาขา) · เปลี่ยนเมื่อไรก็ผูกใหม่
 * - เหตุการณ์ที่มาติด ๆ กันรวบเป็นการโหลดครั้งเดียว (delay ms)
 * - สำรองกรณี Realtime หลุด: โหลดใหม่ทุก fallbackMs ขณะเปิดหน้า (0 = ไม่ใช้)
 * ตารางต้องอยู่ใน publication supabase_realtime และ RLS อนุญาตให้ผู้ใช้อ่าน ไม่งั้นจะไม่มีเหตุการณ์มา
 */
export interface RealtimeSource {
  table: string
  /** เช่น `branch_id=eq.<uuid>` */
  filter?: string
}

export function useRealtimeReload(
  name: string,
  sources: () => RealtimeSource[] | null,
  reload: () => unknown,
  opts: { delay?: number; fallbackMs?: number } = {},
) {
  const supabase = useSupabaseClient()
  const instanceId = Math.random().toString(36).slice(2, 8) // ชื่อ channel ไม่ซ้ำต่อ instance
  let channel: ReturnType<typeof supabase.channel> | null = null
  let timer: ReturnType<typeof setTimeout> | null = null

  const schedule = () => {
    if (timer) clearTimeout(timer)
    timer = setTimeout(() => void reload(), opts.delay ?? 400)
  }
  function unsubscribe() {
    if (channel) supabase.removeChannel(channel)
    channel = null
  }

  watch(
    () => JSON.stringify(sources()),
    (key) => {
      unsubscribe()
      const list = JSON.parse(key) as RealtimeSource[] | null
      if (!import.meta.client || !list?.length) return
      let ch = supabase.channel(`${name}-${instanceId}`)
      for (const s of list) {
        ch = ch.on('postgres_changes', { event: '*', schema: 'public', table: s.table, ...(s.filter ? { filter: s.filter } : {}) }, schedule)
      }
      channel = ch.subscribe()
    },
    { immediate: true },
  )

  if (opts.fallbackMs !== 0) useLiveInterval(reload, opts.fallbackMs ?? 60_000)

  onBeforeUnmount(() => {
    unsubscribe()
    if (timer) clearTimeout(timer)
  })
}
