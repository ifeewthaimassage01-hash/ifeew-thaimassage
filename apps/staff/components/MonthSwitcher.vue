<script setup lang="ts">
// เลือกเดือน ‹ พฤศจิกายน 2569 › (v-model = YYYY-MM) · ไปเดือนอนาคตไม่ได้ · มีปุ่มกลับ "เดือนนี้"
import { ChevronLeft, ChevronRight } from '@lucide/vue'
import { bangkokToday } from '@ifeew/shared'

const month = defineModel<string>({ required: true })
const thisMonth = bangkokToday().slice(0, 7)

function shift(delta: number) {
  const [y, m] = month.value.split('-').map(Number) as [number, number]
  const d = new Date(Date.UTC(y, m - 1 + delta, 1))
  month.value = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`
}
const label = computed(() => {
  const [y, m] = month.value.split('-').map(Number) as [number, number]
  return new Date(Date.UTC(y, m - 1, 15)).toLocaleDateString('th-TH', { month: 'long', year: 'numeric', timeZone: 'UTC' })
})
</script>

<template>
  <div class="flex items-center gap-2">
    <div class="flex flex-1 items-center gap-1 rounded-lg border border-border bg-card p-1 sm:flex-none">
      <Button variant="ghost" size="icon-sm" aria-label="เดือนก่อน" @click="shift(-1)"><ChevronLeft /></Button>
      <span class="min-w-36 flex-1 text-center text-[15px] font-medium text-heading" aria-live="polite">{{ label }}</span>
      <Button variant="ghost" size="icon-sm" aria-label="เดือนถัดไป" :disabled="month >= thisMonth" @click="shift(1)"><ChevronRight /></Button>
    </div>
    <Button v-if="month !== thisMonth" variant="ghost" size="sm" @click="month = thisMonth">เดือนนี้</Button>
  </div>
</template>
