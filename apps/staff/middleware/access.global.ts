// ตรวจหลัง login (การ redirect ไป /login เมื่อไม่มี session ทำโดย @nuxtjs/supabase)
// - บัญชีที่ไม่มี membership (เช่นลูกค้า) ใช้ Staff App ไม่ได้
// - OWNER ต้องผ่าน MFA (aal2) ก่อนใช้งาน
// - หน้า meta.ownerOnly ต้องเป็น OWNER ที่ผ่าน MFA แล้ว
// หมายเหตุ: เป็นการนำทางเท่านั้น สิทธิ์จริงบังคับด้วย RLS
export default defineNuxtRouteMiddleware(async (to) => {
  if (to.path === '/login') return

  const user = useSupabaseUser()
  if (!user.value) return

  const supabase = useSupabaseClient()
  const { access, company, isOwner, needsMfa, refresh } = useAccess()

  if (!access.value || access.value.user_id !== user.value.sub) {
    try {
      await refresh()
    } catch {
      return navigateTo('/login?error=access')
    }
  }

  if (!company.value) {
    await supabase.auth.signOut()
    return navigateTo('/login?error=not_staff')
  }

  if (needsMfa.value && to.path !== '/mfa') return navigateTo('/mfa')

  if (to.meta.ownerOnly && !isOwner.value) return navigateTo('/')
})
