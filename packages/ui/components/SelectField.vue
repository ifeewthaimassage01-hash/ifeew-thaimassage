<script setup lang="ts" generic="T">
// Select + ป้ายกำกับ — รับ items เป็น string หรือ object (itemTitle/itemValue) และค่า null ได้
// (SelectItem ของ reka-ui ไม่รับค่าว่าง จึงแปลงเป็นคีย์ภายในก่อน)
import type { HTMLAttributes } from 'vue'
import { cn } from 'cn'

const model = defineModel<unknown>()
const props = withDefaults(
  defineProps<{
    items: readonly T[]
    itemTitle?: string
    itemValue?: string
    label?: string
    placeholder?: string
    hint?: string
    disabled?: boolean
    /** ใช้เมื่อไม่มี label ที่มองเห็น */
    ariaLabel?: string
    class?: HTMLAttributes['class']
  }>(),
  { itemTitle: 'title', itemValue: 'value', placeholder: 'เลือก' },
)
const id = useId()

const options = computed(() =>
  props.items.map((it, i) => {
    const obj = it !== null && typeof it === 'object' ? (it as Record<string, unknown>) : null
    return {
      key: `k${i}`,
      title: String(obj ? (obj[props.itemTitle] ?? '') : it),
      value: obj ? obj[props.itemValue] : it,
    }
  }),
)
const selectedKey = computed(() => options.value.find((o) => o.value === model.value)?.key)
function onSelect(key: unknown) {
  const o = options.value.find((x) => x.key === key)
  if (o) model.value = o.value
}
</script>

<template>
  <div :class="cn('grid gap-1.5', props.class)">
    <Label v-if="label" :for="id">{{ label }}</Label>
    <Select :model-value="selectedKey" :disabled="disabled" @update:model-value="onSelect">
      <SelectTrigger :id="id" class="w-full" :aria-label="label ? undefined : ariaLabel" :aria-describedby="hint ? `${id}-d` : undefined">
        <SelectValue :placeholder="placeholder" />
      </SelectTrigger>
      <SelectContent>
        <SelectItem v-for="o in options" :key="o.key" :value="o.key">{{ o.title }}</SelectItem>
      </SelectContent>
    </Select>
    <p v-if="hint" :id="`${id}-d`" class="m-0 text-sm text-muted-foreground">{{ hint }}</p>
  </div>
</template>
