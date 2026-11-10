<script setup lang="ts">
// หน้าร้าน (POS) — ออกแบบให้คนที่ไม่ถนัดเทคโนโลยีเข้าใจได้ทันที:
//   หน้าหลักมี 2 ทางเลือกชัด ๆ (รับลูกค้าใหม่ / ลูกค้าที่จองไว้) + รายชื่อลูกค้าวันนี้ (แต่ละคนมีปุ่มหลักปุ่มเดียว)
//   รับลูกค้า = ทำทีละขั้น: 1) ใครมา → 2) เลือกบริการ (การ์ด ไม่ใช่ dropdown) → 3) เลือกเวลา + ยืนยัน → เลขคิว
// กะเปิดอัตโนมัติ (migration 031) · ร้านไม่มีเครื่องพิมพ์: แจ้งเลขคิวที่แสดงบนจอแก่ลูกค้า
import { ArrowLeft, Banknote, CalendarCheck, Check, ChevronRight, Clock, Plus, Search, UserPlus, X } from '@lucide/vue'
import {
  bangkokTime,
  formatBaht,
  formatDuration,
  formatQueueNumber,
  invoiceStatusLabels,
  newIdempotencyKey,
  queueStatusLabels,
  thaiPhoneSchema,
  type AvailableSlot,
  type Database,
  type FinanceBoard,
  type PosOrder,
  type StaffBookingRow,
} from '@ifeew/shared'

const { confirm } = useDialog()
type CatalogRow = Database['public']['Views']['v_public_branch_services']['Row']
type SearchRow = { customer_id: string; display_name: string; phone_masked: string; is_member: boolean }

const supabase = useSupabaseClient()
const { activeBranch, company } = useAccess()
const { board, loading, error, load } = usePosBoard()

const message = ref<{ type: 'success' | 'error' | 'info'; text: string } | null>(null)
const saving = ref(false)
const fail = (e: unknown, fallback?: string) => (message.value = { type: 'error', text: errorText(e, fallback) })

// หน้าจอ: home · bookings (รอเช็กอิน) · walkin (ทีละขั้น) · done (เลขคิว)
const screen = ref<'home' | 'bookings' | 'walkin' | 'done'>('home')
function show(s: typeof screen.value) {
  screen.value = s
  message.value = null
  window.scrollTo({ top: 0 })
}

// ---------------------------------------------------------------------------
// การเงินหน้าร้าน (สถานะบิล, ทิปเงินสดที่ยังไม่จ่าย)
// ---------------------------------------------------------------------------
const finance = ref<FinanceBoard | null>(null)
async function loadFinance() {
  if (!activeBranch.value) return
  const { data } = await supabase.rpc('pos_finance_board', { p_branch_id: activeBranch.value.branch_id })
  finance.value = (data ?? null) as unknown as FinanceBoard | null
}
watch(() => [board.value?.orders.length, activeBranch.value?.branch_id], loadFinance, { immediate: true })
const invoiceOf = (orderId: string) => finance.value?.invoices.find((i) => i.service_order_id === orderId && i.status !== 'VOID')

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

const activeOrders = computed(() => [...(board.value?.orders ?? [])].reverse().filter((o) => o.status !== 'CANCELLED'))
const canPay = (o: PosOrder) => o.items.some((i) => ['IN_SERVICE', 'COMPLETED'].includes(i.queue_status))
const isPaid = (o: PosOrder) => invoiceOf(o.order_id)?.status === 'PAID'

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

// คิวที่เพิ่งสร้าง (แสดงเลขคิวให้แจ้งลูกค้า)
const created = ref<PosOrder | null>(null)
const createdBefore = ref<Set<string>>(new Set())
const newQueues = computed(() =>
  (created.value?.items ?? []).filter((i) => !createdBefore.value.has(i.queue_id) && i.queue_status !== 'CANCELLED'),
)

async function checkIn(b: StaffBookingRow) {
  saving.value = true
  try {
    createdBefore.value = new Set()
    created.value = (await must(supabase.rpc('pos_check_in_booking', { p_booking_id: b.booking_id }))) as unknown as PosOrder
    show('done')
    await load()
  } catch (e) {
    fail(e, 'เช็กอินไม่สำเร็จ')
  } finally {
    saving.value = false
  }
}

// ---------------------------------------------------------------------------
// รับลูกค้า / เพิ่มบริการ — ทีละขั้น
// ---------------------------------------------------------------------------
const addToOrder = ref<PosOrder | null>(null) // != null = เพิ่มบริการให้ลูกค้าเดิม (ข้ามขั้นเลือกลูกค้า)
const step = ref<1 | 2 | 3>(1)
const phone = ref('')
const found = ref<SearchRow[] | null>(null)
const searching = ref(false)
const customerId = ref<string | null>(null)
const customerLabel = ref('ลูกค้าทั่วไป')
const catalog = ref<CatalogRow[]>([])
const picked = ref<string[]>([]) // option_id ต่อคน (คนละ 1 รายการ)
const starts = ref<AvailableSlot[]>([])
const startAt = ref<string | null>(null)
const startsLoading = ref(false)
let idemKey = newIdempotencyKey()

const optionOf = (id: string) => catalog.value.find((c) => c.option_id === id)
// จัดกลุ่ม: หมวดหมู่ → บริการ → ช่วงเวลา (catalog เรียงตามหมวด/บริการ/นาทีมาแล้ว)
const catalogGroups = computed(() => {
  const cats: Array<{ name: string; services: Array<{ service_id: string; name: string; options: CatalogRow[] }> }> = []
  for (const row of catalog.value) {
    let cat = cats.find((c) => c.name === row.category_name)
    if (!cat) cats.push((cat = { name: row.category_name, services: [] }))
    let svc = cat.services.find((s) => s.service_id === row.service_id)
    if (!svc) cat.services.push((svc = { service_id: row.service_id, name: row.name, options: [] }))
    svc.options.push(row)
  }
  return cats
})
const countOf = (id: string) => picked.value.filter((x) => x === id).length
const total = computed(() => picked.value.reduce((sum, id) => sum + Number(optionOf(id)?.price ?? 0), 0))
const steps = computed(() => (addToOrder.value ? ['เลือกบริการ', 'เลือกเวลา'] : ['ลูกค้า', 'เลือกบริการ', 'เลือกเวลา']))
const stepIndex = computed(() => (addToOrder.value ? step.value - 2 : step.value - 1))

async function startWalkIn(order: PosOrder | null = null) {
  addToOrder.value = order
  step.value = order ? 2 : 1
  phone.value = ''
  found.value = null
  customerId.value = null
  customerLabel.value = order?.customer_name ?? 'ลูกค้าทั่วไป'
  picked.value = []
  starts.value = []
  startAt.value = null
  idemKey = newIdempotencyKey()
  show('walkin')
  const { data } = await supabase
    .from('v_public_branch_services')
    .select('*')
    .eq('branch_id', activeBranch.value!.branch_id)
    .order('category_sort_order').order('sort_order').order('duration_minutes')
  catalog.value = (data ?? []) as CatalogRow[]
}

async function searchCustomer() {
  const p = thaiPhoneSchema.safeParse(phone.value)
  if (!p.success) {
    fail(null, 'กรอกเบอร์โทรให้ครบ 10 หลัก')
    return
  }
  searching.value = true
  message.value = null
  try {
    found.value = (await must(supabase.rpc('search_customers_by_phone', {
      p_company_id: company.value!.company_id, p_phone: p.data,
    }))) as SearchRow[]
  } catch (e) {
    fail(e)
  } finally {
    searching.value = false
  }
}

function chooseCustomer(c: SearchRow | null) {
  customerId.value = c?.customer_id ?? null
  customerLabel.value = c ? c.display_name : 'ลูกค้าทั่วไป'
  step.value = 2
}

function removeOne(id: string) {
  const i = picked.value.lastIndexOf(id)
  if (i >= 0) picked.value.splice(i, 1)
}

function back() {
  if (step.value === 3) step.value = 2
  else if (step.value === 2 && !addToOrder.value) step.value = 1
  else show('home')
}

// ขั้นที่ 3: โหลดเวลาว่างของวันนี้ (ตัวแรก = เร็วที่สุด เลือกให้อัตโนมัติ)
async function goToTime() {
  if (!picked.value.length || !activeBranch.value) return
  step.value = 3
  startAt.value = null
  idemKey = newIdempotencyKey()
  startsLoading.value = true
  const { data, error: err } = await supabase.rpc('pos_available_starts', {
    p_branch_id: activeBranch.value.branch_id, p_option_ids: picked.value,
  })
  startsLoading.value = false
  starts.value = err ? [] : ((data ?? []) as unknown as AvailableSlot[])
  startAt.value = starts.value[0]?.starts_at ?? null
}

async function submitWalkIn() {
  if (!startAt.value || !activeBranch.value) return
  saving.value = true
  try {
    createdBefore.value = new Set((addToOrder.value?.items ?? []).map((i) => i.queue_id))
    created.value = addToOrder.value
      ? ((await must(supabase.rpc('pos_add_order_items', {
          p_order_id: addToOrder.value.order_id,
          p_starts_at: startAt.value,
          p_option_ids: picked.value,
          p_idempotency_key: idemKey,
        }))) as unknown as PosOrder)
      : ((await must(supabase.rpc('pos_create_walkin', {
          p_branch_id: activeBranch.value.branch_id,
          p_customer_id: customerId.value,
          p_starts_at: startAt.value,
          p_option_ids: picked.value,
          p_note: null,
          p_idempotency_key: idemKey,
        }))) as unknown as PosOrder)
    show('done')
    await load()
  } catch (e) {
    fail(e, 'สร้างคิวไม่สำเร็จ')
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-4xl">
    <h1 class="sr-only">หน้าร้าน {{ activeBranch?.name }}</h1>
    <MessageAlert :message="message" class="mb-4" @close="message = null" />
    <Alert v-if="error" variant="destructive" class="mb-4"><AlertDescription>{{ error }}</AlertDescription></Alert>
    <LoadingBar v-if="loading" class="mb-4" />

    <!-- ================================ หน้าหลัก ================================ -->
    <div v-if="screen === 'home'" class="grid gap-6">
      <div class="grid gap-3 sm:grid-cols-2">
        <button
          type="button"
          class="flex items-center gap-4 rounded-xl bg-primary p-5 text-left text-primary-foreground shadow-soft transition-colors hover:bg-primary-hover focus-visible:ring-3 focus-visible:ring-ring/60 focus-visible:outline-none"
          @click="startWalkIn()"
        >
          <span class="grid size-11 shrink-0 place-items-center rounded-full bg-white/20"><UserPlus class="size-5" /></span>
          <span class="min-w-0 flex-1">
            <span class="block text-[17px] font-semibold">รับลูกค้าใหม่</span>
            <span class="block text-sm opacity-90">ลูกค้าเดินเข้าร้าน ไม่ได้จอง</span>
          </span>
          <ChevronRight class="size-5 shrink-0 opacity-80" />
        </button>
        <button
          type="button"
          class="flex items-center gap-4 rounded-xl border border-border bg-card p-5 text-left shadow-soft transition-colors hover:border-input hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/60 focus-visible:outline-none"
          @click="show('bookings')"
        >
          <span class="grid size-11 shrink-0 place-items-center rounded-full bg-secondary text-primary"><CalendarCheck class="size-5" /></span>
          <span class="min-w-0 flex-1">
            <span class="block text-[17px] font-semibold text-heading">ลูกค้าที่จองไว้</span>
            <span class="block text-sm text-muted-foreground">รอเช็กอิน <span class="num font-medium text-heading">{{ awaiting.length }}</span> คน</span>
          </span>
          <ChevronRight class="size-5 shrink-0 text-muted-soft" />
        </button>
      </div>

      <!-- ทิปเงินสดที่ยังไม่จ่ายหมอ (แสดงเมื่อมีเท่านั้น) -->
      <div v-if="finance?.unpaid_cash_tips.length" class="flex flex-wrap items-center gap-2 rounded-xl bg-pending-soft px-4 py-3">
        <span class="mr-1 text-[15px] font-medium text-pending-ink">ทิปเงินสดที่ยังไม่จ่ายหมอ:</span>
        <Button v-for="t in finance.unpaid_cash_tips" :key="t.employee_id" size="sm" variant="outline" @click="payOutTips(t)">
          จ่าย {{ t.nickname }} <span class="num">{{ formatBaht(Number(t.amount)) }}</span>
        </Button>
      </div>

      <!-- ลูกค้าวันนี้ -->
      <section aria-labelledby="today-h">
        <h2 id="today-h" class="m-0 mb-3 text-base font-semibold">ลูกค้าวันนี้ <span class="num font-normal text-muted-foreground">{{ activeOrders.length }} คน</span></h2>
        <p v-if="!activeOrders.length" class="m-0 rounded-xl border border-dashed border-input px-4 py-8 text-center text-[15px] text-muted-foreground">
          ยังไม่มีลูกค้า — กด “รับลูกค้าใหม่” เพื่อเริ่ม
        </p>
        <ul v-else class="m-0 grid list-none gap-2 p-0">
          <li v-for="o in activeOrders" :key="o.order_id" class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border bg-card px-4 py-3.5">
            <div class="min-w-0">
              <p class="m-0 flex flex-wrap items-center gap-2 text-[15px] font-semibold text-heading">
                {{ o.customer_name ?? 'ลูกค้าทั่วไป' }}
                <Badge v-if="isPaid(o)" variant="success" dot>จ่ายแล้ว</Badge>
                <Badge v-else-if="invoiceOf(o.order_id)" variant="pending" dot>{{ invoiceStatusLabels[invoiceOf(o.order_id)!.status] }}</Badge>
              </p>
              <p v-for="i in o.items" :key="i.queue_id" class="m-0 text-sm" :class="i.queue_status === 'CANCELLED' ? 'text-muted-foreground line-through' : 'text-foreground'">
                <span class="num font-medium text-heading">คิว {{ formatQueueNumber(i.queue_number) }}</span>
                · {{ i.service_name }} {{ formatDuration(i.duration_minutes) }}
                · <span class="text-muted-foreground">{{ queueStatusLabels[i.queue_status] }}<template v-if="i.therapist"> · {{ i.therapist.nickname }}</template></span>
              </p>
            </div>
            <div class="flex items-center gap-2">
              <Button variant="ghost" size="sm" @click="startWalkIn(o)"><Plus /> เพิ่มบริการ</Button>
              <Button v-if="canPay(o) && !isPaid(o)" as-child size="sm">
                <NuxtLink :to="`/checkout/${o.order_id}`"><Banknote /> รับเงิน</NuxtLink>
              </Button>
              <Button v-else-if="isPaid(o)" as-child size="sm" variant="outline">
                <NuxtLink :to="`/checkout/${o.order_id}`">ดูบิล</NuxtLink>
              </Button>
            </div>
          </li>
        </ul>
      </section>
    </div>

    <!-- ============================ ลูกค้าที่จองไว้ ============================ -->
    <div v-else-if="screen === 'bookings'" class="grid gap-4">
      <div class="flex items-center gap-2">
        <Button variant="ghost" size="icon" aria-label="กลับ" @click="show('home')"><ArrowLeft class="size-5" /></Button>
        <h2 class="m-0 text-lg font-semibold">ลูกค้าที่จองไว้วันนี้</h2>
      </div>
      <p v-if="!awaiting.length" class="m-0 rounded-xl border border-dashed border-input px-4 py-8 text-center text-[15px] text-muted-foreground">
        ไม่มีลูกค้าที่รอเช็กอิน
      </p>
      <ul v-else class="m-0 grid list-none gap-2 p-0">
        <li v-for="b in awaiting" :key="b.booking_id" class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border bg-card px-4 py-3.5">
          <div class="flex min-w-0 items-center gap-4">
            <span class="num shrink-0 rounded-lg bg-secondary px-3 py-1.5 text-lg font-semibold text-heading">{{ bangkokTime(b.starts_at) }}</span>
            <div class="min-w-0">
              <p class="m-0 text-[15px] font-semibold text-heading">{{ b.customer_name }}</p>
              <p class="m-0 text-sm text-muted-foreground">{{ b.items.map((i) => `${i.service_name} ${formatDuration(i.duration_minutes)}`).join(' · ') }}</p>
            </div>
          </div>
          <Button :disabled="saving" @click="checkIn(b)"><Check /> เช็กอิน</Button>
        </li>
      </ul>
    </div>

    <!-- ========================== รับลูกค้า (ทีละขั้น) ========================== -->
    <div v-else-if="screen === 'walkin'" class="grid gap-5 pb-24">
      <div class="grid gap-3">
        <div class="flex items-center gap-2">
          <Button variant="ghost" size="icon" :aria-label="stepIndex === 0 ? 'ยกเลิก' : 'ย้อนกลับ'" @click="back">
            <X v-if="stepIndex === 0" class="size-5" /><ArrowLeft v-else class="size-5" />
          </Button>
          <h2 class="m-0 text-lg font-semibold">{{ addToOrder ? `เพิ่มบริการ · ${customerLabel}` : 'รับลูกค้าใหม่' }}</h2>
        </div>
        <!-- ตัวบอกขั้น -->
        <ol class="m-0 flex list-none gap-2 p-0" :aria-label="`ขั้นที่ ${stepIndex + 1} จาก ${steps.length}`">
          <li v-for="(t, i) in steps" :key="t" class="flex flex-1 flex-col gap-1">
            <span class="h-1.5 rounded-full" :class="i <= stepIndex ? 'bg-primary' : 'bg-secondary'" />
            <span class="text-[13px]" :class="i === stepIndex ? 'font-semibold text-heading' : 'text-muted-foreground'">{{ i + 1 }}. {{ t }}</span>
          </li>
        </ol>
      </div>

      <!-- ขั้นที่ 1: ลูกค้า -->
      <template v-if="step === 1">
        <button
          type="button"
          class="flex items-center gap-4 rounded-xl bg-primary p-5 text-left text-primary-foreground shadow-soft transition-colors hover:bg-primary-hover focus-visible:ring-3 focus-visible:ring-ring/60 focus-visible:outline-none"
          @click="chooseCustomer(null)"
        >
          <span class="min-w-0 flex-1">
            <span class="block text-[17px] font-semibold">ลูกค้าทั่วไป</span>
            <span class="block text-sm opacity-90">ไม่ต้องกรอกข้อมูล ไปเลือกบริการเลย</span>
          </span>
          <ChevronRight class="size-5 shrink-0" />
        </button>

        <div class="grid gap-3 rounded-xl border border-border bg-card p-4">
          <p class="m-0 text-[15px] font-medium text-heading">หรือ ลูกค้าเก่า — ค้นด้วยเบอร์โทร</p>
          <form class="flex gap-2" @submit.prevent="searchCustomer">
            <Input v-model="phone" numeric="digits" type="tel" inputmode="tel" maxlength="10" placeholder="0812345678" aria-label="เบอร์โทรลูกค้า" class="num flex-1" />
            <Button type="submit" variant="secondary" :disabled="searching"><Search /> ค้นหา</Button>
          </form>
          <button
            v-for="c in found ?? []"
            :key="c.customer_id"
            type="button"
            class="flex items-center justify-between gap-3 rounded-lg border border-border px-4 py-3 text-left transition-colors hover:border-primary hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/60 focus-visible:outline-none"
            @click="chooseCustomer(c)"
          >
            <span>
              <span class="block text-[15px] font-medium text-heading">{{ c.display_name }}</span>
              <span class="num block text-sm text-muted-foreground">{{ c.phone_masked }}</span>
            </span>
            <span class="flex items-center gap-1 text-sm font-medium text-primary">เลือก <ChevronRight class="size-4" /></span>
          </button>
          <p v-if="found && !found.length" class="m-0 text-sm text-muted-foreground">ไม่พบเบอร์นี้ — รับเป็น “ลูกค้าทั่วไป” ได้เลย</p>
        </div>
      </template>

      <!-- ขั้นที่ 2: เลือกบริการ -->
      <template v-else-if="step === 2">
        <p class="m-0 text-[15px] text-muted-foreground">กดเวลาที่ลูกค้าต้องการ · มากันหลายคน กดซ้ำได้ (1 ครั้ง = 1 คน)</p>
        <p v-if="!catalog.length" class="m-0 rounded-xl border border-dashed border-input px-4 py-8 text-center text-[15px] text-muted-foreground">ยังไม่มีบริการที่เปิดขายในสาขานี้</p>

        <!-- หมวดหมู่ → บริการ (การ์ด) → เวลา/ราคา (ปุ่ม) -->
        <section v-for="cat in catalogGroups" :key="cat.name" class="grid gap-2" :aria-label="cat.name">
          <h3 class="m-0 flex items-center gap-2 text-[13px] font-semibold tracking-wide text-muted-foreground">
            {{ cat.name }} <span class="h-px flex-1 bg-border" aria-hidden="true" />
          </h3>
          <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <div
              v-for="s in cat.services"
              :key="s.service_id"
              class="grid gap-3 rounded-xl border bg-card p-4 transition-colors"
              :class="s.options.some((o) => countOf(o.option_id)) ? 'border-primary ring-1 ring-primary/30' : 'border-border'"
            >
              <p class="m-0 text-base font-semibold text-heading">{{ s.name }}</p>
              <!-- แถวละ 1 ตัวเลือกเวลา: ซ้าย = เวลา/ราคา · ขวา = "+ เพิ่ม" หรือตัวนับ − n คน + -->
              <ul class="m-0 grid list-none gap-1.5 p-0">
                <li
                  v-for="o in s.options"
                  :key="o.option_id"
                  class="flex min-h-12 items-center justify-between gap-3 rounded-lg px-3 py-1.5 transition-colors"
                  :class="countOf(o.option_id) ? 'bg-secondary' : 'bg-muted/50'"
                >
                  <span class="flex items-baseline gap-3">
                    <span class="flex items-center gap-1.5 text-[15px] font-medium text-heading"><Clock class="size-4 self-center text-brand-accent" /> {{ formatDuration(o.duration_minutes) }}</span>
                    <span class="num text-[15px] font-semibold text-heading">{{ formatBaht(Number(o.price)) }}</span>
                  </span>

                  <Button
                    v-if="!countOf(o.option_id)"
                    variant="outline"
                    size="sm"
                    class="bg-card"
                    :disabled="picked.length >= 10"
                    :aria-label="`เพิ่ม ${s.name} ${formatDuration(o.duration_minutes)}`"
                    @click="picked.push(o.option_id)"
                  ><Plus /> เพิ่ม</Button>
                  <div v-else class="flex items-center gap-1" role="group" :aria-label="`จำนวน ${s.name} ${formatDuration(o.duration_minutes)}`">
                    <Button variant="outline" size="icon-sm" class="bg-card text-lg" aria-label="ลด 1 คน" @click="removeOne(o.option_id)">−</Button>
                    <span class="min-w-14 text-center text-[15px] text-heading"><span class="num font-semibold">{{ countOf(o.option_id) }}</span> คน</span>
                    <Button size="icon-sm" aria-label="เพิ่ม 1 คน" :disabled="picked.length >= 10" @click="picked.push(o.option_id)"><Plus /></Button>
                  </div>
                </li>
              </ul>
            </div>
          </div>
        </section>
      </template>

      <!-- ขั้นที่ 3: เวลา -->
      <template v-else>
        <div class="grid gap-1 rounded-xl border border-border bg-card px-4 py-3 text-[15px]">
          <p class="m-0 text-muted-foreground">ลูกค้า: <span class="font-medium text-heading">{{ customerLabel }}</span></p>
          <p v-for="(id, idx) in picked" :key="idx" class="m-0 text-heading">
            คนที่ {{ idx + 1 }} · {{ optionOf(id)?.name }} {{ formatDuration(optionOf(id)?.duration_minutes ?? 0) }}
          </p>
        </div>
        <div class="grid gap-2">
          <p class="m-0 text-[15px] font-medium text-heading">เริ่มกี่โมง <span class="font-normal text-muted-foreground">(เลือกเวลาที่เร็วที่สุดไว้ให้แล้ว)</span></p>
          <LoadingBar v-if="startsLoading" />
          <div v-if="starts.length" class="grid grid-cols-3 gap-2 sm:grid-cols-5" role="radiogroup" aria-label="เวลาเริ่ม">
            <button
              v-for="s in starts"
              :key="s.starts_at"
              type="button"
              role="radio"
              :aria-checked="startAt === s.starts_at"
              class="h-11 rounded-lg border text-[15px] font-medium transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
              :class="startAt === s.starts_at ? 'border-primary bg-primary text-primary-foreground' : 'border-border bg-card text-heading hover:bg-muted'"
              @click="startAt = s.starts_at"
            ><span class="num">{{ s.time }}</span></button>
          </div>
          <p v-else-if="!startsLoading" class="m-0 rounded-xl border border-dashed border-input px-4 py-6 text-center text-[15px] text-muted-foreground">
            วันนี้ไม่มีเวลาว่างสำหรับบริการนี้แล้ว
          </p>
        </div>
      </template>

      <!-- แถบล่าง: ยอดรวม + ปุ่มไปต่อ (ปุ่มหลักปุ่มเดียว) -->
      <div v-if="step > 1" class="fixed inset-x-0 bottom-[calc(4.25rem+env(safe-area-inset-bottom))] z-30 border-t border-border bg-background/95 px-4 py-3 backdrop-blur-sm md:bottom-0 md:pl-[calc(76px+1.5rem)] xl:pl-[calc(var(--sidebar-width)+0.5rem)]">
        <div class="mx-auto flex max-w-4xl items-center justify-between gap-3">
          <span class="text-[15px] text-muted-foreground">
            <template v-if="picked.length"><span class="num text-heading">{{ picked.length }}</span> คน · รวม <span class="num text-lg font-semibold text-heading">{{ formatBaht(total) }}</span></template>
            <template v-else>ยังไม่ได้เลือกบริการ</template>
          </span>
          <Button v-if="step === 2" size="lg" :disabled="!picked.length" @click="goToTime">ถัดไป <ChevronRight /></Button>
          <Button v-else size="lg" :disabled="!startAt || saving" @click="submitWalkIn"><Check /> {{ saving ? 'กำลังสร้างคิว…' : 'ยืนยัน สร้างคิว' }}</Button>
        </div>
      </div>
    </div>

    <!-- =============================== เลขคิว =============================== -->
    <div v-else class="grid justify-items-center gap-5 py-8 text-center" aria-live="polite">
      <span class="grid size-14 place-items-center rounded-full bg-success-soft text-success-ink"><Check class="size-8" /></span>
      <div>
        <h2 class="m-0 text-xl font-semibold">สร้างคิวแล้ว</h2>
        <p class="m-0 text-[15px] text-muted-foreground">แจ้งเลขคิวให้ลูกค้า · {{ created?.customer_name ?? 'ลูกค้าทั่วไป' }}</p>
      </div>
      <div class="flex flex-wrap justify-center gap-3">
        <div v-for="i in newQueues" :key="i.queue_id" class="min-w-44 rounded-xl border border-border bg-card px-6 py-4 shadow-soft">
          <p class="num m-0 text-5xl leading-none font-semibold text-heading">{{ formatQueueNumber(i.queue_number) }}</p>
          <p class="m-0 mt-2 text-[15px] text-heading">{{ i.service_name }} {{ formatDuration(i.duration_minutes) }}</p>
          <p class="m-0 text-sm text-muted-foreground">เริ่มประมาณ <span class="num">{{ bangkokTime(i.planned_starts_at) }}</span></p>
        </div>
      </div>
      <div class="flex flex-wrap justify-center gap-2">
        <Button size="lg" @click="startWalkIn()"><UserPlus /> รับลูกค้าคนต่อไป</Button>
        <Button size="lg" variant="outline" @click="show('home')">กลับหน้าหลัก</Button>
      </div>
    </div>
  </div>
</template>
