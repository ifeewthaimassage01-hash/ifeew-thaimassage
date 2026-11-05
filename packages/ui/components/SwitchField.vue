<script setup lang="ts">
// สวิตช์ + ป้าย (+ คำอธิบาย) — ทั้งแถวกดได้ผ่าน label
import type { HTMLAttributes } from 'vue'
import { cn } from 'cn'

const model = defineModel<boolean | null | undefined>()
const props = defineProps<{ label: string; hint?: string; disabled?: boolean; class?: HTMLAttributes['class'] }>()
const id = useId()
</script>

<template>
  <div :class="cn('flex items-start justify-between gap-4', props.class)">
    <div class="grid gap-0.5">
      <Label :for="id" class="text-[15px]">{{ label }}</Label>
      <p v-if="hint" class="m-0 text-sm text-muted-foreground">{{ hint }}</p>
    </div>
    <Switch :id="id" :model-value="!!model" :disabled="disabled" @update:model-value="(v: boolean) => (model = v)" />
  </div>
</template>
