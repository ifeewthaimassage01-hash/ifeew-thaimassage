<script setup lang="ts">
// แดชบอร์ดสาขา: โหลด staff_dashboard (คิวของฉัน + เตียง/อุปกรณ์) แล้วส่งให้ StaffDashboardView
// สรุปการเงินโหลดเองใน DashboardMoneySummary (เจ้าของร้าน)
import type { StaffDashboard } from '@ifeew/shared'

const supabase = useSupabaseClient()
const { activeBranch, isOwner } = useAccess()

// แดชบอร์ดเป็นของเจ้าของร้าน — พนักงานเข้าระบบแล้วไปหน้าร้าน (POS) เลย
if (!isOwner.value) await navigateTo('/pos', { replace: true })

const dash = ref<StaffDashboard | null>(null)
const error = ref<string | null>(null)

async function loadSummary() {
  if (!activeBranch.value) return
  try {
    dash.value = (await must(supabase.rpc('staff_dashboard', { p_branch_id: activeBranch.value.branch_id }))) as unknown as StaffDashboard
    error.value = null
  } catch (e) {
    error.value = errorText(e, 'โหลดแดชบอร์ดไม่สำเร็จ')
  }
}

watch(() => activeBranch.value?.branch_id, loadSummary, { immediate: true })
useIntervalFn(loadSummary, 30_000)
</script>

<template>
  <StaffDashboardView
    :dash="dash"
    :error="error"
    :is-owner="isOwner"
    :branch-name="activeBranch?.name"
    :branch-id="activeBranch?.branch_id"
  />
</template>
