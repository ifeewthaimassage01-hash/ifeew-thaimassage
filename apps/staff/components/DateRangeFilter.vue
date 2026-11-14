<script setup lang="ts">
// ช่วงวันที่ของตัวกรอง: ปุ่มลัด (7 วัน / เดือนนี้ / เดือนก่อน …) + "กำหนดเอง" แล้วจึงแสดงช่องตั้งแต่/ถึง
// v-model:from / v-model:to เป็น YYYY-MM-DD · เลือกวันในอนาคตไม่ได้ (ค่าเริ่มต้น)
import { bangkokToday } from '@ifeew/shared'

const props = withDefaults(defineProps<{ presets?: readonly RangePreset[]; max?: string; label?: string }>(), {
  presets: () => ['week', 'month', 'last-month'] as const,
  max: undefined,
  label: 'ช่วงวันที่',
})
const from = defineModel<string>('from', { required: true })
const to = defineModel<string>('to', { required: true })

const custom = ref(false)
const key = computed<RangeKey>({
  get: () => (custom.value ? 'custom' : matchRange(from.value, to.value, props.presets)),
  set: (k) => {
    custom.value = k === 'custom'
    if (k !== 'custom') [from.value, to.value] = rangeOf(k)
  },
})
const items = computed(() => [...props.presets, 'custom' as const].map((k) => ({ value: k, label: RANGE_LABELS[k] })))
const maxDate = computed(() => props.max ?? bangkokToday())
</script>

<template>
  <div class="grid w-full gap-3">
    <SegmentedControl v-model="key" :items="items" :label="label" fill />
    <div v-if="key === 'custom'" class="grid grid-cols-2 gap-3 sm:max-w-sm">
      <TextField v-model="from" type="date" label="ตั้งแต่" :max="to" />
      <TextField v-model="to" type="date" label="ถึง" :min="from" :max="maxDate" />
    </div>
  </div>
</template>
