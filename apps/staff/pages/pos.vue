<script setup lang="ts">
// หน้าร้าน (POS): เปิดกะ, รับลูกค้า Walk-in, เช็กอินลูกค้าที่จอง, เพิ่มบริการ
// ร้านไม่มีเครื่องพิมพ์: หลังสร้างคิวให้แจ้งเลขคิวที่แสดงบนจอแก่ลูกค้า
import {
  bangkokTime,
  formatBaht,
  formatDuration,
  formatQueueNumber,
  newIdempotencyKey,
  orderChannelLabels,
  queueStatusLabels,
  thaiPhoneSchema,
  type AvailableSlot,
  type Database,
  type PosOrder,
  type StaffBookingRow,
  invoiceStatusLabels,
  type FinanceBoard,
} from '@ifeew/shared'

type CatalogRow = Database['public']['Views']['v_public_branch_services']['Row']
type SearchRow = { customer_id: string; display_name: string; phone_masked: string; is_member: boolean }

const supabase = useSupabaseClient()
const { activeBranch, company } = useAccess()
const { board, loading, error, load } = usePosBoard()

// ---------------------------------------------------------------------------
// การเงินหน้าร้าน (Invoice ค้างชำระ, ทิปเงินสดที่ยังไม่จ่าย)
// ---------------------------------------------------------------------------
const finance = ref<FinanceBoard | null>(null)
async function loadFinance() {
  if (!activeBranch.value) return
  const { data } = await supabase.rpc('pos_finance_board', { p_branch_id: activeBranch.value.branch_id })
  finance.value = (data ?? null) as unknown as FinanceBoard | null
}
watch(() => [board.value?.session?.session_id, board.value?.orders.length, activeBranch.value?.branch_id], loadFinance, { immediate: true })
const invoiceOf = (orderId: string) => finance.value?.invoices.find((i) => i.service_order_id === orderId && i.status !== 'VOID')
const outstanding = computed(() => (finance.value?.invoices ?? []).filter((i) => ['ISSUED', 'PARTIALLY_PAID'].includes(i.status)))

// เงินเข้า/ออกลิ้นชัก
const cashDialog = ref(false)
const cashForm = reactive({ type: 'CASH_IN' as 'CASH_IN' | 'CASH_OUT', amount: '' as number | string, reason: '' })
async function submitCash() {
  if (!activeBranch.value) return
  saving.value = true
  try {
    await must(supabase.rpc('pos_cash_adjustment', {
      p_branch_id: activeBranch.value.branch_id, p_type: cashForm.type, p_amount: Number(cashForm.amount), p_reason: cashForm.reason.trim(),
    }))
    cashDialog.value = false
    message.value = { type: 'success', text: 'บันทึกเงินเข้า/ออกลิ้นชักแล้ว' }
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}

async function payOutTips(t: FinanceBoard['unpaid_cash_tips'][number]) {
  if (!activeBranch.value || !window.confirm(`จ่ายทิปเงินสด ${formatBaht(Number(t.amount))} ให้ ${t.nickname} จากลิ้นชัก?`)) return
  try {
    await must(supabase.rpc('pos_pay_out_tips', { p_branch_id: activeBranch.value.branch_id, p_employee_id: t.employee_id }))
    message.value = { type: 'success', text: `จ่ายทิปให้ ${t.nickname} แล้ว` }
    await loadFinance()
  } catch (e) {
    fail(e)
  }
}

// ปิดกะ: นับเงินก่อน (ไม่แสดงยอดที่ระบบคาดไว้) แล้วระบบแจ้งผลต่าง
const closeDialog = ref(false)
const closeCash = ref<number | string>('')
const closeNote = ref('')
const closeNeedsNote = ref(false)
const closeResult = ref<Record<string, number> | null>(null)
function openClose() {
  closeCash.value = ''
  closeNote.value = ''
  closeNeedsNote.value = false
  closeResult.value = null
  closeDialog.value = true
}
async function submitClose() {
  if (!board.value?.session || closeCash.value === '') return
  saving.value = true
  try {
    const { data, error: err } = await supabase.rpc('pos_close_session', {
      p_session_id: board.value.session.session_id, p_actual_cash: Number(closeCash.value), p_note: closeNote.value.trim() || null,
    })
    if (err) {
      if ((err as { hint?: string }).hint === 'DIFFERENCE_NOTE') {
        closeNeedsNote.value = true
        message.value = { type: 'error', text: err.message }
        return
      }
      throw err
    }
    closeResult.value = data as unknown as Record<string, number>
    await load()
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}

const message = ref<{ type: 'success' | 'error' | 'info'; text: string } | null>(null)
const saving = ref(false)
const fail = (e: unknown, fallback?: string) => (message.value = { type: 'error', text: errorText(e, fallback) })

const orders = computed(() => [...(board.value?.orders ?? [])].reverse())
const activeOrders = computed(() => orders.value.filter((o) => o.status !== 'CANCELLED'))

// ---------------------------------------------------------------------------
// เปิดกะ
// ---------------------------------------------------------------------------
const sessionDialog = ref(false)
const openingCash = ref<number | string>('')
const openingNote = ref('')

async function openSession() {
  const cash = Number(openingCash.value)
  if (!activeBranch.value || openingCash.value === '' || !Number.isFinite(cash) || cash < 0) {
    fail(null, 'กรุณาระบุเงินสดเริ่มต้น')
    return
  }
  saving.value = true
  try {
    await must(supabase.rpc('pos_open_session', {
      p_branch_id: activeBranch.value.branch_id, p_opening_cash: cash, p_note: openingNote.value.trim() || null,
    }))
    sessionDialog.value = false
    message.value = { type: 'success', text: 'เปิดกะแล้ว' }
    await load()
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}

// ---------------------------------------------------------------------------
// การจองวันนี้ที่รอเช็กอิน
// ---------------------------------------------------------------------------
const bookings = ref<StaffBookingRow[]>([])
const awaiting = computed(() => bookings.value.filter((b) => b.status === 'CONFIRMED'))

async function loadBookings() {
  if (!activeBranch.value || !board.value) return
  try {
    bookings.value = (await must(supabase.rpc('staff_bookings', {
      p_branch_id: activeBranch.value.branch_id, p_date: board.value.business_date,
    }))) as unknown as StaffBookingRow[]
  } catch {
    bookings.value = []
  }
}
watch(() => [board.value?.business_date, board.value?.orders.length], loadBookings)

const created = ref<PosOrder | null>(null)

async function checkIn(b: StaffBookingRow) {
  saving.value = true
  try {
    addToOrder.value = null
    created.value = (await must(supabase.rpc('pos_check_in_booking', { p_booking_id: b.booking_id }))) as unknown as PosOrder
    await load()
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}

// ---------------------------------------------------------------------------
// Walk-in / เพิ่มบริการ
// ---------------------------------------------------------------------------
const walkDialog = ref(false)
const addToOrder = ref<PosOrder | null>(null)   // != null = เพิ่มบริการใน Order เดิม
const step = ref(1)
const phone = ref('')
const found = ref<SearchRow[] | null>(null)
const customerId = ref<string | null>(null)
const customerLabel = ref('ลูกค้าทั่วไป')
const catalog = ref<CatalogRow[]>([])
const people = ref<Array<{ option_id: string | null }>>([{ option_id: null }])
const starts = ref<AvailableSlot[]>([])
const startAt = ref<string | null>(null)
const startsLoading = ref(false)
const note = ref('')
let idemKey = newIdempotencyKey()

const optionItems = computed(() =>
  catalog.value.map((c) => ({ value: c.option_id, title: `${c.name} ${formatDuration(c.duration_minutes)} · ${formatBaht(Number(c.price))}` })),
)
const optionIds = computed(() => people.value.map((p) => p.option_id).filter((x): x is string => !!x))
const total = computed(() =>
  optionIds.value.reduce((sum, id) => sum + Number(catalog.value.find((c) => c.option_id === id)?.price ?? 0), 0),
)

async function loadCatalog() {
  const { data } = await supabase
    .from('v_public_branch_services')
    .select('*')
    .eq('branch_id', activeBranch.value!.branch_id)
    .order('category_sort_order').order('sort_order').order('duration_minutes')
  catalog.value = (data ?? []) as CatalogRow[]
}

async function openWalkIn(order: PosOrder | null = null) {
  addToOrder.value = order
  step.value = order ? 2 : 1
  phone.value = ''
  found.value = null
  customerId.value = null
  customerLabel.value = 'ลูกค้าทั่วไป'
  people.value = [{ option_id: null }]
  starts.value = []
  startAt.value = null
  note.value = ''
  idemKey = newIdempotencyKey()
  walkDialog.value = true
  await loadCatalog()
}

async function searchCustomer() {
  const p = thaiPhoneSchema.safeParse(phone.value)
  if (!p.success) {
    fail(null, 'กรุณากรอกเบอร์โทรเต็ม')
    return
  }
  try {
    found.value = (await must(supabase.rpc('search_customers_by_phone', {
      p_company_id: company.value!.company_id, p_phone: p.data,
    }))) as SearchRow[]
  } catch (e) {
    fail(e)
  }
}

function chooseCustomer(c: SearchRow | null) {
  customerId.value = c?.customer_id ?? null
  customerLabel.value = c ? `${c.display_name} (${c.phone_masked})` : 'ลูกค้าทั่วไป'
  step.value = 2
}

// เวลาว่างของวันนี้ (ตัวแรก = เร็วที่สุด เลือกให้อัตโนมัติ)
watch([() => optionIds.value.join(','), step], async () => {
  startAt.value = null
  idemKey = newIdempotencyKey()
  if (step.value !== 2 || !optionIds.value.length || optionIds.value.length !== people.value.length || !activeBranch.value) {
    starts.value = []
    return
  }
  startsLoading.value = true
  const { data, error: err } = await supabase.rpc('pos_available_starts', {
    p_branch_id: activeBranch.value.branch_id, p_option_ids: optionIds.value,
  })
  startsLoading.value = false
  starts.value = err ? [] : ((data ?? []) as unknown as AvailableSlot[])
  startAt.value = starts.value[0]?.starts_at ?? null
})

async function submitWalkIn() {
  if (!startAt.value || !activeBranch.value) return
  saving.value = true
  try {
    created.value = addToOrder.value
      ? ((await must(supabase.rpc('pos_add_order_items', {
          p_order_id: addToOrder.value.order_id,
          p_starts_at: startAt.value,
          p_option_ids: optionIds.value,
          p_idempotency_key: idemKey,
        }))) as unknown as PosOrder)
      : ((await must(supabase.rpc('pos_create_walkin', {
          p_branch_id: activeBranch.value.branch_id,
          p_customer_id: customerId.value,
          p_starts_at: startAt.value,
          p_option_ids: optionIds.value,
          p_note: note.value.trim() || null,
          p_idempotency_key: idemKey,
        }))) as unknown as PosOrder)
    walkDialog.value = false
    await load()
  } catch (e) {
    fail(e, 'สร้างคิวไม่สำเร็จ')
  } finally {
    saving.value = false
  }
}

// คิวที่เพิ่งสร้าง (แสดงเลขคิวให้แจ้งลูกค้า แทนการพิมพ์)
const newQueues = computed(() => {
  if (!created.value) return []
  const before = new Set((addToOrder.value?.items ?? []).map((i) => i.queue_id))
  return created.value.items.filter((i) => !before.has(i.queue_id) && i.queue_status !== 'CANCELLED')
})
</script>

<template>
  <div>
    <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
      <h1 class="m-0 text-2xl font-semibold text-cocoa">หน้าร้าน · {{ activeBranch?.name }}</h1>
      <div class="flex gap-2">
        <v-btn color="primary" size="large" prepend-icon="mdi-account-plus-outline" @click="openWalkIn()">รับลูกค้า Walk-in</v-btn>
        <v-btn variant="tonal" to="/queue" prepend-icon="mdi-format-list-numbered">ดูคิว</v-btn>
      </div>
    </div>

    <v-alert v-if="message" :type="message.type" variant="tonal" class="mb-4" closable :text="message.text" @click:close="message = null" />
    <v-alert v-if="error" type="error" variant="tonal" class="mb-4" :text="error" />
    <v-progress-linear v-if="loading" indeterminate color="primary" />

    <!-- ค้างชำระ / ทิป -->
    <v-card v-if="finance && (outstanding.length || finance.unpaid_cash_tips.length)" class="mb-4 p-4">
      <div v-if="outstanding.length">
        <p class="m-0 mb-2 font-medium">ค้างชำระ {{ formatBaht(Number(finance.outstanding)) }}</p>
        <div class="flex flex-wrap gap-2">
          <v-chip v-for="i in outstanding" :key="i.invoice_id" :to="`/checkout/${i.service_order_id}`" color="warning" variant="tonal">
            {{ i.invoice_number }} · {{ i.customer_name ?? 'ลูกค้าทั่วไป' }} · ค้าง {{ formatBaht(Number(i.balance)) }}
          </v-chip>
        </div>
      </div>
      <div v-if="finance.unpaid_cash_tips.length" class="mt-3">
        <p class="m-0 mb-2 font-medium">ทิปเงินสดที่ยังไม่จ่ายหมอ</p>
        <div class="flex flex-wrap gap-2">
          <v-btn v-for="t in finance.unpaid_cash_tips" :key="t.employee_id" size="small" variant="tonal" :disabled="!board?.session"
            @click="payOutTips(t)">จ่าย {{ t.nickname }} {{ formatBaht(Number(t.amount)) }}</v-btn>
        </div>
      </div>
    </v-card>

    <!-- กะ -->
    <v-card class="mb-4 p-4">
      <div v-if="board?.session" class="flex flex-wrap items-center justify-between gap-2">
        <p class="m-0">
          <v-icon icon="mdi-cash-register" color="success" class="mr-1" />
          กะเปิดอยู่ตั้งแต่ {{ bangkokTime(board.session.opened_at) }} โดย {{ board.session.opened_by_name ?? '-' }}
          · เงินสดเริ่มต้น {{ formatBaht(Number(board.session.opening_cash)) }}
        </p>
        <div class="flex gap-2">
          <v-btn variant="text" @click="cashDialog = true; cashForm.amount = ''; cashForm.reason = ''">เงินเข้า/ออกลิ้นชัก</v-btn>
          <v-btn color="primary" variant="tonal" @click="openClose">ปิดกะ</v-btn>
        </div>
      </div>
      <div v-else class="flex flex-wrap items-center justify-between gap-2">
        <p class="m-0"><v-icon icon="mdi-cash-register" class="mr-1" /> ยังไม่เปิดกะ (รับลูกค้าได้ แต่ต้องเปิดกะก่อนรับเงิน)</p>
        <v-btn color="primary" variant="tonal" @click="sessionDialog = true; openingCash = ''; openingNote = ''">เปิดกะ</v-btn>
      </div>
    </v-card>

    <!-- เลขคิวที่เพิ่งสร้าง -->
    <v-card v-if="created && newQueues.length" class="mb-4 border-2 border-soft-pink p-5">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p class="m-0 text-sm text-light-brown">แจ้งเลขคิวให้ลูกค้า · {{ created.customer_name ?? 'ลูกค้าทั่วไป' }}</p>
          <div class="mt-2 flex flex-wrap gap-4">
            <div v-for="i in newQueues" :key="i.queue_id" class="rounded-2xl bg-cream px-5 py-3 text-center">
              <p class="m-0 text-5xl font-semibold text-cocoa">{{ formatQueueNumber(i.queue_number) }}</p>
              <p class="m-0 text-sm">{{ i.service_name }} {{ formatDuration(i.duration_minutes) }}</p>
              <p class="m-0 text-xs text-light-brown">เริ่มประมาณ {{ bangkokTime(i.planned_starts_at) }}</p>
            </div>
          </div>
        </div>
        <v-btn icon="mdi-close" variant="text" aria-label="ปิด" @click="created = null" />
      </div>
    </v-card>

    <div class="grid gap-4 lg:grid-cols-2">
      <!-- รอเช็กอิน -->
      <section>
        <p class="m-0 mb-2 text-lg font-medium">ลูกค้าที่จองไว้วันนี้ ({{ awaiting.length }})</p>
        <p v-if="!awaiting.length" class="text-light-brown">ไม่มีการจองที่รอเช็กอิน</p>
        <div class="grid gap-3">
          <v-card v-for="b in awaiting" :key="b.booking_id" class="p-4">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <div>
                <p class="m-0 font-medium">{{ bangkokTime(b.starts_at) }} · {{ b.customer_name }}</p>
                <p class="m-0 text-sm text-light-brown">{{ b.booking_code }} · {{ b.phone_masked }}</p>
                <p class="m-0 text-sm">{{ b.items.map((i) => `${i.service_name} ${formatDuration(i.duration_minutes)}`).join(' · ') }}</p>
              </div>
              <v-btn color="primary" :loading="saving" @click="checkIn(b)">เช็กอิน</v-btn>
            </div>
          </v-card>
        </div>
      </section>

      <!-- Order วันนี้ -->
      <section>
        <p class="m-0 mb-2 text-lg font-medium">ลูกค้าวันนี้ ({{ activeOrders.length }})</p>
        <p v-if="!activeOrders.length" class="text-light-brown">ยังไม่มีลูกค้า</p>
        <div class="grid gap-3">
          <v-card v-for="o in activeOrders" :key="o.order_id" class="p-4">
            <div class="flex flex-wrap items-start justify-between gap-2">
              <div class="min-w-0">
                <p class="m-0 font-medium">
                  {{ o.customer_name ?? 'ลูกค้าทั่วไป' }}
                  <v-chip size="x-small" variant="tonal">{{ orderChannelLabels[o.channel] }}</v-chip>
                  <v-chip v-if="o.status === 'COMPLETED'" size="x-small" color="primary" variant="tonal">เสร็จแล้ว</v-chip>
                </p>
                <p v-for="i in o.items" :key="i.queue_id" class="m-0 text-sm" :class="{ 'line-through text-light-brown': i.queue_status === 'CANCELLED' }">
                  คิว {{ formatQueueNumber(i.queue_number) }} · {{ i.service_name }} {{ formatDuration(i.duration_minutes) }}
                  · {{ queueStatusLabels[i.queue_status] }}<span v-if="i.therapist"> · {{ i.therapist.nickname }}</span>
                </p>
              </div>
              <div class="flex flex-col items-end gap-1">
                <v-chip v-if="invoiceOf(o.order_id)" size="x-small" variant="tonal">{{ invoiceStatusLabels[invoiceOf(o.order_id)!.status] }}</v-chip>
                <v-btn v-if="o.items.some((i) => ['IN_SERVICE', 'COMPLETED'].includes(i.queue_status))" size="small" color="primary"
                  variant="tonal" prepend-icon="mdi-cash" :to="`/checkout/${o.order_id}`">
                  {{ invoiceOf(o.order_id)?.status === 'PAID' ? 'ดูการชำระ' : 'ชำระเงิน' }}
                </v-btn>
                <v-btn size="small" variant="text" prepend-icon="mdi-plus" @click="openWalkIn(o)">เพิ่มบริการ</v-btn>
              </div>
            </div>
          </v-card>
        </div>
      </section>
    </div>

    <!-- เงินเข้า/ออกลิ้นชัก -->
    <v-dialog v-model="cashDialog" max-width="420">
      <v-card class="p-6">
        <p class="m-0 mb-3 text-lg font-medium">เงินเข้า/ออกลิ้นชัก</p>
        <v-btn-toggle v-model="cashForm.type" mandatory color="primary" class="mb-3">
          <v-btn value="CASH_IN">เงินเข้า</v-btn>
          <v-btn value="CASH_OUT">เงินออก</v-btn>
        </v-btn-toggle>
        <v-text-field v-model="cashForm.amount" type="number" label="จำนวนเงิน (บาท)" />
        <v-text-field v-model="cashForm.reason" label="เหตุผล (เช่น แลกเหรียญ, นำเงินฝากธนาคาร)" />
        <p class="m-0 mb-2 text-xs text-light-brown">รายจ่ายของร้านให้บันทึกที่เมนู “รายจ่าย”</p>
        <div class="flex justify-end gap-2">
          <v-btn variant="text" @click="cashDialog = false">ปิด</v-btn>
          <v-btn color="primary" :loading="saving" @click="submitCash">บันทึก</v-btn>
        </div>
      </v-card>
    </v-dialog>

    <!-- ปิดกะ -->
    <v-dialog v-model="closeDialog" max-width="460" persistent>
      <v-card class="p-6">
        <p class="m-0 mb-1 text-lg font-medium">ปิดกะ</p>
        <template v-if="!closeResult">
          <p class="m-0 mb-3 text-sm text-light-brown">นับเงินสดในลิ้นชักทั้งหมด แล้วกรอกยอดที่นับได้ (ระบบจะแสดงยอดที่ควรมีหลังบันทึก)</p>
          <v-text-field v-model="closeCash" type="number" label="เงินสดที่นับได้ (บาท)" />
          <v-textarea v-if="closeNeedsNote" v-model="closeNote" label="เหตุผลที่เงินไม่ตรง (บังคับ)" rows="2" variant="outlined" />
          <div class="flex justify-end gap-2">
            <v-btn variant="text" @click="closeDialog = false">ยกเลิก</v-btn>
            <v-btn color="primary" :disabled="closeCash === ''" :loading="saving" @click="submitClose">ปิดกะ</v-btn>
          </div>
        </template>
        <template v-else>
          <div class="grid grid-cols-2 gap-1 text-sm">
            <span>เงินสดเริ่มต้น</span><span class="text-right">{{ formatBaht(Number(closeResult.opening_cash)) }}</span>
            <span>ขายเงินสด</span><span class="text-right">{{ formatBaht(Number(closeResult.cash_sales)) }}</span>
            <span>ทิปเงินสด</span><span class="text-right">{{ formatBaht(Number(closeResult.cash_tips)) }}</span>
            <span>เงินเข้า</span><span class="text-right">{{ formatBaht(Number(closeResult.cash_in)) }}</span>
            <span>เงินออก</span><span class="text-right">−{{ formatBaht(Number(closeResult.cash_out)) }}</span>
            <span>คืนเงินสด</span><span class="text-right">−{{ formatBaht(Number(closeResult.cash_refunds)) }}</span>
            <span class="font-medium">ควรมี</span><span class="text-right font-medium">{{ formatBaht(Number(closeResult.expected_cash)) }}</span>
            <span class="font-medium">นับได้</span><span class="text-right font-medium">{{ formatBaht(Number(closeResult.actual_cash)) }}</span>
            <span class="font-medium">ผลต่าง</span>
            <span class="text-right font-semibold" :class="Number(closeResult.cash_difference) === 0 ? 'text-green-800' : 'text-red-700'">
              {{ formatBaht(Number(closeResult.cash_difference)) }}</span>
            <span>โอน / QR</span><span class="text-right">{{ formatBaht(Number(closeResult.transfer_sales)) }} / {{ formatBaht(Number(closeResult.qr_sales)) }}</span>
          </div>
          <p class="m-0 mt-3 text-sm text-light-brown">ปิดกะแล้ว รอเจ้าของร้านตรวจ · เปิดกะใหม่ได้ทันที</p>
          <div class="mt-3 flex justify-end"><v-btn color="primary" @click="closeDialog = false">เสร็จสิ้น</v-btn></div>
        </template>
      </v-card>
    </v-dialog>

    <!-- เปิดกะ -->
    <v-dialog v-model="sessionDialog" max-width="420">
      <v-card class="p-6">
        <p class="m-0 mb-3 text-lg font-medium">เปิดกะ · {{ activeBranch?.name }}</p>
        <v-text-field v-model="openingCash" type="number" min="0" label="เงินสดเริ่มต้นในลิ้นชัก (บาท)" />
        <v-text-field v-model="openingNote" label="หมายเหตุ (ถ้ามี)" />
        <div class="flex justify-end gap-2">
          <v-btn variant="text" @click="sessionDialog = false">ยกเลิก</v-btn>
          <v-btn color="primary" :loading="saving" @click="openSession">เปิดกะ</v-btn>
        </div>
      </v-card>
    </v-dialog>

    <!-- Walk-in / เพิ่มบริการ -->
    <v-dialog v-model="walkDialog" max-width="620" scrollable>
      <v-card class="p-6">
        <p class="m-0 mb-4 text-lg font-medium">
          {{ addToOrder ? `เพิ่มบริการ · ${addToOrder.customer_name ?? 'ลูกค้าทั่วไป'}` : 'รับลูกค้า Walk-in' }}
        </p>

        <template v-if="step === 1">
          <p class="m-0 mb-2 text-sm font-medium">1. ลูกค้า</p>
          <v-form class="flex gap-2" @submit.prevent="searchCustomer">
            <v-text-field v-model="phone" label="เบอร์โทรเต็ม" type="tel" hide-details />
            <v-btn type="submit" color="primary" class="!h-auto">ค้นหา</v-btn>
          </v-form>
          <v-list v-if="found?.length" class="mt-2">
            <v-list-item v-for="c in found" :key="c.customer_id" :title="c.display_name"
              :subtitle="`${c.phone_masked} · ${c.is_member ? 'สมาชิก' : 'Guest'}`" rounded="lg" @click="chooseCustomer(c)" />
          </v-list>
          <p v-else-if="found" class="m-0 mt-2 text-sm text-light-brown">ไม่พบลูกค้า เพิ่มลูกค้าใหม่ได้ที่เมนู “ลูกค้า”</p>
          <div class="mt-4 flex justify-between gap-2">
            <v-btn variant="text" @click="walkDialog = false">ยกเลิก</v-btn>
            <v-btn variant="tonal" @click="chooseCustomer(null)">ลูกค้าทั่วไป (ไม่ระบุ)</v-btn>
          </div>
        </template>

        <template v-else>
          <p v-if="!addToOrder" class="m-0 mb-3 text-sm">ลูกค้า: <b>{{ customerLabel }}</b></p>
          <p class="m-0 mb-2 text-sm font-medium">บริการ (คนละ 1 รายการ)</p>
          <div v-for="(p, idx) in people" :key="idx" class="flex items-center gap-2">
            <v-select v-model="p.option_id" :items="optionItems" :label="`คนที่ ${idx + 1}`" hide-details class="mb-2" />
            <v-btn v-if="people.length > 1" icon="mdi-close" variant="text" size="small" aria-label="ลบ" @click="people.splice(idx, 1)" />
          </div>
          <v-btn v-if="people.length < 10" variant="text" size="small" prepend-icon="mdi-plus" @click="people.push({ option_id: null })">เพิ่มคน</v-btn>

          <p class="m-0 mb-2 mt-4 text-sm font-medium">เวลาเริ่ม (วันนี้)</p>
          <v-progress-linear v-if="startsLoading" indeterminate color="primary" />
          <div class="grid grid-cols-4 gap-2 sm:grid-cols-6">
            <v-btn v-for="(s, n) in starts" :key="s.starts_at" size="small"
              :color="startAt === s.starts_at ? 'primary' : undefined"
              :variant="startAt === s.starts_at ? 'flat' : 'outlined'" @click="startAt = s.starts_at">
              {{ n === 0 ? `${s.time} เร็วสุด` : s.time }}
            </v-btn>
          </div>
          <p v-if="optionIds.length && optionIds.length === people.length && !startsLoading && !starts.length" class="m-0 text-sm text-light-brown">
            วันนี้ไม่มีเวลาว่างสำหรับบริการนี้
          </p>

          <v-textarea v-if="!addToOrder" v-model="note" class="mt-3" label="หมายเหตุ" rows="2" variant="outlined" />
          <p class="m-0 mt-2 text-right">รวม <b>{{ formatBaht(total) }}</b></p>
          <div class="mt-4 flex justify-end gap-2">
            <v-btn v-if="!addToOrder" variant="text" @click="step = 1">ย้อนกลับ</v-btn>
            <v-btn v-else variant="text" @click="walkDialog = false">ยกเลิก</v-btn>
            <v-btn color="primary" :disabled="!startAt || optionIds.length !== people.length" :loading="saving" @click="submitWalkIn">
              สร้างคิว
            </v-btn>
          </div>
        </template>
      </v-card>
    </v-dialog>
  </div>
</template>
