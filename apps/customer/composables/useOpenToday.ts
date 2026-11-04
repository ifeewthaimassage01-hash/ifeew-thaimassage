import { bangkokToday } from '@ifeew/shared'

/** เวลาเปิด-ปิด "วันนี้" ของแต่ละสาขา (รวมวันหยุด/เวลาพิเศษ) เป็นนาทีนับจากเที่ยงคืน */
export interface TodayHours {
  closed: boolean
  /** ชื่อวันหยุด (ถ้าวันนี้เป็นวันพิเศษ) */
  holiday: string | null
  opens: number | null
  /** ถ้าปิดหลังเที่ยงคืน จะมากกว่า 1440 */
  closes: number | null
}

const toMin = (t: string | null) => {
  if (!t) return null
  const [h, m] = t.split(':').map(Number)
  return h! * 60 + m!
}

/** ISO day of week (1=จันทร์ … 7=อาทิตย์) ของวันที่ 'YYYY-MM-DD' */
export function isoDow(date: string): number {
  const d = new Date(`${date}T00:00:00Z`).getUTCDay()
  return d === 0 ? 7 : d
}

/** นาทีนับจากเที่ยงคืนตามเวลาไทย */
export function bangkokMinutes(now: Date = new Date()): number {
  const t = new Date(now.getTime() + 7 * 3600_000)
  return t.getUTCHours() * 60 + t.getUTCMinutes()
}

export function hhmm(min: number): string {
  const m = ((min % 1440) + 1440) % 1440
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`
}

/** อ่านเวลาเปิดวันนี้ของหลายสาขาในครั้งเดียว (anon อ่านได้ตาม RLS *_select_public) */
export function useOpenToday(branchIds: Ref<string[]>) {
  const supabase = useSupabaseClient()
  const key = computed(() => `open-today-${branchIds.value.join(',')}`)

  return useAsyncData(
    key,
    async () => {
      const ids = branchIds.value
      const out: Record<string, TodayHours> = {}
      if (!ids.length) return out
      const today = bangkokToday()
      const [hours, holidays] = await Promise.all([
        supabase
          .from('branch_opening_hours')
          .select('branch_id, is_closed, opens_at, closes_at')
          .in('branch_id', ids)
          .eq('iso_dow', isoDow(today)),
        supabase
          .from('branch_holidays')
          .select('branch_id, name, is_closed, opens_at, closes_at')
          .in('branch_id', ids)
          .eq('is_active', true)
          .eq('holiday_date', today),
      ])
      const make = (r: { is_closed: boolean; opens_at: string | null; closes_at: string | null }, holiday: string | null): TodayHours => {
        const opens = toMin(r.opens_at)
        let closes = toMin(r.closes_at)
        if (opens !== null && closes !== null && closes <= opens) closes += 1440
        return { closed: r.is_closed || opens === null || closes === null, holiday, opens, closes }
      }
      for (const r of hours.data ?? []) out[r.branch_id] = make(r, null)
      for (const r of holidays.data ?? []) out[r.branch_id] = make(r, r.name)
      return out
    },
    { watch: [branchIds] },
  )
}
