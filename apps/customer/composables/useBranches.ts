import type { Tables } from '@ifeew/shared'

export type PublicBranch = Pick<
  Tables<'branches'>,
  'id' | 'company_id' | 'code' | 'name' | 'address' | 'phone' | 'map_url' | 'sort_order'
>

/** สาขาที่เปิดให้บริการของบริษัทนี้ (anon อ่านได้ตาม RLS branches_select_public_active) */
export function useBranches() {
  const supabase = useSupabaseClient()
  const { load } = useCompany()
  return useAsyncData('public-branches', async () => {
    const company = await load()
    if (!company) return [] as PublicBranch[]
    const { data, error } = await supabase
      .from('branches')
      .select('id, company_id, code, name, address, phone, map_url, sort_order')
      .eq('company_id', company.company_id)
      .eq('is_active', true)
      .order('sort_order')
      .order('name')
    if (error) throw error
    return (data ?? []) as PublicBranch[]
  })
}
