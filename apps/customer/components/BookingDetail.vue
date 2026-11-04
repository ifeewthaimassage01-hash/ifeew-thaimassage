<script setup lang="ts">
// แสดงการจอง + ชำระมัดจำ (QR PromptPay + อัปโหลดสลิป) — ใช้ทั้งสมาชิกและ Guest
// คำถามของหน้า: "ร้านยืนยันหรือยัง ต้องทำอะไรต่อ" — ถ้าต้องโอนมัดจำ การ์ดชำระเงินมาก่อน
import QRCode from 'qrcode'
import { CalendarX2, Phone } from '@lucide/vue'
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
const file = ref<File | null>(null)
const fileInput = ref<HTMLInputElement | null>(null)
const uploading = ref(false)
const slipResult = ref<{ type: 'success' | 'warning' | 'destructive'; text: string } | null>(null)

// นับถอยหลังเวลากันที่
const now = ref(Date.now())
useIntervalFn(() => (now.value = Date.now()), 1000)
const remaining = computed(() => {
  if (!props.booking.hold_expires_at) return null
  const ms = new Date(props.booking.hold_expires_at).getTime() - now.value
  if (ms <= 0) return null
  const m = Math.floor(ms / 60000)
  const s = Math.floor((ms % 60000) / 1000)
  return `${m}:${s.toString().padStart(2, '0')}`
})

watch(
  () => props.booking.payment,
  async (p) => {
    qr.value = p ? await QRCode.toDataURL(promptPayPayload(p.promptpay_id, Number(p.amount)), { width: 480, margin: 1 }) : null
  },
  { immediate: true },
)

function onFile(e: Event) {
  file.value = (e.target as HTMLInputElement).files?.[0] ?? null
  slipResult.value = null
}

async function uploadSlip() {
  const f = file.value
  if (!f) {
    slipResult.value = { type: 'destructive', text: 'กรุณาเลือกรูปสลิป' }
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
          : { type: 'destructive', text: `สลิปไม่ผ่าน: ${view.slip_message ?? 'กรุณาตรวจสอบแล้วส่งใหม่'}` }
    file.value = null
    if (fileInput.value) fileInput.value.value = ''
    emit('updated', view)
  } catch (e) {
    slipResult.value = { type: 'destructive', text: edgeErrorText(e) }
  } finally {
    uploading.value = false
  }
}

type BadgeVariant = 'positive' | 'warning' | 'destructive' | 'neutral' | 'default'
const statusVariant = computed<BadgeVariant>(
  () =>
    (({ CONFIRMED: 'positive', PENDING: 'warning', CANCELLED: 'destructive', EXPIRED: 'neutral', NO_SHOW: 'destructive', COMPLETED: 'default', CHECKED_IN: 'default' }) as Record<string, BadgeVariant>)[
      props.booking.status
    ] ?? 'neutral',
)
const needsPayment = computed(() => props.booking.can_upload_slip && !!props.booking.payment)
const tel = (p: string) => `tel:${p.replace(/\s|-/g, '')}`
</script>

<template>
  <div class="grid items-start gap-4 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
    <!-- ชำระมัดจำ (มาก่อนเมื่อยังต้องจ่าย) -->
    <Card v-if="needsPayment && booking.payment" class="gap-4 py-5 md:order-2">
      <CardHeader class="px-5">
        <CardTitle as="h2">โอนมัดจำ <span class="num">{{ formatBaht(Number(booking.payment.amount)) }}</span></CardTitle>
        <p class="m-0 text-[15px]">
          <template v-if="remaining">ส่งสลิปภายใน <span class="num font-semibold">{{ remaining }}</span> นาที ไม่เช่นนั้นระบบจะยกเลิกคิวให้อัตโนมัติ</template>
          <template v-else>หมดเวลาส่งสลิปแล้ว กรุณาติดต่อร้าน</template>
        </p>
      </CardHeader>
      <CardContent class="grid gap-4 px-5">
        <figure class="m-0 grid justify-items-center gap-2 rounded-lg bg-muted/60 p-4">
          <img v-if="qr" :src="qr" alt="QR PromptPay สำหรับโอนมัดจำ" class="size-56 rounded-md bg-white p-2" width="224" height="224">
          <Skeleton v-else class="size-56" />
          <figcaption class="text-center">
            <span class="block font-medium">{{ booking.payment.account_name }}</span>
            <span class="num block text-sm text-muted-foreground">PromptPay {{ booking.payment.promptpay_id }}<template v-if="booking.payment.bank_name"> · {{ booking.payment.bank_name }}</template></span>
          </figcaption>
        </figure>
        <div class="grid gap-1.5">
          <Label for="slip">รูปสลิปการโอน</Label>
          <input
            id="slip"
            ref="fileInput"
            type="file"
            accept="image/jpeg,image/png,image/webp"
            aria-describedby="slip-hint"
            class="block w-full cursor-pointer rounded-lg border border-input bg-card text-[15px] file:mr-3 file:h-11 file:cursor-pointer file:border-0 file:bg-secondary file:px-4 file:font-medium file:text-secondary-foreground"
            @change="onFile"
          >
          <p id="slip-hint" class="m-0 text-sm text-muted-foreground">ไฟล์ JPG, PNG หรือ WEBP</p>
        </div>
        <Alert v-if="slipResult" :variant="slipResult.type"><AlertDescription>{{ slipResult.text }}</AlertDescription></Alert>
        <Button size="lg" class="w-full" :disabled="uploading" @click="uploadSlip">{{ uploading ? 'กำลังส่ง…' : 'ส่งสลิป' }}</Button>
      </CardContent>
    </Card>

    <!-- รายละเอียดการจอง -->
    <Card class="gap-4 py-5 md:order-1" :class="needsPayment ? '' : 'md:col-span-2 md:max-w-2xl'">
      <CardHeader class="px-5">
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0">
            <p class="num m-0 text-sm text-muted-foreground">{{ booking.booking_code ?? 'รอยืนยัน' }}</p>
            <CardTitle as="h2" class="text-xl">{{ booking.branch.name }}</CardTitle>
          </div>
          <Badge :variant="statusVariant">{{ bookingStatusLabels[booking.status] }}</Badge>
        </div>
      </CardHeader>
      <CardContent class="grid gap-4 px-5">
        <div>
          <p class="m-0 text-lg">{{ bangkokDateLong(booking.starts_at) }}</p>
          <p class="num m-0 text-2xl font-semibold">{{ bangkokTime(booking.starts_at) }}–{{ bangkokTime(booking.ends_at) }} น.</p>
        </div>
        <Alert v-if="booking.deposit_status === 'PENDING_REVIEW'" variant="info">
          <AlertDescription>ได้รับสลิปแล้ว รอพนักงานตรวจสอบ เราจะยืนยันการจองโดยเร็วที่สุด</AlertDescription>
        </Alert>
        <table class="w-full border-collapse text-[15px]">
          <caption class="sr-only">รายการบริการ</caption>
          <tbody>
            <tr v-for="(i, idx) in booking.items" :key="idx" class="border-b border-border/70">
              <td class="py-2 pr-3">คนที่ {{ idx + 1 }} · {{ i.service_name }} <span class="text-muted-foreground">{{ formatDuration(i.duration_minutes) }}</span></td>
              <td class="num py-2 text-right">{{ formatBaht(Number(i.line_total)) }}</td>
            </tr>
          </tbody>
          <tfoot>
            <tr>
              <th scope="row" class="pt-3 pr-3 text-left font-medium">รวมค่าบริการ <span class="font-normal text-muted-foreground">(ชำระที่ร้าน)</span></th>
              <td class="num pt-3 text-right text-lg font-semibold">{{ formatBaht(Number(booking.total_amount)) }}</td>
            </tr>
            <tr v-if="booking.deposit_required > 0">
              <th scope="row" class="pt-1 pr-3 text-left font-normal text-muted-foreground">มัดจำ · {{ depositStatusLabels[booking.deposit_status] }}</th>
              <td class="num pt-1 text-right text-muted-foreground">{{ formatBaht(Number(booking.deposit_required)) }}</td>
            </tr>
          </tfoot>
        </table>
        <p v-if="booking.customer_note" class="m-0 text-[15px]"><span class="text-muted-foreground">หมายเหตุ:</span> {{ booking.customer_note }}</p>
        <p v-if="booking.cancel_reason" class="m-0 text-[15px] text-tint-danger-ink">เหตุผลที่ยกเลิก: {{ booking.cancel_reason }}</p>

        <div class="border-t border-border/70 pt-4">
          <Button v-if="canCancel" variant="outline" class="border-destructive/40 text-destructive hover:bg-tint-danger" @click="emit('cancel')">
            <CalendarX2 /> ยกเลิกการจอง
          </Button>
          <p v-else-if="['PENDING', 'CONFIRMED'].includes(booking.status)" class="m-0 flex flex-wrap items-center gap-2 text-[15px] text-muted-foreground">
            ต้องการเปลี่ยนหรือยกเลิก กรุณาติดต่อร้าน
            <Button v-if="booking.branch.phone" as-child variant="outline" size="sm">
              <a :href="tel(booking.branch.phone)"><Phone /> <span class="num">{{ booking.branch.phone }}</span></a>
            </Button>
          </p>
        </div>
      </CardContent>
    </Card>
  </div>
</template>
