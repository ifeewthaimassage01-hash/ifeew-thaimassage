<script setup lang="ts">
// กราฟเส้นจิ๋วในการ์ดสรุป (ตกแต่งประกอบตัวเลข — ข้อมูลจริง ตัวเลขหลักอยู่ในการ์ดแล้วจึงซ่อนจากโปรแกรมอ่านหน้าจอ)
const props = defineProps<{ values: number[] }>()
const W = 72
const H = 26
const d = computed(() => {
  const v = props.values.length > 1 ? props.values : [0, 0]
  const max = Math.max(1, ...v)
  return v.map((n, i) => `${i ? 'L' : 'M'}${((i / (v.length - 1)) * (W - 4) + 2).toFixed(1)},${(H - 3 - (n / max) * (H - 6)).toFixed(1)}`).join(' ')
})
</script>

<template>
  <svg :viewBox="`0 0 ${W} ${H}`" class="h-[26px] w-[72px] shrink-0" aria-hidden="true">
    <path :d="d" fill="none" stroke="var(--brand-accent)" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
  </svg>
</template>
