<script setup lang="ts">
// ตารางนัดรายชั่วโมงของวัน (แดชบอร์ด) — การจองไม่ผูกกับหมอ/เตียง จึงวางเป็น "ช่อง" ตามเวลาที่ทับกัน
// เส้นเวลาปัจจุบันแสดงเฉพาะวันนี้
import { User } from '@lucide/vue'
import { bangkokTime, bangkokToday, bookingStatusLabels, type StaffBookingRow } from '@ifeew/shared'

const props = defineProps<{ rows: StaffBookingRow[]; date: string }>()

const HOUR_PX = 40
const GUTTER = 56
const DAY_MS = 86_400_000
const minuteOfDay = (iso: string) => (((new Date(iso).getTime() + 7 * 3_600_000) % DAY_MS) + DAY_MS) % DAY_MS / 60_000

const visible = computed(() =>
  props.rows
    .filter((r) => !['CANCELLED', 'EXPIRED'].includes(r.status))
    .map((r) => {
      const start = minuteOfDay(r.starts_at)
      const end = Math.max(start + 15, minuteOfDay(r.ends_at) || 24 * 60)
      return { row: r, start, end }
    })
    .sort((a, b) => a.start - b.start),
)

// ช่วงชั่วโมงที่แสดง: อย่างน้อย 10:00–21:00 ขยายตามนัดจริง
const range = computed(() => {
  const s = visible.value.length ? Math.min(...visible.value.map((v) => v.start)) : 10 * 60
  const e = visible.value.length ? Math.max(...visible.value.map((v) => v.end)) : 21 * 60
  return { from: Math.max(0, Math.min(10, Math.floor(s / 60))), to: Math.min(24, Math.max(21, Math.ceil(e / 60))) }
})
const hours = computed(() => Array.from({ length: range.value.to - range.value.from + 1 }, (_, i) => range.value.from + i))

// จัดช่อง (interval partitioning): นัดที่เวลาทับกันอยู่คนละช่อง
const placed = computed(() => {
  const laneEnds: number[] = []
  const out = visible.value.map((v) => {
    let lane = laneEnds.findIndex((end) => end <= v.start)
    if (lane === -1) lane = laneEnds.push(v.end) - 1
    else laneEnds[lane] = v.end
    return { ...v, lane }
  })
  return { items: out, lanes: Math.max(laneEnds.length, 3) }
})

const top = (m: number) => ((m - range.value.from * 60) / 60) * HOUR_PX
const laneStyle = (lane: number, lanes: number) => ({
  left: `calc(${GUTTER}px + (100% - ${GUTTER}px) * ${lane} / ${lanes} + 4px)`,
  width: `calc((100% - ${GUTTER}px) / ${lanes} - 8px)`,
})

// เส้นเวลาปัจจุบัน
const now = ref(Date.now())
useIntervalFn(() => (now.value = Date.now()), 60_000)
const nowTop = computed(() => {
  if (props.date !== bangkokToday(new Date(now.value))) return null
  const m = minuteOfDay(new Date(now.value).toISOString())
  return m >= range.value.from * 60 && m <= range.value.to * 60 ? top(m) : null
})

const tone = (s: StaffBookingRow['status']) =>
  s === 'PENDING'
    ? 'bg-pending-soft border-brand-accent/40'
    : s === 'CONFIRMED'
      ? 'bg-secondary border-brand-accent/50'
      : 'bg-muted border-border'
const dot = (s: StaffBookingRow['status']) => (s === 'PENDING' ? 'bg-brand-accent' : s === 'CONFIRMED' ? 'bg-primary' : 'bg-muted-soft')
</script>

<template>
  <div class="scrollbar-hidden overflow-x-auto">
    <!-- หัวคอลัมน์ของช่อง (ภาพอ้างอิง) -->
    <div class="mb-2 flex h-8 min-w-[244px] rounded-lg bg-muted" :style="{ marginLeft: `${GUTTER}px` }" aria-hidden="true">
      <span v-for="l in placed.lanes" :key="`head-${l}`" class="flex flex-1 items-center justify-center gap-1.5 text-[12px] text-muted-foreground">
        <User class="size-3.5" :stroke-width="1.6" /> {{ l }}
      </span>
    </div>
    <div class="relative min-w-[300px]" :style="{ height: `${(hours.length - 1) * HOUR_PX + 12}px` }">
      <!-- เส้นชั่วโมง + ป้ายเวลา -->
      <div v-for="(h, i) in hours" :key="h" class="absolute inset-x-0 flex items-center" :style="{ top: `${i * HOUR_PX}px` }">
        <span class="num w-14 shrink-0 -translate-y-px pr-3 text-right text-[12px] text-muted-foreground">{{ String(h).padStart(2, '0') }}:00</span>
        <span class="h-px flex-1 bg-border/80" />
      </div>
      <!-- เส้นแบ่งช่อง -->
      <div
        v-for="l in placed.lanes - 1"
        :key="`lane-${l}`"
        class="absolute top-0 bottom-3 w-px bg-border/60"
        :style="{ left: `calc(${GUTTER}px + (100% - ${GUTTER}px) * ${l} / ${placed.lanes})` }"
        aria-hidden="true"
      />

      <!-- นัด -->
      <NuxtLink
        v-for="it in placed.items"
        :key="it.row.booking_id"
        to="/bookings"
        class="absolute flex flex-col justify-center overflow-hidden rounded-lg border px-2.5 py-1 text-[12px] leading-[1.25] text-heading no-underline shadow-soft transition-transform hover:-translate-y-px"
        :class="tone(it.row.status)"
        :style="{ top: `${top(it.start) + 2}px`, height: `${Math.max(26, top(it.end) - top(it.start) - 4)}px`, ...laneStyle(it.lane, placed.lanes) }"
        :aria-label="`${bangkokTime(it.row.starts_at)} ${it.row.customer_name} ${bookingStatusLabels[it.row.status]}`"
      >
        <span class="flex min-w-0 items-center gap-1.5">
          <span class="size-1.5 shrink-0 rounded-full" :class="dot(it.row.status)" aria-hidden="true" />
          <span class="num shrink-0 font-medium">{{ bangkokTime(it.row.starts_at) }}</span>
          <span class="truncate text-muted-foreground">{{ it.row.items.map((i) => i.service_name).join(', ') }}</span>
        </span>
        <span class="flex min-w-0 items-center gap-1 text-muted-foreground">
          <User class="size-3 shrink-0" aria-hidden="true" /><span class="truncate">{{ it.row.customer_name }}</span>
        </span>
      </NuxtLink>

      <!-- เวลาปัจจุบัน -->
      <div v-if="nowTop !== null" class="pointer-events-none absolute right-0 flex items-center" :style="{ top: `${nowTop}px`, left: `${GUTTER - 5}px` }" aria-hidden="true">
        <span class="size-2.5 rounded-full bg-primary" />
        <span class="h-px flex-1 bg-primary" />
      </div>
    </div>
  </div>
</template>
