/**
 * กล่องยืนยัน / กรอกข้อความ ตาม Design (แทน window.confirm / window.prompt)
 * ต้องมี <AppDialogHost /> ใน layout หนึ่งครั้ง
 *
 *   const { confirm, prompt } = useDialog()
 *   if (!(await confirm({ title: 'ลบรายการนี้?', destructive: true }))) return
 *   const reason = await prompt({ title: 'เหตุผล', minLength: 3 })   // null = ยกเลิก
 */
export interface ConfirmOptions {
  title: string
  description?: string
  confirmText?: string
  cancelText?: string
  /** ปุ่มยืนยันสีแดง สำหรับการกระทำที่ย้อนกลับไม่ได้ */
  destructive?: boolean
}

export interface PromptOptions extends ConfirmOptions {
  label?: string
  placeholder?: string
  defaultValue?: string
  /** ความยาวขั้นต่ำหลัง trim (0 = ไม่บังคับ) */
  minLength?: number
  maxLength?: number
  multiline?: boolean
}

export interface DialogRequest {
  kind: 'confirm' | 'prompt'
  options: PromptOptions
  resolve: (value: boolean | string | null) => void
}

export function useDialog() {
  const current = useState<DialogRequest | null>('app-dialog', () => null)

  function open<T>(kind: DialogRequest['kind'], options: PromptOptions): Promise<T> {
    // มีกล่องค้างอยู่ → ถือว่ายกเลิกกล่องเดิม
    current.value?.resolve(kind === 'confirm' ? false : null)
    return new Promise<T>((resolve) => {
      current.value = { kind, options, resolve: resolve as DialogRequest['resolve'] }
    })
  }

  const confirm = (options: ConfirmOptions) => open<boolean>('confirm', options)
  const prompt = (options: PromptOptions) => open<string | null>('prompt', options)

  return { current, confirm, prompt }
}
