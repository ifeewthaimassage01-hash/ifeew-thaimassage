// หน้าที่ต้องเข้าสู่ระบบ (ใช้ร่วมกับ definePageMeta({ middleware: 'auth' }))
// การป้องกันข้อมูลจริงอยู่ที่ RLS — middleware นี้ใช้นำทางเท่านั้น
export default defineNuxtRouteMiddleware((to) => {
  const user = useSupabaseUser()
  if (!user.value) {
    return navigateTo({ path: '/login', query: { redirect: to.fullPath } })
  }
})
