import type { Component } from 'vue'
import {
  BedDouble,
  Building2,
  CalendarCheck,
  ChartBar,
  ChartColumn,
  FileChartColumn,
  HandCoins,
  LayoutDashboard,
  ListOrdered,
  MonitorSmartphone,
  ReceiptText,
  Settings,
  Sparkles,
  Store,
  UserCog,
  UserCheck,
  Users,
  Wallet,
} from '@lucide/vue'

export interface StaffNavItem {
  to: string
  label: string
  icon: Component
  /** จับคู่ path แบบตรงตัวเท่านั้น (กันเมนูแม่ติด active ตอนอยู่หน้าลูก) */
  exact?: boolean
}
export interface StaffNavGroup {
  label: string
  items: StaffNavItem[]
}

/**
 * เมนู Staff/Owner — แสดงเฉพาะที่บทบาทเข้าถึงได้ (DESIGN.md §5)
 * หมายเหตุ: เป็นการนำทางเท่านั้น สิทธิ์จริงบังคับด้วย RLS และ middleware ownerOnly
 */
export function useStaffNav() {
  const { isOwner } = useAccess()
  const route = useRoute()

  // พนักงาน (ไม่ใช่เจ้าของร้าน): เมนูเฉพาะงานหน้าร้าน
  const staffGroups: StaffNavGroup[] = [
    {
      label: 'งานประจำวัน',
      items: [
        { to: '/pos', label: 'หน้าร้าน (POS)', icon: Store },
        { to: '/payments', label: 'ชำระเงิน', icon: Wallet },
        { to: '/queue', label: 'คิว', icon: ListOrdered },
        { to: '/bookings', label: 'การจอง', icon: CalendarCheck },
      ],
    },
    { label: 'เงินของสาขา', items: [{ to: '/expenses', label: 'รายจ่าย', icon: ReceiptText }] },
  ]

  const ownerGroups: StaffNavGroup[] = [
    {
      label: 'งานประจำวัน',
      items: [
        { to: '/', label: 'แดชบอร์ด', icon: LayoutDashboard, exact: true },
        { to: '/pos', label: 'หน้าร้าน (POS)', icon: Store },
        { to: '/payments', label: 'ชำระเงิน', icon: Wallet },
        { to: '/queue', label: 'คิว', icon: ListOrdered },
        { to: '/bookings', label: 'การจอง', icon: CalendarCheck },
        { to: '/customers', label: 'ลูกค้า', icon: Users },
        { to: '/attendance', label: 'เข้างาน/ประกันมือ', icon: UserCheck },
      ],
    },
    {
      label: 'เงินของสาขา',
      items: [
        { to: '/expenses', label: 'รายจ่าย', icon: ReceiptText },
      ],
    },
    {
      label: 'รายงานและบัญชี',
      items: [
        { to: '/owner', label: 'ภาพรวมทุกสาขา', icon: ChartColumn },
        { to: '/reports/finance', label: 'รายงานการเงิน', icon: FileChartColumn },
        { to: '/reports/therapists', label: 'สรุปงานหมอ', icon: ChartBar },
        { to: '/commissions', label: 'ค่ามือหมอ', icon: HandCoins },
      ],
    },
    {
      label: 'จัดการร้าน',
      items: [
        { to: '/services', label: 'บริการและราคา', icon: Sparkles },
        { to: '/resources', label: 'เตียงและอุปกรณ์', icon: BedDouble },
        { to: '/employees', label: 'พนักงาน', icon: UserCog },
        { to: '/branches', label: 'สาขา', icon: Building2 },
        { to: '/settings', label: 'ตั้งค่าบริษัท', icon: Settings, exact: true },
        { to: '/settings/devices', label: 'ตั้งค่าเครื่อง', icon: MonitorSmartphone },
      ],
    },
  ]

  const groups = computed<StaffNavGroup[]>(() => (isOwner.value ? ownerGroups : staffGroups))

  const isActive = (i: StaffNavItem) => (i.exact ? route.path === i.to : route.path === i.to || route.path.startsWith(`${i.to}/`))

  /** breadcrumb: กลุ่ม › หน้า (› รายละเอียด) */
  const crumbs = computed(() => {
    for (const g of groups.value) {
      const item = g.items.find(isActive)
      if (item) {
        const detail = route.path !== item.to
        return [{ label: g.label }, { label: item.label, to: detail ? item.to : undefined }, ...(detail ? [{ label: 'รายละเอียด' }] : [])]
      }
    }
    if (route.path.startsWith('/checkout')) return [{ label: 'งานประจำวัน' }, { label: 'ชำระเงิน', to: '/payments' }, { label: 'รายละเอียด' }]
    return [{ label: 'แดชบอร์ด' }]
  })

  return { groups, isActive, crumbs }
}
