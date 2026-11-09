/**
 * วันทำงานของเครื่อง: เริ่ม 03:00 น. (เวลาไทย) — ออกจากระบบอัตโนมัติเมื่อขึ้นวันทำงานใหม่
 * (แทนการล็อกเมื่อไม่ได้ใช้งาน) เวลา login เก็บใน localStorage ของเครื่อง
 */
const LOGIN_AT_KEY = 'ifeew.login_at'
export const WORKDAY_START_HOUR = 3
const BANGKOK_OFFSET_MS = 7 * 3_600_000

/** วันทำงาน (YYYY-MM-DD) ของเวลาที่ระบุ: ก่อนตี 3 นับเป็นวันก่อนหน้า */
export function workDayOf(ms: number): string {
  return new Date(ms + BANGKOK_OFFSET_MS - WORKDAY_START_HOUR * 3_600_000).toISOString().slice(0, 10)
}

function readLoginAt(): number | null {
  try {
    const v = Number(localStorage.getItem(LOGIN_AT_KEY))
    return Number.isFinite(v) && v > 0 ? v : null
  } catch {
    return null
  }
}

/** บันทึกเวลาที่ login (เรียกหลัง login สำเร็จ) */
export function markLogin(at = Date.now()) {
  try {
    localStorage.setItem(LOGIN_AT_KEY, String(at))
  } catch {
    /* ไม่มี storage */
  }
}

export function clearLoginMark() {
  try {
    localStorage.removeItem(LOGIN_AT_KEY)
  } catch {
    /* ไม่มี storage */
  }
}

/**
 * true = session นี้ login ในวันทำงานก่อนหน้า (เลยตี 3 แล้ว) ต้องออกจากระบบ
 * ไม่มีเวลา login (session เดิมก่อนมีฟีเจอร์นี้) → นับว่าเพิ่ง login วันนี้
 */
export function loginExpired(now = Date.now()): boolean {
  const at = readLoginAt()
  if (at === null) {
    markLogin(now)
    return false
  }
  return workDayOf(at) !== workDayOf(now)
}
