/**
 * สีประจำหมวดบริการ (pastel-consumer): พื้นสีอ่อนของแบรนด์ + หมึกสีเข้มเฉดเดียวกัน
 * หมวดเดิมได้สีเดิมเสมอ (hash จากชื่อ) — ใช้กับ tile เล็ก/ชิปเท่านั้น ไม่ทาทั้งการ์ด
 */
const TINTS = [
  'bg-tint-green text-tint-green-ink',
  'bg-tint-pink text-tint-pink-ink',
  'bg-tint-beige text-tint-beige-ink',
] as const

export function categoryTint(name: string | null | undefined): string {
  if (!name) return TINTS[2]
  let h = 0
  for (const ch of name) h = (h * 31 + ch.codePointAt(0)!) >>> 0
  return TINTS[h % TINTS.length]!
}
