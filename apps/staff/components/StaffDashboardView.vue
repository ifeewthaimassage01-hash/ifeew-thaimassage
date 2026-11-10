<script setup lang="ts">
// เนื้อหาแดชบอร์ดสาขา (โครงตามภาพอ้างอิง Warm Cream) — รับข้อมูลทาง props เท่านั้น หน้า pages/index.vue เป็นคนโหลด
//   การ์ดสรุป 4 ใบ → ตารางนัดรายชั่วโมง + นัดถัดไป/ต้องจัดการ → เตียงและอุปกรณ์ + ภาพรวมการจอง
import {
  AlarmClock,
  Banknote,
  BedDouble,
  CalendarCheck,
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  CircleCheck,
  List,
  FileWarning,
  ListOrdered,
  ReceiptText,
  UserCheck,
  Wallet,
} from '@lucide/vue'
import {
  addDays,
  bangkokDateLong,
  bangkokTime,
  bangkokToday,
  bookingStatusLabels,
  formatBaht,
  formatDuration,
  formatQueueNumber,
  queueStatusLabels,
  type StaffBookingRow,
  type StaffDashboard,
} from '@ifeew/shared'

const props = defineProps<{
  dash: StaffDashboard | null
  money: { today_sales: number; outstanding: number; pending_void_requests: number } | null
  rows: StaffBookingRow[]
  error: string | null
  loadingDay: boolean
  isOwner: boolean
  branchName?: string
}>()
const date = defineModel<string>('date', { required: true })

const isToday = computed(() => date.value === bangkokToday())

// นัดเริ่มในแต่ละชั่วโมง 10:00–21:00 (กราฟจิ๋วในการ์ดการจอง)
const perHour = computed(() => {
  const hrs = props.rows.filter((r) => !['CANCELLED', 'EXPIRED'].includes(r.status)).map((r) => Number(bangkokTime(r.starts_at).slice(0, 2)))
  return Array.from({ length: 12 }, (_, i) => hrs.filter((h) => h === 10 + i).length)
})

// นัดถัดไป
const now = ref(Date.now())
useIntervalFn(() => (now.value = Date.now()), 60_000)
const upcoming = computed(() =>
  props.rows
    .filter((r) => ['PENDING', 'CONFIRMED'].includes(r.status) && (!isToday.value || new Date(r.ends_at).getTime() > now.value))
    .sort((a, b) => a.starts_at.localeCompare(b.starts_at))
    .slice(0, 4),
)
const statusVariant = (s: StaffBookingRow['status']) =>
  (({ PENDING: 'pending', CONFIRMED: 'success', CHECKED_IN: 'default', COMPLETED: 'success', CANCELLED: 'danger', NO_SHOW: 'danger', EXPIRED: 'neutral' }) as const)[s]

// ต้องจัดการ (แทนกล่องข้อความในภาพ — งานที่รอคนทำจริง)
const todo = computed(() => {
  if (!props.dash) return []
  const d = props.dash
  const out = [
    { key: 'slip', icon: FileWarning, text: 'สลิปมัดจำรอตรวจ', n: d.bookings.slip_review, to: '/bookings', urgent: true },
    { key: 'overdue', icon: AlarmClock, text: 'คิวเลยเวลาจบ', n: d.queue.overdue, to: '/queue', urgent: true },
    { key: 'checkin', icon: UserCheck, text: 'การจองรอเช็กอิน', n: d.bookings.awaiting_check_in, to: '/bookings', urgent: false },
    { key: 'called', icon: ListOrdered, text: 'คิวเรียกแล้ว รอเริ่ม', n: d.queue.called, to: '/queue', urgent: false },
  ]
  if (props.money && Number(props.money.outstanding) > 0) {
    out.push({ key: 'outstanding', icon: Wallet, text: `ยอดค้างชำระ ${formatBaht(Number(props.money.outstanding))}`, n: 1, to: '/payments', urgent: true })
  }
  if (props.isOwner && props.money?.pending_void_requests) {
    out.push({ key: 'void', icon: ReceiptText, text: 'คำขอยกเลิกรายจ่าย', n: props.money.pending_void_requests, to: '/expenses', urgent: false })
  }
  return out.filter((t) => t.n > 0)
})
</script>

<template>
  <div class="grid grid-cols-1 gap-5">
    <h1 class="sr-only">แดชบอร์ด {{ branchName }}</h1>

    <Alert v-if="error" variant="destructive"><AlertDescription>{{ error }}</AlertDescription></Alert>

    <!-- คิวของฉัน (เฉพาะคนที่มีคิวมอบหมาย) -->
    <SectionCard v-if="dash?.my_queue.length" title="คิวของฉัน" :description="`${dash.my_queue.length} คิวที่มอบหมายให้คุณ`">
      <template #actions><Button as-child variant="outline" size="sm"><NuxtLink to="/queue">ไปที่คิว</NuxtLink></Button></template>
      <div class="flex flex-wrap gap-2">
        <NuxtLink
          v-for="q in dash.my_queue"
          :key="q.queue_id"
          to="/queue"
          class="flex items-center gap-3 rounded-lg border border-border bg-muted px-4 py-2.5 text-foreground no-underline hover:border-input"
        >
          <span class="num text-lg font-semibold text-heading">{{ formatQueueNumber(q.queue_number) }}</span>
          <span class="text-[15px]">{{ q.service_name }} <span class="text-muted-foreground">{{ formatDuration(q.duration_minutes) }}</span></span>
          <Badge>{{ queueStatusLabels[q.status] }}</Badge>
        </NuxtLink>
      </div>
    </SectionCard>

    <!-- การ์ดสรุป -->
    <div v-if="!dash && !error" class="grid grid-cols-2 gap-4 lg:grid-cols-4">
      <Skeleton v-for="n in 4" :key="n" class="h-36 rounded-xl" />
    </div>
    <div v-else-if="dash" class="grid grid-cols-2 gap-4 lg:grid-cols-4">
      <StatCard label="การจองวันนี้" :icon="CalendarCheck" :value="dash.bookings.total" to="/bookings">
        <template #trailing><MiniSparkline :values="perHour" /></template>
        <template #hint>มาแล้ว <span class="num">{{ dash.bookings.checked_in }}</span> · รอ <span class="num">{{ dash.bookings.awaiting_check_in }}</span></template>
      </StatCard>
      <StatCard label="คิวรอเรียก" :icon="ListOrdered" :value="dash.queue.waiting" to="/queue">
        <template #hint>กำลังบริการ <span class="num">{{ dash.queue.in_service }}</span></template>
      </StatCard>
      <StatCard label="บริการเสร็จวันนี้" :icon="CircleCheck" :value="dash.queue.completed" to="/queue" :hint="`Walk-in ${dash.walk_in_orders} ราย`" />
      <StatCard label="ยอดรับวันนี้" :icon="Banknote" :value="money ? formatBaht(Number(money.today_sales)) : '—'" to="/payments" hint="ไม่รวมทิป" />
    </div>

    <!-- ตารางนัด + แผงขวา -->
    <div class="grid grid-cols-1 gap-5 xl:grid-cols-[minmax(0,1fr)_340px]">
      <!-- ซ้าย: ตารางนัด + ภาพรวมการจอง · ขวา: นัดถัดไป, ต้องจัดการ, เตียง — การ์ดสุดท้ายของแต่ละฝั่งยืดให้ขอบล่างตรงกัน -->
      <div class="flex min-w-0 flex-col gap-5">
      <section class="rounded-xl border border-border bg-card p-4 shadow-soft sm:p-5" aria-labelledby="timeline-h">
        <div class="mb-4 flex flex-wrap items-center gap-2">
          <h2 id="timeline-h" class="sr-only">ตารางนัด</h2>
          <Button variant="outline" size="icon-sm" class="rounded-lg" aria-label="วันก่อน" @click="date = addDays(date, -1)"><ChevronLeft /></Button>
          <Button variant="outline" size="icon-sm" class="rounded-lg" aria-label="วันถัดไป" @click="date = addDays(date, 1)"><ChevronRight /></Button>
          <span class="ml-1 flex min-w-0 items-center gap-2 text-[15px] font-medium text-heading">
            <CalendarDays class="size-4 shrink-0 text-brand-accent" aria-hidden="true" />
            <span class="truncate">{{ bangkokDateLong(`${date}T12:00:00+07:00`) }}</span>
          </span>
          <Button v-if="!isToday" variant="ghost" size="sm" @click="date = bangkokToday()">วันนี้</Button>
          <span class="flex-1" />
          <span v-if="loadingDay" class="text-[13px] text-muted-foreground">กำลังโหลด…</span>
          <div class="inline-flex rounded-lg border border-border bg-card p-0.5" role="group" aria-label="มุมมอง">
            <span class="grid size-8 place-items-center rounded-md bg-primary text-primary-foreground" aria-current="true" title="ตารางเวลา"><CalendarDays class="size-4" /><span class="sr-only">ตารางเวลา</span></span>
            <NuxtLink to="/bookings" class="grid size-8 place-items-center rounded-md text-muted-foreground no-underline hover:bg-muted hover:text-heading" title="รายการการจอง"><List class="size-4" /><span class="sr-only">รายการการจอง</span></NuxtLink>
          </div>
        </div>
        <DashboardTimeline :rows="rows" :date="date" />
        <p v-if="!loadingDay && !rows.length" class="m-0 mt-3 text-center text-sm text-muted-foreground">ไม่มีการจองในวันนี้</p>
      </section>

        <!-- ภาพรวมการจอง -->
        <section class="flex-1 rounded-xl border border-border bg-card p-5 shadow-soft" aria-labelledby="chart-h">
          <h2 id="chart-h" class="m-0 mb-4 text-[15px] font-semibold">ภาพรวมการจอง<span class="font-normal text-muted-foreground"> · {{ isToday ? 'วันนี้' : bangkokDateLong(`${date}T12:00:00+07:00`) }}</span></h2>
          <DashboardBookingCharts :rows="rows" />
        </section>
      </div>

      <div class="grid grid-cols-1 content-start gap-5 md:grid-cols-2 xl:flex xl:flex-col">
        <!-- นัดถัดไป -->
        <section class="rounded-xl border border-border bg-card p-5 shadow-soft" aria-labelledby="upcoming-h">
          <h2 id="upcoming-h" class="m-0 mb-3 text-[15px] font-semibold">นัดถัดไป</h2>
          <p v-if="!upcoming.length" class="m-0 py-4 text-center text-sm text-muted-foreground">ไม่มีนัดที่รออยู่</p>
          <ul v-else class="m-0 grid list-none gap-1 p-0">
            <li v-for="b in upcoming" :key="b.booking_id">
              <NuxtLink to="/bookings" class="-mx-2 flex items-center gap-3 rounded-lg px-2 py-1.5 text-foreground no-underline hover:bg-muted">
                <span class="grid size-9 shrink-0 place-items-center rounded-lg bg-muted text-brand-accent" aria-hidden="true"><CalendarCheck class="size-4" :stroke-width="1.6" /></span>
                <span class="min-w-0 flex-1">
                  <span class="block truncate text-[14px] font-medium text-heading">{{ b.customer_name }}</span>
                  <span class="block truncate text-[12px] text-muted-foreground"><span class="num">{{ bangkokTime(b.starts_at) }}</span> · {{ b.items.map((i) => i.service_name).join(', ') }}</span>
                </span>
                <Badge :variant="statusVariant(b.status)" class="shrink-0">{{ bookingStatusLabels[b.status] }}</Badge>
                <ChevronRight class="size-4 shrink-0 text-muted-soft" aria-hidden="true" />
              </NuxtLink>
            </li>
          </ul>
          <Button as-child variant="secondary" size="sm" class="mt-3 w-full"><NuxtLink to="/bookings">ดูการจองทั้งหมด</NuxtLink></Button>
        </section>

        <!-- ต้องจัดการ -->
        <section class="rounded-xl border border-border bg-card p-5 shadow-soft" aria-labelledby="todo-h">
          <h2 id="todo-h" class="m-0 mb-3 text-[15px] font-semibold">ต้องจัดการ</h2>
          <p v-if="!todo.length" class="m-0 py-4 text-center text-sm text-muted-foreground">ไม่มีงานค้าง</p>
          <ul v-else class="m-0 grid list-none gap-1 p-0">
            <li v-for="t in todo" :key="t.key">
              <NuxtLink :to="t.to" class="-mx-2 flex items-center gap-3 rounded-lg px-2 py-1.5 text-foreground no-underline hover:bg-muted">
                <span class="grid size-7 shrink-0 place-items-center text-muted-soft" aria-hidden="true"><component :is="t.icon" class="size-[18px]" :stroke-width="1.6" /></span>
                <span class="min-w-0 flex-1 truncate text-[14px] text-heading">{{ t.text }}</span>
                <span class="flex shrink-0 items-center gap-1.5 text-[13px] text-muted-foreground">
                  <span class="size-1.5 rounded-full" :class="t.urgent ? 'bg-danger' : 'bg-success'" aria-hidden="true" />
                  <span v-if="t.key !== 'outstanding'" class="num">{{ t.n }}</span>
                  <span class="sr-only">{{ t.urgent ? '(เร่งด่วน)' : '' }}</span>
                </span>
              </NuxtLink>
            </li>
          </ul>
        </section>

        <!-- เตียงและอุปกรณ์ -->
        <section v-if="dash" class="xl:flex-1 rounded-xl border border-border bg-card p-5 shadow-soft" aria-labelledby="res-h">
          <h2 id="res-h" class="m-0 mb-3 text-[15px] font-semibold">เตียงและอุปกรณ์ตอนนี้</h2>
          <p v-if="!dash.resources.length" class="m-0 py-4 text-center text-sm text-muted-foreground">ยังไม่ได้ตั้งค่าเตียงและอุปกรณ์</p>
          <ul v-else class="m-0 grid list-none p-0">
            <li v-for="r in dash.resources" :key="r.resource_type_id" class="flex items-center gap-3 border-b border-border/70 py-2.5 last:border-0">
              <span class="grid size-8 shrink-0 place-items-center rounded-full bg-muted text-brand-accent" aria-hidden="true"><BedDouble class="size-4" :stroke-width="1.6" /></span>
              <span class="min-w-0 flex-1">
                <span class="block truncate text-[14px] text-heading">{{ r.name }}</span>
                <span class="mt-1 block h-1.5 overflow-hidden rounded-full bg-muted" role="img" :aria-label="`ใช้อยู่ ${r.in_use} จาก ${r.total}`">
                  <span class="block h-full rounded-full bg-brand-accent" :style="{ width: `${r.total ? Math.min(100, (r.in_use / r.total) * 100) : 0}%` }" />
                </span>
              </span>
              <Badge v-if="r.status !== 'ACTIVE'" variant="danger" class="shrink-0">{{ r.status === 'MAINTENANCE' ? 'ซ่อมบำรุง' : 'ปิดใช้งาน' }}</Badge>
              <Badge v-else :variant="r.total - r.in_use > 0 ? 'success' : 'pending'" class="shrink-0">
                ว่าง <span class="num">{{ Math.max(0, r.total - r.in_use) }}/{{ r.total }}</span>
              </Badge>
            </li>
          </ul>
        </section>
      </div>
    </div>
  </div>
</template>
