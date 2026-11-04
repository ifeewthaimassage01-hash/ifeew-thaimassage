/**
 * Step-up TOTP สำหรับการกระทำเสี่ยงสูง
 * DB ตอบ STEP_UP_REQUIRED เมื่อ JWT ไม่มี amr totp ภายใน 5 นาที
 * -> เปิด StepUpDialog ให้กรอกรหัส Authenticator -> ได้ JWT ใหม่ -> ลองคำสั่งเดิมอีกครั้ง
 */
let pending: ((ok: boolean) => void) | null = null

export function isStepUpError(e: unknown): boolean {
  const err = e as { message?: string; data?: { error_code?: string } } | null
  return err?.message === 'STEP_UP_REQUIRED' || err?.data?.error_code === 'STEP_UP_REQUIRED'
}

/** ข้อความ error ที่แสดงผู้ใช้ได้ (ข้อความจาก DB Function เป็นภาษาไทยอยู่แล้ว) */
export function errorText(e: unknown, fallback = 'ดำเนินการไม่สำเร็จ'): string {
  const err = e as { message?: string; data?: { message?: string; error_code?: string } } | null
  if (err?.message === 'STEP_UP_CANCELLED') return 'ยกเลิกการยืนยันตัวตน'
  return err?.data?.message ?? (err?.message && !/fetch|network/i.test(err.message) ? err.message : fallback)
}

/** แปลงผล { data, error } ของ supabase-js ให้ throw เมื่อมี error */
export async function must<T>(p: PromiseLike<{ data: T; error: unknown }>): Promise<T> {
  const { data, error } = await p
  if (error) throw error
  return data
}

export function useStepUp() {
  const open = useState('step-up-open', () => false)

  function request(): Promise<boolean> {
    open.value = true
    return new Promise((resolve) => {
      pending = resolve
    })
  }

  function finish(ok: boolean) {
    open.value = false
    pending?.(ok)
    pending = null
  }

  async function run<T>(fn: () => Promise<T>): Promise<T> {
    try {
      return await fn()
    } catch (e) {
      if (!isStepUpError(e)) throw e
      const ok = await request()
      if (!ok) throw new Error('STEP_UP_CANCELLED')
      return await fn()
    }
  }

  return { open, run, finish }
}
