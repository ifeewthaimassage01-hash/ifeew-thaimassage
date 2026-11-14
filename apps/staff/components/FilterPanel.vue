<script setup lang="ts">
// แผงตัวกรองของหน้า: กรอบเดียว ใส่ <FilterRow label="…"> ทีละแถว
// จอใหญ่: ป้ายอยู่คอลัมน์ซ้าย ตัวเลือกอยู่ขวา · มือถือ: ป้ายอยู่บน ตัวเลือกเต็มความกว้าง
defineProps<{ label?: string }>()
</script>

<template>
  <section class="mb-5 grid gap-4 rounded-2xl border border-border bg-card p-4 sm:p-5" :aria-label="label ?? 'ตัวกรอง'">
    <slot />
  </section>
</template>
