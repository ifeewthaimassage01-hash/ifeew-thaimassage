<script setup lang="ts">
// แถบเวลาเปิดวันนี้: ช่วงเปิดเป็นแถบสีน้ำตาลอ่อน (สีข้อมูล) เส้นสีเข้มคือ "ตอนนี้" — ตอบว่า "ตอนนี้ไปได้ไหม ปิดกี่โมง"
import { bangkokMinutes, hhmm, type TodayHours } from '~/composables/useOpenToday'

const props = defineProps<{ hours?: TodayHours | null }>()

// เวลาปัจจุบันคำนวณฝั่ง client เท่านั้น (กัน hydration mismatch) และอัปเดตทุก 30 วินาที
const now = ref<number | null>(null)
onMounted(() => (now.value = bangkokMinutes()))
useIntervalFn(() => (now.value = bangkokMinutes()), 30_000)

const open = computed(() => (props.hours && !props.hours.closed ? props.hours : null))
const axis = computed(() => {
  if (!open.value) return null
  return { from: open.value.opens! - 60, to: open.value.closes! + 60 }
})
const pct = (m: number) => (axis.value ? ((m - axis.value.from) / (axis.value.to - axis.value.from)) * 100 : 0)

// ถ้าร้านปิดหลังเที่ยงคืนและตอนนี้เป็นช่วงหลังเที่ยงคืน ให้นับต่อจากวันก่อน
const nowOnAxis = computed(() => {
  if (now.value === null || !open.value) return null
  const n = now.value
  return open.value.closes! > 1440 && n < open.value.opens! && n + 1440 < open.value.closes! ? n + 1440 : n
})

const status = computed<{ text: string; variant: 'positive' | 'neutral' | 'warning' } | null>(() => {
  if (!props.hours) return null
  if (!open.value) return { text: props.hours.holiday ? `วันนี้ปิด · ${props.hours.holiday}` : 'วันนี้ปิด', variant: 'neutral' }
  const n = nowOnAxis.value
  if (n === null) return { text: `เปิด ${hhmm(open.value.opens!)}–${hhmm(open.value.closes!)} น.`, variant: 'neutral' }
  if (n < open.value.opens!) return { text: `ยังไม่เปิด · เปิด ${hhmm(open.value.opens!)} น.`, variant: 'warning' }
  if (n < open.value.closes!) return { text: `เปิดอยู่ · ปิด ${hhmm(open.value.closes!)} น.`, variant: 'positive' }
  return { text: 'ปิดแล้ววันนี้', variant: 'neutral' }
})
</script>

<template>
  <div v-if="hours" class="grid gap-2">
    <div class="flex flex-wrap items-center gap-2">
      <Badge v-if="status" :variant="status.variant">{{ status.text }}</Badge>
      <span v-if="open && hours.holiday" class="text-sm text-muted-foreground">เวลาพิเศษ: {{ hours.holiday }}</span>
    </div>
    <div v-if="open && axis" class="relative pt-1" role="img" :aria-label="`เปิดวันนี้ ${hhmm(open.opens!)} ถึง ${hhmm(open.closes!)} น.`">
      <div class="relative h-2 rounded-full bg-muted">
        <div class="absolute inset-y-0 rounded-full bg-data" :style="{ left: `${pct(open.opens!)}%`, right: `${100 - pct(open.closes!)}%` }" />
        <div
          v-if="nowOnAxis !== null && nowOnAxis >= axis.from && nowOnAxis <= axis.to"
          class="absolute -top-1.5 h-5 w-0.5 -translate-x-1/2 rounded-full bg-foreground ring-2 ring-card"
          :style="{ left: `${pct(nowOnAxis)}%` }"
        />
      </div>
      <div class="num relative mt-1 h-5 text-[13px] text-muted-foreground">
        <span class="absolute -translate-x-1/2" :style="{ left: `${pct(open.opens!)}%` }">{{ hhmm(open.opens!) }}</span>
        <span class="absolute -translate-x-1/2" :style="{ left: `${pct(open.closes!)}%` }">{{ hhmm(open.closes!) }}</span>
      </div>
    </div>
  </div>
</template>
