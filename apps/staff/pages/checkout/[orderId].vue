<script setup lang="ts">
// ชำระเงินของ Order: ออก Invoice ให้อัตโนมัติ (ข้ามขั้นร่าง · หักมัดจำอัตโนมัติ) → รับเงิน (เงินสด / โอน+สลิป — QR รวมกับโอน) + ทิป
// ยกเลิกบิล (Void ต้องมีเหตุผล) / คืนเงิน (OWNER) — ใบเสร็จเก็บในระบบเท่านั้น
import { ArrowLeft, Banknote, Camera, Check, CircleCheck, QrCode } from '@lucide/vue'
import {
  formatBaht,
  formatDuration,
  newIdempotencyKey,
  paymentMethodLabels,
  reasonSchema,
  bangkokTime,
  type InvoiceView,
  type SlipCheck,
} from '@ifeew/shared'

const route = useRoute()
const supabase = useSupabaseClient()
const { isOwner } = useAccess()
const { run } = useStepUp()
const { call, callForm } = useEdgeFunction()

const orderId = computed(() => String(route.params.orderId))
const invoice = ref<InvoiceView | null>(null)
const loading = ref(true)
const saving = ref(false)
const message = ref<{ type: 'success' | 'error' | 'info'; text: string } | null>(null)
const ok = (text: string) => (message.value = { type: 'success', text })
const fail = (e: unknown, fallback?: string) => (message.value = { type: 'error', text: errorText(e, fallback) })

async function load() {
  loading.value = true
  try {
    invoice.value = (await must(supabase.rpc('pos_create_invoice', { p_order_id: orderId.value }))) as unknown as InvoiceView
    // ข้ามขั้นร่าง: ออก Invoice ทันทีแล้วไปบันทึกรับเงิน
    if (invoice.value.status === 'DRAFT') {
      invoice.value = (await must(supabase.rpc('pos_issue_invoice', { p_invoice_id: invoice.value.invoice_id }))) as unknown as InvoiceView
    }
  } catch (e) {
    fail(e, 'สร้าง Invoice ไม่สำเร็จ')
  } finally {
    loading.value = false
  }
}
onMounted(load)

const isDraft = computed(() => invoice.value?.status === 'DRAFT')
const payable = computed(() => ['ISSUED', 'PARTIALLY_PAID'].includes(invoice.value?.status ?? ''))

// ---------------------------------------------------------------------------
// ส่วนลด (ร่างเท่านั้น)
// ---------------------------------------------------------------------------
const discountDialog = ref(false)
const discountItem = ref<InvoiceView['items'][number] | null>(null)
const discountAmount = ref<number | string>(0)
const discountReason = ref('')

function openDiscount(item: InvoiceView['items'][number]) {
  discountItem.value = item
  discountAmount.value = Number(item.discount_amount)
  discountReason.value = item.discount_reason ?? ''
  discountDialog.value = true
}

async function saveDiscount() {
  if (!discountItem.value) return
  const itemId = discountItem.value.invoice_item_id
  saving.value = true
  try {
    invoice.value = (await run(() => must(supabase.rpc('pos_set_invoice_discount', {
      p_invoice_item_id: itemId, p_amount: Number(discountAmount.value) || 0, p_reason: discountReason.value.trim() || null,
    })))) as unknown as InvoiceView
    discountDialog.value = false
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}

async function issue() {
  if (!invoice.value) return
  saving.value = true
  try {
    invoice.value = (await must(supabase.rpc('pos_issue_invoice', { p_invoice_id: invoice.value.invoice_id }))) as unknown as InvoiceView
    ok(`ออก Invoice ${invoice.value.invoice_number}`)
    resetPayment()
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}

// ---------------------------------------------------------------------------
// รับเงิน
// ---------------------------------------------------------------------------
// โอน = รวม QR หน้าร้าน + โอนเข้าบัญชี (บันทึกเป็น BANK_TRANSFER)
const method = ref<'CASH' | 'BANK_TRANSFER'>('CASH')
// รับเต็มยอดค้างเสมอ (ไม่มีช่องกรอกยอด/ทิป/เงินทอน)
const amount = computed(() => (invoice.value ? Number(invoice.value.balance) : 0))
const slip = ref<SlipCheck | null>(null)
const slipUploading = ref(false)
let payKey = newIdempotencyKey()

function resetPayment() {
  slip.value = null
  payKey = newIdempotencyKey()
}
watch(() => invoice.value?.invoice_id, resetPayment)
watch([method, amount], () => {
  slip.value = null
  payKey = newIdempotencyKey()
})

async function onSlipSelected(e: Event) {
  const file = (e.target as HTMLInputElement).files?.[0]
  ;(e.target as HTMLInputElement).value = ''
  if (!file || !invoice.value) return
  slipUploading.value = true
  slip.value = null
  try {
    const form = new FormData()
    form.append('file', file)
    form.append('invoice_id', invoice.value.invoice_id)
    form.append('amount', String(amount.value))
    slip.value = await callForm<SlipCheck>('pos-payment-slip', form)
  } catch (err) {
    message.value = { type: 'error', text: edgeErrorText(err, 'อัปโหลดสลิปไม่สำเร็จ') }
  } finally {
    slipUploading.value = false
  }
}

const canPay = computed(() => {
  if (!payable.value || !(amount.value > 0)) return false
  if (method.value === 'CASH') return true
  // โอน/QR: ต้องแนบสลิปก่อน (ไม่ตรวจสลิปอัตโนมัติ)
  return !!slip.value && slip.value.outcome !== 'REJECTED'
})

async function pay() {
  if (!invoice.value || !canPay.value) return
  saving.value = true
  try {
    invoice.value = (await must(supabase.rpc('pos_record_payment', {
      p_invoice_id: invoice.value.invoice_id,
      p_method: method.value,
      p_amount: amount.value,
      p_slip_check_id: method.value === 'CASH' ? null : slip.value!.slip_check_id,
      p_manual_reason: null,
      p_tip_amount: 0,
      p_tip_employee_id: null,
      p_idempotency_key: payKey,
    }))) as unknown as InvoiceView
    // จ่ายครบ: กล่องเขียว "จ่ายครบแล้ว" บอกอยู่แล้ว → ค้างไว้ 3 วินาทีแล้วกลับหน้าร้าน (POS)
    if (invoice.value.status === 'PAID') startBackCountdown()
    else ok('บันทึกการรับเงินแล้ว')
    resetPayment()
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}

// หลังรับเงินครบ: นับถอยหลัง 3 วินาทีแล้วกลับหน้าร้าน (เฉพาะตอนเพิ่งจ่าย ไม่ใช่ตอนเปิดดูบิลที่จ่ายแล้ว)
const backCountdown = ref(0)
let backTimer: ReturnType<typeof setInterval> | null = null
function stopBackCountdown() {
  if (backTimer) clearInterval(backTimer)
  backTimer = null
  backCountdown.value = 0
}
function startBackCountdown() {
  stopBackCountdown()
  backCountdown.value = 3
  backTimer = setInterval(() => {
    backCountdown.value--
    if (backCountdown.value <= 0) {
      stopBackCountdown()
      navigateTo('/pos')
    }
  }, 1000)
}
onBeforeUnmount(stopBackCountdown)

// สลิปอยู่บน Cloudinary (private) หรือ bucket เดิม — ขอ URL ที่เซ็นแล้วจาก Edge Function (ตรวจสิทธิ์สาขา)
async function viewSlip(path: string) {
  // เปิดแท็บก่อน await เพื่อไม่ให้เบราว์เซอร์มือถือบล็อก popup
  const tab = window.open('', '_blank')
  try {
    const { url } = await call<{ url: string }>('payment-slip-url', { slip_path: path })
    if (tab) tab.location.href = url
    else window.location.href = url
  } catch (err) {
    tab?.close()
    message.value = { type: 'error', text: edgeErrorText(err, 'เปิดสลิปไม่สำเร็จ') }
  }
}

// ---------------------------------------------------------------------------
// Void / คืนเงิน
// ---------------------------------------------------------------------------
const voidDialog = ref(false)
const voidReason = ref('')
let voidKey = newIdempotencyKey()

async function submitVoid() {
  if (!invoice.value || !reasonSchema.safeParse(voidReason.value).success) {
    fail(null, 'กรุณาระบุเหตุผล')
    return
  }
  const id = invoice.value.invoice_id
  saving.value = true
  try {
    invoice.value = (await run(() => must(supabase.rpc('pos_void_invoice', {
      p_invoice_id: id, p_reason: voidReason.value.trim(), p_idempotency_key: voidKey,
    })))) as unknown as InvoiceView
    voidDialog.value = false
    ok('ยกเลิกบิลแล้ว ออกบิลใหม่ได้ด้วยปุ่ม “ออกบิลใหม่”')
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
    voidKey = newIdempotencyKey()
  }
}

const refundDialog = ref(false)
const refundPayment = ref<InvoiceView['payments'][number] | null>(null)
const refundForm = reactive({ amount: '' as number | string, method: 'CASH' as 'CASH' | 'BANK_TRANSFER', reference: '', reason: '' })
let refundKey = newIdempotencyKey()

function openRefund(p: InvoiceView['payments'][number]) {
  refundPayment.value = p
  Object.assign(refundForm, { amount: Number(p.amount) - Number(p.refunded), method: 'CASH', reference: '', reason: '' })
  refundKey = newIdempotencyKey()
  refundDialog.value = true
}

async function submitRefund() {
  if (!refundPayment.value) return
  const paymentId = refundPayment.value.payment_id
  saving.value = true
  try {
    invoice.value = (await run(() => must(supabase.rpc('pos_refund_payment', {
      p_payment_id: paymentId, p_amount: Number(refundForm.amount), p_method: refundForm.method,
      p_reference: refundForm.reference.trim() || null, p_reason: refundForm.reason.trim(), p_idempotency_key: refundKey,
    })))) as unknown as InvoiceView
    refundDialog.value = false
    ok('บันทึกการคืนเงินแล้ว')
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <!-- ทางเดียวจากบนลงล่าง: ยอดที่ต้องจ่าย → รายการ → วิธีจ่าย → ปุ่มยืนยัน · ประวัติการรับเงิน/ยกเลิกบิลอยู่ท้ายหน้า -->
  <div class="mx-auto grid max-w-2xl gap-5">
    <div class="flex items-center gap-2">
      <Button as-child variant="ghost" size="icon" aria-label="กลับหน้าชำระเงิน"><NuxtLink to="/payments"><ArrowLeft class="size-5" /></NuxtLink></Button>
      <h1 class="m-0 min-w-0 flex-1 truncate text-lg font-semibold">{{ invoice?.customer_name ?? 'ลูกค้าทั่วไป' }}</h1>
    </div>

    <MessageAlert :message="message" @close="message = null" />
    <LoadingBar v-if="loading" />

    <template v-if="invoice">
      <!-- สถานะ / ยอด -->
      <div v-if="invoice.status === 'PAID'" class="flex items-center gap-4 rounded-xl bg-success-soft px-5 py-4 text-success-ink">
        <CircleCheck class="size-8 shrink-0" />
        <div>
          <p class="m-0 text-lg font-semibold">จ่ายครบแล้ว <span class="num">{{ formatBaht(Number(invoice.total)) }}</span></p>
          <p v-if="invoice.receipt_number" class="m-0 text-sm">ใบเสร็จ <span class="num">{{ invoice.receipt_number }}</span></p>
          <p v-if="backCountdown > 0" class="m-0 mt-1 text-sm">
            กลับหน้าร้านใน <span class="num font-semibold">{{ backCountdown }}</span> วินาที…
            <button type="button" class="ml-1 font-medium underline underline-offset-2" @click="stopBackCountdown">อยู่หน้านี้ต่อ</button>
          </p>
        </div>
      </div>
      <div v-else-if="invoice.status === 'VOID'" class="grid gap-3 rounded-xl bg-danger-soft px-5 py-4 text-danger-ink">
        <p class="m-0 text-lg font-semibold">บิลนี้ถูกยกเลิกแล้ว</p>
        <p v-if="invoice.void_reason" class="m-0 text-[15px]">เหตุผล: {{ invoice.void_reason }}</p>
        <Button class="w-fit" @click="load">ออกบิลใหม่</Button>
      </div>
      <div v-else class="rounded-xl border border-border bg-card px-5 py-4 shadow-soft">
        <p class="m-0 text-[15px] text-muted-foreground">ยอดที่ต้องจ่าย</p>
        <p class="num m-0 text-4xl leading-tight font-semibold text-heading">{{ formatBaht(Number(invoice.balance)) }}</p>
        <p v-if="Number(invoice.paid_amount) > 0" class="m-0 text-sm text-muted-foreground">
          จ่ายไปแล้ว <span class="num">{{ formatBaht(Number(invoice.paid_amount)) }}</span> จากทั้งหมด <span class="num">{{ formatBaht(Number(invoice.total)) }}</span>
        </p>
      </div>

      <!-- รายการ -->
      <section class="rounded-xl border border-border bg-card shadow-soft" aria-labelledby="items-h">
        <h2 id="items-h" class="m-0 border-b border-border px-5 py-3 text-[15px] font-semibold">รายการ</h2>
        <ul class="m-0 grid list-none p-0">
          <li v-for="i in invoice.items" :key="i.invoice_item_id" class="flex items-start justify-between gap-3 border-b border-border px-5 py-3 last:border-0">
            <div class="min-w-0">
              <p class="m-0 text-[15px] text-heading">{{ i.description }} <span class="text-muted-foreground">{{ formatDuration(i.duration_minutes) }}</span></p>
              <p v-if="Number(i.discount_amount)" class="m-0 text-sm text-muted-foreground">
                ลด <span class="num">{{ formatBaht(Number(i.discount_amount)) }}</span><template v-if="i.discount_reason"> · {{ i.discount_reason }}</template>
              </p>
            </div>
            <div class="flex shrink-0 items-center gap-2">
              <span class="num text-[15px] font-medium text-heading">{{ formatBaht(Number(i.line_total)) }}</span>
              <Button v-if="isDraft" size="sm" variant="ghost" @click="openDiscount(i)">ส่วนลด</Button>
            </div>
          </li>
        </ul>
        <p class="m-0 flex items-baseline justify-between border-t border-border px-5 py-3">
          <span class="text-[15px] font-semibold text-heading">รวม</span>
          <span class="num text-lg font-semibold text-heading">{{ formatBaht(Number(invoice.total)) }}</span>
        </p>
        <div v-if="isDraft" class="flex flex-wrap items-center justify-end gap-3 border-t border-border px-5 py-3">
          <span v-if="invoice.deposit_available" class="text-sm text-muted-foreground">หักมัดจำ <span class="num">{{ formatBaht(Number(invoice.deposit_available)) }}</span> ให้อัตโนมัติ</span>
          <Button :disabled="saving" @click="issue">ยืนยันรายการ</Button>
        </div>
      </section>

      <!-- รับเงิน -->
      <section v-if="payable" class="grid gap-4 rounded-xl border-2 border-primary/30 bg-card p-5 shadow-soft" aria-labelledby="pay-h">
        <h2 id="pay-h" class="m-0 text-[15px] font-semibold">ลูกค้าจ่ายด้วยอะไร</h2>
        <div class="grid grid-cols-2 gap-2" role="radiogroup" aria-label="วิธีรับเงิน">
          <button
            v-for="m in ([{ value: 'CASH', label: 'เงินสด', icon: Banknote }, { value: 'BANK_TRANSFER', label: 'โอน / สแกน QR', icon: QrCode }] as const)"
            :key="m.value"
            type="button"
            role="radio"
            :aria-checked="method === m.value"
            class="flex h-14 items-center justify-center gap-2 rounded-lg border-2 text-[15px] font-medium transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
            :class="method === m.value ? 'border-primary bg-secondary text-heading' : 'border-border text-muted-foreground hover:border-input hover:text-heading'"
            @click="method = m.value"
          >
            <component :is="m.icon" class="size-5" /> {{ m.label }}
          </button>
        </div>

        <p v-if="method === 'CASH'" class="m-0 text-[15px] text-muted-foreground">รับเงินสด <span class="num font-semibold text-heading">{{ formatBaht(amount) }}</span> จากลูกค้า แล้วกดปุ่มด้านล่าง</p>
        <div v-else class="grid gap-3">
          <p class="m-0 text-[15px] text-muted-foreground">ให้ลูกค้าโอน <span class="num font-semibold text-heading">{{ formatBaht(amount) }}</span> แล้วถ่ายรูปสลิป</p>
          <label
            v-if="!slip"
            class="flex cursor-pointer items-center justify-center gap-2 rounded-lg border-2 border-dashed border-input px-4 py-4 text-[15px] font-medium text-heading hover:bg-muted focus-within:ring-3 focus-within:ring-ring/50"
            :class="slipUploading || !(amount > 0) ? 'pointer-events-none opacity-50' : ''"
          >
            <input type="file" accept="image/*" capture="environment" class="sr-only" :disabled="slipUploading || !(amount > 0)" @change="onSlipSelected">
            <Camera class="size-5 text-brand-accent" /> {{ slipUploading ? 'กำลังอัปโหลด…' : 'ถ่ายรูปสลิป' }}
          </label>
          <div v-else class="flex items-center justify-between gap-3 rounded-lg bg-success-soft px-4 py-3 text-[15px] text-success-ink">
            <span class="flex items-center gap-2"><CircleCheck class="size-5" /> แนบสลิปแล้ว</span>
            <span class="flex gap-1">
              <Button type="button" size="sm" variant="ghost" @click="viewSlip(slip.slip_path)">ดู</Button>
              <label class="inline-flex h-8 cursor-pointer items-center rounded-lg px-3 text-sm font-medium hover:bg-success-soft/60">
                <input type="file" accept="image/*" capture="environment" class="sr-only" :disabled="slipUploading" @change="onSlipSelected">ถ่ายใหม่
              </label>
            </span>
          </div>
        </div>

        <Button size="lg" class="h-12 w-full text-base" :disabled="!canPay || saving" @click="pay">
          <Check /> {{ saving ? 'กำลังบันทึก…' : `ได้รับเงินแล้ว ${formatBaht(amount)}` }}
        </Button>
      </section>

      <!-- ประวัติการรับเงิน -->
      <section v-if="invoice.payments.length || invoice.tips.length" class="rounded-xl border border-border bg-card" aria-labelledby="hist-h">
        <h2 id="hist-h" class="m-0 border-b border-border px-5 py-3 text-[15px] font-semibold">รับเงินแล้ว</h2>
        <ul class="m-0 grid list-none p-0">
          <li v-for="p in invoice.payments" :key="p.payment_id" class="flex flex-wrap items-center justify-between gap-2 border-b border-border px-5 py-3 last:border-0">
            <div :class="{ 'text-muted-foreground line-through': p.status === 'VOID' }">
              <span class="text-[15px] text-heading">{{ paymentMethodLabels[p.method] }}</span> <span class="num font-semibold text-heading">{{ formatBaht(Number(p.amount)) }}</span>
              <span class="block text-sm text-muted-foreground">
                <span class="num">{{ bangkokTime(p.received_at) }}</span> {{ p.received_by_name ?? '' }}
                <template v-if="Number(p.refunded)"> · คืนแล้ว <span class="num">{{ formatBaht(Number(p.refunded)) }}</span></template>
              </span>
            </div>
            <div class="flex gap-1">
              <Button v-if="p.slip_path" size="sm" variant="ghost" @click="viewSlip(p.slip_path)">ดูสลิป</Button>
              <Button v-if="isOwner && p.status === 'SUCCESS' && p.method !== 'DEPOSIT' && Number(p.refunded) < Number(p.amount)"
                size="sm" variant="ghost" class="text-danger-ink" @click="openRefund(p)">คืนเงิน</Button>
            </div>
          </li>
        </ul>
        <div v-if="invoice.tips.length" class="border-t border-border px-5 py-3 text-sm">
          <p v-for="t in invoice.tips" :key="t.tip_id" class="m-0" :class="{ 'line-through': t.status === 'VOID' }">
            ทิป {{ t.nickname }} <span class="num">{{ formatBaht(Number(t.amount)) }}</span> ({{ paymentMethodLabels[t.method as 'CASH'] }}){{ t.status === 'PAID_OUT' ? ' · จ่ายหมอแล้ว' : '' }}
          </p>
        </div>
      </section>

      <div v-if="invoice.status !== 'VOID'" class="flex justify-center">
        <Button variant="ghost" size="sm" class="text-danger-ink hover:bg-danger-soft hover:text-danger-ink" @click="voidDialog = true; voidReason = ''">ยกเลิกบิลนี้</Button>
      </div>
    </template>

    <!-- ส่วนลด -->
    <Dialog v-model:open="discountDialog">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>ส่วนลด · {{ discountItem?.description }}</DialogTitle>
          <DialogDescription v-if="discountItem && invoice">
            ราคา {{ formatBaht(Number(discountItem.unit_price)) }} · พนักงานลดได้ไม่เกิน {{ invoice.max_staff_discount_percent }}% (เกินนี้ต้องให้เจ้าของร้านยืนยันตัวตน)
          </DialogDescription>
        </DialogHeader>
        <form class="grid gap-4" @submit.prevent="saveDiscount">
          <TextField v-model="discountAmount" type="number" label="ส่วนลด" suffix="บาท" class="num" />
          <TextField v-model="discountReason" label="เหตุผล" />
          <DialogFooter class="gap-2">
            <Button type="button" variant="outline" @click="discountDialog = false">ปิด</Button>
            <Button type="submit" :disabled="saving">บันทึก</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>

    <!-- ยกเลิกบิล -->
    <Dialog v-model:open="voidDialog">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>ยกเลิกบิล</DialogTitle>
          <DialogDescription>ถ้ารับเงินแล้ว ต้องให้เจ้าของร้านยืนยันตัวตน และเงินต้องอยู่ในกะที่ยังเปิด (นอกนั้นใช้คืนเงิน)</DialogDescription>
        </DialogHeader>
        <TextareaField v-model="voidReason" label="เหตุผล" hint="บังคับ" rows="2" />
        <DialogFooter class="gap-2">
          <Button variant="outline" @click="voidDialog = false">ปิด</Button>
          <Button variant="destructive" :disabled="saving" @click="submitVoid">ยืนยันยกเลิกบิล</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>

    <!-- คืนเงิน (OWNER) -->
    <Dialog v-model:open="refundDialog">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>คืนเงิน</DialogTitle>
          <DialogDescription v-if="refundPayment">{{ paymentMethodLabels[refundPayment.method] }} {{ formatBaht(Number(refundPayment.amount)) }}</DialogDescription>
        </DialogHeader>
        <form class="grid gap-4" @submit.prevent="submitRefund">
          <TextField v-model="refundForm.amount" type="number" label="ยอดคืน" suffix="บาท" class="num" />
          <SegmentedControl v-model="refundForm.method" :items="[{ value: 'CASH', label: 'คืนเงินสด' }, { value: 'BANK_TRANSFER', label: 'โอนคืน' }]" label="วิธีคืนเงิน" />
          <TextField v-if="refundForm.method === 'BANK_TRANSFER'" v-model="refundForm.reference" label="เลขอ้างอิงการโอนคืน" />
          <TextareaField v-model="refundForm.reason" label="เหตุผล" hint="บังคับ" rows="2" />
          <DialogFooter class="gap-2">
            <Button type="button" variant="outline" @click="refundDialog = false">ปิด</Button>
            <Button type="submit" variant="destructive" :disabled="saving">คืนเงิน</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  </div>
</template>
