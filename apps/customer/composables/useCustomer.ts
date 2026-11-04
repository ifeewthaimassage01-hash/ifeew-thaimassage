import type { MyCustomer } from '@ifeew/shared'

/**
 * ข้อมูลลูกค้าของผู้ใช้ที่ login อยู่ (public.my_customer)
 * undefined = ยังไม่โหลด, null = login แล้วแต่ยังไม่ลงทะเบียนเป็นลูกค้า
 */
export function useCustomer() {
  const supabase = useSupabaseClient()
  const user = useSupabaseUser()
  const { code } = useCompany()
  const customer = useState<MyCustomer | null | undefined>('my-customer', () => undefined)
  const loadedFor = useState<string | null>('my-customer-user', () => null)

  async function refresh(): Promise<MyCustomer | null> {
    if (!user.value) {
      customer.value = null
      loadedFor.value = null
      return null
    }
    const { data, error } = await supabase.rpc('my_customer', { p_company_code: code })
    if (error) throw error
    customer.value = (data as unknown as MyCustomer) ?? null
    loadedFor.value = user.value.sub
    return customer.value
  }

  async function ensure(): Promise<MyCustomer | null> {
    if (customer.value !== undefined && loadedFor.value === (user.value?.sub ?? null)) return customer.value ?? null
    return await refresh()
  }

  function clear() {
    customer.value = undefined
    loadedFor.value = null
  }

  return { customer, refresh, ensure, clear }
}
