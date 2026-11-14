/**
 * ดึงข้อมูลซ้ำทุก ms มิลลิวินาที เฉพาะตอนที่หน้านี้เปิดดูอยู่
 * - แท็บถูกซ่อน/จอแท็บเล็ตดับ → หยุด (ไม่เปลืองแบตและโควตา Supabase)
 * - กลับมาเปิด → เรียกทันทีหนึ่งครั้งให้ข้อมูลสด แล้วนับรอบใหม่
 * ใช้แทน useIntervalFn สำหรับงานที่โหลดข้อมูล (ตัวนับเวลาบนจอใช้ได้เหมือนกัน)
 */
export function useLiveInterval(fn: () => unknown, ms: number) {
  const visibility = useDocumentVisibility()
  const { pause, resume } = useIntervalFn(fn, ms)

  watch(visibility, (v) => {
    if (v === 'hidden') {
      pause()
      return
    }
    void fn()
    resume()
  })

  return { pause, resume }
}
