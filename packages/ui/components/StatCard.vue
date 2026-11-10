<script setup lang="ts">
import type { Component } from 'vue'
import { NuxtLink } from '#components'

// การ์ดสรุป (ตามภาพอ้างอิง): ไอคอนในวงกลมเบจ + ป้าย (และบรรทัดรองใต้ป้าย) · ตัวเลขใหญ่ + ช่อง trailing (เช่น กราฟจิ๋ว)
// dense: ย่อขนาดบนมือถือ — ใช้เมื่อวางการ์ด 3 ใบเรียงแถวเดียวบนจอแคบ
defineProps<{ label: string; value?: string | number | null; hint?: string; icon?: Component; to?: string; dense?: boolean }>()
</script>

<template>
  <component
    :is="to ? NuxtLink : 'div'"
    :to="to"
    class="group flex items-start gap-3 rounded-xl border border-border bg-card p-4 no-underline shadow-soft transition-colors max-sm:flex-col sm:gap-4 sm:px-5 sm:py-5"
    :class="[to ? 'hover:border-input' : '', dense ? 'max-sm:gap-2 max-sm:p-3' : '']"
  >
    <span v-if="icon" class="grid size-12 shrink-0 place-items-center rounded-full bg-muted text-brand-accent" :class="dense ? 'max-sm:size-9' : ''" aria-hidden="true">
      <component :is="icon" class="size-[22px]" :class="dense ? 'max-sm:size-[18px]' : ''" :stroke-width="1.5" />
    </span>
    <div class="grid w-full min-w-0 flex-1 gap-1.5">
      <div class="min-w-0">
        <span class="block truncate text-[14px] leading-snug text-muted-foreground" :class="dense ? 'max-sm:text-[13px]' : ''">{{ label }}</span>
        <span v-if="hint || $slots.hint" class="line-clamp-2 block text-[12px] leading-snug text-muted-foreground/80"><slot name="hint">{{ hint }}</slot></span>
      </div>
      <div class="flex flex-wrap items-end justify-between gap-x-3 gap-y-2">
        <div class="num min-w-0 truncate leading-none font-normal tracking-tight text-heading sm:text-[30px]" :class="dense ? 'text-[19px]' : 'text-[26px]'">
          <slot>{{ value ?? '—' }}</slot>
        </div>
        <slot name="trailing" />
      </div>
    </div>
  </component>
</template>
