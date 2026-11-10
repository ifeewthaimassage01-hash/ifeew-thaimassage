<script setup lang="ts">
// ภาพรวมการจองของวัน: โดนัทสถานะ (ขั้นตอนเรียงลำดับ → โทนน้ำตาลอ่อน→เข้ม + เทาสำหรับยกเลิก) และเส้นจำนวนนัดรายชั่วโมง
// สีผ่าน validate_palette (แยกคู่ติดกันได้ทั้งตาบอดสีและตาปกติ) และมีป้าย+จำนวนทุกช่อง ไม่พึ่งสีอย่างเดียว
import type { StaffBookingRow } from '@ifeew/shared'

const props = defineProps<{ rows: StaffBookingRow[] }>()

const GROUPS = [
  { key: 'pending', label: 'รอยืนยัน', color: '#e2c9ad', statuses: ['PENDING'] },
  { key: 'confirmed', label: 'ยืนยันแล้ว', color: '#b38b67', statuses: ['CONFIRMED'] },
  { key: 'done', label: 'มาแล้ว/เสร็จ', color: '#6e4f37', statuses: ['CHECKED_IN', 'COMPLETED'] },
  { key: 'cancelled', label: 'ยกเลิก/ไม่มา', color: '#d9d4ce', statuses: ['CANCELLED', 'NO_SHOW', 'EXPIRED'] },
] as const

const counts = computed(() => GROUPS.map((g) => ({ ...g, n: props.rows.filter((r) => (g.statuses as readonly string[]).includes(r.status)).length })))
const total = computed(() => props.rows.length)

// โดนัท: วงรัศมี 40 เส้นหนา 12 เว้นช่อง 2px ระหว่างช่อง
const R = 40
const C = 2 * Math.PI * R
const segments = computed(() => {
  let acc = 0
  const live = counts.value.filter((c) => c.n > 0)
  const gap = live.length > 1 ? 2 : 0
  return live.map((c) => {
    const len = (c.n / total.value) * C
    const seg = { ...c, dash: `${Math.max(0, len - gap)} ${C}`, offset: -acc }
    acc += len
    return seg
  })
})

// เส้น: นัดที่เริ่มในแต่ละชั่วโมง (ไม่นับยกเลิก)
const DAY_MS = 86_400_000
const hourOf = (iso: string) => Math.floor((((new Date(iso).getTime() + 7 * 3_600_000) % DAY_MS) + DAY_MS) % DAY_MS / 3_600_000)
const series = computed(() => {
  const active = props.rows.filter((r) => !['CANCELLED', 'EXPIRED', 'NO_SHOW'].includes(r.status))
  const hrs = active.map((r) => hourOf(r.starts_at))
  const from = Math.min(10, ...hrs)
  const to = Math.max(21, ...hrs)
  return Array.from({ length: to - from + 1 }, (_, i) => ({ hour: from + i, n: hrs.filter((h) => h === from + i).length }))
})
// กว้างตามพื้นที่จริง (ไม่ยืดสเกล) — ตัวอักษร/เส้นคงขนาดไม่ว่าการ์ดจะกว้างเท่าไร
const chartBox = ref<HTMLElement | null>(null)
const { width: boxWidth } = useElementSize(chartBox)
const W = computed(() => Math.max(200, Math.round(boxWidth.value) || 280))
const H = 110
const PAD = { l: 8, r: 8, t: 10, b: 20 }
const maxN = computed(() => Math.max(1, ...series.value.map((p) => p.n)))
const x = (i: number) => PAD.l + (i / Math.max(1, series.value.length - 1)) * (W.value - PAD.l - PAD.r)
const y = (n: number) => PAD.t + (1 - n / maxN.value) * (H - PAD.t - PAD.b)
const path = computed(() => series.value.map((p, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(p.n).toFixed(1)}`).join(' '))
const area = computed(() => `${path.value} L${x(series.value.length - 1)},${H - PAD.b} L${x(0)},${H - PAD.b} Z`)

const hover = ref<number | null>(null)
function onMove(e: PointerEvent) {
  const svg = e.currentTarget as SVGSVGElement
  const rect = svg.getBoundingClientRect()
  const px = ((e.clientX - rect.left) / rect.width) * W.value
  const i = Math.round(((px - PAD.l) / (W.value - PAD.l - PAD.r)) * (series.value.length - 1))
  hover.value = Math.min(series.value.length - 1, Math.max(0, i))
}
const hh = (h: number) => `${String(h).padStart(2, '0')}:00`
const peak = computed(() => series.value.reduce((a, b) => (b.n > a.n ? b : a), series.value[0]!))
</script>

<template>
  <div class="@container"><div class="grid gap-6 @xl:grid-cols-[auto_minmax(0,1fr)] @xl:items-center">
    <!-- โดนัทสถานะ -->
    <div class="flex items-center gap-5">
      <svg viewBox="0 0 100 100" class="size-28 shrink-0" role="img" :aria-label="`การจองทั้งหมด ${total} รายการ`">
        <g transform="rotate(-90 50 50)">
        <circle cx="50" cy="50" :r="R" fill="none" stroke="var(--muted)" stroke-width="12" />
        <circle
          v-for="s in segments"
          :key="s.key"
          cx="50"
          cy="50"
          :r="R"
          fill="none"
          :stroke="s.color"
          stroke-width="12"
          :stroke-dasharray="s.dash"
          :stroke-dashoffset="s.offset"
        ><title>{{ s.label }} {{ s.n }} รายการ</title></circle>
        </g>
        <text x="50" y="50" text-anchor="middle" dominant-baseline="central" class="num fill-heading text-[20px] font-medium">{{ total }}</text>
      </svg>
      <ul class="m-0 grid list-none gap-1.5 p-0 text-[13px]">
        <li v-for="c in counts" :key="c.key" class="flex items-center gap-2">
          <span class="size-2.5 rounded-full" :style="{ background: c.color }" aria-hidden="true" />
          <span class="text-foreground">{{ c.label }}</span>
          <span class="num ml-auto pl-2 font-medium text-heading">{{ c.n }}</span>
        </li>
      </ul>
    </div>

    <!-- นัดรายชั่วโมง -->
    <div ref="chartBox" class="relative min-w-0">
      <p class="m-0 mb-1 text-[13px] text-muted-foreground">
        นัดที่เริ่มในแต่ละชั่วโมง<span v-if="peak?.n"> · มากสุด <span class="num">{{ hh(peak.hour) }}</span> (<span class="num">{{ peak.n }}</span>)</span>
      </p>
      <svg
        :viewBox="`0 0 ${W} ${H}`"
        class="h-auto w-full touch-none overflow-visible"
        role="img"
        aria-label="จำนวนนัดที่เริ่มในแต่ละชั่วโมง"
        @pointermove="onMove"
        @pointerleave="hover = null"
      >
        <line :x1="PAD.l" :x2="W - PAD.r" :y1="H - PAD.b" :y2="H - PAD.b" stroke="var(--border)" stroke-width="1" vector-effect="non-scaling-stroke" />
        <path :d="area" fill="var(--brand-accent)" fill-opacity="0.08" />
        <path :d="path" fill="none" stroke="var(--brand-accent)" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" vector-effect="non-scaling-stroke" />
        <template v-for="(p, i) in series" :key="p.hour">
          <text v-if="i % 3 === 0" :x="x(i)" :y="H - 4" text-anchor="middle" class="num fill-muted-foreground text-[11px]">{{ String(p.hour).padStart(2, '0') }}</text>
        </template>
        <g v-if="hover !== null">
          <line :x1="x(hover)" :x2="x(hover)" :y1="PAD.t" :y2="H - PAD.b" stroke="var(--muted-soft)" stroke-width="1" stroke-dasharray="3 3" vector-effect="non-scaling-stroke" />
          <circle :cx="x(hover)" :cy="y(series[hover]!.n)" r="4" fill="var(--card)" stroke="var(--brand-accent)" stroke-width="2" vector-effect="non-scaling-stroke" />
        </g>
      </svg>
      <div
        v-if="hover !== null"
        class="pointer-events-none absolute top-0 -translate-x-1/2 rounded-md border border-border bg-card px-2 py-1 text-[12px] whitespace-nowrap text-heading shadow-soft"
        :style="{ left: `${(x(hover) / W) * 100}%` }"
      >
        <span class="num">{{ hh(series[hover]!.hour) }}</span> · <span class="num font-medium">{{ series[hover]!.n }}</span> นัด
      </div>
      <!-- ตารางสำหรับโปรแกรมอ่านหน้าจอ -->
      <table class="sr-only">
        <caption>จำนวนนัดที่เริ่มในแต่ละชั่วโมง</caption>
        <tr v-for="p in series" :key="p.hour"><th scope="row">{{ hh(p.hour) }}</th><td>{{ p.n }}</td></tr>
      </table>
    </div>
  </div>
  </div>
</template>
