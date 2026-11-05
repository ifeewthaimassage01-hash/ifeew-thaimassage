import type { Component } from 'vue'
import { CalendarCheck, CalendarPlus, HandHeart, History, House, MapPin, UserRound } from '@lucide/vue'

export interface NavItem {
  to: string
  label: string
  icon: Component
}

/** เมนูของลูกค้า — ไม่มีฟังก์ชันจัดการร้าน (DESIGN.md §4) */
export function useAppNav() {
  const user = useSupabaseUser()
  const route = useRoute()

  const groups = computed(() => {
    const main: NavItem[] = [
      { to: '/', label: 'หน้าแรก', icon: House },
      { to: '/services', label: 'บริการ', icon: HandHeart },
      { to: '/branches', label: 'สาขา', icon: MapPin },
      { to: '/book', label: 'จองคิว', icon: CalendarPlus },
    ]
    const mine: NavItem[] = [
      { to: '/bookings', label: 'การจองของฉัน', icon: CalendarCheck },
      { to: '/history', label: 'ประวัติการนวด', icon: History },
      { to: '/profile', label: 'โปรไฟล์', icon: UserRound },
    ]
    return [
      { label: 'เมนู', items: main },
      ...(user.value ? [{ label: 'บัญชีของฉัน', items: mine }] : []),
    ]
  })

  const isActive = (to: string) => (to === '/' ? route.path === '/' : route.path === to || route.path.startsWith(`${to}/`))

  /** ตำแหน่งปัจจุบันสำหรับ breadcrumb ใน topbar */
  const crumbs = computed(() => {
    const all = groups.value.flatMap((g) => g.items)
    const item = all.filter((i) => i.to !== '/').find((i) => isActive(i.to))
    const extra: Record<string, string> = {
      '/login': 'เข้าสู่ระบบ',
      '/register': 'สมัครสมาชิก',
      '/complete-profile': 'ข้อมูลของคุณ',
    }
    if (route.path.startsWith('/t/')) return [{ label: 'สถานะการจอง' }]
    if (extra[route.path]) return [{ label: extra[route.path]! }]
    if (!item) return [{ label: 'หน้าแรก' }]
    const detail = route.path !== item.to
    return detail ? [{ label: item.label, to: item.to }, { label: 'รายละเอียด' }] : [{ label: item.label }]
  })

  return { groups, isActive, crumbs }
}
