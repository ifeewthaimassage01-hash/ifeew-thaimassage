<script setup lang="ts">
// แถบข้อความผลการทำรายการ ({ type, text }) ปิดได้ — ใช้แทน v-alert closable ในหน้าต่าง ๆ
import { X } from '@lucide/vue'

type Kind = 'success' | 'error' | 'info' | 'warning'
defineProps<{ message: { type: Kind; text: string } | null | undefined; closable?: boolean }>()
const emit = defineEmits<{ close: [] }>()
const variant = (t: Kind) => ({ success: 'success', error: 'destructive', info: 'info', warning: 'warning' } as const)[t]
</script>

<template>
  <Alert v-if="message" :variant="variant(message.type)" :role="message.type === 'error' ? 'alert' : 'status'">
    <AlertDescription class="flex items-start justify-between gap-3">
      <span>{{ message.text }}</span>
      <button
        v-if="closable !== false"
        type="button"
        class="-mt-0.5 -mr-1 grid size-7 shrink-0 place-items-center rounded-md opacity-70 transition-opacity hover:opacity-100 focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
        aria-label="ปิดข้อความ"
        @click="emit('close')"
      ><X class="size-4" /></button>
    </AlertDescription>
  </Alert>
</template>
