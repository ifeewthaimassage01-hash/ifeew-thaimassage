<script setup lang="ts">
// แสดงการจอง + ชำระมัดจำ (QR PromptPay + อัปโหลดสลิป) — ใช้ทั้งสมาชิกและ Guest
import QRCode from 'qrcode'
import {
  bangkokDateLong,
  bangkokTime,
  bookingStatusLabels,
  depositStatusLabels,
  formatBaht,
  formatDuration,
  promptPayPayload,
  type BookingView,
} from '@ifeew/shared'

const props = defineProps<{
  booking: BookingView
  /** Guest: token / สมาชิก: ไม่ส่ง (ใช้ JWT) */
  token?: string
  canCancel?: boolean
}>()
const emit = defineEmits<{ updated: [view: BookingView]; cancel: [] }>()

const { code: companyCode } = useCompany()
const { call } = useEdgeFunction()

const qr = ref<string | null>(null)
const file = ref<File | File[] | null>(null)
const uploading = ref(false)
const slipResult = ref<{ type: 'success' | 'warning' | 'error'; text: string } | null>(null)

// นับถอยหลังเวลากันที่
const now = ref(Date.now())
useIntervalFn(() => (now.value = Date.now()), 1000)
const remaining = computed(() => {
  if (!props.booking.hold_expires_at) return null
  const ms = new Date(props.booking.hold_expires_at).getTime() - now.value
  if (ms <= 0) return 'หมดเวลา'
  const m = Math.floor(ms / 60000)
  const s = Math.floor((ms % 60000) / 1000)
  return `${m}:${s.toString().padStart(2, '0')}`
})

watch(
  () => props.booking.payment,
  async (p) => {
    qr.value = p ? await QRCode.toDataURL(promptPayPayload(p.promptpay_id, Number(p.amount)), { width: 240, margin: 1 }) : null
  },
  { immediate: true },
)

async function uploadSlip() {
  const f = Array.isArray(file.value) ? file.value[0] : file.value
  if (!f) {
    slipResult.value = { type: 'error', text: 'กรุณาเลือกรูปสลิป' }
    return
  }
  uploading.value = true
  slipResult.value = null
  try {
    const form = new FormData()
    form.append('file', f)
    if (props.token) form.append('token', props.token)
    else {
      form.append('booking_id', props.booking.booking_id)
      form.append('company_code', companyCode)
    }
    const view = await call<BookingView>('booking-deposit-slip', form, !props.token)
    slipResult.value =
      view.slip_outcome === 'VERIFIED'
        ? { type: 'success', text: 'ชำระมัดจำเรียบร้อย การจองได้รับการยืนยันแล้ว' }
        : view.slip_outcome === 'REVIEW'
          ? { type: 'warning', text: 'ได้รับสลิปแล้ว รอพนักงานตรวจสอบ ระบบกันเวลาให้ระหว่างนี้' }
          : { type: 'error', text: `สลิปไม่ผ่าน: ${view.slip_message ?? 'กรุณาตรวจสอบแล้วส่งใหม่'}` }
    file.value = null
    emit('updated', view)
  } catch (e) {
    slipResult.value = { type: 'error', text: edgeErrorText(e) }
  } finally {
    uploading.value = false
  }
}

const statusColor = computed(() =>
  ({ CONFIRMED: 'success', PENDING: 'warning', CANCELLED: 'error', EXPIRED: 'grey', NO_SHOW: 'error', COMPLETED: 'primary', CHECKED_IN: 'primary' })[
    props.booking.status
  ] ?? 'grey',
)
</script>

<template>
  <div class="grid gap-4">
    <v-card class="p-6">
      <div class="mb-3 flex items-start justify-between gap-3">
        <div>
          <p class="m-0 text-sm text-light-brown">{{ booking.booking_code ?? 'รอยืนยัน' }}</p>
          <p class="m-0 text-xl font-semibold text-cocoa">{{ booking.branch.name }}</p>
        </div>
        <v-chip :color="statusColor" variant="tonal">{{ bookingStatusLabels[booking.status] }}</v-chip>
      </div>
      <p class="m-0 text-lg">{{ bangkokDateLong(booking.starts_at) }}</p>
      <p class="m-0 mb-4 text-lg font-medium">{{ bangkokTime(booking.starts_at) }} – {{ bangkokTime(booking.ends_at) }} น.</p>

      <div v-for="(i, idx) in booking.items" :key="idx" class="flex justify-between border-t border-beige py-2 text-sm">
        <span>คนที่ {{ idx + 1 }} · {{ i.service_name }} {{ formatDuration(i.duration_minutes) }}</span>
        <span>{{ formatBaht(Number(i.line_total)) }}</span>
      </div>
      <div class="flex justify-between border-t border-beige pt-2 font-medium">
        <span>รวมค่าบริการ (ชำระที่ร้าน)</span><span>{{ formatBaht(Number(booking.total_amount)) }}</span>
      </div>
      <div v-if="booking.deposit_required > 0" class="mt-1 flex justify-between text-sm text-light-brown">
        <span>มัดจำ ({{ depositStatusLabels[booking.deposit_status] }})</span>
        <span>{{ formatBaht(Number(booking.deposit_required)) }}</span>
      </div>
      <p v-if="booking.customer_note" class="m-0 mt-3 text-sm">หมายเหตุ: {{ booking.customer_note }}</p>
      <p v-if="booking.cancel_reason" class="m-0 mt-3 text-sm text-red-700">เหตุผลที่ยกเลิก: {{ booking.cancel_reason }}</p>
    </v-card>

    <!-- ชำระมัดจำ -->
    <v-card v-if="booking.can_upload_slip && booking.payment" class="p-6">
      <p class="m-0 mb-1 text-lg font-medium">ชำระมัดจำ {{ formatBaht(Number(booking.payment.amount)) }}</p>
      <p class="m-0 mb-4 text-sm text-light-brown">
        สแกนจ่ายผ่าน PromptPay แล้วอัปโหลดสลิปภายใน
        <span class="font-semibold text-cocoa">{{ remaining }}</span> นาที มิฉะนั้นการจองจะถูกยกเลิกอัตโนมัติ
      </p>
      <div class="flex flex-col items-center">
        <img v-if="qr" :src="qr" alt="QR PromptPay" class="h-60 w-60 rounded-xl bg-white p-2" >
        <p class="m-0 mt-2 font-medium">{{ booking.payment.account_name }}</p>
        <p class="m-0 text-sm text-light-brown">PromptPay {{ booking.payment.promptpay_id }}<span v-if="booking.payment.bank_name"> · {{ booking.payment.bank_name }}</span></p>
      </div>
      <v-file-input v-model="file" class="mt-4" label="รูปสลิปการโอน" accept="image/jpeg,image/png,image/webp" prepend-icon="mdi-receipt-text-outline" variant="outlined" />
      <v-btn color="primary" block :loading="uploading" @click="uploadSlip">ส่งสลิป</v-btn>
    </v-card>

    <v-alert v-if="booking.deposit_status === 'PENDING_REVIEW'" type="info" variant="tonal"
      text="ได้รับสลิปแล้ว รอพนักงานตรวจสอบ เราจะยืนยันการจองโดยเร็วที่สุด" />
    <v-alert v-if="slipResult" :type="slipResult.type" variant="tonal" :text="slipResult.text" />

    <v-card class="p-5 text-sm">
      <template v-if="canCancel">
        <v-btn variant="text" color="error" prepend-icon="mdi-calendar-remove-outline" @click="emit('cancel')">ยกเลิกการจอง</v-btn>
      </template>
      <p v-else-if="['PENDING', 'CONFIRMED'].includes(booking.status)" class="m-0 text-light-brown">
        ต้องการเปลี่ยนแปลงหรือยกเลิก กรุณาติดต่อร้าน
        <a v-if="booking.branch.phone" :href="`tel:${booking.branch.phone.replace(/\s|-/g, '')}`" class="text-light-brown">{{ booking.branch.phone }}</a>
      </p>
    </v-card>
  </div>
</template>
