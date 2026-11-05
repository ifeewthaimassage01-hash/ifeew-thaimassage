<script setup lang="ts">
// ตัวเลือกแบบปุ่มติดกัน (แทน v-btn-toggle / แท็บง่าย ๆ) — role=radiogroup, ใช้ลูกศรซ้าย/ขวาได้
import type { HTMLAttributes } from 'vue'
import { cn } from 'cn'

type Item = string | { value: unknown; label: string; disabled?: boolean }
const model = defineModel<unknown>()
const props = defineProps<{ items: readonly Item[]; label?: string; size?: 'sm' | 'default'; class?: HTMLAttributes['class'] }>()

const opts = computed(() => props.items.map((i) => (typeof i === 'string' ? { value: i, label: i, disabled: false } : { disabled: false, ...i })))
const refs = ref<HTMLButtonElement[]>([])
function move(i: number, dir: number) {
  const n = opts.value.length
  for (let k = 1; k <= n; k++) {
    const j = (i + dir * k + n) % n
    if (!opts.value[j]!.disabled) {
      model.value = opts.value[j]!.value
      refs.value[j]?.focus()
      return
    }
  }
}
</script>

<template>
  <div role="radiogroup" :aria-label="label" :class="cn('inline-flex max-w-full flex-wrap gap-1 rounded-lg border border-border bg-card p-1', props.class)">
    <button
      v-for="(o, i) in opts"
      :key="String(o.value)"
      ref="refs"
      type="button"
      role="radio"
      :aria-checked="model === o.value"
      :tabindex="model === o.value || (i === 0 && !opts.some((x) => x.value === model)) ? 0 : -1"
      :disabled="o.disabled"
      class="rounded-md px-3 text-[15px] whitespace-nowrap transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none disabled:opacity-50"
      :class="[size === 'sm' ? 'h-8' : 'h-9', model === o.value ? 'bg-secondary font-medium text-heading' : 'text-muted-foreground hover:text-heading']"
      @click="model = o.value"
      @keydown.right.prevent="move(i, 1)"
      @keydown.left.prevent="move(i, -1)"
    >{{ o.label }}</button>
  </div>
</template>
