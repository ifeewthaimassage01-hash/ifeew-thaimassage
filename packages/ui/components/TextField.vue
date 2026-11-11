<script setup lang="ts">
// ช่องกรอก + ป้ายกำกับด้านบน + คำอธิบาย/ข้อผิดพลาด (ผูก aria-describedby ให้อัตโนมัติ)
// attrs อื่น (type, min, maxlength, autocomplete, inputmode, disabled, ...) ส่งต่อให้ <Input>
import type { HTMLAttributes } from 'vue'
import { cn } from 'cn'

defineOptions({ inheritAttrs: false })
const model = defineModel<string | number | null | undefined>()
const props = defineProps<{
  label?: string
  hint?: string
  error?: string | null
  /** หน่วยท้ายช่อง เช่น บาท, นาที */
  suffix?: string
  class?: HTMLAttributes['class']
}>()
const id = useId()
// เว้นที่ขวาให้หน่วยตามความยาว (หน่วยสั้นอย่าง ฿ ไม่กินที่พิมพ์ในช่องแคบบนมือถือ)
const suffixPad = computed(() => (!props.suffix ? '' : props.suffix.length <= 2 ? 'pr-8' : props.suffix.length <= 4 ? 'pr-12' : 'pr-16'))
const describedBy = computed(() => (props.error || props.hint ? `${id}-d` : undefined))
</script>

<template>
  <div :class="cn('grid content-start gap-1.5', props.class)">
    <Label v-if="label" :for="id">{{ label }}</Label>
    <div class="relative">
      <Input
        :id="id"
        :model-value="model ?? ''"
        v-bind="$attrs"
        :aria-describedby="describedBy"
        :aria-invalid="error ? true : undefined"
        :class="suffixPad"
        @update:model-value="(v) => (model = v)"
      />
      <span v-if="suffix" class="pointer-events-none absolute top-1/2 right-3.5 -translate-y-1/2 text-sm text-muted-foreground">{{ suffix }}</span>
    </div>
    <p v-if="error" :id="`${id}-d`" class="m-0 text-sm text-danger-ink">{{ error }}</p>
    <p v-else-if="hint" :id="`${id}-d`" class="m-0 text-sm text-muted-foreground">{{ hint }}</p>
  </div>
</template>
