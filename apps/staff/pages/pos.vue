<script setup lang="ts">
// หน้าร้าน (POS): กะเปิดอัตโนมัติ (migration 031), รับลูกค้า Walk-in, เช็กอินลูกค้าที่จอง, เพิ่มบริการ
// ร้านไม่มีเครื่องพิมพ์: หลังสร้างคิวให้แจ้งเลขคิวที่แสดงบนจอแก่ลูกค้า
import { Banknote, ListOrdered, Plus, Search, UserPlus, X } from '@lucide/vue'
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


const { confirm } = useDialog()
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
watch(() => [board.value?.orders.length, activeBranch.value?.branch_id], loadFinance, { immediate: true })
const invoiceOf = (orderId: string) => finance.value?.invoices.find((i) => i.service_order_id === orderId && i.status !== 'VOID')
const outstanding = computed(() => (finance.value?.invoices ?? []).filter((i) => ['ISSUED', 'PARTIALLY_PAID'].includes(i.status)))

async function payOutTips(t: FinanceBoard['unpaid_cash_tips'][number]) {
  if (!activeBranch.value || !(await confirm({ title: `จ่ายทิปให้ ${t.nickname}?`, description: `จ่ายเงินสด ${formatBaht(Number(t.amount))}`, confirmText: 'จ่ายทิป' }))) return
  try {
    await must(supabase.rpc('pos_pay_out_tips', { p_branch_id: activeBranch.value.branch_id, p_employee_id: t.employee_id }))
    message.value = { type: 'success', text: `จ่ายทิปให้ ${t.nickname} แล้ว` }
    await Promise.all([loadFinance(), load()])
  } catch (e) {
    fail(e)
  }
}

const message = ref<{ type: 'success' | 'error' | 'info'; text: string } | null>(null)
const saving = ref(false)
const fail = (e: unknown, fallback?: string) => (message.value = { type: 'error', text: errorText(e, fallback) })

const orders = computed(() => [...(board.value?.orders ?? [])].reverse())
const activeOrders = computed(() => orders.value.filter((o) => o.status !== 'CANCELLED'))

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
    await goToQueue()
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
    await goToQueue()
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

// สร้างคิว/เช็กอินเสร็จ → ไปหน้าคิวทันที (หน้าคิวแสดงเลขคิวใหม่และไฮไลต์การ์ด)
async function goToQueue() {
  const ids = newQueues.value.map((i) => i.queue_id)
  await navigateTo({ path: '/queue', query: ids.length ? { new: ids.join(',') } : undefined })
}
</script>

<template>
  <div>
    <PageHeader title="หน้าร้าน (POS)" :description="`${activeBranch?.name ?? ''} · รับลูกค้า เช็กอินการจอง และรับเงิน`">
      <template #actions>
        <Button as-child variant="outline"><NuxtLink to="/queue"><ListOrdered /> ดูคิว</NuxtLink></Button>
        <Button size="lg" @click="openWalkIn()"><UserPlus /> รับลูกค้า Walk-in</Button>
      </template>
    </PageHeader>

    <MessageAlert :message="message" class="mb-4" @close="message = null" />
    <Alert v-if="error" variant="destructive" class="mb-4"><AlertDescription>{{ error }}</AlertDescription></Alert>
    <LoadingBar v-if="loading" class="mb-4" />

    <div class="grid gap-6">
      <!-- เลขคิวที่เพิ่งสร้าง -->
      <section v-if="created && newQueues.length" class="rounded-xl border-2 border-primary/40 bg-card p-5" aria-live="polite" aria-labelledby="new-queue-h">
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h2 id="new-queue-h" class="m-0 text-base font-semibold">แจ้งเลขคิวให้ลูกค้า</h2>
            <p class="m-0 text-sm text-muted-foreground">{{ created.customer_name ?? 'ลูกค้าทั่วไป' }}</p>
          </div>
          <Button variant="ghost" size="icon" aria-label="ปิดเลขคิว" @click="created = null"><X /></Button>
        </div>
        <div class="mt-3 flex flex-wrap gap-3">
          <div v-for="i in newQueues" :key="i.queue_id" class="min-w-40 rounded-xl bg-secondary px-5 py-4 text-center">
            <p class="num m-0 text-5xl leading-none font-semibold text-heading">{{ formatQueueNumber(i.queue_number) }}</p>
            <p class="m-0 mt-2 text-[15px] text-heading">{{ i.service_name }} {{ formatDuration(i.duration_minutes) }}</p>
            <p class="m-0 text-sm text-muted-foreground">เริ่มประมาณ <span class="num">{{ bangkokTime(i.planned_starts_at) }}</span></p>
          </div>
        </div>
      </section>

      <!-- ค้างชำระ / ทิป -->
      <SectionCard v-if="finance && (outstanding.length || finance.unpaid_cash_tips.length)" title="ต้องจัดการ" flush>
        <div v-if="outstanding.length" class="border-b border-border px-5 py-4 last:border-0">
          <p class="m-0 mb-2 text-[15px] font-medium text-heading">ค้างชำระ <span class="num text-pending-ink">{{ formatBaht(Number(finance.outstanding)) }}</span></p>
          <div class="flex flex-wrap gap-2">
            <NuxtLink v-for="i in outstanding" :key="i.invoice_id" :to="`/checkout/${i.service_order_id}`"
              class="rounded-lg border border-brand-accent/40 bg-pending-soft px-3 py-1.5 text-sm text-pending-ink no-underline hover:border-brand-accent">
              <span class="num">{{ i.invoice_number }}</span> · {{ i.customer_name ?? 'ลูกค้าทั่วไป' }} · ค้าง <span class="num font-medium">{{ formatBaht(Number(i.balance)) }}</span>
            </NuxtLink>
          </div>
        </div>
        <div v-if="finance.unpaid_cash_tips.length" class="px-5 py-4">
          <p class="m-0 mb-2 text-[15px] font-medium text-heading">ทิปเงินสดที่ยังไม่จ่ายหมอ</p>
          <div class="flex flex-wrap gap-2">
            <Button v-for="t in finance.unpaid_cash_tips" :key="t.employee_id" size="sm" variant="outline" @click="payOutTips(t)">
              จ่าย {{ t.nickname }} <span class="num">{{ formatBaht(Number(t.amount)) }}</span>
            </Button>
          </div>
        </div>
      </SectionCard>

      <div class="grid items-start gap-6 xl:grid-cols-2">
        <!-- รอเช็กอิน -->
        <SectionCard title="ลูกค้าที่จองไว้วันนี้" :description="`รอเช็กอิน ${awaiting.length} ราย`" flush>
          <EmptyState v-if="!awaiting.length" compact title="ไม่มีการจองที่รอเช็กอิน" class="m-5" />
          <ul v-else class="m-0 grid list-none p-0">
            <li v-for="b in awaiting" :key="b.booking_id" class="flex flex-wrap items-center justify-between gap-3 border-b border-border px-5 py-3.5 last:border-0">
              <div class="min-w-0">
                <p class="m-0 font-medium text-heading"><span class="num">{{ bangkokTime(b.starts_at) }}</span> · {{ b.customer_name }}</p>
                <p class="m-0 text-sm text-muted-foreground"><span class="num">{{ b.booking_code }}</span> · <span class="num">{{ b.phone_masked }}</span></p>
                <p class="m-0 text-sm">{{ b.items.map((i) => `${i.service_name} ${formatDuration(i.duration_minutes)}`).join(' · ') }}</p>
              </div>
              <Button :disabled="saving" @click="checkIn(b)">เช็กอิน</Button>
            </li>
          </ul>
        </SectionCard>

        <!-- Order วันนี้ -->
        <SectionCard title="ลูกค้าวันนี้" :description="`${activeOrders.length} ราย`" flush>
          <EmptyState v-if="!activeOrders.length" compact title="ยังไม่มีลูกค้า" class="m-5">
            <Button variant="outline" size="sm" @click="openWalkIn()"><UserPlus /> รับลูกค้า Walk-in</Button>
          </EmptyState>
          <ul v-else class="m-0 grid list-none p-0">
            <li v-for="o in activeOrders" :key="o.order_id" class="flex flex-wrap items-start justify-between gap-3 border-b border-border px-5 py-3.5 last:border-0">
              <div class="min-w-0">
                <p class="m-0 flex flex-wrap items-center gap-2 font-medium text-heading">
                  {{ o.customer_name ?? 'ลูกค้าทั่วไป' }}
                  <Badge variant="neutral">{{ orderChannelLabels[o.channel] }}</Badge>
                  <Badge v-if="o.status === 'COMPLETED'" variant="success">เสร็จแล้ว</Badge>
                </p>
                <p v-for="i in o.items" :key="i.queue_id" class="m-0 text-sm" :class="{ 'text-muted-foreground line-through': i.queue_status === 'CANCELLED' }">
                  คิว <span class="num">{{ formatQueueNumber(i.queue_number) }}</span> · {{ i.service_name }} {{ formatDuration(i.duration_minutes) }}
                  · {{ queueStatusLabels[i.queue_status] }}<span v-if="i.therapist"> · {{ i.therapist.nickname }}</span>
                </p>
              </div>
              <div class="flex flex-col items-end gap-1.5">
                <Badge v-if="invoiceOf(o.order_id)" :variant="invoiceOf(o.order_id)!.status === 'PAID' ? 'success' : 'pending'">{{ invoiceStatusLabels[invoiceOf(o.order_id)!.status] }}</Badge>
                <Button v-if="o.items.some((i) => ['IN_SERVICE', 'COMPLETED'].includes(i.queue_status))" as-child size="sm" :variant="invoiceOf(o.order_id)?.status === 'PAID' ? 'outline' : 'default'">
                  <NuxtLink :to="`/checkout/${o.order_id}`"><Banknote /> {{ invoiceOf(o.order_id)?.status === 'PAID' ? 'ดูการชำระ' : 'ชำระเงิน' }}</NuxtLink>
                </Button>
                <Button size="sm" variant="ghost" @click="openWalkIn(o)"><Plus /> เพิ่มบริการ</Button>
              </div>
            </li>
          </ul>
        </SectionCard>
      </div>
    </div>

    <!-- Walk-in / เพิ่มบริการ -->
    <Dialog v-model:open="walkDialog">
      <DialogContent class="max-h-[90dvh] grid-rows-[auto_minmax(0,1fr)_auto] sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>{{ addToOrder ? `เพิ่มบริการ · ${addToOrder.customer_name ?? 'ลูกค้าทั่วไป'}` : 'รับลูกค้า Walk-in' }}</DialogTitle>
          <DialogDescription>{{ step === 1 ? 'ค้นหาลูกค้าด้วยเบอร์โทร หรือเลือกลูกค้าทั่วไป' : `ลูกค้า: ${customerLabel}` }}</DialogDescription>
        </DialogHeader>

        <div class="-mx-6 grid content-start gap-4 overflow-y-auto px-6">
          <template v-if="step === 1">
            <form class="flex items-end gap-2" @submit.prevent="searchCustomer">
              <TextField v-model="phone" numeric="digits" label="เบอร์โทรเต็ม" type="tel" class="num flex-1" />
              <Button type="submit"><Search /> ค้นหา</Button>
            </form>
            <div v-if="found?.length" class="grid gap-2">
              <button
                v-for="c in found"
                :key="c.customer_id"
                type="button"
                class="flex items-center justify-between gap-3 rounded-lg border border-border px-4 py-3 text-left transition-colors hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
                @click="chooseCustomer(c)"
              >
                <span>
                  <span class="block font-medium text-heading">{{ c.display_name }}</span>
                  <span class="num block text-sm text-muted-foreground">{{ c.phone_masked }}</span>
                </span>
                <Badge :variant="c.is_member ? 'default' : 'neutral'">{{ c.is_member ? 'สมาชิก' : 'Guest' }}</Badge>
              </button>
            </div>
            <EmptyState v-else-if="found" compact title="ไม่พบลูกค้า" description="เพิ่มลูกค้าใหม่ได้ที่เมนู “ลูกค้า” หรือรับเป็นลูกค้าทั่วไป" />
          </template>

          <template v-else>
            <fieldset class="m-0 grid gap-2 border-0 p-0">
              <legend class="mb-1 text-sm font-medium text-heading">บริการ (คนละ 1 รายการ)</legend>
              <div v-for="(p, idx) in people" :key="idx" class="flex items-end gap-2">
                <SelectField v-model="p.option_id" :items="optionItems" :aria-label="`บริการของคนที่ ${idx + 1}`" :placeholder="`คนที่ ${idx + 1}: เลือกบริการ`" class="flex-1" />
                <Button v-if="people.length > 1" variant="ghost" size="icon" :aria-label="`ลบคนที่ ${idx + 1}`" @click="people.splice(idx, 1)"><X /></Button>
              </div>
              <Button v-if="people.length < 10" variant="outline" size="sm" class="w-fit" @click="people.push({ option_id: null })"><UserPlus /> เพิ่มคน</Button>
            </fieldset>

            <div class="grid gap-2">
              <p class="m-0 text-sm font-medium text-heading">เวลาเริ่ม (วันนี้)</p>
              <LoadingBar v-if="startsLoading" />
              <div v-if="starts.length" class="grid grid-cols-3 gap-2 sm:grid-cols-5" role="radiogroup" aria-label="เวลาเริ่ม">
                <button
                  v-for="(s, n) in starts"
                  :key="s.starts_at"
                  type="button"
                  role="radio"
                  :aria-checked="startAt === s.starts_at"
                  class="h-11 rounded-lg border text-[15px] font-medium transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none md:h-10"
                  :class="startAt === s.starts_at ? 'border-primary bg-primary text-primary-foreground' : 'border-border bg-card text-heading hover:bg-muted'"
                  @click="startAt = s.starts_at"
                ><span class="num">{{ s.time }}</span><span v-if="n === 0" class="ml-1 text-[13px] opacity-80">เร็วสุด</span></button>
              </div>
              <p v-else-if="optionIds.length && optionIds.length === people.length && !startsLoading" class="m-0 rounded-lg border border-dashed border-input px-4 py-3 text-[15px] text-muted-foreground">
                วันนี้ไม่มีเวลาว่างสำหรับบริการนี้
              </p>
            </div>

            <TextareaField v-if="!addToOrder" v-model="note" label="หมายเหตุ" rows="2" />
            <div class="flex items-baseline justify-between border-t border-border pt-3">
              <span class="font-medium text-heading">รวม</span>
              <span class="num text-xl font-semibold text-heading">{{ formatBaht(total) }}</span>
            </div>
          </template>
        </div>

        <DialogFooter class="gap-2">
          <template v-if="step === 1">
            <Button variant="outline" @click="walkDialog = false">ยกเลิก</Button>
            <Button variant="secondary" @click="chooseCustomer(null)">ลูกค้าทั่วไป (ไม่ระบุ)</Button>
          </template>
          <template v-else>
            <Button v-if="!addToOrder" variant="outline" @click="step = 1">ย้อนกลับ</Button>
            <Button v-else variant="outline" @click="walkDialog = false">ยกเลิก</Button>
            <Button :disabled="!startAt || optionIds.length !== people.length || saving" @click="submitWalkIn">สร้างคิว</Button>
          </template>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
