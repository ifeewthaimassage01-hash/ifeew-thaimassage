<script setup lang="ts">
// แดชบอร์ดสาขา: โหลด staff_dashboard (คิวของฉัน + เตียง/อุปกรณ์) แล้วส่งให้ StaffDashboardView
// สรุปการเงินโหลดเองใน DashboardMoneySummary (เจ้าของร้าน)
// Realtime: คิว/ออเดอร์/บิลเปลี่ยน (รับลูกค้า เริ่มนวด นวดเสร็จ ยกเลิก รับเงิน) → โหลดใหม่ทันที
//   การจองเตียงเปลี่ยนใน transaction เดียวกับคิวเสมอ จึงฟังแค่ตารางเหล่านี้พอ
//   สำรอง: โหลดใหม่ทุก 30 วินาที (เตียงที่จองล่วงหน้าเริ่ม "ใช้อยู่" เองเมื่อถึงเวลา โดยไม่มีอะไรเปลี่ยนใน DB)
import type { StaffDashboard } from '@ifeew/shared'

const supabase = useSupabaseClient()
const { activeBranch, isOwner } = useAccess()

// แดชบอร์ดเป็นของเจ้าของร้าน — พนักงานเข้าระบบแล้วไปหน้าร้าน (POS) เลย
if (!isOwner.value) await navigateTo('/pos', { replace: true })

const dash = ref<StaffDashboard | null>(null)
const error = ref<string | null>(null)
const moneyTick = ref(0) // เพิ่มเมื่อมีการเปลี่ยนแปลง → DashboardMoneySummary โหลดใหม่

async function loadSummary() {
  if (!activeBranch.value) return
  try {
    dash.value = (await must(supabase.rpc('staff_dashboard', { p_branch_id: activeBranch.value.branch_id }))) as unknown as StaffDashboard
    error.value = null
  } catch (e) {
    error.value = errorText(e, 'โหลดแดชบอร์ดไม่สำเร็จ')
  }
}

// รวมหลายเหตุการณ์ที่มาติดกัน (เช่น สร้างคิวหลายคน) เป็นการโหลดครั้งเดียว
let timer: ReturnType<typeof setTimeout> | null = null
function scheduleReload() {
  if (timer) clearTimeout(timer)
  timer = setTimeout(() => {
    loadSummary()
    moneyTick.value++
  }, 400)
}

let channel: ReturnType<typeof supabase.channel> | null = null
const instanceId = Math.random().toString(36).slice(2, 10)
function unsubscribe() {
  if (channel) supabase.removeChannel(channel)
  channel = null
}
function subscribe(branchId: string) {
  unsubscribe()
  const filter = `branch_id=eq.${branchId}`
  channel = supabase
    .channel(`dashboard-${branchId}-${instanceId}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'queue_items', filter }, scheduleReload)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'service_orders', filter }, scheduleReload)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'invoices', filter }, scheduleReload)
    .subscribe()
}

watch(
  () => activeBranch.value?.branch_id,
  (branchId) => {
    if (!branchId) return unsubscribe()
    subscribe(branchId)
    loadSummary()
  },
  { immediate: true },
)
useIntervalFn(loadSummary, 30_000)
onBeforeUnmount(() => {
  unsubscribe()
  if (timer) clearTimeout(timer)
})
</script>

<template>
  <StaffDashboardView
    :dash="dash"
    :error="error"
    :is-owner="isOwner"
    :branch-name="activeBranch?.name"
    :branch-id="activeBranch?.branch_id"
    :money-tick="moneyTick"
  />
</template>
