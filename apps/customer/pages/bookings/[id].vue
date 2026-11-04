<script setup lang="ts">
// รายละเอียดการจองของสมาชิก + ชำระมัดจำ + ยกเลิก (ก่อนนัดตามนโยบาย)
import type { BookingView } from '@ifeew/shared'

definePageMeta({ middleware: 'auth' })

const route = useRoute()
const supabase = useSupabaseClient()
const { code } = useCompany()
const id = computed(() => String(route.params.id))

const booking = ref<BookingView | null>(null)
const loading = ref(true)
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)
const cancelDialog = ref(false)
const cancelReason = ref('')
const cancelling = ref(false)

async function load() {
  const { data } = await supabase.rpc('my_booking', { p_company_code: code, p_booking_id: id.value })
  booking.value = (data ?? null) as unknown as BookingView | null
  loading.value = false
}

const canCancel = computed(
  () => !!booking.value && ['PENDING', 'CONFIRMED'].includes(booking.value.status) && booking.value.deposit_status !== 'PENDING_REVIEW',
)

async function cancel() {
  cancelling.value = true
  const { data, error } = await supabase.rpc('cancel_my_booking', {
    p_company_code: code, p_booking_id: id.value, p_reason: cancelReason.value.trim() || null,
  })
  cancelling.value = false
  cancelDialog.value = false
  if (error) {
    message.value = { type: 'error', text: error.message }
    return
  }
  booking.value = data as unknown as BookingView
  message.value = {
    type: 'success',
    text: booking.value.deposit_status === 'REFUND_PENDING' ? 'ยกเลิกแล้ว ร้านจะโอนคืนมัดจำให้' : 'ยกเลิกการจองแล้ว',
  }
}

onMounted(load)
</script>

<template>
  <div>
    <v-btn variant="text" prepend-icon="mdi-arrow-left" to="/bookings" class="mb-2">การจองของฉัน</v-btn>
    <v-alert v-if="message" :type="message.type" variant="tonal" class="mb-4" :text="message.text" />
    <v-progress-linear v-if="loading" indeterminate color="primary" />
    <v-alert v-else-if="!booking" type="info" variant="tonal" text="ไม่พบการจอง" />
    <BookingDetail v-else :booking="booking" :can-cancel="canCancel" @updated="(v) => (booking = { ...booking!, ...v })" @cancel="cancelDialog = true" />

    <v-dialog v-model="cancelDialog" max-width="420">
      <v-card class="p-6">
        <p class="m-0 mb-2 text-lg font-medium">ยกเลิกการจอง?</p>
        <p class="m-0 mb-4 text-sm text-light-brown">ยกเลิกได้ก่อนเวลานัดตามนโยบายของร้าน และรับมัดจำคืน (ถ้าชำระแล้ว)</p>
        <v-textarea v-model="cancelReason" label="เหตุผล (ไม่บังคับ)" rows="2" variant="outlined" />
        <div class="flex justify-end gap-2">
          <v-btn variant="text" @click="cancelDialog = false">ไม่ยกเลิก</v-btn>
          <v-btn color="error" :loading="cancelling" @click="cancel">ยืนยันยกเลิก</v-btn>
        </div>
      </v-card>
    </v-dialog>
  </div>
</template>
