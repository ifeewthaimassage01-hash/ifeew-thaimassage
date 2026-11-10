import { publicImageUrl, type Database, type Tables } from '@ifeew/shared'

export type PublicBranch = Pick<
  Tables<'branches'>,
  'id' | 'company_id' | 'code' | 'name' | 'address' | 'phone' | 'map_url' | 'sort_order' | 'image_path'
>

// anon มีสิทธิ์อ่าน branches เฉพาะบางคอลัมน์ (column-level grant) — ห้ามใช้ select('*')
const PUBLIC_COLUMNS = 'id, company_id, code, name, address, phone, map_url, sort_order'

/**
 * รูปสาขาแยกอีก query และยอมให้พลาดได้: ก่อนรัน migration 036 ยังไม่มีคอลัมน์/สิทธิ์ image_path
 * ถ้าอ่านไม่ได้จะได้ map ว่าง (สาขาไม่มีรูป) แทนที่จะทำให้ทั้งหน้าโหลดสาขาไม่ได้
 * รับ client เป็นพารามิเตอร์: ฟังก์ชันนี้ถูกเรียกหลัง await ใน useAsyncData ซึ่งเรียก composable (useSupabaseClient) ไม่ได้แล้ว
 */
export async function loadBranchImages(supabase: ReturnType<typeof useSupabaseClient<Database>>, ids: string[]): Promise<Record<string, string | null>> {
  if (!ids.length) return {}
  const { data, error } = await supabase.from('branches').select('id, image_path').in('id', ids)
  if (error) return {}
  return Object.fromEntries((data ?? []).map((r: { id: string; image_path: string | null }) => [r.id, r.image_path ?? null]))
}

/** สาขาที่เปิดให้บริการของบริษัทนี้ (anon อ่านได้ตาม RLS branches_select_public_active) */
export function useBranches() {
  const supabase = useSupabaseClient()
  const { load } = useCompany()
  return useAsyncData('public-branches', async () => {
    const company = await load()
    if (!company) return [] as PublicBranch[]
    const { data, error } = await supabase
      .from('branches')
      .select(PUBLIC_COLUMNS)
      .eq('company_id', company.company_id)
      .eq('is_active', true)
      .order('sort_order')
      .order('name')
    if (error) throw error
    const rows = data ?? []
    const images = await loadBranchImages(supabase, rows.map((b) => b.id))
    return rows.map((b) => ({ ...b, image_path: images[b.id] ?? null })) as PublicBranch[]
  })
}

/** URL รูปสาขา — Cloudinary ("cloudinary:<id>") หรือรูปเก่าใน Supabase Storage (bucket branch-images) */
export function branchImageUrl(path: string | null | undefined, width = 1200): string | null {
  const config = useRuntimeConfig()
  return publicImageUrl(path, {
    supabaseUrl: config.public.supabase.url as string,
    bucket: 'branch-images',
    cloudName: (config.public.cloudinaryCloudName as string) || null,
    width,
  })
}
