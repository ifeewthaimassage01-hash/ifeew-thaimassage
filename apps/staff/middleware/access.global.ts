// ตรวจหลัง login (การ redirect ไป /login เมื่อไม่มี session ทำโดย @nuxtjs/supabase)
// - บัญชีที่ไม่มี membership (เช่นลูกค้า) ใช้ Staff App ไม่ได้
// - OWNER ต้องผ่าน MFA (aal2) ก่อนใช้งาน
// - หน้า meta.ownerOnly ต้องเป็น OWNER ที่ผ่าน MFA แล้ว
// หมายเหตุ: เป็นการนำทางเท่านั้น สิทธิ์จริงบังคับด้วย RLS
export default defineNuxtRouteMiddleware(async (to) => {
  if (to.path === '/login' || to.path === '/set-password') return

  // ใช้ session (ตั้งค่าทันทีหลัง login) ไม่ใช่ useSupabaseUser() ซึ่ง @nuxtjs/supabase v2
  // เติมค่าแบบ async ผ่าน getClaims() — ตอน navigateTo('/') หลัง login user ยังเป็น null
  // ทำให้ข้ามการโหลดสิทธิ์ และทุกหน้าไม่โหลดข้อมูล
  const supabase = useSupabaseClient()
  const { data: sessionData } = await supabase.auth.getSession()
  const userId = sessionData.session?.user.id
  if (!userId) return

  // เลยตี 3 ของวันทำงานที่ login แล้ว (เช่นเปิดแอปค้างข้ามคืน) → ออกจากระบบ ให้ login ใหม่ = เข้างานวันใหม่
  if (loginExpired()) {
    await supabase.auth.signOut()
    useAccess().clear()
    clearLoginMark()
    return navigateTo('/login?error=day_end')
  }

  const { access, company, isOwner, needsMfa, refresh } = useAccess()

  if (!access.value || access.value.user_id !== userId) {
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
