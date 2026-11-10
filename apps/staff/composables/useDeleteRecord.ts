// ลบข้อมูลหลัก (บริการ หมวดหมู่ เตียง/อุปกรณ์ พนักงาน สาขา): กล่องยืนยัน → ยืนยันตัวตนซ้ำ (step-up) → RPC
// RPC ฝั่ง DB ลบได้เฉพาะรายการที่ยังไม่มีประวัติ (migration 039/043) — มีประวัติแล้วจะได้ข้อความให้ "ปิดใช้งาน" แทน
type DeleteRpc =
  | { fn: 'delete_service'; args: { p_service_id: string } }
  | { fn: 'delete_service_category'; args: { p_category_id: string } }
  | { fn: 'delete_resource_type'; args: { p_resource_type_id: string } }
  | { fn: 'delete_branch'; args: { p_branch_id: string } }

export function useDeleteRecord() {
  const supabase = useSupabaseClient()
  const { confirm } = useDialog()
  const { run } = useStepUp()
  const deletingId = ref<string | null>(null)

  /**
   * คืน 'deleted' เมื่อลบสำเร็จ, 'cancelled' เมื่อผู้ใช้ยกเลิก (กล่องยืนยัน/step-up)
   * ลบไม่สำเร็จ → throw (ผู้เรียกแสดง errorText)
   */
  async function remove<T = unknown>(
    id: string,
    action: DeleteRpc | (() => Promise<T>),
    text: { title: string; description: string; confirmText?: string },
  ): Promise<'deleted' | 'cancelled'> {
    const ok = await confirm({ ...text, confirmText: text.confirmText ?? 'ลบ', destructive: true })
    if (!ok) return 'cancelled'
    deletingId.value = id
    try {
      await run(() => (typeof action === 'function' ? action() : must(supabase.rpc(action.fn, action.args as never))))
      return 'deleted'
    } catch (e) {
      if ((e as Error)?.message === 'STEP_UP_CANCELLED') return 'cancelled'
      throw e
    } finally {
      deletingId.value = null
    }
  }

  return { remove, deletingId }
}
