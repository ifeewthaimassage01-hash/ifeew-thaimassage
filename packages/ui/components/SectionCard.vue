<script setup lang="ts">
// การ์ดเนื้อหาที่มีหัวข้อ: หัวการ์ด (ชื่อ + คำอธิบาย + ปุ่มด้านขวา) คั่นด้วยเส้นบาง แล้วตามด้วยเนื้อหา
// flush = เนื้อหาชิดขอบ (ใช้กับตาราง/รายการ)
import type { HTMLAttributes } from 'vue'
import { cn } from 'cn'

const props = defineProps<{
  title?: string
  description?: string
  flush?: boolean
  as?: 'h2' | 'h3'
  class?: HTMLAttributes['class']
  bodyClass?: HTMLAttributes['class']
}>()
</script>

<template>
  <section :class="cn('overflow-hidden rounded-xl border border-border bg-card shadow-soft', props.class)">
    <div v-if="title || $slots.header || $slots.actions" class="flex flex-wrap items-center justify-between gap-3 border-b border-border px-5 py-4">
      <slot name="header">
        <div class="min-w-0">
          <component :is="as ?? 'h2'" class="m-0 text-base font-semibold">{{ title }}</component>
          <p v-if="description" class="m-0 mt-0.5 text-sm text-muted-foreground">{{ description }}</p>
        </div>
      </slot>
      <div v-if="$slots.actions" class="flex flex-wrap items-center gap-2"><slot name="actions" /></div>
    </div>
    <div :class="cn(flush ? '' : 'p-5', props.bodyClass)"><slot /></div>
    <div v-if="$slots.footer" class="border-t border-border bg-muted px-5 py-3 text-sm text-muted-foreground"><slot name="footer" /></div>
  </section>
</template>
