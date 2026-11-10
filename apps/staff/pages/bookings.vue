<script setup lang="ts">
// การจองของสาขา (รายวัน): สร้างการจองให้ลูกค้า, ตรวจสลิปมัดจำ, ยกเลิก, ไม่มาตามนัด, คืนมัดจำ (OWNER)
import { CalendarPlus, ChevronLeft, ChevronRight, Copy, EllipsisVertical, NotebookPen, ReceiptText, Search, UserPlus, X } from '@lucide/vue'
import {
  addDays,
  bangkokTime,
  bangkokToday,
  bookingStatusLabels,
  depositStatusLabels,
  formatBaht,
  formatDuration,
  newIdempotencyKey,
  reasonSchema,
  thaiPhoneSchema,
  type AvailableSlot,
  type Database,
  type StaffBookingDeposit,
  type StaffBookingRow,
} from '@ifeew/shared'


const { confirm, prompt } = useDialog()
type CatalogRow = Database['public']['Views']['v_public_branch_services']['Row']
type SearchRow = { customer_id: string; display_name: string; phone_masked: string; is_member: boolean }

const supabase = useSupabaseClient()
const config = useRuntimeConfig()
const { activeBranch, company, isOwner } = useAccess()
const { run } = useStepUp()

const date = ref(bangkokToday())
const rows = ref<StaffBookingRow[]>([])
const loading = ref(false)
const statusFilter = ref<'ALL' | 'ACTIVE' | 'REVIEW'>('ACTIVE')
const message = ref<{ type: 'success' | 'error' | 'info'; text: string } | null>(null)
const ok = (text: string) => (message.value = { type: 'success', text })
const fail = (e: unknown, fallback?: string) => (message.value = { type: 'error', text: errorText(e, fallback) })

const visible = computed(() =>
  rows.value.filter((r) =>
    statusFilter.value === 'ALL' ? true
      : statusFilter.value === 'REVIEW' ? r.deposit_status === 'PENDING_REVIEW'
        : ['PENDING', 'CONFIRMED', 'CHECKED_IN'].includes(r.status),
  ),
)
const reviewCount = computed(() => rows.value.filter((r) => r.deposit_status === 'PENDING_REVIEW').length)

async function load() {
  if (!activeBranch.value) return
  loading.value = true
  try {
    rows.value = (await must(
      supabase.rpc('staff_bookings', { p_branch_id: activeBranch.value.branch_id, p_date: date.value }),
    )) as unknown as StaffBookingRow[]
  } catch (e) {
    fail(e, 'โหลดการจองไม่สำเร็จ')
  } finally {
    loading.value = false
  }
}

watch([date, () => activeBranch.value?.branch_id], load, { immediate: true })

// สีของสถานะการจอง (Badge variant ตาม DESIGN.md: Success = ยืนยัน/เสร็จ, Danger = ยกเลิก/ไม่มา)
type StatusVariant = 'success' | 'danger' | 'pending' | 'neutral' | 'default'
const statusVariant = (s: string): StatusVariant =>
  (({ CONFIRMED: 'success', COMPLETED: 'success', PENDING: 'pending', CANCELLED: 'danger', NO_SHOW: 'danger', EXPIRED: 'neutral', CHECKED_IN: 'default' }) as Record<string, StatusVariant>)[s] ?? 'neutral'

// ---------------------------------------------------------------------------
// ตรวจสลิป
// ---------------------------------------------------------------------------
const slipDialog = ref(false)
const slipRow = ref<StaffBookingRow | null>(null)
const slipDeposit = ref<StaffBookingDeposit | null>(null)
const slipUrl = ref<string | null>(null)
const reviewNote = ref('')
const saving = ref(false)

async function openSlip(r: StaffBookingRow, d: StaffBookingDeposit) {
  slipRow.value = r
  slipDeposit.value = d
  reviewNote.value = ''
  slipUrl.value = null
  slipDialog.value = true
  if (d.slip_path) {
    const { data } = await supabase.storage.from('booking-slips').createSignedUrl(d.slip_path, 600)
    slipUrl.value = data?.signedUrl ?? null
  }
}

async function review(approve: boolean) {
  if (!slipDeposit.value) return
  if (!approve && reviewNote.value.trim().length < 3) {
    fail(null, 'กรุณาระบุเหตุผลที่ปฏิเสธ')
    return
  }
  saving.value = true
  try {
    await must(supabase.rpc('review_deposit', {
      p_deposit_id: slipDeposit.value.deposit_id, p_approve: approve, p_note: reviewNote.value.trim() || null,
    }))
    slipDialog.value = false
    ok(approve ? 'อนุมัติสลิปแล้ว' : 'ปฏิเสธสลิปและยกเลิกการจองแล้ว')
    await load()
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}

// ---------------------------------------------------------------------------
// ยกเลิก / ไม่มาตามนัด / คืนมัดจำ / หมายเหตุ
// ---------------------------------------------------------------------------
const cancelDialog = ref(false)
const cancelRow = ref<StaffBookingRow | null>(null)
const cancelForm = reactive({ reason: '', forceRefund: false })

function openCancel(r: StaffBookingRow) {
  cancelRow.value = r
  cancelForm.reason = ''
  cancelForm.forceRefund = false
  cancelDialog.value = true
}

async function submitCancel() {
  const reason = reasonSchema.safeParse(cancelForm.reason)
  if (!cancelRow.value || !reason.success) {
    fail(null, 'กรุณาระบุเหตุผล')
    return
  }
  saving.value = true
  try {
    await run(() => must(supabase.rpc('staff_cancel_booking', {
      p_booking_id: cancelRow.value!.booking_id, p_reason: reason.data, p_force_refund: cancelForm.forceRefund,
    })))
    cancelDialog.value = false
    ok('ยกเลิกการจองแล้ว')
    await load()
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}

async function noShow(r: StaffBookingRow) {
  if (!(await confirm({ title: 'บันทึกว่าไม่มาตามนัด?', description: `${r.customer_name} · มัดจำจะถูกริบ`, confirmText: 'บันทึกไม่มา', destructive: true }))) return
  try {
    await must(supabase.rpc('mark_no_show', { p_booking_id: r.booking_id }))
    ok('บันทึกไม่มาตามนัดแล้ว')
    await load()
  } catch (e) {
    fail(e)
  }
}

async function refund(r: StaffBookingRow) {
  const ref = await prompt({
    title: 'บันทึกการคืนมัดจำ',
    description: `โอนคืน ${formatBaht(Number(r.deposit_required))} ให้ ${r.customer_name}`,
    label: 'เลขอ้างอิงการโอน',
    minLength: 3,
    confirmText: 'บันทึก',
  })
  if (ref === null) return
  try {
    await run(() => must(supabase.rpc('record_deposit_refund', { p_booking_id: r.booking_id, p_reference: ref.trim() })))
    ok('บันทึกการคืนมัดจำแล้ว')
    await load()
  } catch (e) {
    fail(e)
  }
}

async function editNote(r: StaffBookingRow) {
  const note = await prompt({
    title: 'หมายเหตุของร้าน',
    description: 'ลูกค้าไม่เห็นข้อความนี้',
    defaultValue: r.staff_note ?? '',
    multiline: true,
    maxLength: 500,
    confirmText: 'บันทึก',
  })
  if (note === null) return
  try {
    await must(supabase.rpc('set_booking_staff_note', { p_booking_id: r.booking_id, p_note: note }))
    await load()
  } catch (e) {
    fail(e)
  }
}

// ---------------------------------------------------------------------------
// สร้างการจองให้ลูกค้า (โทรจอง)
// ---------------------------------------------------------------------------
const createDialog = ref(false)
const step = ref(1)
const phone = ref('')
const found = ref<SearchRow[] | null>(null)
const customerId = ref<string | null>(null)
const catalog = ref<CatalogRow[]>([])
const people = ref<Array<{ option_id: string | null }>>([{ option_id: null }])
const newDate = ref(bangkokToday())
const slots = ref<AvailableSlot[]>([])
const slot = ref<AvailableSlot | null>(null)
const newNote = ref('')
const collectDeposit = ref(false)
const trackingLink = ref<string | null>(null)
let idemKey = newIdempotencyKey()

const optionItems = computed(() =>
  catalog.value.map((c) => ({ value: c.option_id, title: `${c.name} ${formatDuration(c.duration_minutes)} · ${formatBaht(Number(c.price))}` })),
)
const optionIds = computed(() => people.value.map((p) => p.option_id).filter((x): x is string => !!x))

async function openCreate() {
  step.value = 1
  phone.value = ''
  found.value = null
  customerId.value = null
  people.value = [{ option_id: null }]
  newDate.value = bangkokToday()
  slot.value = null
  newNote.value = ''
  collectDeposit.value = false
  trackingLink.value = null
  idemKey = newIdempotencyKey()
  createDialog.value = true
  const { data } = await supabase
    .from('v_public_branch_services')
    .select('*')
    .eq('branch_id', activeBranch.value!.branch_id)
    .order('category_sort_order').order('sort_order').order('duration_minutes')
  catalog.value = (data ?? []) as CatalogRow[]
}

async function searchCustomer() {
  const p = thaiPhoneSchema.safeParse(phone.value)
  if (!p.success || !activeBranch.value) {
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

watch([newDate, () => optionIds.value.join(','), step], async () => {
  slot.value = null
  idemKey = newIdempotencyKey()
  if (step.value !== 2 || optionIds.value.length !== people.value.length || !activeBranch.value) return
  const { data, error } = await supabase.rpc('get_available_slots', {
    p_branch_id: activeBranch.value.branch_id, p_date: newDate.value, p_option_ids: optionIds.value,
  })
  slots.value = error ? [] : ((data ?? []) as unknown as AvailableSlot[])
})

async function copyLink() {
  if (trackingLink.value) await navigator.clipboard.writeText(trackingLink.value)
  ok('คัดลอกลิงก์แล้ว')
}

async function submitCreate() {
  if (!customerId.value || !slot.value || !activeBranch.value) return
  saving.value = true
  try {
    const res = (await must(supabase.rpc('staff_create_booking', {
      p_branch_id: activeBranch.value.branch_id,
      p_customer_id: customerId.value,
      p_starts_at: slot.value.starts_at,
      p_option_ids: optionIds.value,
      p_note: newNote.value.trim() || null,
      p_collect_deposit: collectDeposit.value,
      p_idempotency_key: idemKey,
    }))) as { booking_id: string; tracking_token?: string }
    if (res.tracking_token) {
      const base = (config.public.customerAppUrl as string) || ''
      trackingLink.value = `${base}/t/${res.tracking_token}`
      step.value = 3
    } else {
      createDialog.value = false
      ok('สร้างการจองแล้ว (ยืนยันทันที)')
    }
    date.value = new Date(slot.value.starts_at).toLocaleDateString('sv-SE', { timeZone: 'Asia/Bangkok' })
    await load()
  } catch (e) {
    fail(e, 'สร้างการจองไม่สำเร็จ')
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-4xl">
    <PageHeader title="การจอง" description="นัดของลูกค้าในแต่ละวัน · กด ⋯ ที่รายการเพื่อยกเลิกหรือเพิ่มหมายเหตุ">
      <template #actions><Button @click="openCreate"><CalendarPlus /> สร้างการจอง</Button></template>
    </PageHeader>

    <div class="mb-6 flex flex-wrap items-center justify-between gap-3">
      <div class="flex items-center gap-1 rounded-lg border border-border bg-card p-1">
        <Button variant="ghost" size="icon-sm" aria-label="วันก่อน" @click="date = addDays(date, -1)"><ChevronLeft /></Button>
        <TextField v-model="date" type="date" aria-label="วันที่" class="num w-44 [&_input]:h-9 [&_input]:border-0" />
        <Button variant="ghost" size="icon-sm" aria-label="วันถัดไป" @click="date = addDays(date, 1)"><ChevronRight /></Button>
        <Button variant="ghost" size="sm" @click="date = bangkokToday()">วันนี้</Button>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <SegmentedControl
          v-model="statusFilter"
          :items="[{ value: 'ACTIVE', label: 'นัดที่ยังไม่จบ' }, { value: 'REVIEW', label: reviewCount ? `รอตรวจสลิป (${reviewCount})` : 'รอตรวจสลิป' }, { value: 'ALL', label: 'ทั้งหมด' }]"
          label="กรองสถานะ"
        />
      </div>
    </div>

    <MessageAlert :message="message" class="mb-4" @close="message = null" />
    <LoadingBar v-if="loading" class="mb-3" />
    <EmptyState v-else-if="!visible.length" :title="statusFilter === 'REVIEW' ? 'ไม่มีสลิปรอตรวจ' : 'ไม่มีการจองในวันนี้'">
      <Button variant="outline" @click="openCreate"><CalendarPlus /> สร้างการจอง</Button>
    </EmptyState>

    <!-- แต่ละการจอง: เวลา · ชื่อ · บริการ · สถานะ — ปุ่มหลักเฉพาะเมื่อมีงานต้องทำ (ตรวจสลิป) งานอื่นอยู่ในเมนู ⋯ -->
    <ul v-if="visible.length" class="m-0 grid list-none gap-2 p-0">
      <li v-for="r in visible" :key="r.booking_id" class="flex flex-wrap items-start gap-4 rounded-xl border border-border bg-card px-4 py-3.5">
        <span class="num shrink-0 rounded-lg bg-secondary px-3 py-1.5 text-lg font-semibold text-heading">{{ bangkokTime(r.starts_at) }}</span>

        <div class="min-w-0 flex-1">
          <p class="m-0 flex flex-wrap items-center gap-2 text-[15px] font-semibold text-heading">
            {{ r.customer_name }}
            <Badge :variant="statusVariant(r.status)" dot>{{ bookingStatusLabels[r.status] }}</Badge>
          </p>
          <p class="m-0 text-sm text-heading">{{ r.items.map((i) => `${i.service_name} ${formatDuration(i.duration_minutes)}`).join(' · ') }}</p>
          <p class="m-0 text-sm text-muted-foreground">
            <span class="num">{{ r.phone_masked }}</span>
            <template v-if="r.deposit_status !== 'NOT_REQUIRED'"> · มัดจำ <span class="num">{{ formatBaht(Number(r.deposit_required)) }}</span> {{ depositStatusLabels[r.deposit_status] }}</template>
          </p>
          <p v-if="r.customer_note" class="m-0 text-sm"><span class="text-muted-foreground">ลูกค้าฝากว่า:</span> {{ r.customer_note }}</p>
          <p v-if="r.staff_note" class="m-0 text-sm"><span class="text-muted-foreground">หมายเหตุร้าน:</span> {{ r.staff_note }}</p>
          <p v-if="r.cancel_reason" class="m-0 text-sm text-danger-ink">ยกเลิก: {{ r.cancel_reason }}</p>
        </div>

        <div class="flex items-center gap-1">
          <template v-for="d in r.deposits ?? []" :key="d.deposit_id">
            <Button v-if="d.status === 'PENDING_REVIEW'" size="sm" @click="openSlip(r, d)"><ReceiptText /> ตรวจสลิป</Button>
          </template>
          <DropdownMenu>
            <DropdownMenuTrigger as-child>
              <Button variant="ghost" size="icon-sm" :aria-label="`ตัวเลือก ${r.customer_name}`"><EllipsisVertical /></Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" class="w-52">
              <DropdownMenuItem v-for="d in (r.deposits ?? []).filter((x) => x.status !== 'PENDING_REVIEW')" :key="d.deposit_id" @select="openSlip(r, d)">
                <ReceiptText /> ดูสลิปมัดจำ
              </DropdownMenuItem>
              <DropdownMenuItem @select="editNote(r)"><NotebookPen /> หมายเหตุ</DropdownMenuItem>
              <DropdownMenuItem v-if="r.status === 'CONFIRMED'" @select="noShow(r)">ลูกค้าไม่มาตามนัด</DropdownMenuItem>
              <DropdownMenuItem v-if="isOwner && r.deposit_status === 'REFUND_PENDING'" @select="refund(r)">บันทึกคืนมัดจำ</DropdownMenuItem>
              <DropdownMenuItem
                v-if="['PENDING', 'CONFIRMED'].includes(r.status) && r.deposit_status !== 'PENDING_REVIEW'"
                class="text-danger-ink focus:bg-danger-soft focus:text-danger-ink"
                @select="openCancel(r)"
              >ยกเลิกการจอง</DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </li>
    </ul>

    <!-- ตรวจสลิป -->
    <Dialog v-model:open="slipDialog">
      <DialogContent class="max-h-[90dvh] grid-rows-[auto_minmax(0,1fr)_auto] sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>สลิปมัดจำ · {{ slipRow?.customer_name }}</DialogTitle>
          <DialogDescription>ตรวจยอดเงินเข้าบัญชีของสาขาจริงก่อนอนุมัติ</DialogDescription>
        </DialogHeader>
        <div v-if="slipDeposit" class="-mx-6 grid gap-4 overflow-y-auto px-6">
          <img v-if="slipUrl" :src="slipUrl" alt="สลิปการโอนมัดจำ" class="mx-auto max-h-[45vh] rounded-lg border border-border">
          <dl class="m-0 grid grid-cols-2 gap-x-4 gap-y-1.5 text-[15px]">
            <dt class="text-muted-foreground">ยอดมัดจำ</dt><dd class="num m-0 text-heading">{{ formatBaht(Number(slipDeposit.amount)) }}</dd>
            <dt class="text-muted-foreground">ยอดในสลิป</dt><dd class="num m-0 text-heading">{{ slipDeposit.slip_amount != null ? formatBaht(Number(slipDeposit.slip_amount)) : '—' }}</dd>
            <dt class="text-muted-foreground">เลขอ้างอิง</dt><dd class="num m-0 break-all">{{ slipDeposit.slip_trans_ref ?? '—' }}</dd>
            <dt class="text-muted-foreground">ผู้โอน</dt><dd class="m-0">{{ slipDeposit.slip_sender_name ?? '—' }}</dd>
            <dt class="text-muted-foreground">ผู้รับ</dt><dd class="m-0">{{ slipDeposit.slip_receiver_name ?? '—' }}</dd>
            <dt class="text-muted-foreground">ผลตรวจอัตโนมัติ</dt><dd class="m-0">{{ slipDeposit.provider_message ?? '—' }}</dd>
          </dl>
          <TextareaField v-if="slipDeposit.status === 'PENDING_REVIEW'" v-model="reviewNote" label="หมายเหตุ" hint="บังคับเมื่อปฏิเสธ" rows="2" />
        </div>
        <DialogFooter class="gap-2">
          <template v-if="slipDeposit?.status === 'PENDING_REVIEW'">
            <Button variant="outline" class="text-danger-ink" :disabled="saving" @click="review(false)">ปฏิเสธ</Button>
            <Button :disabled="saving" @click="review(true)">อนุมัติ</Button>
          </template>
          <Button v-else variant="outline" @click="slipDialog = false">ปิด</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>

    <!-- ยกเลิก -->
    <Dialog v-model:open="cancelDialog">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>ยกเลิกการจอง {{ cancelRow?.customer_name }}</DialogTitle>
          <DialogDescription>{{ cancelRow?.deposit_status === 'PAID' ? 'ยกเลิกก่อนนัดตามนโยบาย = คืนมัดจำ, ช้ากว่านั้น = ริบมัดจำ' : 'ลูกค้าจะเห็นสถานะยกเลิกในลิงก์ติดตาม' }}</DialogDescription>
        </DialogHeader>
        <form class="grid gap-4" @submit.prevent="submitCancel">
          <TextareaField v-model="cancelForm.reason" label="เหตุผล" hint="บังคับ" rows="2" />
          <CheckboxField v-if="isOwner && cancelRow?.deposit_status === 'PAID'" v-model="cancelForm.forceRefund"
            label="คืนมัดจำแม้ยกเลิกช้า (เช่น ร้านปิดฉุกเฉิน) ต้องยืนยันตัวตน" />
          <DialogFooter class="gap-2">
            <Button type="button" variant="outline" @click="cancelDialog = false">ปิด</Button>
            <Button type="submit" variant="destructive" :disabled="saving">ยืนยันยกเลิก</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>

    <!-- สร้างการจอง -->
    <Dialog v-model:open="createDialog">
      <DialogContent class="max-h-[90dvh] grid-rows-[auto_minmax(0,1fr)_auto] sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>สร้างการจอง</DialogTitle>
          <DialogDescription>{{ activeBranch?.name }} · {{ step === 1 ? 'ขั้นที่ 1 จาก 2: ลูกค้า' : step === 2 ? 'ขั้นที่ 2 จาก 2: บริการและเวลา' : 'เสร็จแล้ว' }}</DialogDescription>
        </DialogHeader>

        <div class="-mx-6 grid content-start gap-4 overflow-y-auto px-6">
          <template v-if="step === 1">
            <form class="flex items-end gap-2" @submit.prevent="searchCustomer">
              <TextField v-model="phone" numeric="digits" label="เบอร์โทรเต็ม" type="tel" class="num flex-1" />
              <Button type="submit"><Search /> ค้นหา</Button>
            </form>
            <div v-if="found?.length" class="grid gap-2" role="radiogroup" aria-label="เลือกลูกค้า">
              <button
                v-for="c in found"
                :key="c.customer_id"
                type="button"
                role="radio"
                :aria-checked="customerId === c.customer_id"
                class="flex items-center justify-between gap-3 rounded-lg border px-4 py-3 text-left transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
                :class="customerId === c.customer_id ? 'border-primary bg-secondary' : 'border-border hover:bg-muted'"
                @click="customerId = c.customer_id"
              >
                <span>
                  <span class="block font-medium text-heading">{{ c.display_name }}</span>
                  <span class="num block text-sm text-muted-foreground">{{ c.phone_masked }}</span>
                </span>
                <Badge :variant="c.is_member ? 'default' : 'neutral'">{{ c.is_member ? 'สมาชิก' : 'Guest' }}</Badge>
              </button>
            </div>
            <EmptyState v-else-if="found" compact title="ไม่พบลูกค้า" description="เพิ่มลูกค้าใหม่ได้ที่เมนู “ลูกค้า”" />
          </template>

          <template v-else-if="step === 2">
            <fieldset class="m-0 grid gap-2 border-0 p-0">
              <legend class="mb-1 text-sm font-medium text-heading">บริการ (คนละ 1 รายการ)</legend>
              <div v-for="(p, idx) in people" :key="idx" class="flex items-end gap-2">
                <SelectField v-model="p.option_id" :items="optionItems" :aria-label="`บริการของคนที่ ${idx + 1}`" :placeholder="`คนที่ ${idx + 1}: เลือกบริการ`" class="flex-1" />
                <Button v-if="people.length > 1" variant="ghost" size="icon" :aria-label="`ลบคนที่ ${idx + 1}`" @click="people.splice(idx, 1)"><X /></Button>
              </div>
              <Button v-if="people.length < 4" variant="outline" size="sm" class="w-fit" @click="people.push({ option_id: null })"><UserPlus /> เพิ่มคน</Button>
            </fieldset>

            <TextField v-model="newDate" type="date" label="วันที่" :min="bangkokToday()" class="w-52" />
            <div v-if="slots.length" class="grid grid-cols-4 gap-2 sm:grid-cols-6" role="radiogroup" aria-label="เวลาเริ่ม">
              <button
                v-for="s in slots"
                :key="s.starts_at"
                type="button"
                role="radio"
                :aria-checked="slot?.starts_at === s.starts_at"
                class="num h-10 rounded-lg border text-[15px] font-medium transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
                :class="slot?.starts_at === s.starts_at ? 'border-primary bg-primary text-primary-foreground' : 'border-border bg-card text-heading hover:bg-muted'"
                @click="slot = s"
              >{{ s.time }}</button>
            </div>
            <p v-else-if="optionIds.length === people.length" class="m-0 rounded-lg border border-dashed border-input px-4 py-3 text-[15px] text-muted-foreground">ไม่มีเวลาว่างในวันนี้</p>

            <TextareaField v-model="newNote" label="หมายเหตุ" rows="2" />
            <SwitchField v-model="collectDeposit" label="เก็บมัดจำ" hint="ส่งลิงก์ให้ลูกค้าชำระและส่งสลิป" />
          </template>

          <template v-else>
            <Alert variant="success"><AlertDescription>สร้างการจองแล้ว ส่งลิงก์นี้ให้ลูกค้าเพื่อชำระมัดจำ (ลิงก์ใช้ได้เฉพาะดูสถานะและชำระมัดจำ)</AlertDescription></Alert>
            <div class="flex items-end gap-2">
              <TextField :model-value="trackingLink ?? ''" readonly label="ลิงก์ชำระมัดจำ" class="flex-1" />
              <Button variant="outline" @click="copyLink"><Copy /> คัดลอก</Button>
            </div>
          </template>
        </div>

        <DialogFooter class="gap-2">
          <template v-if="step === 1">
            <Button variant="outline" @click="createDialog = false">ยกเลิก</Button>
            <Button :disabled="!customerId" @click="step = 2">ถัดไป</Button>
          </template>
          <template v-else-if="step === 2">
            <Button variant="outline" @click="step = 1">ย้อนกลับ</Button>
            <Button :disabled="!slot || saving" @click="submitCreate">สร้างการจอง</Button>
          </template>
          <Button v-else @click="createDialog = false">เสร็จสิ้น</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
