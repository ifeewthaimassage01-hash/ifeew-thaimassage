<script setup lang="ts">
// เลือกเวลาแบบ 24 ชม. (ชั่วโมง 00–23 + นาที) — ใช้แทน <input type="time">
// ซึ่งแสดง AM/PM ตามภาษาของเครื่องและบังคับเป็น 24 ชม. ไม่ได้
// ค่าเป็นสตริง "HH:MM" (หรือ '' เมื่อยังไม่เลือก)
import type { HTMLAttributes } from 'vue'
import { cn } from 'cn'

const model = defineModel<string | null | undefined>()
const props = withDefaults(
  defineProps<{
    label?: string
    hint?: string
    disabled?: boolean
    /** ระยะห่างของนาทีในรายการ (ค่าเดิมที่ไม่ตรงระยะยังแสดงได้) */
    minuteStep?: number
    /** ใช้เมื่อไม่มี label ที่มองเห็น */
    ariaLabel?: string
    class?: HTMLAttributes['class']
  }>(),
  { minuteStep: 5 },
)
const id = useId()
const pad = (n: number) => String(n).padStart(2, '0')

const parts = computed(() => {
  const m = /^(\d{1,2}):(\d{2})/.exec(model.value ?? '')
  return m ? { h: pad(Number(m[1])), m: m[2]! } : { h: undefined, m: undefined }
})

const hours = Array.from({ length: 24 }, (_, i) => pad(i))
const minutes = computed(() => {
  const list = Array.from({ length: Math.ceil(60 / props.minuteStep) }, (_, i) => pad(i * props.minuteStep))
  const cur = parts.value.m
  if (cur && !list.includes(cur)) list.push(cur)
  return list.sort()
})

function setHour(v: unknown) {
  model.value = `${v as string}:${parts.value.m ?? '00'}`
}
function setMinute(v: unknown) {
  model.value = `${parts.value.h ?? '00'}:${v as string}`
}
const groupLabel = computed(() => props.label ?? props.ariaLabel)
</script>

<template>
  <div :class="cn('grid gap-1.5', props.class)">
    <Label v-if="label" :id="`${id}-l`" :for="`${id}-h`">{{ label }}</Label>
    <div class="num flex items-center gap-1.5" role="group" :aria-label="label ? undefined : ariaLabel" :aria-labelledby="label ? `${id}-l` : undefined">
      <Select :model-value="parts.h" :disabled="disabled" @update:model-value="setHour">
        <SelectTrigger :id="`${id}-h`" class="w-full min-w-0" :aria-label="`${groupLabel ?? 'เวลา'} ชั่วโมง`" :aria-describedby="hint ? `${id}-d` : undefined">
          <SelectValue placeholder="--" />
        </SelectTrigger>
        <SelectContent class="max-h-72">
          <SelectItem v-for="h in hours" :key="h" :value="h">{{ h }}</SelectItem>
        </SelectContent>
      </Select>
      <span class="text-muted-foreground" aria-hidden="true">:</span>
      <Select :model-value="parts.m" :disabled="disabled" @update:model-value="setMinute">
        <SelectTrigger class="w-full min-w-0" :aria-label="`${groupLabel ?? 'เวลา'} นาที`">
          <SelectValue placeholder="--" />
        </SelectTrigger>
        <SelectContent class="max-h-72">
          <SelectItem v-for="m in minutes" :key="m" :value="m">{{ m }}</SelectItem>
        </SelectContent>
      </Select>
      <span class="shrink-0 pl-0.5 text-sm text-muted-foreground">น.</span>
    </div>
    <p v-if="hint" :id="`${id}-d`" class="m-0 text-sm text-muted-foreground">{{ hint }}</p>
  </div>
</template>
