<script setup lang="ts">
// ช่องติ๊ก + ป้าย (slot ใช้แทนป้ายได้)
import type { HTMLAttributes } from 'vue'
import { cn } from 'cn'

const model = defineModel<boolean | null | undefined>()
const props = defineProps<{ label?: string; disabled?: boolean; class?: HTMLAttributes['class'] }>()
const id = useId()
</script>

<template>
  <div :class="cn('flex items-start gap-3', props.class)">
    <Checkbox :id="id" :model-value="!!model" :disabled="disabled" class="mt-0.5" @update:model-value="(v) => (model = v === true)" />
    <Label :for="id" class="block text-[15px] leading-6 font-normal"><slot>{{ label }}</slot></Label>
  </div>
</template>
