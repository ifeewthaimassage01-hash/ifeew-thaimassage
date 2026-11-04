import type { PosBoard } from '@ifeew/shared'

/**
 * กระดานคิวของสาขาที่เลือก (public.pos_board) + Realtime
 * Realtime ใช้แค่บอกว่า "มีอะไรเปลี่ยน" แล้วโหลดใหม่จาก DB (ความถูกต้องอยู่ที่ Database)
 * ผูก/เลิกผูก channel ตามสาขา และเลิกผูกเมื่อออกจากหน้า
 */
export function usePosBoard() {
  const supabase = useSupabaseClient()
  const { activeBranch } = useAccess()

  const board = ref<PosBoard | null>(null)
  const loading = ref(false)
  const error = ref<string | null>(null)
  let channel: ReturnType<typeof supabase.channel> | null = null
  let timer: ReturnType<typeof setTimeout> | null = null

  async function load() {
    const branchId = activeBranch.value?.branch_id
    if (!branchId) return
    loading.value = !board.value
    try {
      board.value = (await must(supabase.rpc('pos_board', { p_branch_id: branchId }))) as unknown as PosBoard
      error.value = null
    } catch (e) {
      error.value = errorText(e, 'โหลดคิวไม่สำเร็จ')
    } finally {
      loading.value = false
    }
  }

  // รวมหลายเหตุการณ์ที่มาติดกันเป็นการโหลดครั้งเดียว
  function scheduleReload() {
    if (timer) clearTimeout(timer)
    timer = setTimeout(load, 300)
  }

  function unsubscribe() {
    if (channel) {
      supabase.removeChannel(channel)
      channel = null
    }
  }

  function subscribe(branchId: string) {
    unsubscribe()
    const filter = `branch_id=eq.${branchId}`
    channel = supabase
      .channel(`pos-board-${branchId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'queue_items', filter }, scheduleReload)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'service_orders', filter }, scheduleReload)
      .subscribe()
  }

  watch(
    () => activeBranch.value?.branch_id,
    (branchId) => {
      board.value = null
      if (!branchId) {
        unsubscribe()
        return
      }
      subscribe(branchId)
      load()
    },
    { immediate: true },
  )

  // สำรองกรณี Realtime หลุด: โหลดใหม่ทุก 60 วินาที
  useIntervalFn(load, 60_000)

  onBeforeUnmount(() => {
    unsubscribe()
    if (timer) clearTimeout(timer)
  })

  return { board, loading, error, load }
}
