<script setup lang="ts">
// แป้นกด PIN 6 หลัก (ปุ่มใหญ่สำหรับหน้าจอสัมผัส)
import { Delete } from '@lucide/vue'
const props = defineProps<{ loading?: boolean; error?: string | null }>()
const emit = defineEmits<{ submit: [pin: string] }>()

const pin = ref('')
const LENGTH = 6

function press(d: string) {
  if (props.loading || pin.value.length >= LENGTH) return
  pin.value += d
  if (pin.value.length === LENGTH) emit('submit', pin.value)
}
function backspace() {
  pin.value = pin.value.slice(0, -1)
}
function reset() {
  pin.value = ''
}

defineExpose({ reset })

onKeyStroke((e) => {
  if (/^[0-9]$/.test(e.key)) press(e.key)
  else if (e.key === 'Backspace') backspace()
})
</script>

<template>
  <div class="flex flex-col items-center gap-5">
    <div class="flex gap-3" role="img" :aria-label="`กรอก PIN แล้ว ${pin.length} จาก ${LENGTH} หลัก`">
      <span
        v-for="i in LENGTH"
        :key="i"
        class="block size-3.5 rounded-full border-2 transition-colors"
        :class="i <= pin.length ? 'border-primary bg-primary' : 'border-muted-foreground/60 bg-transparent'"
      />
    </div>

    <p v-if="error" class="m-0 text-center text-sm text-danger-ink" role="alert">{{ error }}</p>

    <div class="grid grid-cols-3 gap-3">
      <button
        v-for="d in ['1', '2', '3', '4', '5', '6', '7', '8', '9']"
        :key="d"
        type="button"
        class="num h-16 w-20 rounded-xl border border-border bg-card text-2xl font-medium text-heading transition-colors hover:bg-muted active:scale-[0.97] focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none disabled:opacity-50"
        :disabled="loading"
        @click="press(d)"
      >{{ d }}</button>
      <span />
      <button
        type="button"
        class="num h-16 w-20 rounded-xl border border-border bg-card text-2xl font-medium text-heading transition-colors hover:bg-muted active:scale-[0.97] focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none disabled:opacity-50"
        :disabled="loading"
        @click="press('0')"
      >0</button>
      <button
        type="button"
        class="grid h-16 w-20 place-items-center rounded-xl text-muted-foreground transition-colors hover:bg-muted hover:text-heading focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none disabled:opacity-50"
        :disabled="loading"
        aria-label="ลบ"
        @click="backspace"
      ><Delete class="size-6" :stroke-width="1.75" /></button>
    </div>

    <LoadingBar v-if="loading" class="max-w-xs" />
  </div>
</template>
