/** "สาขา" + ชื่อ โดยไม่ซ้ำคำ (ชื่อสาขาในระบบหลายแห่งขึ้นต้นด้วย "สาขา" อยู่แล้ว เช่น "สาขาสุรินทร์") */
export function branchLabel(name: string | null | undefined): string {
  const n = (name ?? '').trim()
  if (!n) return 'สาขา'
  return n.startsWith('สาขา') ? n : `สาขา${n}`
}
