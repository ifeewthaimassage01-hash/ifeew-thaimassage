<script setup lang="ts">
// หนึ่งแถวใน <FilterPanel>: ป้าย + ตัวเลือก (SegmentedControl fill / SelectField / DateRangeFilter / ปุ่มเลื่อนวัน)
defineProps<{ label: string }>()
</script>

<template>
  <div class="grid gap-2 sm:grid-cols-[6.5rem_minmax(0,1fr)] sm:items-start sm:gap-4">
    <span class="text-sm font-medium text-heading sm:pt-2.5">{{ label }}</span>
    <div class="flex min-w-0 flex-wrap items-center gap-3">
      <slot />
    </div>
  </div>
</template>
