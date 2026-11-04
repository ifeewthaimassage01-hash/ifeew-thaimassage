import type { CurrentPolicy } from '@ifeew/shared'

type Policies = Partial<Record<'PRIVACY_NOTICE' | 'MARKETING', CurrentPolicy>>

/** นโยบายฉบับปัจจุบันของบริษัท (anon เรียกได้) */
export function usePolicies() {
  const supabase = useSupabaseClient()
  const { code } = useCompany()
  return useAsyncData('current-policies', async () => {
    const { data, error } = await supabase.rpc('get_current_policies', { p_company_code: code })
    if (error) throw error
    return (data ?? {}) as unknown as Policies
  })
}
