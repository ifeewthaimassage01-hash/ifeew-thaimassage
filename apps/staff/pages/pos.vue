<script setup lang="ts">
// หน้าร้าน (POS) — ออกแบบให้คนที่ไม่ถนัดเทคโนโลยีเข้าใจได้ทันที:
//   หน้าหลักมี 2 ทางเลือกชัด ๆ (รับลูกค้าใหม่ / ลูกค้าที่จองไว้) + รายชื่อลูกค้าวันนี้ (แต่ละคนมีปุ่มหลักปุ่มเดียว)
//   รับลูกค้า = ทำทีละขั้น: 1) ใครมา → 2) เลือกบริการ (การ์ด ไม่ใช่ dropdown) → 3) เลือกเวลา + ยืนยัน → เลขคิว
// กะเปิดอัตโนมัติ (migration 031) · ร้านไม่มีเครื่องพิมพ์: แจ้งเลขคิวที่แสดงบนจอแก่ลูกค้า
import { ArrowLeft, Banknote, CalendarCheck, Check, ChevronRight, CircleCheck, Clock, Plus, UserPlus, X } from '@lucide/vue'
import {
  bangkokTime,
  formatBaht,
  formatDuration,
  formatQueueNumber,
  newIdempotencyKey,
  type AvailableSlot,
  type Database,
  type FinanceBoard,
  type PosOrder,
  type StaffBookingRow,
} from '@ifeew/shared'

const { confirm } = useDialog()
type CatalogRow = Database['public']['Views']['v_public_branch_services']['Row']

const supabase = useSupabaseClient()
const { activeBranch, company } = useAccess()
const { board, loading, error, load } = usePosBoard()

const message = ref<{ type: 'success' | 'error' | 'info' | 'warning'; text: string } | null>(null)
const saving = ref(false)
const fail = (e: unknown, fallback?: string) => (message.value = { type: 'error', text: errorText(e, fallback) })

// หน้าจอ: home · bookings (รอเช็กอิน) · walkin (ทีละขั้น) · done (เลขคิว)
const screen = ref<'home' | 'bookings' | 'walkin' | 'done'>('home')
function show(s: typeof screen.value) {
  screen.value = s
  message.value = null
  window.scrollTo({ top: 0 })
  if (s === 'done') startCountdown()
  else stopCountdown()
}

// หน้าเลขคิว: แสดง 3 วินาทีแล้วไปหน้าคิวเอง (ไฮไลต์คิวใหม่) — กด "รับลูกค้าคนต่อไป" เพื่อยกเลิกการไป
const countdown = ref(0)
let countdownTimer: ReturnType<typeof setInterval> | null = null
function stopCountdown() {
  if (countdownTimer) clearInterval(countdownTimer)
  countdownTimer = null
  countdown.value = 0
}
function startCountdown() {
  stopCountdown()
  countdown.value = 3
  countdownTimer = setInterval(() => {
    countdown.value--
    if (countdown.value <= 0) goToQueue()
  }, 1000)
}
async function goToQueue() {
  const ids = newQueues.value.map((i) => i.queue_id)
  stopCountdown()
  await navigateTo({ path: '/queue', query: ids.length ? { new: ids.join(',') } : undefined })
}
onBeforeUnmount(stopCountdown)

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
// รายการที่ยังนับ (ไม่รวมคิวที่ยกเลิก) · ยอด = ยอดค้างในบิล หรือราคารวมถ้ายังไม่ออกบิล
const liveItems = (o: PosOrder) => o.items.filter((i) => i.queue_status !== 'CANCELLED')
const dueOf = (o: PosOrder) => {
  const inv = invoiceOf(o.order_id)
  return inv ? Number(inv.balance) : liveItems(o).reduce((s, i) => s + Number(i.unit_price), 0)
}
const unpaidOrders = computed(() => activeOrders.value.filter((o) => !isPaid(o) && liveItems(o).length))
const paidOrders = computed(() => activeOrders.value.filter((o) => isPaid(o)))
const itemChip = (i: PosOrder['items'][number]) =>
  i.queue_status === 'IN_SERVICE'
    ? { label: 'กำลังนวด', cls: 'bg-success-soft text-success-ink' }
    : i.queue_status === 'COMPLETED'
      ? { label: 'เสร็จแล้ว', cls: 'bg-secondary text-heading' }
      : { label: 'รอคิว', cls: 'bg-pending-soft text-pending-ink' }

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

// กด "เช็กอิน" → ขั้น "เลือกหมอ" ก่อน (เหมือนรับลูกค้าหน้าร้าน) · ยังไม่บันทึกอะไร
//   กดยืนยันด้านล่าง = เช็กอินจริง (สร้างคิว) แล้วเริ่มนวดคิวที่เลือกหมอไว้
//   ย้อนกลับ = ไม่เกิดอะไรขึ้น การจองยังรอเช็กอินอยู่
const checkinBooking = ref<StaffBookingRow | null>(null)
const checkinMode = computed(() => !!checkinBooking.value)

async function checkIn(b: StaffBookingRow) {
  if (!therapists.value.length) {
    // สาขาไม่มีหมอในระบบ: เช็กอินเลยเหมือนเดิม
    checkinBooking.value = b
    assigns.value = b.items.map(() => ({ kind: 'none', employeeId: null, name: '', fuel: false }))
    await finishCheckin()
    return
  }
  addToOrder.value = null
  customerLabel.value = b.customer_name
  checkinBooking.value = b
  assigns.value = b.items.map(() => ({ kind: 'none', employeeId: null, name: '', fuel: false }))
  step.value = 4
  show('walkin')
  await loadFuelSetting()
}

// ---------------------------------------------------------------------------
// รับลูกค้า / เพิ่มบริการ — ทีละขั้น
// ---------------------------------------------------------------------------
const addToOrder = ref<PosOrder | null>(null) // != null = เพิ่มบริการให้ลูกค้าเดิม (ข้ามขั้นเลือกลูกค้า)
const step = ref<1 | 2 | 3 | 4>(1)
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
const steps = computed(() => (checkinMode.value ? ['เลือกหมอ'] : ['เลือกบริการ', 'เลือกเวลา', 'เลือกหมอ']))
const stepIndex = computed(() => (checkinMode.value ? 0 : step.value - 2))
/** บริการของคนที่ idx (รับหน้าร้าน = ตัวเลือกที่กด · เช็กอิน = คิวที่สร้างจากการจอง) */
const personService = (idx: number) => {
  if (checkinMode.value) {
    const it = checkinBooking.value?.items[idx]
    return it ? `${it.service_name} ${formatDuration(it.duration_minutes)}` : ''
  }
  const o = optionOf(picked.value[idx]!)
  return o ? `${o.name} ${formatDuration(o.duration_minutes ?? 0)}` : ''
}

// ---------------------------------------------------------------------------
// ขั้นที่ 4: เลือกหมอต่อคน (ลูกค้าหน้าร้าน และลูกค้าจองหลังกดเช็กอิน)
//   เลือกหมอ = สร้างคิวแล้วเริ่มนวดทันที (queue_call_start เหมือนกด "เริ่มนวด" ในหน้าคิว)
//   "เลือกทีหลัง" = คิวรอเรียกตามปกติ
// ---------------------------------------------------------------------------
// none = ยังไม่ได้เลือก (ทำเหมือน later: คิวรอเรียกในหน้าคิว) · later = กด "เลือกหมอทีหลัง" เอง
type Assign = { kind: 'none' | 'later' | 'staff' | 'freelance'; employeeId: string | null; name: string; fuel: boolean }
const starting = (a: Assign) => a.kind === 'staff' || a.kind === 'freelance'
const assigns = ref<Assign[]>([])
const fuelSetting = ref(0)
const therapists = computed(() => board.value?.therapists ?? [])
const takenBy = (employeeId: string, idx: number) =>
  assigns.value.some((a, j) => j !== idx && a.kind === 'staff' && a.employeeId === employeeId)
type Therapist = (typeof therapists.value)[number]
/** สถานะของหมอบนการ์ด: ข้อความ + สีจุด · unavailable = กดไม่ได้ */
function therapistState(t: Therapist, idx: number) {
  if (t.busy_queue_number) return { text: `มีคิว ${formatQueueNumber(t.busy_queue_number)}`, dot: 'bg-muted-soft', unavailable: true }
  if (takenBy(t.employee_id, idx)) return { text: 'เลือกให้คนอื่นแล้ว', dot: 'bg-muted-soft', unavailable: true }
  if (t.on_shift) return { text: 'เข้างานแล้ว', dot: 'bg-success', unavailable: false }
  return { text: 'ยังไม่เช็คชื่อ', dot: 'bg-brand-accent', unavailable: false }
}
const isPicked = (a: Assign, t: Therapist) => a.kind === 'staff' && a.employeeId === t.employee_id
function chooseTherapist(idx: number, kind: Assign['kind'], employeeId: string | null = null) {
  const a = assigns.value[idx]!
  a.kind = kind
  a.employeeId = employeeId
  if (kind !== 'freelance') a.fuel = false
}
const assignsReady = computed(() => assigns.value.every((a) => a.kind !== 'freelance' || a.name.trim().length > 0))
async function loadFuelSetting() {
  if (!company.value) return
  const { data } = await supabase.from('company_settings').select('freelance_fuel_amount').eq('company_id', company.value.company_id).maybeSingle()
  fuelSetting.value = Number(data?.freelance_fuel_amount ?? 0)
}
async function goToTherapist() {
  if (!startAt.value) return
  step.value = 4
  assigns.value = picked.value.map(() => ({ kind: 'none', employeeId: null, name: '', fuel: false }))
  await loadFuelSetting()
}

// เช็กอิน: บันทึกเช็กอิน (สร้างคิว) → เริ่มนวดคิวที่เลือกหมอไว้ → หน้าเลขคิว
async function finishCheckin() {
  const b = checkinBooking.value
  if (!b) return
  saving.value = true
  try {
    createdBefore.value = new Set()
    created.value = (await must(supabase.rpc('pos_check_in_booking', { p_booking_id: b.booking_id }))) as unknown as PosOrder
    // คิวเรียงตามลำดับรายการในการจอง (คนที่ 1, 2, …)
    const fresh = created.value.items
      .filter((i) => i.queue_status !== 'CANCELLED')
      .sort((x, y) => x.queue_number - y.queue_number)
    let failed: string[] = []
    if (assigns.value.some(starting)) {
      failed = await startAssigned(fresh)
    }
    await load()
    created.value = board.value?.orders.find((o) => o.order_id === created.value?.order_id) ?? created.value
    checkinBooking.value = null
    show('done')
    if (failed.length) {
      message.value = { type: 'warning', text: `เริ่มนวดไม่สำเร็จ ยังรอเรียกอยู่ — เลือกหมอในหน้าคิว (${failed.join(' · ')})` }
    }
  } catch (e) {
    fail(e, 'เช็กอินไม่สำเร็จ')
  } finally {
    saving.value = false
  }
}

// เริ่มนวดคิวที่เลือกหมอไว้ (หลังสร้างคิวแล้ว) — ไม่สำเร็จ = คิวยังรอเรียก ให้เลือกหมอในหน้าคิว
async function startAssigned(items: PosOrder['items']) {
  const failed: string[] = []
  for (const [idx, a] of assigns.value.entries()) {
    const q = items[idx]
    if (!q || !starting(a)) continue
    const { error: err } = await supabase.rpc('queue_call_start', {
      p_queue_id: q.queue_id,
      p_employee_id: a.kind === 'staff' ? a.employeeId : null,
      p_confirm_off_shift: true,
      p_freelance_name: a.kind === 'freelance' ? a.name.trim() : null,
      p_with_fuel: a.kind === 'freelance' && a.fuel,
    })
    if (err) failed.push(`คิว ${formatQueueNumber(q.queue_number)}: ${errorText(err)}`)
  }
  return failed
}

async function startWalkIn(order: PosOrder | null = null) {
  checkinBooking.value = null
  addToOrder.value = order
  step.value = 2
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

function removeOne(id: string) {
  const i = picked.value.lastIndexOf(id)
  if (i >= 0) picked.value.splice(i, 1)
}

function back() {
  if (checkinMode.value) {
    // ยังไม่ได้เช็กอิน: กลับไปรายชื่อลูกค้าที่จองไว้ การจองยังอยู่
    checkinBooking.value = null
    show('bookings')
  }
  else if (step.value === 4) step.value = 3
  else if (step.value === 3) step.value = 2
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
          p_customer_id: null, // ลูกค้าหน้าร้าน = ลูกค้าทั่วไป
          p_starts_at: startAt.value,
          p_option_ids: picked.value,
          p_note: null,
          p_idempotency_key: idemKey,
        }))) as unknown as PosOrder)
    // คิวใหม่เรียงตามลำดับที่เลือก (คนที่ 1, 2, …) → เริ่มนวดตามหมอที่เลือกไว้
    const fresh = created.value.items
      .filter((i) => !createdBefore.value.has(i.queue_id) && i.queue_status !== 'CANCELLED')
      .sort((a, b) => a.queue_number - b.queue_number)
    let failed: string[] = []
    if (assigns.value.some(starting)) {
      failed = await startAssigned(fresh)
      await load()
      created.value = board.value?.orders.find((o) => o.order_id === created.value!.order_id) ?? created.value
    }
    show('done')
    if (failed.length) {
      message.value = { type: 'warning', text: `เริ่มนวดไม่สำเร็จ ยังรอเรียกอยู่ — เลือกหมอในหน้าคิว (${failed.join(' · ')})` }
    }
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
    <PageHeader v-if="screen === 'home'" title="หน้าร้าน" description="กด “รับลูกค้าใหม่” เมื่อลูกค้าเดินเข้าร้าน หรือ “ลูกค้าที่จองไว้” เพื่อเช็กอิน" />
    <h1 v-else class="sr-only">หน้าร้าน {{ activeBranch?.name }}</h1>
    <PendingSlipBanner v-if="screen === 'home'" />
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
            <span class="block text-title font-semibold">รับลูกค้าใหม่</span>
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
            <span class="block text-title font-semibold text-heading">ลูกค้าที่จองไว้</span>
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
      <section aria-labelledby="today-h" class="grid gap-3">
        <h2 id="today-h" class="m-0 text-base font-semibold">ลูกค้าวันนี้ <span class="num font-normal text-muted-foreground">{{ activeOrders.length }} กลุ่ม</span></h2>
        <p v-if="!activeOrders.length" class="m-0 rounded-xl border border-dashed border-input px-4 py-8 text-center text-[15px] text-muted-foreground">
          ยังไม่มีลูกค้า — กด “รับลูกค้าใหม่” เพื่อเริ่ม
        </p>

        <!-- ยังไม่จ่าย: การ์ดเต็ม (หัว = ชื่อ+ยอด · กลาง = ตารางคิว · ล่าง = ปุ่มตำแหน่งเดิมเสมอ) -->
        <article v-for="o in unpaidOrders" :key="o.order_id" class="overflow-hidden rounded-xl border border-border bg-card shadow-soft">
          <header class="flex items-baseline justify-between gap-3 px-4 pt-3.5 pb-2">
            <p class="m-0 min-w-0 truncate text-[15px] font-semibold text-heading">
              {{ o.customer_name ?? 'ลูกค้าทั่วไป' }}
              <span class="font-normal text-muted-foreground">· {{ liveItems(o).length }} คน</span>
            </p>
            <p class="num m-0 shrink-0 text-[15px] font-semibold text-heading">{{ formatBaht(dueOf(o)) }}</p>
          </header>
          <ul class="m-0 grid list-none px-4 pb-2">
            <li v-for="i in liveItems(o)" :key="i.queue_id" class="grid grid-cols-[3.25rem_minmax(0,1fr)_auto] items-center gap-2 border-t border-border/60 py-2 text-sm">
              <span class="num font-semibold text-heading">{{ formatQueueNumber(i.queue_number) }}</span>
              <span class="min-w-0 truncate text-foreground">
                {{ i.service_name }} {{ formatDuration(i.duration_minutes) }}<span v-if="i.therapist" class="text-muted-foreground"> · {{ i.therapist.nickname }}</span>
              </span>
              <span class="rounded-full px-2 py-0.5 text-[13px] font-medium" :class="itemChip(i).cls">{{ itemChip(i).label }}</span>
            </li>
          </ul>
          <footer class="flex items-center justify-between gap-2 border-t border-border bg-muted/40 px-3 py-2">
            <Button variant="ghost" size="sm" @click="startWalkIn(o)"><Plus /> เพิ่มบริการ</Button>
            <Button v-if="canPay(o)" as-child size="sm">
              <NuxtLink :to="`/checkout/${o.order_id}`"><Banknote /> รับเงิน</NuxtLink>
            </Button>
            <span v-else class="px-2 text-sm text-muted-foreground">รับเงินได้เมื่อเริ่มนวด</span>
          </footer>
        </article>

        <!-- จ่ายแล้ว: แถวสั้น -->
        <div v-if="paidOrders.length" class="overflow-hidden rounded-xl border border-border bg-card">
          <p class="m-0 border-b border-border bg-muted/40 px-4 py-2 text-sm font-medium text-muted-foreground">จ่ายแล้ว · <span class="num">{{ paidOrders.length }}</span> กลุ่ม</p>
          <NuxtLink
            v-for="o in paidOrders"
            :key="o.order_id"
            :to="`/checkout/${o.order_id}`"
            class="flex items-center gap-3 border-b border-border px-4 py-2.5 text-sm text-foreground no-underline last:border-0 hover:bg-muted"
          >
            <CircleCheck class="size-4 shrink-0 text-success-ink" />
            <span class="min-w-0 flex-1 truncate">
              <span class="font-medium text-heading">{{ o.customer_name ?? 'ลูกค้าทั่วไป' }}</span>
              <span class="num text-muted-foreground"> · คิว {{ liveItems(o).map((i) => formatQueueNumber(i.queue_number)).join(', ') }}</span>
            </span>
            <span class="num shrink-0 font-medium text-heading">{{ formatBaht(Number(invoiceOf(o.order_id)?.total ?? dueOf(o))) }}</span>
            <ChevronRight class="size-4 shrink-0 text-muted-soft" />
          </NuxtLink>
        </div>
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
          <Button variant="ghost" size="icon" :aria-label="checkinMode ? 'ย้อนกลับ' : stepIndex === 0 ? 'ยกเลิก' : 'ย้อนกลับ'" @click="back">
            <X v-if="stepIndex === 0 && !checkinMode" class="size-5" /><ArrowLeft v-else class="size-5" />
          </Button>
          <h2 class="m-0 text-lg font-semibold">{{ checkinMode ? `เช็กอิน · ${customerLabel}` : addToOrder ? `เพิ่มบริการ · ${customerLabel}` : 'รับลูกค้าใหม่' }}</h2>
        </div>
        <!-- ตัวบอกขั้น -->
        <ol v-if="!checkinMode" class="m-0 flex list-none gap-2 p-0" :aria-label="`ขั้นที่ ${stepIndex + 1} จาก ${steps.length}`">
          <li v-for="(t, i) in steps" :key="t" class="flex flex-1 flex-col gap-1">
            <span class="h-1.5 rounded-full" :class="i <= stepIndex ? 'bg-primary' : 'bg-secondary'" />
            <span class="text-[13px]" :class="i === stepIndex ? 'font-semibold text-heading' : 'text-muted-foreground'">{{ i + 1 }}. {{ t }}</span>
          </li>
        </ol>
      </div>

      <!-- ขั้นที่ 2: เลือกบริการ -->
      <template v-if="step === 2">
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
                  class="grid min-h-12 grid-cols-[5rem_minmax(0,1fr)_auto] items-center gap-3 rounded-lg px-3 py-1.5 transition-colors"
                  :class="countOf(o.option_id) ? 'bg-secondary' : 'bg-muted/50'"
                >
                  <!-- คอลัมน์: เวลา (กว้างคงที่) | ราคา (ชิดขวา ตัวเลขตรงหลักกัน) | ปุ่ม -->
                  <span class="flex items-center gap-1.5 text-[15px] leading-none font-medium text-heading">
                    <Clock class="size-4 shrink-0 text-brand-accent" /> {{ formatDuration(o.duration_minutes) }}
                  </span>
                  <span class="num text-right text-[15px] leading-none font-semibold text-heading tabular-nums">{{ formatBaht(Number(o.price)) }}</span>

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

      <!-- ขั้นที่ 4: เลือกหมอ (ต่อคน) -->
      <template v-else-if="step === 4">
        <p class="m-0 text-[15px] text-muted-foreground">
          เลือกหมอให้แต่ละคน — <span class="font-medium text-heading">เลือกหมอแล้วจะเริ่มนวดทันที</span> ถ้าหมอยังไม่ว่าง กด “เลือกหมอทีหลัง” แล้วไปเลือกในหน้าคิว
        </p>
        <section v-for="(a, idx) in assigns" :key="idx" class="grid gap-3 rounded-xl border border-border bg-card p-4" :aria-label="`หมอของคนที่ ${idx + 1}`">
          <p class="m-0 text-[15px] font-semibold text-heading">
            คนที่ {{ idx + 1 }} <span class="font-normal text-muted-foreground">· {{ personService(idx) }}</span>
          </p>
          <div class="grid gap-3" role="radiogroup" :aria-label="`หมอของคนที่ ${idx + 1}`">
            <!-- หมอในร้าน: การ์ดใหญ่ ชื่อ + จุดสถานะ · ที่เลือก = พื้นน้ำตาลเข้ม + เครื่องหมายถูก -->
            <div v-if="therapists.length" class="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-4">
              <button
                v-for="t in therapists"
                :key="t.employee_id"
                type="button"
                role="radio"
                :aria-checked="isPicked(a, t)"
                :disabled="therapistState(t, idx).unavailable"
                class="flex min-h-16 items-center gap-2 rounded-xl border-2 px-3 py-2.5 text-left transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none disabled:cursor-not-allowed"
                :class="isPicked(a, t)
                  ? 'border-primary bg-primary text-primary-foreground shadow-soft'
                  : therapistState(t, idx).unavailable
                    ? 'border-transparent bg-muted text-muted-foreground'
                    : 'border-border bg-background text-heading hover:border-primary/60'"
                @click="chooseTherapist(idx, 'staff', t.employee_id)"
              >
                <span class="grid min-w-0 flex-1 gap-1">
                  <span class="truncate text-base leading-tight font-semibold">{{ t.nickname }}</span>
                  <span class="flex items-center gap-1.5 text-[13px] leading-tight">
                    <span class="size-2 shrink-0 rounded-full" :class="isPicked(a, t) ? 'bg-primary-foreground' : therapistState(t, idx).dot" aria-hidden="true" />
                    <span class="truncate">{{ therapistState(t, idx).text }}</span>
                  </span>
                </span>
                <Check v-if="isPicked(a, t)" class="size-5 shrink-0" aria-hidden="true" />
              </button>
            </div>
            <!-- ทางเลือกอื่น: แยกจากรายชื่อหมอด้วยเส้นคั่น -->
            <div class="flex flex-wrap items-center gap-2 border-t border-border pt-3">
              <span class="mr-1 text-sm text-muted-foreground">หรือ</span>
              <button
                type="button"
                role="radio"
                :aria-checked="a.kind === 'freelance'"
                class="flex h-11 items-center gap-1.5 rounded-full border border-dashed px-4 text-[15px] transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
                :class="a.kind === 'freelance' ? 'border-solid border-primary bg-secondary font-medium text-heading' : 'border-input bg-background text-foreground hover:text-heading'"
                @click="chooseTherapist(idx, 'freelance')"
              ><Check v-if="a.kind === 'freelance'" class="size-4" aria-hidden="true" /><UserPlus v-else class="size-4" aria-hidden="true" /> หมอวิ่ง</button>
              <button
                type="button"
                role="radio"
                :aria-checked="a.kind === 'later'"
                class="flex h-11 items-center gap-1.5 rounded-full border px-4 text-[15px] transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
                :class="a.kind === 'later' ? 'border-primary bg-secondary font-medium text-heading' : 'border-border bg-background text-foreground hover:text-heading'"
                @click="chooseTherapist(idx, 'later')"
              ><Check v-if="a.kind === 'later'" class="size-4" aria-hidden="true" /><Clock v-else class="size-4" aria-hidden="true" /> เลือกหมอทีหลัง</button>
            </div>
          </div>
          <div v-if="a.kind === 'freelance'" class="grid gap-2 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end">
            <TextField v-model="a.name" label="ชื่อหมอวิ่ง" maxlength="60" placeholder="ชื่อเล่น" />
            <CheckboxField
              v-if="fuelSetting > 0"
              v-model="a.fuel"
              :label="`มีค่าน้ำมัน ${formatBaht(fuelSetting)}`"
              class="sm:pb-2.5"
            />
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
            <template v-if="checkinMode"><span class="num text-heading">{{ checkinBooking?.items.length }}</span> คน · {{ customerLabel }}</template>
            <template v-else-if="picked.length"><span class="num text-heading">{{ picked.length }}</span> คน · รวม <span class="num text-lg font-semibold text-heading">{{ formatBaht(total) }}</span></template>
            <template v-else>ยังไม่ได้เลือกบริการ</template>
          </span>
          <Button v-if="step === 2" size="lg" :disabled="!picked.length" @click="goToTime">ถัดไป <ChevronRight /></Button>
          <Button v-else-if="step === 3" size="lg" :disabled="!startAt" @click="goToTherapist">ถัดไป <ChevronRight /></Button>
          <Button v-else-if="checkinMode" size="lg" :disabled="!assignsReady || saving" @click="finishCheckin">
            <Check /> {{ saving ? 'กำลังเช็กอิน…' : assigns.some(starting) ? 'เช็กอิน เริ่มนวด' : 'เช็กอิน' }}
          </Button>
          <Button v-else size="lg" :disabled="!startAt || !assignsReady || saving" @click="submitWalkIn">
            <Check /> {{ saving ? 'กำลังสร้างคิว…' : assigns.some(starting) ? 'ยืนยัน เริ่มนวด' : 'ยืนยัน สร้างคิว' }}
          </Button>
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
      <p v-if="countdown > 0" class="m-0 text-[15px] text-muted-foreground">
        กำลังไปหน้าคิวใน <span class="num font-semibold text-heading">{{ countdown }}</span> วินาที…
      </p>
      <div class="flex flex-wrap justify-center gap-2">
        <Button size="lg" @click="goToQueue">ไปหน้าคิวเลย</Button>
        <Button size="lg" variant="outline" @click="startWalkIn()"><UserPlus /> รับลูกค้าคนต่อไป</Button>
      </div>
    </div>
  </div>
</template>
