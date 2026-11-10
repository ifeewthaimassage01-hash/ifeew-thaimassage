<script setup lang="ts">
// แดชบอร์ดสาขา: โหลดข้อมูลจริง (staff_dashboard, staff_dashboard_finance, staff_bookings) แล้วส่งให้ StaffDashboardView
import { bangkokToday, type StaffBookingRow, type StaffDashboard } from '@ifeew/shared'

const supabase = useSupabaseClient()
const { activeBranch, isOwner } = useAccess()

const dash = ref<StaffDashboard | null>(null)
const money = ref<{ today_sales: number; outstanding: number; pending_void_requests: number } | null>(null)
const rows = ref<StaffBookingRow[]>([])
const date = ref(bangkokToday())
const error = ref<string | null>(null)
const loadingDay = ref(false)

async function loadSummary() {
  if (!activeBranch.value) return
  const branchId = activeBranch.value.branch_id
  try {
    const [d, m] = await Promise.all([
      must(supabase.rpc('staff_dashboard', { p_branch_id: branchId })),
      must(supabase.rpc('staff_dashboard_finance', { p_branch_id: branchId })),
    ])
    dash.value = d as unknown as StaffDashboard
    money.value = (m ?? null) as typeof money.value
    error.value = null
  } catch (e) {
    error.value = errorText(e, 'โหลดแดชบอร์ดไม่สำเร็จ')
  }
}

// กันคำตอบเก่ามาทับเมื่อเปลี่ยนวันเร็ว ๆ
let daySeq = 0
async function loadDay() {
  if (!activeBranch.value || !date.value) return
  const seq = ++daySeq
  loadingDay.value = true
  try {
    const data = await must(supabase.rpc('staff_bookings', { p_branch_id: activeBranch.value.branch_id, p_date: date.value }))
    if (seq === daySeq) rows.value = (data ?? []) as unknown as StaffBookingRow[]
  } catch (e) {
    if (seq === daySeq) error.value = errorText(e, 'โหลดการจองไม่สำเร็จ')
  } finally {
    if (seq === daySeq) loadingDay.value = false
  }
}

watch(() => activeBranch.value?.branch_id, loadSummary, { immediate: true })
watch([() => activeBranch.value?.branch_id, date], loadDay, { immediate: true })
useIntervalFn(() => {
  loadSummary()
  loadDay()
}, 30_000)
</script>

<template>
  <StaffDashboardView
    v-model:date="date"
    :dash="dash"
    :money="money"
    :rows="rows"
    :error="error"
    :loading-day="loadingDay"
    :is-owner="isOwner"
    :branch-name="activeBranch?.name"
  />
</template>
