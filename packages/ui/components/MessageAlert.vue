<script setup lang="ts">
// ข้อความผลการทำรายการ ({ type, text }) → แสดงเป็น Toast (Sonner) แทนแถบในหน้า
// หน้าเดิมใช้ <MessageAlert :message="message" @close="message = null" /> ได้เหมือนเดิม:
//   ทุกครั้งที่ message เปลี่ยนเป็นค่าใหม่ → ส่ง toast แล้ว emit close ให้หน้าล้างค่า (ข้อความถัดไปจะขึ้นได้อีก)
// ตัว Toaster (<Sonner />) วางไว้ใน layout ของแต่ละแอป
import { toast } from 'vue-sonner'

defineOptions({ inheritAttrs: false })

type Kind = 'success' | 'error' | 'info' | 'warning'
const props = defineProps<{ message: { type: Kind; text: string } | null | undefined; closable?: boolean }>()
const emit = defineEmits<{ close: [] }>()

const show: Record<Kind, typeof toast.success> = {
  success: toast.success,
  error: toast.error,
  info: toast.info,
  warning: toast.warning,
}

watch(
  () => props.message,
  (m) => {
    if (!m) return
    // ผิดพลาด/เตือน ค้างนานกว่า ให้มีเวลาอ่าน
    show[m.type](m.text, { duration: m.type === 'error' || m.type === 'warning' ? 8000 : 4000 })
    emit('close')
  },
  { immediate: true },
)
</script>

<template>
  <span v-if="false" />
</template>
