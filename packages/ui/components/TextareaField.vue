<script setup lang="ts">
// ช่องข้อความหลายบรรทัด + ป้ายกำกับ + คำอธิบาย
import type { HTMLAttributes } from 'vue'
import { cn } from 'cn'

defineOptions({ inheritAttrs: false })
const model = defineModel<string | null | undefined>()
const props = defineProps<{ label?: string; hint?: string; error?: string | null; class?: HTMLAttributes['class'] }>()
const id = useId()
</script>

<template>
  <div :class="cn('grid gap-1.5', props.class)">
    <Label v-if="label" :for="id">{{ label }}</Label>
    <Textarea
      :id="id"
      :model-value="model ?? ''"
      v-bind="$attrs"
      :aria-describedby="error || hint ? `${id}-d` : undefined"
      :aria-invalid="error ? true : undefined"
      @update:model-value="(v) => (model = String(v))"
    />
    <p v-if="error" :id="`${id}-d`" class="m-0 text-sm text-danger-ink">{{ error }}</p>
    <p v-else-if="hint" :id="`${id}-d`" class="m-0 text-sm text-muted-foreground">{{ hint }}</p>
  </div>
</template>
