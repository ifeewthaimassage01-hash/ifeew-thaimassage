<script setup lang="ts">
// ชำระเงินของ Order: ออก Invoice ให้อัตโนมัติ (ข้ามขั้นร่าง · หักมัดจำอัตโนมัติ) → รับเงิน (เงินสด / โอน+สลิป — QR รวมกับโอน) + ทิป
// ยกเลิกบิล (Void ต้องมีเหตุผล) / คืนเงิน (OWNER) — ใบเสร็จเก็บในระบบเท่านั้น
import { Camera, CircleCheck } from '@lucide/vue'
import {
  formatBaht,
  formatDuration,
  invoiceStatusLabels,
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
    ok(invoice.value.status === 'PAID' ? `ชำระครบแล้ว · ใบเสร็จ ${invoice.value.receipt_number}` : 'บันทึกการรับเงินแล้ว')
    resetPayment()
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}

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
  <div>
    <MessageAlert :message="message" class="mb-4" @close="message = null" />
    <LoadingBar v-if="loading" class="mb-4" />

    <template v-if="invoice">
      <PageHeader :title="invoice.invoice_number ?? 'ร่าง Invoice'" :description="`${invoice.customer_name ?? 'ลูกค้าทั่วไป'} · ${invoice.business_date}`">
        <template #actions>
          <Badge dot :variant="invoice.status === 'PAID' ? 'success' : invoice.status === 'VOID' ? 'danger' : invoice.status === 'DRAFT' ? 'neutral' : 'pending'">
            {{ invoiceStatusLabels[invoice.status] }}
          </Badge>
          <Button v-if="invoice.status === 'VOID'" @click="load">ออกบิลใหม่</Button>
          <Button v-else variant="ghost" class="text-danger-ink" @click="voidDialog = true; voidReason = ''">ยกเลิกบิล</Button>
          <Button as-child variant="outline"><NuxtLink to="/payments">กลับหน้าชำระเงิน</NuxtLink></Button>
        </template>
      </PageHeader>
      <div v-if="invoice.receipt_number || invoice.void_reason" class="-mt-4 mb-6 grid gap-1 text-[15px]">
        <p v-if="invoice.receipt_number" class="m-0">ใบเสร็จ (เก็บในระบบ): <span class="num text-heading">{{ invoice.receipt_number }}</span></p>
        <p v-if="invoice.void_reason" class="m-0 text-danger-ink">ยกเลิกบิล: {{ invoice.void_reason }}</p>
      </div>

      <div class="grid items-start gap-6 xl:grid-cols-[minmax(0,1fr)_420px]">
        <div class="grid gap-6">
          <!-- รายการ -->
          <SectionCard title="รายการ" flush>
            <div class="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow class="hover:bg-transparent">
                    <TableHead>รายการ</TableHead><TableHead class="text-right">ราคา</TableHead><TableHead class="text-right">ส่วนลด</TableHead>
                    <TableHead class="text-right">สุทธิ</TableHead><TableHead class="text-right"><span class="sr-only">การทำงาน</span></TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  <TableRow v-for="i in invoice.items" :key="i.invoice_item_id">
                    <TableCell class="whitespace-normal">
                      <span class="text-heading">{{ i.description }}</span> <span class="text-muted-foreground">{{ formatDuration(i.duration_minutes) }}</span>
                      <span v-if="i.discount_reason" class="block text-sm text-muted-foreground">{{ i.discount_reason }}</span>
                    </TableCell>
                    <TableCell class="num text-right">{{ formatBaht(Number(i.unit_price)) }}</TableCell>
                    <TableCell class="num text-right">{{ Number(i.discount_amount) ? '−' + formatBaht(Number(i.discount_amount)) : '—' }}</TableCell>
                    <TableCell class="num text-right font-medium text-heading">{{ formatBaht(Number(i.line_total)) }}</TableCell>
                    <TableCell class="text-right"><Button v-if="isDraft" size="sm" variant="ghost" @click="openDiscount(i)">ส่วนลด</Button></TableCell>
                  </TableRow>
                </TableBody>
              </Table>
            </div>
            <dl class="m-0 grid gap-1.5 border-t border-border px-5 py-4 text-[15px] sm:ml-auto sm:w-80">
              <div class="flex justify-between"><dt class="font-medium text-heading">รวม</dt><dd class="num m-0 text-xl font-semibold text-heading">{{ formatBaht(Number(invoice.total)) }}</dd></div>
              <div class="flex justify-between"><dt class="text-muted-foreground">จ่ายแล้ว</dt><dd class="num m-0">{{ formatBaht(Number(invoice.paid_amount)) }}</dd></div>
              <div v-if="Number(invoice.refunded_amount)" class="flex justify-between"><dt class="text-muted-foreground">คืนแล้ว</dt><dd class="num m-0">{{ formatBaht(Number(invoice.refunded_amount)) }}</dd></div>
              <div v-if="invoice.status !== 'VOID'" class="flex justify-between border-t border-border pt-2">
                <dt class="font-medium text-heading">ค้างชำระ</dt>
                <dd class="num m-0 text-lg font-semibold" :class="Number(invoice.balance) > 0 ? 'text-pending-ink' : 'text-success-ink'">{{ formatBaht(Number(invoice.balance)) }}</dd>
              </div>
            </dl>
            <div v-if="isDraft" class="flex flex-wrap items-center justify-end gap-3 border-t border-border px-5 py-4">
              <span v-if="invoice.deposit_available" class="text-sm text-muted-foreground">จะหักมัดจำ <span class="num">{{ formatBaht(Number(invoice.deposit_available)) }}</span> อัตโนมัติ</span>
              <Button size="lg" :disabled="saving" @click="issue">ออก Invoice</Button>
            </div>
          </SectionCard>

          <!-- รายการรับเงิน -->
          <SectionCard v-if="invoice.payments.length || invoice.tips.length" title="การรับเงิน" flush>
            <ul class="m-0 grid list-none p-0">
              <li v-for="p in invoice.payments" :key="p.payment_id" class="flex flex-wrap items-center justify-between gap-2 border-b border-border px-5 py-3 last:border-0">
                <div :class="{ 'text-muted-foreground line-through': p.status === 'VOID' }">
                  <span class="text-heading">{{ paymentMethodLabels[p.method] }}</span> <span class="num font-semibold text-heading">{{ formatBaht(Number(p.amount)) }}</span>
                  <span class="block text-sm text-muted-foreground">
                    <span class="num">{{ bangkokTime(p.received_at) }}</span> {{ p.received_by_name ?? '' }}
                    <template v-if="p.verification"> · สลิป{{ p.verification === 'AUTO' ? 'ตรวจอัตโนมัติ' : 'ยืนยันโดยพนักงาน' }}</template>
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
            <template v-if="invoice.tips.length" #footer>
              <p v-for="t in invoice.tips" :key="t.tip_id" class="m-0" :class="{ 'line-through': t.status === 'VOID' }">
                ทิป <span class="text-heading">{{ t.nickname }}</span> <span class="num">{{ formatBaht(Number(t.amount)) }}</span> ({{ paymentMethodLabels[t.method as 'CASH'] }})
                {{ t.status === 'PAID_OUT' ? '· จ่ายหมอแล้ว' : '' }}
              </p>
            </template>
          </SectionCard>
        </div>

        <!-- รับเงิน -->
        <SectionCard v-if="payable" title="รับเงิน" class="xl:sticky xl:top-24">
          <form class="grid gap-4" @submit.prevent="pay">
            <SegmentedControl v-model="method" :items="[{ value: 'CASH', label: 'เงินสด' }, { value: 'BANK_TRANSFER', label: 'โอน / QR' }]" label="วิธีรับเงิน" class="w-full [&>button]:flex-1" />

            <div v-if="method !== 'CASH'" class="grid gap-3 rounded-lg bg-muted p-4">
              <p class="m-0 text-[15px]">ลูกค้าสแกน QR หรือโอนเข้าบัญชีร้าน ยอด <span class="num font-semibold text-heading">{{ formatBaht(amount) }}</span> แล้วถ่ายรูปสลิป</p>
              <label
                class="flex cursor-pointer items-center justify-center gap-2 rounded-lg border border-dashed border-input bg-card px-4 py-3 text-[15px] text-heading hover:bg-muted focus-within:ring-3 focus-within:ring-ring/50"
                :class="slipUploading || !(amount > 0) ? 'pointer-events-none opacity-50' : ''"
              >
                <input type="file" accept="image/*" capture="environment" class="sr-only" :disabled="slipUploading || !(amount > 0)" @change="onSlipSelected">
                <Camera class="size-5 text-brand-accent" /> {{ slipUploading ? 'กำลังอัปโหลดสลิป…' : slip ? 'ถ่ายใหม่' : 'ถ่ายรูปสลิป' }}
              </label>
              <div v-if="slip" class="flex items-center justify-between gap-3 rounded-lg bg-success-soft px-3 py-2 text-[15px] text-success-ink">
                <span class="flex items-center gap-2"><CircleCheck class="size-4" /> แนบสลิปแล้ว</span>
                <Button type="button" size="sm" variant="ghost" @click="viewSlip(slip.slip_path)">ดูสลิป</Button>
              </div>
            </div>

            <Button type="submit" size="lg" class="w-full" :disabled="!canPay || saving">{{ saving ? 'กำลังบันทึก…' : `บันทึกรับเงิน ${formatBaht(amount)}` }}</Button>
          </form>
        </SectionCard>
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
