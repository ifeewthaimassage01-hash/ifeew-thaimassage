<script setup lang="ts">
import type { Component } from 'vue'
import { NuxtLink } from '#components'

// การ์ดสรุป: ป้าย · ตัวเลข/คำตอบ · บรรทัดรอง — ไอคอนเส้นสี accent (ไม่มีพื้นสี)
defineProps<{ label: string; value?: string | number | null; hint?: string; icon?: Component; to?: string }>()
</script>

<template>
  <component
    :is="to ? NuxtLink : 'div'"
    :to="to"
    class="group flex flex-col gap-2 rounded-xl border border-border bg-card p-5 no-underline transition-colors"
    :class="to ? 'hover:border-input' : ''"
  >
    <div class="flex items-center justify-between gap-3">
      <span class="text-[15px] text-muted-foreground">{{ label }}</span>
      <component :is="icon" v-if="icon" class="size-5 text-brand-accent" :stroke-width="1.75" aria-hidden="true" />
    </div>
    <div class="num text-2xl leading-tight font-semibold text-heading">
      <slot>{{ value ?? '—' }}</slot>
    </div>
    <p v-if="hint || $slots.hint" class="m-0 text-sm text-muted-foreground"><slot name="hint">{{ hint }}</slot></p>
  </component>
</template>
