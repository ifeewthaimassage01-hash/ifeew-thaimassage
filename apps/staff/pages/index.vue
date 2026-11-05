<script setup lang="ts">
// แดชบอร์ด STAFF ของสาขาที่เลือก (ส่วนที่ไม่ใช่เงิน — ยอดขาย/ค้างชำระเพิ่มใน Phase 7)
import { Banknote, CalendarCheck, CircleCheck, ListOrdered, ReceiptText, Store, Wallet } from '@lucide/vue'
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
    <PageHeader :title="`สวัสดี ${displayName || 'ผู้ใช้'}`" :description="`${activeBranch?.name ?? ''} · ${isOwner ? 'เจ้าของร้าน' : 'พนักงาน'} · อัปเดตทุก 30 วินาที`">
      <template #actions>
        <Button as-child variant="outline"><NuxtLink to="/queue">ดูคิว</NuxtLink></Button>
        <Button as-child><NuxtLink to="/pos">เปิดหน้าร้าน (POS)</NuxtLink></Button>
      </template>
    </PageHeader>

    <Alert v-if="error" variant="destructive" class="mb-6"><AlertDescription>{{ error }}</AlertDescription></Alert>

    <div v-if="!dash && !error" class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <Skeleton v-for="n in 4" :key="n" class="h-32 rounded-xl" />
    </div>

    <div v-if="dash" class="grid gap-6">
      <!-- คิวของฉัน -->
      <SectionCard v-if="dash.my_queue.length" title="คิวของฉัน" :description="`${dash.my_queue.length} คิวที่มอบหมายให้คุณ`">
        <template #actions><Button as-child variant="outline" size="sm"><NuxtLink to="/queue">ไปที่คิว</NuxtLink></Button></template>
        <div class="flex flex-wrap gap-2">
          <NuxtLink
            v-for="q in dash.my_queue"
            :key="q.queue_id"
            to="/queue"
            class="flex items-center gap-3 rounded-lg border border-border bg-background/60 px-4 py-2.5 text-foreground no-underline hover:border-input"
          >
            <span class="num text-lg font-semibold text-heading">{{ formatQueueNumber(q.queue_number) }}</span>
            <span class="text-[15px]">{{ q.service_name }} <span class="text-muted-foreground">{{ formatDuration(q.duration_minutes) }}</span></span>
            <Badge variant="default">{{ queueStatusLabels[q.status] }}</Badge>
          </NuxtLink>
        </div>
      </SectionCard>

      <!-- สรุปวันนี้ -->
      <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard label="คิวรอเรียก" :icon="ListOrdered" :value="dash.queue.waiting" to="/queue">
          <template #hint>
            เรียกแล้ว <span class="num">{{ dash.queue.called }}</span> · กำลังบริการ <span class="num">{{ dash.queue.in_service }}</span>
            <span v-if="dash.queue.overdue" class="block font-medium text-danger-ink">เลยเวลาจบ {{ dash.queue.overdue }} คิว</span>
          </template>
        </StatCard>
        <StatCard label="บริการเสร็จวันนี้" :icon="CircleCheck" :value="dash.queue.completed" to="/queue" :hint="`Walk-in ${dash.walk_in_orders} ราย`" />
        <StatCard label="การจองวันนี้" :icon="CalendarCheck" :value="dash.bookings.total" to="/bookings">
          <template #hint>
            รอเช็กอิน <span class="num">{{ dash.bookings.awaiting_check_in }}</span> · มาแล้ว <span class="num">{{ dash.bookings.checked_in }}</span>
            <span v-if="dash.bookings.slip_review" class="block font-medium text-danger-ink">สลิปรอตรวจ {{ dash.bookings.slip_review }}</span>
          </template>
        </StatCard>
        <StatCard label="กะ POS" :icon="Store" to="/pos">
          <span v-if="dash.session" class="text-success-ink">เปิดอยู่</span>
          <span v-else class="text-muted-foreground">ยังไม่มีกะ</span>
          <template #hint>
            <template v-if="dash.session">ตั้งแต่ <span class="num">{{ bangkokTime(dash.session.opened_at) }}</span> · เงินทอน <span class="num">{{ formatBaht(Number(dash.session.opening_cash)) }}</span></template>
            <template v-else>เปิดให้อัตโนมัติเมื่อรับเงินครั้งแรก</template>
          </template>
        </StatCard>
      </div>

      <div class="grid items-start gap-6 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
        <!-- เตียงและอุปกรณ์ -->
        <SectionCard title="เตียงและอุปกรณ์ตอนนี้" flush>
          <EmptyState v-if="!dash.resources.length" compact title="ยังไม่ได้ตั้งค่าเตียงและอุปกรณ์" class="m-5" />
          <ul v-else class="m-0 grid list-none p-0">
            <li v-for="r in dash.resources" :key="r.resource_type_id" class="grid gap-2 border-b border-border px-5 py-3.5 last:border-0">
              <div class="flex items-baseline justify-between gap-3">
                <span class="text-heading">{{ r.name }}</span>
                <span class="text-[15px]">ว่าง <span class="num font-semibold text-heading">{{ Math.max(0, r.total - r.in_use) }}</span> / <span class="num">{{ r.total }}</span></span>
              </div>
              <div class="h-1.5 overflow-hidden rounded-full bg-secondary" role="img" :aria-label="`ใช้อยู่ ${r.in_use} จาก ${r.total}`">
                <div class="h-full rounded-full bg-brand-accent" :style="{ width: `${r.total ? Math.min(100, (r.in_use / r.total) * 100) : 0}%` }" />
              </div>
              <Badge v-if="r.status !== 'ACTIVE'" variant="danger" class="w-fit">{{ r.status === 'MAINTENANCE' ? 'ปิดซ่อมบำรุง' : 'ปิดใช้งาน' }}</Badge>
            </li>
          </ul>
        </SectionCard>

        <!-- เงินวันนี้ -->
        <div v-if="money" class="grid gap-4 sm:grid-cols-2 xl:grid-cols-2">
          <StatCard label="ยอดรับวันนี้" :icon="Banknote" :value="formatBaht(Number(money.today_sales))" to="/pos" hint="ไม่รวมทิป" />
          <StatCard label="ยอดค้างชำระ" :icon="Wallet" to="/pos" :hint="Number(money.outstanding) > 0 ? 'มีบิลที่ยังเก็บเงินไม่ครบ' : 'ไม่มียอดค้าง'">
            <span :class="Number(money.outstanding) > 0 ? 'text-danger-ink' : ''">{{ formatBaht(Number(money.outstanding)) }}</span>
          </StatCard>
          <StatCard v-if="isOwner" label="คำขอยกเลิกรายจ่าย" :icon="ReceiptText" :value="money.pending_void_requests" to="/expenses" class="sm:col-span-2"
            :hint="money.pending_void_requests ? 'รอเจ้าของร้านอนุมัติ' : 'ไม่มีคำขอค้าง'" />
        </div>
      </div>
    </div>
  </div>
</template>
