<script setup lang="ts">
// กราฟแท่งชุดเดียว (เช่น รายรับรายวัน) — สี Primary ตาม DESIGN.md, ปลายแท่งมน 4px, เส้นกริดสี Border, hover แสดงค่า
// มีปุ่มสลับดูเป็นตาราง (ไม่พึ่งสีอย่างเดียว)
const props = defineProps<{
  title: string
  points: Array<{ label: string; value: number }>
  format: (v: number) => string
  labelEvery?: number
}>()

const showTable = ref(false)
const hover = ref<number | null>(null)

const W = 720
const H = 220
const PAD = { top: 12, right: 8, bottom: 28, left: 64 }
const innerW = W - PAD.left - PAD.right
const innerH = H - PAD.top - PAD.bottom

const max = computed(() => {
  const m = Math.max(0, ...props.points.map((p) => p.value))
  if (m <= 0) return 1
  const mag = 10 ** Math.floor(Math.log10(m))
  return Math.ceil(m / mag) * mag
})
const min = computed(() => Math.min(0, ...props.points.map((p) => p.value)))
const span = computed(() => max.value - min.value || 1)
const y = (v: number) => PAD.top + innerH - ((v - min.value) / span.value) * innerH
const slot = computed(() => innerW / Math.max(1, props.points.length))
const barW = computed(() => Math.max(2, Math.min(28, slot.value - 2)))
const ticks = computed(() => [min.value, min.value + span.value / 2, max.value])

// แท่งปลายมนเฉพาะด้านที่ห่างจากเส้นฐาน
function barPath(i: number, v: number): string {
  const x = PAD.left + i * slot.value + (slot.value - barW.value) / 2
  const y0 = y(0)
  const y1 = y(v)
  const h = Math.abs(y1 - y0)
  if (h < 0.5) return ''
  const r = Math.min(4, barW.value / 2, h)
  const w = barW.value
  return v >= 0
    ? `M${x},${y0} V${y1 + r} Q${x},${y1} ${x + r},${y1} H${x + w - r} Q${x + w},${y1} ${x + w},${y1 + r} V${y0} Z`
    : `M${x},${y0} V${y1 - r} Q${x},${y1} ${x + r},${y1} H${x + w - r} Q${x + w},${y1} ${x + w},${y1 - r} V${y0} Z`
}
</script>

<template>
  <div>
    <div class="mb-3 flex items-center justify-between gap-3">
      <h3 class="m-0 text-base font-semibold">{{ title }}</h3>
      <SegmentedControl
        :model-value="showTable ? 'table' : 'chart'"
        :items="[{ value: 'chart', label: 'กราฟ' }, { value: 'table', label: 'ตาราง' }]"
        size="sm"
        :label="`มุมมอง ${title}`"
        @update:model-value="(v) => (showTable = v === 'table')"
      />
    </div>

    <div v-if="showTable" class="max-h-72 overflow-auto rounded-lg border border-border">
      <Table>
        <TableBody>
          <TableRow v-for="p in points" :key="p.label">
            <TableCell class="py-2">{{ p.label }}</TableCell>
            <TableCell class="num py-2 text-right text-heading">{{ format(p.value) }}</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </div>

    <div v-else class="relative">
      <svg :viewBox="`0 0 ${W} ${H}`" class="block h-auto w-full" role="img" :aria-label="title" @mouseleave="hover = null">
        <g>
          <line v-for="t in ticks" :key="t" :x1="PAD.left" :x2="W - PAD.right" :y1="y(t)" :y2="y(t)"
            stroke="var(--border)" stroke-width="1" />
          <text v-for="t in ticks" :key="'l' + t" :x="PAD.left - 8" :y="y(t) + 4" text-anchor="end"
            class="num text-[11px]" fill="var(--muted-foreground)">{{ format(t) }}</text>
        </g>
        <path v-for="(p, i) in points" :key="p.label" :d="barPath(i, p.value)"
          :style="{ fill: 'var(--primary)', opacity: hover === null || hover === i ? 1 : 0.4 }" />
        <!-- พื้นที่ hover ใหญ่กว่าแท่ง -->
        <rect v-for="(p, i) in points" :key="'h' + p.label" :x="PAD.left + i * slot" :y="PAD.top" :width="slot" :height="innerH"
          fill="transparent" @mouseenter="hover = i" @touchstart.passive="hover = i" />
        <template v-for="(p, i) in points" :key="'x' + p.label">
          <text v-if="i % (labelEvery ?? 1) === 0 || i === points.length - 1" :x="PAD.left + i * slot + slot / 2" :y="H - 8"
            text-anchor="middle" class="text-[11px]" fill="var(--muted-foreground)">{{ p.label }}</text>
        </template>
      </svg>
      <div v-if="hover !== null && points[hover]"
        class="pointer-events-none absolute top-0 rounded-lg border border-border bg-card px-3 py-1 text-sm shadow-sm"
        :style="{ left: `${((PAD.left + hover * slot + slot / 2) / W) * 100}%`, transform: 'translateX(-50%)' }">
        <span class="text-muted-foreground">{{ points[hover].label }}</span> · <b class="num text-heading">{{ format(points[hover].value) }}</b>
      </div>
    </div>
  </div>
</template>
