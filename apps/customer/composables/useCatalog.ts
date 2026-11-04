import type { Database } from '@ifeew/shared'

/** 1 แถว = 1 ช่วงเวลาที่ขาย */
export type CatalogRow = Database['public']['Views']['v_public_branch_services']['Row']

/** บริการของสาขา + ช่วงเวลา/ราคาทั้งหมด */
export interface CatalogItem {
  branch_service_id: string
  branch_id: string
  service_id: string
  name: string
  name_en: string | null
  description: string | null
  image_path: string | null
  category_name: string
  options: Array<{ option_id: string; duration_minutes: number; price: number }>
}

export function groupCatalog(rows: CatalogRow[]): CatalogItem[] {
  const map = new Map<string, CatalogItem>()
  for (const r of rows) {
    let item = map.get(r.branch_service_id)
    if (!item) {
      item = {
        branch_service_id: r.branch_service_id,
        branch_id: r.branch_id,
        service_id: r.service_id,
        name: r.name,
        name_en: r.name_en,
        description: r.description,
        image_path: r.image_path,
        category_name: r.category_name,
        options: [],
      }
      map.set(r.branch_service_id, item)
    }
    item.options.push({ option_id: r.option_id, duration_minutes: r.duration_minutes, price: Number(r.price) })
  }
  for (const item of map.values()) item.options.sort((a, b) => a.duration_minutes - b.duration_minutes)
  return [...map.values()]
}

/** บริการที่เปิดขาย + ราคาปัจจุบัน (เฉพาะราคาที่มีผลแล้ว) */
export function useCatalog(branchId?: Ref<string | null | undefined>) {
  const supabase = useSupabaseClient()
  const { load } = useCompany()
  const key = computed(() => `catalog-${branchId?.value ?? 'all'}`)

  return useAsyncData(
    key,
    async () => {
      const company = await load()
      if (!company) return [] as CatalogItem[]
      let q = supabase.from('v_public_branch_services').select('*').eq('company_id', company.company_id)
      if (branchId?.value) q = q.eq('branch_id', branchId.value)
      const { data, error } = await q.order('category_sort_order').order('sort_order').order('name').order('duration_minutes')
      if (error) throw error
      return groupCatalog((data ?? []) as CatalogRow[])
    },
    { watch: branchId ? [branchId] : [] },
  )
}

export function serviceImageUrl(path: string | null): string | null {
  if (!path) return null
  return useSupabaseClient().storage.from('service-images').getPublicUrl(path).data.publicUrl
}
