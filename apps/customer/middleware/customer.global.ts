// ผู้ใช้ที่ login แล้วแต่ยังไม่ลงทะเบียนเป็นลูกค้า (เช่น เพิ่งยืนยันอีเมล) ให้กรอกข้อมูลและยอมรับนโยบายก่อน
const ALLOWED = new Set(['/complete-profile', '/login', '/register'])
const ALLOWED_PREFIX = ['/t/']

export default defineNuxtRouteMiddleware(async (to) => {
  if (ALLOWED.has(to.path) || ALLOWED_PREFIX.some((p) => to.path.startsWith(p))) return
  const user = useSupabaseUser()
  if (!user.value) return
  const { ensure } = useCustomer()
  try {
    const customer = await ensure()
    if (!customer) return navigateTo({ path: '/complete-profile', query: { redirect: to.fullPath } })
  } catch {
    // อ่านข้อมูลไม่ได้ (เช่น เครือข่าย) ไม่บล็อกหน้าสาธารณะ
  }
})
