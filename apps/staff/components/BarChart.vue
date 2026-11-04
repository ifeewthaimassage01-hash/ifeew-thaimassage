<script setup lang="ts">
// กราฟแท่งชุดเดียว (เช่น รายรับรายวัน) — สีหลักของธีม, ปลายแท่งมน 4px, เส้นกริดจาง, hover แสดงค่า
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
    <div class="mb-2 flex items-center justify-between">
      <p class="m-0 font-medium">{{ title }}</p>
      <v-btn size="small" variant="text" @click="showTable = !showTable">{{ showTable ? 'ดูกราฟ' : 'ดูตาราง' }}</v-btn>
    </div>

    <v-table v-if="showTable" density="compact" class="max-h-72 overflow-auto">
      <tbody>
        <tr v-for="p in points" :key="p.label"><td>{{ p.label }}</td><td class="text-right">{{ format(p.value) }}</td></tr>
      </tbody>
    </v-table>

    <div v-else class="relative">
      <svg :viewBox="`0 0 ${W} ${H}`" class="block h-auto w-full" role="img" :aria-label="title" @mouseleave="hover = null">
        <g>
          <line v-for="t in ticks" :key="t" :x1="PAD.left" :x2="W - PAD.right" :y1="y(t)" :y2="y(t)"
            stroke="currentColor" stroke-opacity="0.12" stroke-width="1" />
          <text v-for="t in ticks" :key="'l' + t" :x="PAD.left - 8" :y="y(t) + 4" text-anchor="end"
            class="fill-current text-[11px] opacity-60">{{ format(t) }}</text>
        </g>
        <path v-for="(p, i) in points" :key="p.label" :d="barPath(i, p.value)"
          :style="{ fill: 'rgb(var(--v-theme-primary))', opacity: hover === null || hover === i ? 1 : 0.45 }" />
        <!-- พื้นที่ hover ใหญ่กว่าแท่ง -->
        <rect v-for="(p, i) in points" :key="'h' + p.label" :x="PAD.left + i * slot" :y="PAD.top" :width="slot" :height="innerH"
          fill="transparent" @mouseenter="hover = i" @touchstart.passive="hover = i" />
        <template v-for="(p, i) in points" :key="'x' + p.label">
          <text v-if="i % (labelEvery ?? 1) === 0 || i === points.length - 1" :x="PAD.left + i * slot + slot / 2" :y="H - 8"
            text-anchor="middle" class="fill-current text-[11px] opacity-60">{{ p.label }}</text>
        </template>
      </svg>
      <div v-if="hover !== null && points[hover]"
        class="pointer-events-none absolute top-0 rounded-lg bg-white px-3 py-1 text-sm shadow-soft"
        :style="{ left: `${((PAD.left + hover * slot + slot / 2) / W) * 100}%`, transform: 'translateX(-50%)' }">
        <span class="text-light-brown">{{ points[hover].label }}</span> · <b>{{ format(points[hover].value) }}</b>
      </div>
    </div>
  </div>
</template>
