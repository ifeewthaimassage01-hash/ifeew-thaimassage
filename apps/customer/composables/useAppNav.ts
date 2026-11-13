import type { Component } from 'vue'
import { CalendarPlus, CalendarSearch, HandHeart, House, MapPin } from '@lucide/vue'

export interface NavItem {
  to: string
  label: string
  icon: Component
}

/** เมนูของลูกค้า — จองแบบ Guest อย่างเดียว (ไม่มีระบบสมาชิก/เข้าสู่ระบบ) */
export function useAppNav() {
  const route = useRoute()

  const groups = computed(() => [
    {
      label: 'เมนู',
      items: [
        { to: '/', label: 'หน้าแรก', icon: House },
        { to: '/services', label: 'บริการ', icon: HandHeart },
        { to: '/branches', label: 'สาขา', icon: MapPin },
        { to: '/book', label: 'จองคิว', icon: CalendarPlus },
        { to: '/check-booking', label: 'ตรวจสอบการจอง', icon: CalendarSearch },
      ] satisfies NavItem[],
    },
  ])

  const isActive = (to: string) => (to === '/' ? route.path === '/' : route.path === to || route.path.startsWith(`${to}/`))

  /** ตำแหน่งปัจจุบันสำหรับ breadcrumb ใน topbar */
  const crumbs = computed(() => {
    const all = groups.value.flatMap((g) => g.items)
    const item = all.filter((i) => i.to !== '/').find((i) => isActive(i.to))
    if (route.path.startsWith('/t/')) return [{ label: 'สถานะการจอง' }]
    if (!item) return [{ label: 'หน้าแรก' }]
    const detail = route.path !== item.to
    return detail ? [{ label: item.label, to: item.to }, { label: 'รายละเอียด' }] : [{ label: item.label }]
  })

  return { groups, isActive, crumbs }
}
