import type { AccessBranch, AccessCompany, MyAccess } from '@ifeew/shared'

/**
 * สิทธิ์ของผู้ใช้ปัจจุบันจาก public.my_access()
 * ใช้แสดงเมนู/เลือกสาขาเท่านั้น — การบังคับสิทธิ์จริงอยู่ที่ RLS และ Database Function
 */
export function useAccess() {
  const supabase = useSupabaseClient()
  const access = useState<MyAccess | null>('my-access', () => null)
  const activeBranchId = useState<string | null>('active-branch-id', () => null)

  // เฟสแรกมีบริษัทเดียว: ใช้บริษัทแรกที่เป็นสมาชิก
  const company = computed<AccessCompany | null>(() => access.value?.companies[0] ?? null)
  const branches = computed<AccessBranch[]>(() => company.value?.branches ?? [])
  // ตั้งแต่ migration 028 เจ้าของร้านไม่บังคับ MFA (login ด้วย PIN บนเครื่องสาขาได้)
  const isOwner = computed(() => company.value?.role === 'OWNER')
  const needsMfa = computed(() => company.value?.owner_mfa_required === true)
  const activeBranch = computed(() => branches.value.find((b) => b.branch_id === activeBranchId.value) ?? null)

  async function refresh(): Promise<MyAccess | null> {
    const { data, error } = await supabase.rpc('my_access')
    if (error) throw error
    access.value = data as unknown as MyAccess
    if (!branches.value.some((b) => b.branch_id === activeBranchId.value)) {
      activeBranchId.value = branches.value[0]?.branch_id ?? null
    }
    return access.value
  }

  function clear() {
    access.value = null
    activeBranchId.value = null
  }

  return { access, company, branches, activeBranchId, activeBranch, isOwner, needsMfa, refresh, clear }
}
