<script setup lang="ts">
// ชำระเงินของ Order: ร่าง Invoice → ส่วนลด → ออก Invoice (หักมัดจำอัตโนมัติ) → รับเงิน (เงินสด / โอน / QR + สลิป) + ทิป
// Void (ต้องมีเหตุผล) / คืนเงิน (OWNER) — ใบเสร็จเก็บในระบบเท่านั้น
import {
  formatBaht,
  formatDuration,
  invoiceStatusLabels,
  newIdempotencyKey,
  paymentMethodLabels,
  reasonSchema,
  bangkokTime,
  type InvoiceView,
  type PosBoard,
  type SlipCheck,
} from '@ifeew/shared'

const route = useRoute()
const supabase = useSupabaseClient()
const { activeBranch, isOwner } = useAccess()
const { run } = useStepUp()
const { callForm } = useEdgeFunction()

const orderId = computed(() => String(route.params.orderId))
const invoice = ref<InvoiceView | null>(null)
const therapists = ref<PosBoard['therapists']>([])
const loading = ref(true)
const saving = ref(false)
const message = ref<{ type: 'success' | 'error' | 'info'; text: string } | null>(null)
const ok = (text: string) => (message.value = { type: 'success', text })
const fail = (e: unknown, fallback?: string) => (message.value = { type: 'error', text: errorText(e, fallback) })

async function load() {
  loading.value = true
  try {
    invoice.value = (await must(supabase.rpc('pos_create_invoice', { p_order_id: orderId.value }))) as unknown as InvoiceView
  } catch (e) {
    fail(e, 'สร้าง Invoice ไม่สำเร็จ')
  } finally {
    loading.value = false
  }
  if (activeBranch.value) {
    const { data } = await supabase.rpc('pos_board', { p_branch_id: activeBranch.value.branch_id })
    therapists.value = ((data ?? null) as unknown as PosBoard | null)?.therapists ?? []
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
const method = ref<'CASH' | 'QR' | 'BANK_TRANSFER'>('CASH')
const amount = ref<number | string>('')
const tendered = ref<number | string>('')
const tipAmount = ref<number | string>('')
const tipEmployee = ref<string | null>(null)
const slip = ref<SlipCheck | null>(null)
const slipUploading = ref(false)
const manualReason = ref('')
let payKey = newIdempotencyKey()

const tip = computed(() => Math.max(0, Number(tipAmount.value) || 0))
const change = computed(() => Math.max(0, (Number(tendered.value) || 0) - (Number(amount.value) || 0) - tip.value))

function resetPayment() {
  amount.value = invoice.value ? Number(invoice.value.balance) : ''
  tendered.value = ''
  tipAmount.value = ''
  tipEmployee.value = null
  slip.value = null
  manualReason.value = ''
  payKey = newIdempotencyKey()
}
watch(() => invoice.value?.invoice_id, resetPayment)
watch([method, amount, tipAmount], () => {
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
    form.append('amount', String((Number(amount.value) || 0) + tip.value))
    slip.value = await callForm<SlipCheck>('pos-payment-slip', form)
  } catch (err) {
    message.value = { type: 'error', text: edgeErrorText(err, 'อัปโหลดสลิปไม่สำเร็จ') }
  } finally {
    slipUploading.value = false
  }
}

const canPay = computed(() => {
  if (!payable.value || !(Number(amount.value) > 0)) return false
  if (tip.value > 0 && !tipEmployee.value) return false
  if (method.value === 'CASH') return true
  if (!slip.value || slip.value.outcome === 'REJECTED') return false
  return slip.value.outcome === 'VERIFIED' || manualReason.value.trim().length >= 3
})

async function pay() {
  if (!invoice.value || !canPay.value) return
  saving.value = true
  try {
    invoice.value = (await must(supabase.rpc('pos_record_payment', {
      p_invoice_id: invoice.value.invoice_id,
      p_method: method.value,
      p_amount: Number(amount.value),
      p_slip_check_id: method.value === 'CASH' ? null : slip.value!.slip_check_id,
      p_manual_reason: slip.value?.outcome === 'REVIEW' ? manualReason.value.trim() : null,
      p_tip_amount: tip.value,
      p_tip_employee_id: tip.value > 0 ? tipEmployee.value : null,
      p_idempotency_key: payKey,
    }))) as unknown as InvoiceView
    ok(invoice.value.status === 'PAID' ? `ชำระครบแล้ว · ใบเสร็จ ${invoice.value.receipt_number}` : 'บันทึกการรับเงินแล้ว')
    resetPayment()
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}

async function viewSlip(path: string) {
  const { data } = await supabase.storage.from('payment-slips').createSignedUrl(path, 300)
  if (data?.signedUrl) window.open(data.signedUrl, '_blank', 'noopener')
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
    ok('Void Invoice แล้ว ออกใบใหม่ได้ด้วยปุ่ม “สร้าง Invoice ใหม่”')
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
  <div class="max-w-4xl">
    <v-btn variant="text" prepend-icon="mdi-arrow-left" to="/pos" class="mb-2">หน้าร้าน</v-btn>
    <v-alert v-if="message" :type="message.type" variant="tonal" class="mb-4" closable :text="message.text" @click:close="message = null" />
    <v-progress-linear v-if="loading" indeterminate color="primary" />

    <template v-if="invoice">
      <div class="mb-4 flex flex-wrap items-center justify-between gap-2">
        <div>
          <h1 class="m-0 text-2xl font-semibold text-cocoa">
            {{ invoice.invoice_number ?? 'ร่าง Invoice' }}
            <v-chip size="small" variant="tonal" class="ml-1">{{ invoiceStatusLabels[invoice.status] }}</v-chip>
          </h1>
          <p class="m-0 text-light-brown">{{ invoice.customer_name ?? 'ลูกค้าทั่วไป' }} · {{ invoice.business_date }}</p>
          <p v-if="invoice.receipt_number" class="m-0 text-sm">ใบเสร็จ (เก็บในระบบ): {{ invoice.receipt_number }}</p>
          <p v-if="invoice.void_reason" class="m-0 text-sm text-red-700">Void: {{ invoice.void_reason }}</p>
        </div>
        <div class="flex gap-2">
          <v-btn v-if="invoice.status === 'VOID'" color="primary" @click="load">สร้าง Invoice ใหม่</v-btn>
          <v-btn v-else variant="text" color="error" @click="voidDialog = true; voidReason = ''">Void Invoice</v-btn>
        </div>
      </div>

      <v-card class="mb-4 p-4">
        <v-table density="comfortable">
          <thead>
            <tr><th>รายการ</th><th class="text-right">ราคา</th><th class="text-right">ส่วนลด</th><th class="text-right">สุทธิ</th><th /></tr>
          </thead>
          <tbody>
            <tr v-for="i in invoice.items" :key="i.invoice_item_id">
              <td>{{ i.description }} {{ formatDuration(i.duration_minutes) }}
                <div v-if="i.discount_reason" class="text-xs text-light-brown">{{ i.discount_reason }}</div></td>
              <td class="text-right">{{ formatBaht(Number(i.unit_price)) }}</td>
              <td class="text-right">{{ Number(i.discount_amount) ? '−' + formatBaht(Number(i.discount_amount)) : '-' }}</td>
              <td class="text-right">{{ formatBaht(Number(i.line_total)) }}</td>
              <td class="text-right"><v-btn v-if="isDraft" size="small" variant="text" @click="openDiscount(i)">ส่วนลด</v-btn></td>
            </tr>
          </tbody>
        </v-table>
        <div class="mt-3 grid justify-end gap-1 text-right">
          <p class="m-0 text-xl font-semibold">รวม {{ formatBaht(Number(invoice.total)) }}</p>
          <p class="m-0">จ่ายแล้ว {{ formatBaht(Number(invoice.paid_amount)) }}
            <span v-if="Number(invoice.refunded_amount)"> · คืนแล้ว {{ formatBaht(Number(invoice.refunded_amount)) }}</span></p>
          <p v-if="invoice.status !== 'VOID'" class="m-0 text-lg font-medium text-cocoa">ค้างชำระ {{ formatBaht(Number(invoice.balance)) }}</p>
        </div>
        <div v-if="isDraft" class="mt-3 flex items-center justify-end gap-3">
          <span v-if="invoice.deposit_available" class="text-sm text-light-brown">จะหักมัดจำ {{ formatBaht(Number(invoice.deposit_available)) }} อัตโนมัติ</span>
          <v-btn color="primary" size="large" :loading="saving" @click="issue">ออก Invoice</v-btn>
        </div>
      </v-card>

      <!-- รับเงิน -->
      <v-card v-if="payable" class="mb-4 p-5">
        <p class="m-0 mb-3 text-lg font-medium">รับเงิน</p>
        <v-btn-toggle v-model="method" mandatory color="primary" class="mb-4">
          <v-btn value="CASH">เงินสด</v-btn>
          <v-btn value="QR">QR</v-btn>
          <v-btn value="BANK_TRANSFER">โอน</v-btn>
        </v-btn-toggle>
        <div class="grid gap-x-4 md:grid-cols-2">
          <v-text-field v-model="amount" type="number" label="ยอดรับ (บาท)" :hint="`ค้าง ${formatBaht(Number(invoice.balance))}`" persistent-hint class="mb-2" />
          <v-text-field v-if="method === 'CASH'" v-model="tendered" type="number" label="รับเงินมา (คำนวณเงินทอน)" :hint="`ทอน ${formatBaht(change)}`" persistent-hint class="mb-2" />
          <v-text-field v-model="tipAmount" type="number" label="ทิป (ถ้ามี)" />
          <v-select v-if="tip > 0" v-model="tipEmployee" :items="therapists.map((t) => ({ value: t.employee_id, title: t.nickname }))" label="ทิปให้หมอ" />
        </div>

        <template v-if="method !== 'CASH'">
          <p class="m-0 mb-2 text-sm">ลูกค้าโอนผ่าน QR หน้าร้าน ยอด <b>{{ formatBaht((Number(amount) || 0) + tip) }}</b> แล้วถ่ายรูปสลิป</p>
          <label class="inline-block">
            <input type="file" accept="image/*" capture="environment" class="hidden" :disabled="slipUploading || !(Number(amount) > 0)" @change="onSlipSelected" >
            <v-btn tag="span" prepend-icon="mdi-camera" variant="tonal" :loading="slipUploading" :disabled="!(Number(amount) > 0)">ถ่ายรูปสลิป</v-btn>
          </label>
          <v-alert v-if="slip" class="mt-3" variant="tonal"
            :type="slip.outcome === 'VERIFIED' ? 'success' : slip.outcome === 'REJECTED' ? 'error' : 'warning'"
            :text="slip.outcome === 'VERIFIED' ? `สลิปถูกต้อง ${formatBaht(Number(slip.slip_amount))}` : slip.message ?? ''" />
          <v-text-field v-if="slip?.outcome === 'REVIEW'" v-model="manualReason" class="mt-3"
            label="ตรวจยอดเข้าบัญชีแล้ว — ระบุเหตุผลเพื่อยืนยันเอง" />
        </template>

        <div class="mt-4 flex justify-end">
          <v-btn color="primary" size="large" :disabled="!canPay" :loading="saving" @click="pay">บันทึกรับเงิน</v-btn>
        </div>
      </v-card>

      <!-- รายการรับเงิน -->
      <v-card v-if="invoice.payments.length || invoice.tips.length" class="p-4">
        <p class="m-0 mb-2 font-medium">การรับเงิน</p>
        <div v-for="p in invoice.payments" :key="p.payment_id" class="flex flex-wrap items-center justify-between gap-2 border-b py-2">
          <div :class="{ 'line-through text-light-brown': p.status === 'VOID' }">
            {{ paymentMethodLabels[p.method] }} {{ formatBaht(Number(p.amount)) }}
            <span class="text-sm text-light-brown">· {{ bangkokTime(p.received_at) }} {{ p.received_by_name ?? '' }}
              <template v-if="p.verification"> · สลิป{{ p.verification === 'AUTO' ? 'ตรวจอัตโนมัติ' : 'ยืนยันโดยพนักงาน' }}</template>
              <template v-if="Number(p.refunded)"> · คืนแล้ว {{ formatBaht(Number(p.refunded)) }}</template>
            </span>
          </div>
          <div class="flex gap-1">
            <v-btn v-if="p.slip_path" size="small" variant="text" @click="viewSlip(p.slip_path)">ดูสลิป</v-btn>
            <v-btn v-if="isOwner && p.status === 'SUCCESS' && p.method !== 'DEPOSIT' && Number(p.refunded) < Number(p.amount)"
              size="small" variant="text" color="error" @click="openRefund(p)">คืนเงิน</v-btn>
          </div>
        </div>
        <p v-for="t in invoice.tips" :key="t.tip_id" class="m-0 mt-2 text-sm" :class="{ 'line-through': t.status === 'VOID' }">
          ทิป {{ t.nickname }} {{ formatBaht(Number(t.amount)) }} ({{ paymentMethodLabels[t.method as 'CASH'] }})
          {{ t.status === 'PAID_OUT' ? '· จ่ายหมอแล้ว' : '' }}
        </p>
      </v-card>
    </template>

    <!-- ส่วนลด -->
    <v-dialog v-model="discountDialog" max-width="420">
      <v-card v-if="discountItem && invoice" class="p-6">
        <p class="m-0 mb-1 text-lg font-medium">ส่วนลด · {{ discountItem.description }}</p>
        <p class="m-0 mb-3 text-sm text-light-brown">
          ราคา {{ formatBaht(Number(discountItem.unit_price)) }} · พนักงานลดได้ไม่เกิน {{ invoice.max_staff_discount_percent }}%
          (เกินนี้ต้องให้เจ้าของร้านยืนยันตัวตน)
        </p>
        <v-text-field v-model="discountAmount" type="number" label="ส่วนลด (บาท)" />
        <v-text-field v-model="discountReason" label="เหตุผล" />
        <div class="flex justify-end gap-2">
          <v-btn variant="text" @click="discountDialog = false">ปิด</v-btn>
          <v-btn color="primary" :loading="saving" @click="saveDiscount">บันทึก</v-btn>
        </div>
      </v-card>
    </v-dialog>

    <!-- Void -->
    <v-dialog v-model="voidDialog" max-width="440">
      <v-card class="p-6">
        <p class="m-0 mb-1 text-lg font-medium">Void Invoice</p>
        <p class="m-0 mb-3 text-sm text-light-brown">ถ้ารับเงินแล้ว ต้องให้เจ้าของร้านยืนยันตัวตน และเงินต้องอยู่ในกะที่ยังเปิด (นอกนั้นใช้คืนเงิน)</p>
        <v-textarea v-model="voidReason" label="เหตุผล (บังคับ)" rows="2" variant="outlined" />
        <div class="flex justify-end gap-2">
          <v-btn variant="text" @click="voidDialog = false">ปิด</v-btn>
          <v-btn color="error" :loading="saving" @click="submitVoid">ยืนยัน Void</v-btn>
        </div>
      </v-card>
    </v-dialog>

    <!-- คืนเงิน (OWNER) -->
    <v-dialog v-model="refundDialog" max-width="440">
      <v-card class="p-6">
        <p class="m-0 mb-3 text-lg font-medium">คืนเงิน</p>
        <v-text-field v-model="refundForm.amount" type="number" label="ยอดคืน (บาท)" />
        <v-btn-toggle v-model="refundForm.method" mandatory color="primary" class="mb-3">
          <v-btn value="CASH">เงินสดจากลิ้นชัก</v-btn>
          <v-btn value="BANK_TRANSFER">โอนคืน</v-btn>
        </v-btn-toggle>
        <v-text-field v-if="refundForm.method === 'BANK_TRANSFER'" v-model="refundForm.reference" label="เลขอ้างอิงการโอนคืน" />
        <v-textarea v-model="refundForm.reason" label="เหตุผล (บังคับ)" rows="2" variant="outlined" />
        <div class="flex justify-end gap-2">
          <v-btn variant="text" @click="refundDialog = false">ปิด</v-btn>
          <v-btn color="error" :loading="saving" @click="submitRefund">คืนเงิน</v-btn>
        </div>
      </v-card>
    </v-dialog>
  </div>
</template>
