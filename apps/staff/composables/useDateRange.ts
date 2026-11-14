/**
 * ช่วงวันที่สำเร็จรูปของตัวกรอง (วันนี้ / 7 วัน / เดือนนี้ / เดือนก่อน / ปีนี้) — วันที่เป็น YYYY-MM-DD ตามเวลาไทย
 * ใช้คู่กับ <DateRangeFilter> และใช้เขียนบรรทัดสรุป เช่น "3 รายการใน{{ describeRange(from, to) }}"
 */
import { addDays, bangkokToday } from '@ifeew/shared'

export type RangePreset = 'today' | 'week' | 'month' | 'last-month' | 'year'
export type RangeKey = RangePreset | 'custom'

export const RANGE_LABELS: Record<RangeKey, string> = {
  today: 'วันนี้',
  week: '7 วัน',
  month: 'เดือนนี้',
  'last-month': 'เดือนก่อน',
  year: 'ปีนี้',
  custom: 'กำหนดเอง',
}

const RANGE_PHRASES: Record<RangePreset, string> = {
  today: 'วันนี้',
  week: '7 วันล่าสุด',
  month: 'เดือนนี้',
  'last-month': 'เดือนก่อน',
  year: 'ปีนี้',
}

export function rangeOf(key: RangePreset): [string, string] {
  const today = bangkokToday()
  const monthStart = `${today.slice(0, 7)}-01`
  switch (key) {
    case 'today':
      return [today, today]
    case 'week':
      return [addDays(today, -6), today]
    case 'month':
      return [monthStart, today]
    case 'last-month': {
      const lastEnd = addDays(monthStart, -1)
      return [`${lastEnd.slice(0, 7)}-01`, lastEnd]
    }
    case 'year':
      return [`${today.slice(0, 4)}-01-01`, today]
  }
}

/** ช่วงที่ตรงกับปุ่มลัดไหน (ไม่ตรง = custom) */
export function matchRange(from: string, to: string, presets: readonly RangePreset[]): RangeKey {
  return presets.find((k) => {
    const [f, t] = rangeOf(k)
    return f === from && t === to
  }) ?? 'custom'
}

const shortDate = (d: string, withYear = false) =>
  new Date(`${d}T12:00:00+07:00`).toLocaleDateString('th-TH', {
    day: 'numeric',
    month: 'short',
    ...(withYear ? { year: 'numeric' } : {}),
    timeZone: 'Asia/Bangkok',
  })

/** ข้อความของช่วง เช่น "เดือนนี้" หรือ "9 พ.ย. ถึง 15 พ.ย." */
export function describeRange(from: string, to: string): string {
  const k = matchRange(from, to, ['today', 'week', 'month', 'last-month', 'year'])
  if (k !== 'custom') return RANGE_PHRASES[k]
  if (from === to) return shortDate(from, from.slice(0, 4) !== bangkokToday().slice(0, 4))
  const otherYear = from.slice(0, 4) !== to.slice(0, 4) || to.slice(0, 4) !== bangkokToday().slice(0, 4)
  return `${shortDate(from, otherYear)} ถึง ${shortDate(to, otherYear)}`
}
