export interface PublicCompany {
  company_id: string
  code: string
  name: string
}

/** บริษัทของแอปนี้ (จาก NUXT_PUBLIC_COMPANY_CODE) */
export function useCompany() {
  const config = useRuntimeConfig()
  const supabase = useSupabaseClient()
  const code = config.public.companyCode as string

  const company = useState<PublicCompany | null>('public-company', () => null)

  async function load(): Promise<PublicCompany | null> {
    if (company.value) return company.value
    const { data, error } = await supabase.rpc('get_public_company', { p_code: code })
    if (error) throw error
    company.value = (data as unknown as PublicCompany) ?? null
    return company.value
  }

  return { code, company, load }
}
