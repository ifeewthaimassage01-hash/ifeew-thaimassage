<script setup lang="ts">
// หัวหน้า: ชื่อหน้าชัดเจน + คำอธิบาย (ไม่บังคับ) + ปุ่มด้านขวา
defineProps<{ title: string; description?: string }>()
</script>

<template>
  <div class="mb-6 flex flex-wrap items-end justify-between gap-4 md:mb-8">
    <div class="min-w-0">
      <h1 class="m-0 text-2xl font-semibold leading-tight tracking-tight md:text-[28px]">{{ title }}</h1>
      <p v-if="description || $slots.description" class="m-0 mt-1.5 max-w-[60ch] text-[15px] text-muted-foreground">
        <slot name="description">{{ description }}</slot>
      </p>
    </div>
    <div v-if="$slots.actions" class="flex flex-wrap items-center gap-2"><slot name="actions" /></div>
  </div>
</template>
