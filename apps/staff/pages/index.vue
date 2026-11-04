<script setup lang="ts">
// แดชบอร์ด STAFF ของสาขาที่เลือก (ส่วนที่ไม่ใช่เงิน — ยอดขาย/ค้างชำระเพิ่มใน Phase 7)
import { bangkokTime, formatBaht, formatDuration, formatQueueNumber, queueStatusLabels, type StaffDashboard } from '@ifeew/shared'

const user = useSupabaseUser()
const supabase = useSupabaseClient()
const { activeBranch, isOwner } = useAccess()

const displayName = ref('')
watch(
  () => user.value?.sub,
  async (id) => {
    if (!id) return
    const { data } = await supabase.from('profiles').select('display_name').eq('id', id).maybeSingle()
    displayName.value = data?.display_name ?? ''
  },
  { immediate: true },
)

const dash = ref<StaffDashboard | null>(null)
const money = ref<{ today_sales: number; outstanding: number; pending_void_requests: number } | null>(null)
const error = ref<string | null>(null)

async function load() {
  if (!activeBranch.value) return
  try {
    dash.value = (await must(supabase.rpc('staff_dashboard', { p_branch_id: activeBranch.value.branch_id }))) as unknown as StaffDashboard
    const { data } = await supabase.rpc('staff_dashboard_finance', { p_branch_id: activeBranch.value.branch_id })
    money.value = (data ?? null) as typeof money.value
    error.value = null
  } catch (e) {
    error.value = errorText(e, 'โหลดแดชบอร์ดไม่สำเร็จ')
  }
}

watch(() => activeBranch.value?.branch_id, load, { immediate: true })
useIntervalFn(load, 30_000)
</script>

<template>
  <div>
    <div class="mb-6 flex flex-wrap items-center justify-between gap-3">
      <h1 class="m-0 text-2xl font-semibold text-cocoa">สวัสดี {{ displayName || 'ผู้ใช้' }}</h1>
      <p class="m-0 text-light-brown">{{ activeBranch?.name }} · {{ isOwner ? 'เจ้าของร้าน' : 'พนักงาน' }}</p>
    </div>

    <v-alert v-if="error" type="error" variant="tonal" class="mb-4" :text="error" />

    <template v-if="dash">
      <v-card v-if="dash.my_queue.length" class="mb-4 p-5" to="/queue">
        <p class="m-0 mb-2 font-medium">คิวของฉัน</p>
        <div class="flex flex-wrap gap-3">
          <v-chip v-for="q in dash.my_queue" :key="q.queue_id" color="primary" variant="tonal" size="large">
            {{ formatQueueNumber(q.queue_number) }} · {{ q.service_name }} {{ formatDuration(q.duration_minutes) }} · {{ queueStatusLabels[q.status] }}
          </v-chip>
        </div>
      </v-card>

      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <v-card class="p-5" to="/queue">
          <p class="m-0 text-sm text-light-brown">คิวรอเรียก</p>
          <p class="m-0 mt-1 text-3xl font-semibold">{{ dash.queue.waiting }}</p>
          <p class="m-0 text-sm">เรียกแล้ว {{ dash.queue.called }} · กำลังบริการ {{ dash.queue.in_service }}</p>
          <p v-if="dash.queue.overdue" class="m-0 text-sm font-medium text-red-700">เลยเวลาจบ {{ dash.queue.overdue }} คิว</p>
        </v-card>
        <v-card class="p-5" to="/queue">
          <p class="m-0 text-sm text-light-brown">บริการเสร็จวันนี้</p>
          <p class="m-0 mt-1 text-3xl font-semibold">{{ dash.queue.completed }}</p>
          <p class="m-0 text-sm">Walk-in {{ dash.walk_in_orders }} ราย</p>
        </v-card>
        <v-card class="p-5" to="/bookings">
          <p class="m-0 text-sm text-light-brown">การจองวันนี้</p>
          <p class="m-0 mt-1 text-3xl font-semibold">{{ dash.bookings.total }}</p>
          <p class="m-0 text-sm">รอเช็กอิน {{ dash.bookings.awaiting_check_in }} · มาแล้ว {{ dash.bookings.checked_in }}</p>
          <p v-if="dash.bookings.slip_review" class="m-0 text-sm font-medium text-red-700">สลิปรอตรวจ {{ dash.bookings.slip_review }}</p>
        </v-card>
        <v-card class="p-5" to="/pos">
          <p class="m-0 text-sm text-light-brown">กะ POS</p>
          <template v-if="dash.session">
            <p class="m-0 mt-1 text-xl font-semibold text-green-800">เปิดอยู่</p>
            <p class="m-0 text-sm">ตั้งแต่ {{ bangkokTime(dash.session.opened_at) }} · เงินทอน {{ formatBaht(Number(dash.session.opening_cash)) }}</p>
          </template>
          <p v-else class="m-0 mt-1 text-xl font-semibold text-light-brown">ยังไม่เปิดกะ</p>
        </v-card>
      </div>

      <v-card class="mt-4 p-5">
        <p class="m-0 mb-3 font-medium">เตียงและอุปกรณ์ตอนนี้</p>
        <div class="grid gap-3 sm:grid-cols-3">
          <div v-for="r in dash.resources" :key="r.resource_type_id" class="rounded-xl bg-cream px-4 py-3">
            <p class="m-0 text-sm text-light-brown">{{ r.name }}</p>
            <p class="m-0 text-2xl font-semibold">ว่าง {{ Math.max(0, r.total - r.in_use) }} / {{ r.total }}</p>
            <p v-if="r.status !== 'ACTIVE'" class="m-0 text-xs text-red-700">{{ r.status === 'MAINTENANCE' ? 'ปิดซ่อมบำรุง' : 'ปิดใช้งาน' }}</p>
          </div>
        </div>
      </v-card>
      <div v-if="money" class="mt-4 grid gap-4 sm:grid-cols-3">
        <v-card class="p-5" to="/pos">
          <p class="m-0 text-sm text-light-brown">ยอดรับวันนี้</p>
          <p class="m-0 mt-1 text-3xl font-semibold">{{ formatBaht(Number(money.today_sales)) }}</p>
        </v-card>
        <v-card class="p-5" to="/pos">
          <p class="m-0 text-sm text-light-brown">ยอดค้างชำระ</p>
          <p class="m-0 mt-1 text-3xl font-semibold" :class="{ 'text-red-700': Number(money.outstanding) > 0 }">{{ formatBaht(Number(money.outstanding)) }}</p>
        </v-card>
        <v-card v-if="isOwner" class="p-5" to="/expenses">
          <p class="m-0 text-sm text-light-brown">คำขอยกเลิกรายจ่าย</p>
          <p class="m-0 mt-1 text-3xl font-semibold">{{ money.pending_void_requests }}</p>
        </v-card>
      </div>
    </template>
  </div>
</template>
