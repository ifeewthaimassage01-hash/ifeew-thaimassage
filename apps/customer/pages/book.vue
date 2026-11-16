<script setup lang="ts">
// จองบริการ — ทำทีละขั้นแบบเดียวกับ "รับลูกค้าใหม่" ในหน้าร้าน (POS) แต่เพิ่มขั้นแรก "เลือกสาขา"
//   1) สาขา → 2) บริการ → 3) จำนวนชม. + จำนวนคน (คนละบริการ = เพิ่มบริการอื่น สูงสุด MAX_PEOPLE คน)
//   → 4) วันและเวลาว่าง → 5) ข้อมูลผู้จอง + สรุป → จองและชำระมัดจำ
//   แถบล่าง: จำนวนคน + ยอดรวม + ปุ่มหลักปุ่มเดียว (ถัดไป / จอง)
//   รับค่าจากแผงจองด่วนหน้าแรก: ?branch=&service=&option=&date=YYYY-MM-DD&time=<starts_at ISO>
import { ArrowLeft, Check, ChevronRight, Clock, MapPin, MessageCircle, Plus, UserRound, X } from '@lucide/vue'
import { toast } from 'vue-sonner'
import {
  addDays,
  bangkokToday,
  formatBaht,
  formatDuration,
  newIdempotencyKey,
  personNameSchema,
  thaiPhoneSchema,
  type AvailableSlot,
  type BookingView,
} from '@ifeew/shared'

useHead({ title: "จองบริการ — I'FEEW THAIMASSAGE" })

const MAX_PEOPLE = 4
const route = useRoute()
const supabase = useSupabaseClient()
const { code: companyCode } = useCompany()
const { call } = useEdgeFunction()
const { data: branches } = await useBranches()
const { data: policies } = await usePolicies()

const qs = (k: string) => (typeof route.query[k] === 'string' && route.query[k] ? (route.query[k] as string) : null)
const branchId = ref<string | null>(qs('branch'))
const { data: catalog } = await useCatalog(branchId)

// บริการที่เลือก: 1 รายการ = 1 คน (option_id ซ้ำได้ เช่น 2 คนนวดไทย 1 ชม.)
const picked = ref<string[]>(qs('option') ? [qs('option')!] : [])
const today = bangkokToday()
const qDate = qs('date')
const date = ref(qDate && /^\d{4}-\d{2}-\d{2}$/.test(qDate) && qDate >= today ? qDate : addDays(today, 1))
let wantedSlot = qs('time')
const slots = ref<AvailableSlot[]>([])
const loadingSlots = ref(false)
const slotError = ref<string | null>(null)
const slot = ref<AvailableSlot | null>(null)
const note = ref('')

const guest = reactive({ firstName: '', lastName: '', phone: '', email: '' })
const privacy = ref(false)
const marketing = ref(false)
const submitting = ref(false)
const error = ref<string | null>(null)
let idempotencyKey = newIdempotencyKey()

// ---------------------------------------------------------------------------
// ขั้นตอน
// ---------------------------------------------------------------------------
// 1 สาขา → 2 บริการ → 3 จำนวนชม. (+ จำนวนคน) → 4 เวลา → 5 ข้อมูลผู้จอง
type Step = 1 | 2 | 3 | 4 | 5
const STEPS = ['สาขา', 'บริการ', 'จำนวนชม.', 'เวลา', 'ข้อมูลผู้จอง'] as const
// บริการที่กำลังเลือกระยะเวลา (ขั้นที่ 3) · มาจากปุ่ม "จองบริการนี้" (?service=) = เริ่มที่บริการนั้น
const currentService = ref<string | null>(qs('option') ? null : qs('service'))
const step = ref<Step>(!branchId.value ? 1 : picked.value.length ? 4 : currentService.value ? 3 : 2)
function go(s: Step) {
  step.value = s
  error.value = null
  if (import.meta.client) window.scrollTo({ top: 0, behavior: 'smooth' })
}
function back() {
  if (step.value === 1) return navigateTo('/')
  go((step.value - 1) as Step)
}

// ---------------------------------------------------------------------------
// LINE: ส่งยืนยันการจองและเตือนก่อนถึงนัดเข้า LINE
//   เติมชื่อ/นามสกุล/เบอร์จากการจองครั้งล่าสุดของ LINE นี้ (line-my-bookings) · ไม่เคยจอง = ใช้ชื่อ LINE
//   เติมเฉพาะช่องที่ยังว่าง หรือยังเป็นค่าที่ระบบเติมให้ (ไม่ทับสิ่งที่ลูกค้าพิมพ์เอง)
// ---------------------------------------------------------------------------
const line = useLiff()
const autoFilled = reactive({ firstName: '', lastName: '', phone: '' })
function autofill(field: keyof typeof autoFilled, value: string | null | undefined) {
  if (!value) return
  if (guest[field] && guest[field] !== autoFilled[field]) return
  guest[field] = value
  autoFilled[field] = value
}
watch(
  () => line.user.value?.name,
  async (name) => {
    if (!name) return
    autofill('firstName', name.slice(0, 100))
    try {
      const p = (await line.myBookings())?.profile
      if (p) {
        autofill('firstName', p.first_name)
        autofill('lastName', p.last_name)
        autofill('phone', p.phone)
      }
    } catch {
      // เติมไม่ได้ก็กรอกเองตามปกติ
    }
  },
  { immediate: true },
)

// เข้าหน้าจอง: ให้เลือกก่อนว่าจองด้วย LINE หรือจองแบบไม่เข้าสู่ระบบ (Guest)
//   แสดงทุกครั้งที่เข้าหน้าจอง ถ้าร้านเปิดใช้ LINE และยังไม่ได้เข้าสู่ระบบ · ปิดหน้าต่าง = จองแบบ Guest
const modeDialog = ref(false)
let modeAsked = false
watch(
  () => [line.available.value, line.user.value, line.restoring.value] as const,
  ([available, user, restoring]) => {
    if (modeAsked || !import.meta.client || available === null || restoring) return
    modeAsked = true
    if (available && !user) modeDialog.value = true
  },
  { immediate: true },
)
function chooseGuest() {
  modeDialog.value = false
}
async function chooseLine() {
  await lineLogin()
  if (line.user.value) modeDialog.value = false // เข้าสู่ระบบอยู่แล้ว (ไม่ต้องออกจากหน้า)
}
const lineLoggingIn = ref(false)
async function lineLogin() {
  lineLoggingIn.value = true
  try {
    await line.login()
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'เข้าสู่ระบบด้วย LINE ไม่สำเร็จ')
  } finally {
    lineLoggingIn.value = false
  }
}

// ---------------------------------------------------------------------------
// ขั้นที่ 1–2: สาขาและบริการ
// ---------------------------------------------------------------------------
const branch = computed(() => branches.value?.find((b) => b.id === branchId.value) ?? null)
function pickBranch(id: string) {
  if (branchId.value !== id) {
    branchId.value = id
    picked.value = []
    currentService.value = null
    slot.value = null
  }
  go(2)
}

type Opt = { option_id: string; duration_minutes: number; price: number; name: string }
const optionMap = computed(() => {
  const m = new Map<string, Opt>()
  for (const c of catalog.value ?? []) for (const o of c.options) m.set(o.option_id, { ...o, name: c.name })
  return m
})
// ตัวเลือกจากหน้าแรกที่ไม่มีในสาขานี้ → ทิ้ง
watch(optionMap, (m) => {
  if (m.size && picked.value.some((id) => !m.has(id))) picked.value = picked.value.filter((id) => m.has(id))
})
const catalogGroups = computed(() => {
  const groups: Array<{ name: string; services: NonNullable<typeof catalog.value> }> = []
  for (const c of catalog.value ?? []) {
    const g = groups.find((x) => x.name === c.category_name)
    if (g) g.services.push(c)
    else groups.push({ name: c.category_name, services: [c] })
  }
  return groups
})
const total = computed(() => picked.value.reduce((s, id) => s + (optionMap.value.get(id)?.price ?? 0), 0))

// ขั้นที่ 2 → 3: เลือกบริการ แล้วเลือกระยะเวลา + จำนวนคนของบริการนั้น
//   บริการละ 1 ระยะเวลา · คนละบริการ = กด "เพิ่มบริการอื่น" กลับไปเลือกอีกบริการ (ของที่เลือกไว้ยังอยู่)
const serviceById = (id: string | null) => catalog.value?.find((c) => c.branch_service_id === id) ?? null
const optionIdsOf = (serviceId: string) => new Set(serviceById(serviceId)?.options.map((o) => o.option_id) ?? [])
/** รายการที่เลือกแล้ว รวมตามบริการ: { service, option, people } */
const basket = computed(() => {
  const out: Array<{ serviceId: string; name: string; option: Opt; people: number }> = []
  for (const id of picked.value) {
    const o = optionMap.value.get(id)
    const s = catalog.value?.find((c) => c.options.some((x) => x.option_id === id))
    if (!o || !s) continue
    const row = out.find((r) => r.option.option_id === id)
    if (row) row.people++
    else out.push({ serviceId: s.branch_service_id, name: s.name, option: o, people: 1 })
  }
  return out
})
const draft = reactive({ optionId: null as string | null, people: 1 })
// คนที่เลือกไว้ในบริการอื่น (ใช้จำกัดจำนวนคนรวมไม่เกิน MAX_PEOPLE)
const othersCount = computed(() => {
  if (!currentService.value) return picked.value.length
  const mine = optionIdsOf(currentService.value)
  return picked.value.filter((id) => !mine.has(id)).length
})
const maxDraftPeople = computed(() => Math.max(1, MAX_PEOPLE - othersCount.value))
function openService(serviceId: string) {
  currentService.value = serviceId
  go(3)
}
// เปิดขั้นที่ 3: ใช้ค่าที่เลือกไว้แล้วของบริการนี้ ไม่งั้นระยะเวลาแรก 1 คน
watch(
  [currentService, () => catalog.value],
  ([sid]) => {
    const s = serviceById(sid)
    if (!s) return
    const mine = optionIdsOf(s.branch_service_id)
    const chosen = picked.value.filter((id) => mine.has(id))
    draft.optionId = chosen[0] ?? s.options[0]?.option_id ?? null
    draft.people = Math.min(Math.max(1, chosen.length), maxDraftPeople.value)
  },
  { immediate: true },
)
/** บันทึกระยะเวลา + จำนวนคนของบริการที่กำลังเลือกลงตะกร้า */
function applyDraft() {
  if (!currentService.value || !draft.optionId) return
  const mine = optionIdsOf(currentService.value)
  const n = Math.min(draft.people, maxDraftPeople.value)
  picked.value = [...picked.value.filter((id) => !mine.has(id)), ...Array.from({ length: n }, () => draft.optionId!)]
}
function removeService(serviceId: string) {
  const mine = optionIdsOf(serviceId)
  picked.value = picked.value.filter((id) => !mine.has(id))
}
const draftPrice = computed(() => (optionMap.value.get(draft.optionId ?? '')?.price ?? 0) * draft.people)
const fromPrice = (s: { options: Array<{ price: number }> }) => Math.min(...s.options.map((o) => o.price))

// ---------------------------------------------------------------------------
// ขั้นที่ 3: วันและเวลา
// ---------------------------------------------------------------------------
const days = computed(() =>
  Array.from({ length: 14 }, (_, i) => {
    const iso = addDays(today, i)
    const d = new Date(`${iso}T00:00:00+07:00`)
    const fmt = (o: Intl.DateTimeFormatOptions) => d.toLocaleDateString('th-TH', { ...o, timeZone: 'Asia/Bangkok' })
    return { iso, weekday: i === 0 ? 'วันนี้' : i === 1 ? 'พรุ่งนี้' : fmt({ weekday: 'short' }), day: fmt({ day: 'numeric' }), month: fmt({ month: 'short' }) }
  }),
)
const dateLabel = computed(() =>
  new Date(`${date.value}T00:00:00+07:00`).toLocaleDateString('th-TH', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'Asia/Bangkok' }),
)
const slotGroups = computed(() => {
  const groups: Array<{ label: string; items: AvailableSlot[] }> = [
    { label: 'ช่วงเช้า', items: [] },
    { label: 'ช่วงบ่าย', items: [] },
    { label: 'ช่วงเย็น', items: [] },
  ]
  for (const s of slots.value) {
    const h = Number(s.time.slice(0, 2))
    groups[h < 12 ? 0 : h < 17 ? 1 : 2]!.items.push(s)
  }
  return groups.filter((g) => g.items.length)
})
watch(
  [branchId, date, () => picked.value.join(',')],
  async () => {
    slot.value = null
    slots.value = []
    slotError.value = null
    idempotencyKey = newIdempotencyKey()
    if (!branchId.value || !picked.value.length) return
    loadingSlots.value = true
    const { data, error: err } = await supabase.rpc('get_available_slots', {
      p_branch_id: branchId.value, p_date: date.value, p_option_ids: picked.value,
    })
    loadingSlots.value = false
    if (err) {
      slotError.value = err.message
      return
    }
    slots.value = (data ?? []) as unknown as AvailableSlot[]
    // เวลาที่เลือกไว้จากหน้าแรก (ถ้ายังว่าง) — ใช้ครั้งเดียว
    if (wantedSlot) {
      slot.value = slots.value.find((s) => s.starts_at === wantedSlot) ?? null
      wantedSlot = null
    }
  },
  { immediate: true },
)

// ---------------------------------------------------------------------------
// ขั้นที่ 4: ยืนยัน
// ---------------------------------------------------------------------------
async function submit() {
  error.value = null
  if (!branchId.value || !picked.value.length || !slot.value) {
    error.value = 'กรุณาเลือกบริการและเวลาให้ครบ'
    return
  }
  submitting.value = true
  try {
    const first = personNameSchema.safeParse(guest.firstName)
    const phone = thaiPhoneSchema.safeParse(guest.phone)
    if (!first.success || !phone.success) throw new Error('กรุณากรอกชื่อและเบอร์โทรให้ถูกต้อง')
    if (!privacy.value || !policies.value?.PRIVACY_NOTICE) throw new Error('กรุณารับทราบนโยบายความเป็นส่วนตัว')

    const view = await call<BookingView>('guest-booking', {
      company_code: companyCode,
      branch_id: branchId.value,
      starts_at: slot.value.starts_at,
      option_ids: picked.value,
      first_name: first.data,
      last_name: guest.lastName.trim(),
      phone: phone.data,
      email: guest.email.trim() || null,
      note: note.value.trim() || null,
      privacy_version_id: policies.value.PRIVACY_NOTICE.id,
      idempotency_key: idempotencyKey,
      line_id_token: line.user.value ? await line.idToken() : null,
    })
    // เก็บลิงก์ไว้ในเครื่องนี้ ให้ Guest กลับมาดูได้
    const saved = JSON.parse(localStorage.getItem('ifeew.guest_bookings') ?? '[]') as string[]
    localStorage.setItem('ifeew.guest_bookings', JSON.stringify([view.tracking_token, ...saved].slice(0, 10)))
    line.mine.value = null // ให้ "การจองของฉัน" โหลดใหม่
    await navigateTo(`/t/${view.tracking_token}`)
  } catch (e) {
    error.value = e instanceof Error && !(e as { data?: unknown }).data ? e.message : edgeErrorText(e)
  } finally {
    submitting.value = false
  }
}

// แถบล่าง: ปุ่มหลักของแต่ละขั้น
const primary = computed(() => {
  if (step.value === 2) return { label: 'เลือกเวลา', disabled: !picked.value.length, run: () => go(4) }
  if (step.value === 3) return { label: 'เลือกเวลา', disabled: !draft.optionId, run: () => { applyDraft(); go(4) } }
  if (step.value === 4) return { label: 'กรอกข้อมูลผู้จอง', disabled: !slot.value, run: () => go(5) }
  return { label: submitting.value ? 'กำลังจอง…' : 'จองและชำระมัดจำ', disabled: submitting.value, run: submit }
})
// บริการในแถบล่าง: ที่เลือกไว้แล้ว + (ขั้นที่ 3) บริการที่กำลังเลือกอยู่แทนค่าเดิมของบริการนั้น
const barItems = computed(() => {
  const items = basket.value
    .filter((b) => !(step.value === 3 && b.serviceId === currentService.value))
    .map((b) => ({ key: b.option.option_id, name: b.name, duration: formatDuration(b.option.duration_minutes), people: b.people }))
  const s = step.value === 3 ? serviceById(currentService.value) : null
  const o = s ? optionMap.value.get(draft.optionId ?? '') : null
  if (s && o) items.push({ key: `draft-${o.option_id}`, name: s.name, duration: formatDuration(o.duration_minutes), people: draft.people })
  return items
})
// ยอดในแถบล่าง: ขั้นที่ 3 แสดงยอดรวมรวมรายการที่กำลังเลือก
const barPeople = computed(() => (step.value === 3 ? othersCount.value + draft.people : picked.value.length))
const barTotal = computed(() => {
  if (step.value !== 3 || !currentService.value) return total.value
  const mine = optionIdsOf(currentService.value)
  const others = picked.value.filter((id) => !mine.has(id)).reduce((s, id) => s + (optionMap.value.get(id)?.price ?? 0), 0)
  return others + draftPrice.value
})
const chip = (on: boolean) =>
  on ? 'border-primary bg-primary text-primary-foreground' : 'border-border bg-card text-heading hover:border-input hover:bg-muted'
</script>

<template>
  <div class="mx-auto grid max-w-3xl gap-5" :class="barItems.length ? 'pb-44' : 'pb-32'">
    <!-- หัว + ตัวบอกขั้น -->
    <div class="grid gap-3">
      <div class="flex items-center gap-2">
        <Button variant="ghost" size="icon" :aria-label="step === 1 ? 'ยกเลิกการจอง' : 'ย้อนกลับ'" @click="back">
          <X v-if="step === 1" class="size-5" /><ArrowLeft v-else class="size-5" />
        </Button>
        <h1 class="m-0 text-xl font-semibold">จองคิวนวด</h1>
      </div>
      <ol class="m-0 flex list-none gap-2 p-0" :aria-label="`ขั้นที่ ${step} จาก ${STEPS.length}`">
        <li v-for="(t, i) in STEPS" :key="t" class="flex flex-1 flex-col gap-1" :aria-current="i + 1 === step ? 'step' : undefined">
          <span class="h-1.5 rounded-full" :class="i + 1 <= step ? 'bg-primary' : 'bg-secondary'" />
          <span class="text-[13px]" :class="i + 1 === step ? 'font-semibold text-heading' : 'text-muted-foreground'">{{ i + 1 }}. {{ t }}</span>
        </li>
      </ol>
    </div>

    <!-- เลือกวิธีจองก่อนเริ่ม: LINE หรือ Guest -->
    <Dialog :open="modeDialog" @update:open="(v) => !v && chooseGuest()">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>จองแบบไหนดี</DialogTitle>
          <DialogDescription>เลือกได้ทั้งสองแบบ จองได้เหมือนกัน</DialogDescription>
        </DialogHeader>
        <div class="grid gap-3">
          <button
            type="button"
            class="flex items-start gap-3 rounded-xl border-2 border-[#06C755]/40 bg-card p-4 text-left transition-colors hover:border-[#06C755] focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none disabled:opacity-60"
            :disabled="lineLoggingIn"
            @click="chooseLine"
          >
            <span class="grid size-10 shrink-0 place-items-center rounded-full bg-[#06C755] text-white" aria-hidden="true"><MessageCircle class="size-5" /></span>
            <span class="grid gap-1">
              <span class="text-base font-semibold text-heading">{{ lineLoggingIn ? 'กำลังไปที่ LINE…' : 'จองด้วย LINE' }}</span>
              <span class="text-sm text-muted-foreground">ได้ข้อความยืนยันและเตือนก่อนถึงนัดในแชท ดูการจองของคุณได้ทุกเมื่อ ครั้งหน้าไม่ต้องกรอกชื่อและเบอร์ใหม่</span>
            </span>
          </button>
          <button
            type="button"
            class="flex items-start gap-3 rounded-xl border-2 border-border bg-card p-4 text-left transition-colors hover:border-input hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
            @click="chooseGuest"
          >
            <span class="grid size-10 shrink-0 place-items-center rounded-full bg-secondary text-heading" aria-hidden="true"><UserRound class="size-5" /></span>
            <span class="grid gap-1">
              <span class="text-base font-semibold text-heading">จองโดยไม่เข้าสู่ระบบ</span>
              <span class="text-sm text-muted-foreground">กรอกชื่อและเบอร์โทรเอง ตรวจสอบการจองภายหลังด้วยเบอร์โทร</span>
            </span>
          </button>
        </div>
      </DialogContent>
    </Dialog>

    <!-- ===================== ขั้นที่ 1: สาขา ===================== -->
    <section v-if="step === 1" class="grid gap-3" aria-labelledby="s1-h">
      <h2 id="s1-h" class="m-0 text-[15px] text-muted-foreground">นวดที่สาขาไหน</h2>
      <ul class="m-0 grid list-none gap-2 p-0 sm:grid-cols-2">
        <li v-for="b in branches ?? []" :key="b.id">
          <button
            type="button"
            class="flex w-full items-start gap-3 rounded-xl border-2 bg-card p-4 text-left transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
            :class="branchId === b.id ? 'border-primary' : 'border-border hover:border-primary/60'"
            @click="pickBranch(b.id)"
          >
            <span class="grid size-10 shrink-0 place-items-center rounded-full bg-secondary text-primary" aria-hidden="true"><MapPin class="size-5" /></span>
            <span class="grid min-w-0 flex-1 gap-0.5">
              <span class="text-base font-semibold text-heading">{{ b.name }}</span>
              <span v-if="b.address" class="line-clamp-2 text-sm text-muted-foreground">{{ b.address }}</span>
            </span>
            <Check v-if="branchId === b.id" class="size-5 shrink-0 text-primary" aria-hidden="true" />
          </button>
        </li>
      </ul>
      <EmptyState v-if="!branches?.length" compact title="ยังไม่มีสาขาที่เปิดจองออนไลน์" />
    </section>

    <!-- ===================== ขั้นที่ 2: บริการ ===================== -->
    <section v-else-if="step === 2" class="grid gap-4" aria-labelledby="s2-h">
      <h2 id="s2-h" class="m-0 text-[15px] text-muted-foreground">นวดอะไรดี</h2>

      <!-- เลือกไว้แล้ว (มากันหลายคน คนละบริการ) -->
      <div v-if="basket.length" class="grid gap-2 rounded-xl border border-primary/40 bg-secondary/50 p-3">
        <p class="m-0 text-sm font-medium text-heading">เลือกไว้แล้ว {{ picked.length }} คน</p>
        <ul class="m-0 grid list-none gap-1 p-0 text-[15px]">
          <li v-for="b in basket" :key="b.option.option_id" class="flex items-center justify-between gap-3">
            <button type="button" class="min-w-0 text-left text-heading underline-offset-4 hover:underline" @click="openService(b.serviceId)">
              {{ b.name }} {{ formatDuration(b.option.duration_minutes) }} <span class="text-muted-foreground">{{ b.people }} คน</span>
            </button>
            <Button variant="ghost" size="icon-sm" :aria-label="`ลบ ${b.name}`" @click="removeService(b.serviceId)"><X /></Button>
          </li>
        </ul>
      </div>

      <EmptyState v-if="!catalog?.length" compact title="สาขานี้ยังไม่เปิดจองบริการออนไลน์" description="โทรจองที่สาขาได้ หรือเลือกสาขาอื่น" />
      <section v-for="cat in catalogGroups" :key="cat.name" class="grid gap-2" :aria-label="cat.name">
        <h3 class="m-0 flex items-center gap-2 text-[13px] font-semibold text-muted-foreground">
          {{ cat.name }} <span class="h-px flex-1 bg-border" aria-hidden="true" />
        </h3>
        <ul class="m-0 grid list-none grid-cols-1 gap-2 p-0 sm:grid-cols-2">
          <li v-for="s in cat.services" :key="s.branch_service_id">
            <button
              type="button"
              class="flex w-full items-center gap-3 rounded-xl border-2 bg-card p-3 text-left transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
              :class="basket.some((b) => b.serviceId === s.branch_service_id) ? 'border-primary' : 'border-border hover:border-primary/60'"
              @click="openService(s.branch_service_id)"
            >
              <!-- รูปบริการ (ร้านยังไม่อัปโหลด = รูปประกอบตามชื่อบริการ) -->
              <img
                :src="serviceImageUrl(s.image_path, 240) ?? fallbackServiceImage(s.name)"
                alt=""
                class="size-20 shrink-0 rounded-lg bg-muted object-cover sm:size-24"
                loading="lazy"
                decoding="async"
              >
              <span class="grid min-w-0 flex-1 gap-0.5">
                <span class="text-base font-semibold text-heading">{{ s.name }}</span>
                <span v-if="s.description" class="line-clamp-2 text-sm text-muted-foreground">{{ s.description }}</span>
                <span class="text-sm text-muted-foreground">
                  {{ s.options.length > 1 ? `${formatDuration(s.options[0]!.duration_minutes)}–${formatDuration(s.options[s.options.length - 1]!.duration_minutes)}` : formatDuration(s.options[0]!.duration_minutes) }}
                  เริ่ม <span class="num font-medium text-heading">{{ formatBaht(fromPrice(s)) }}</span>
                </span>
              </span>
              <Check v-if="basket.some((b) => b.serviceId === s.branch_service_id)" class="size-5 shrink-0 text-primary" aria-hidden="true" />
              <ChevronRight v-else class="size-5 shrink-0 text-muted-soft" aria-hidden="true" />
            </button>
          </li>
        </ul>
      </section>
    </section>

    <!-- ===================== ขั้นที่ 3: จำนวนชม. + จำนวนคน ===================== -->
    <section v-else-if="step === 3 && serviceById(currentService)" class="grid gap-5" aria-labelledby="s3-h">
      <div class="grid gap-0.5">
        <h2 id="s3-h" class="m-0 text-lg font-semibold text-heading">{{ serviceById(currentService)!.name }}</h2>
        <p v-if="serviceById(currentService)!.description" class="m-0 text-sm text-muted-foreground">{{ serviceById(currentService)!.description }}</p>
      </div>

      <div class="grid gap-2">
        <p class="m-0 text-[15px] font-medium text-heading">นวดกี่ชั่วโมง</p>
        <ul class="m-0 grid list-none gap-2 p-0 sm:grid-cols-2" role="radiogroup" aria-label="ระยะเวลา">
          <li v-for="o in serviceById(currentService)!.options" :key="o.option_id">
            <button
              type="button"
              role="radio"
              :aria-checked="draft.optionId === o.option_id"
              class="flex min-h-14 w-full items-center gap-3 rounded-xl border-2 px-4 py-3 text-left transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
              :class="draft.optionId === o.option_id ? 'border-primary bg-secondary' : 'border-border bg-card hover:border-primary/60'"
              @click="draft.optionId = o.option_id"
            >
              <Clock class="size-5 shrink-0 text-brand-accent" aria-hidden="true" />
              <span class="flex-1 text-base font-medium text-heading">{{ formatDuration(o.duration_minutes) }}</span>
              <span class="num text-base font-semibold text-heading">{{ formatBaht(o.price) }}</span>
              <Check v-if="draft.optionId === o.option_id" class="size-5 shrink-0 text-primary" aria-hidden="true" />
            </button>
          </li>
        </ul>
      </div>

      <div class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border bg-card px-4 py-3">
        <p class="m-0">
          <span class="block text-[15px] font-medium text-heading">กี่คน</span>
          <span class="block text-sm text-muted-foreground">นวดบริการนี้ระยะเวลาเดียวกัน</span>
        </p>
        <div class="flex items-center gap-2" role="group" aria-label="จำนวนคน">
          <Button variant="outline" size="icon" class="text-lg" aria-label="ลด 1 คน" :disabled="draft.people <= 1" @click="draft.people--">−</Button>
          <span class="min-w-14 text-center text-lg text-heading"><span class="num font-semibold">{{ draft.people }}</span> คน</span>
          <Button size="icon" aria-label="เพิ่ม 1 คน" :disabled="draft.people >= maxDraftPeople" @click="draft.people++"><Plus /></Button>
        </div>
      </div>
      <p v-if="draft.people >= maxDraftPeople" class="m-0 -mt-2 text-sm text-pending-ink">จองได้สูงสุด {{ MAX_PEOPLE }} คนต่อครั้ง มากกว่านี้โทรจองที่สาขา</p>

      <Button
        v-if="othersCount + draft.people < MAX_PEOPLE"
        variant="outline"
        class="w-full sm:w-fit"
        :disabled="!draft.optionId"
        @click="applyDraft(); go(2)"
      ><Plus /> เพิ่มบริการอื่น (มากันหลายคน นวดคนละอย่าง)</Button>
    </section>

    <!-- ===================== ขั้นที่ 4: วันและเวลา ===================== -->
    <section v-else-if="step === 4" class="grid gap-4" aria-labelledby="s4t-h">
      <div class="grid gap-1 rounded-xl border border-border bg-card px-4 py-3 text-[15px]">
        <p class="m-0 text-muted-foreground">{{ branch?.name }}</p>
        <p v-for="(id, idx) in picked" :key="idx" class="m-0 text-heading">
          คนที่ {{ idx + 1 }} {{ optionMap.get(id)?.name }} <span class="text-muted-foreground">{{ formatDuration(optionMap.get(id)?.duration_minutes ?? 0) }}</span>
        </p>
      </div>

      <h2 id="s4t-h" class="m-0 text-[15px] font-medium text-heading">วันไหน</h2>
      <div class="-mx-4 overflow-x-auto px-4 pb-1 sm:mx-0 sm:px-0" role="radiogroup" aria-label="วันที่">
        <div class="flex w-max gap-2">
          <button
            v-for="d in days"
            :key="d.iso"
            type="button"
            role="radio"
            :aria-checked="date === d.iso"
            :aria-label="`${d.weekday} ${d.day} ${d.month}`"
            class="grid w-16 justify-items-center gap-0.5 rounded-lg border py-2 transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
            :class="chip(date === d.iso)"
            @click="date = d.iso"
          >
            <span class="text-[13px]" :class="date === d.iso ? 'text-primary-foreground/85' : 'text-muted-foreground'">{{ d.weekday }}</span>
            <span class="num text-lg leading-tight font-semibold">{{ d.day }}</span>
            <span class="text-[13px]" :class="date === d.iso ? 'text-primary-foreground/85' : 'text-muted-foreground'">{{ d.month }}</span>
          </button>
        </div>
      </div>

      <h2 class="m-0 text-[15px] font-medium text-heading">เริ่มกี่โมง</h2>
      <div v-if="loadingSlots" class="grid grid-cols-3 gap-2 sm:grid-cols-5">
        <Skeleton v-for="n in 10" :key="n" class="h-11 rounded-lg" />
      </div>
      <Alert v-else-if="slotError" variant="destructive"><AlertDescription>โหลดเวลาว่างไม่สำเร็จ: {{ slotError }}</AlertDescription></Alert>
      <EmptyState v-else-if="!slots.length" compact :title="`${dateLabel} ไม่มีเวลาว่าง`" description="ร้านปิดหรือคิวเต็ม ลองเลือกวันอื่น" />
      <div v-else class="grid gap-4" role="radiogroup" aria-label="เวลาเริ่ม">
        <div v-for="g in slotGroups" :key="g.label" class="grid gap-2">
          <h3 class="m-0 text-sm font-medium text-muted-foreground">{{ g.label }}</h3>
          <div class="grid grid-cols-3 gap-2 sm:grid-cols-5">
            <button
              v-for="s in g.items"
              :key="s.starts_at"
              type="button"
              role="radio"
              :aria-checked="slot?.starts_at === s.starts_at"
              class="num h-11 rounded-lg border text-[15px] font-medium transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
              :class="chip(slot?.starts_at === s.starts_at)"
              @click="slot = s"
            >{{ s.time }}</button>
          </div>
        </div>
      </div>
    </section>

    <!-- ===================== ขั้นที่ 5: ข้อมูลผู้จอง ===================== -->
    <div v-else-if="step === 3" class="grid gap-3"><Skeleton class="h-8 w-48" /><Skeleton v-for="n in 3" :key="n" class="h-14 rounded-xl" /></div>

    <section v-else-if="step === 5" class="grid gap-4" aria-labelledby="s4-h">
      <!-- สรุปการจอง -->
      <div class="grid gap-3 rounded-xl border border-border bg-card p-4">
        <div class="grid gap-0.5">
          <p class="m-0 text-base font-semibold text-heading">{{ dateLabel }} <span class="num">{{ slot?.time }}</span> น.</p>
          <p class="m-0 text-sm text-muted-foreground">{{ branch?.name }}</p>
        </div>
        <ul class="m-0 grid list-none gap-1 border-t border-border p-0 pt-3 text-[15px]">
          <li v-for="(id, idx) in picked" :key="idx" class="flex justify-between gap-3">
            <span class="min-w-0">คนที่ {{ idx + 1 }} {{ optionMap.get(id)?.name }} <span class="text-muted-foreground">{{ formatDuration(optionMap.get(id)?.duration_minutes ?? 0) }}</span></span>
            <span class="num shrink-0 text-heading">{{ formatBaht(optionMap.get(id)?.price ?? 0) }}</span>
          </li>
        </ul>
        <p class="m-0 text-sm text-muted-foreground">ชำระค่าบริการที่ร้านหลังใช้บริการ หลังกดจองต้องโอนมัดจำผ่าน PromptPay และส่งสลิปภายในเวลาที่กำหนด</p>
      </div>

      <h2 id="s4-h" class="m-0 text-[15px] font-medium text-heading">ข้อมูลผู้จอง</h2>
      <p v-if="line.user.value" class="m-0 rounded-lg bg-success-soft px-3 py-2 text-sm text-success-ink">
        เข้าสู่ระบบด้วย LINE ของ{{ line.user.value.name }} ระบบจะส่งยืนยันการจองและเตือนก่อนถึงนัดทาง LINE
        <template v-if="line.isFriend.value === false">
          <a v-if="line.addFriendUrl.value" :href="line.addFriendUrl.value" class="font-medium underline">เพิ่มเพื่อน LINE ของร้าน</a><span v-else class="font-medium">เพิ่มเพื่อน LINE ของร้าน</span> ก่อน จึงจะได้รับข้อความ
        </template>
      </p>
      <ClientOnly>
        <div v-if="line.available.value && !line.user.value && !line.restoring.value" class="flex flex-wrap items-center gap-3 rounded-xl border border-border bg-card px-4 py-3">
          <span class="grid size-9 shrink-0 place-items-center rounded-full bg-[#06C755] text-white" aria-hidden="true"><MessageCircle class="size-[18px]" /></span>
          <p class="m-0 min-w-0 flex-1 basis-48 text-sm text-foreground">เข้าสู่ระบบด้วย LINE เพื่อรับยืนยันและเตือนนัดในแชท</p>
          <Button variant="outline" size="sm" :disabled="lineLoggingIn" @click="lineLogin">เข้าสู่ระบบด้วย LINE</Button>
        </div>
      </ClientOnly>
      <div class="grid grid-cols-2 gap-3">
        <div class="grid content-start gap-1.5"><Label for="g-first">ชื่อ</Label><Input id="g-first" v-model="guest.firstName" autocomplete="given-name" required /></div>
        <div class="grid content-start gap-1.5"><Label for="g-last">นามสกุล <span class="font-normal text-muted-foreground">(ไม่บังคับ)</span></Label><Input id="g-last" v-model="guest.lastName" autocomplete="family-name" /></div>
      </div>
      <div class="grid gap-3 sm:grid-cols-2">
        <div class="grid content-start gap-1.5"><Label for="g-phone">เบอร์โทร</Label><Input id="g-phone" v-model="guest.phone" numeric="digits" type="tel" inputmode="tel" autocomplete="tel" required class="num" /></div>
        <div class="grid content-start gap-1.5"><Label for="g-email">อีเมล <span class="font-normal text-muted-foreground">(ไม่บังคับ)</span></Label><Input id="g-email" v-model="guest.email" type="email" autocomplete="email" /></div>
      </div>
      <div class="grid gap-1.5">
        <Label for="note">หมายเหตุถึงร้าน <span class="font-normal text-muted-foreground">(ไม่บังคับ)</span></Label>
        <Textarea id="note" v-model="note" rows="2" maxlength="500" placeholder="เช่น นวดหลังเป็นพิเศษ หรือเจ็บไหล่ขวา" />
      </div>
      <ConsentFields v-model:privacy="privacy" v-model:marketing="marketing" :policies="policies ?? null" />
      <Alert v-if="error" variant="destructive"><AlertDescription>{{ error }}</AlertDescription></Alert>
    </section>

    <!-- แถบล่าง: บริการที่เลือก + จำนวนคน/เวลา + ยอดรวม + ปุ่มหลักปุ่มเดียว -->
    <div v-if="step > 1" class="fixed inset-x-0 bottom-0 z-30 border-t border-border bg-background/95 px-4 pt-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] backdrop-blur-sm">
      <p v-if="barItems.length" class="mx-auto mb-2 flex max-w-3xl flex-wrap gap-1.5" aria-label="บริการที่เลือก">
        <span v-for="it in barItems" :key="it.key" class="inline-flex max-w-full items-center gap-1 rounded-full bg-secondary px-2.5 py-0.5 text-[13px] text-heading">
          <span class="truncate">{{ it.name }} {{ it.duration }}</span><span v-if="it.people > 1" class="num shrink-0 font-semibold">×{{ it.people }}</span>
        </span>
      </p>
      <div class="mx-auto flex max-w-3xl items-center justify-between gap-3">
        <p class="m-0 min-w-0">
          <span class="block text-sm text-muted-foreground">{{ barPeople ? `${barPeople} คน` : 'ยังไม่ได้เลือกบริการ' }}{{ step >= 4 && slot ? ` เริ่ม ${slot.time} น.` : '' }}</span>
          <span class="num block text-xl leading-tight font-semibold text-heading">{{ formatBaht(barTotal) }}</span>
        </p>
        <Button size="lg" class="h-12 min-w-40 text-base" :disabled="primary.disabled" @click="primary.run">{{ primary.label }}</Button>
      </div>
    </div>
  </div>
</template>
