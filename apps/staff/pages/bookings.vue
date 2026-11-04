<script setup lang="ts">
// การจองของสาขา (รายวัน): สร้างการจองให้ลูกค้า, ตรวจสลิปมัดจำ, ยกเลิก, ไม่มาตามนัด, คืนมัดจำ (OWNER)
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

const statusColor = (s: string) =>
  ({ CONFIRMED: 'success', PENDING: 'warning', CANCELLED: 'error', EXPIRED: 'grey', NO_SHOW: 'error', CHECKED_IN: 'primary', COMPLETED: 'primary' })[s] ?? 'grey'

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
  if (!window.confirm(`บันทึกว่า ${r.customer_name} ไม่มาตามนัด? (มัดจำจะถูกริบ)`)) return
  try {
    await must(supabase.rpc('mark_no_show', { p_booking_id: r.booking_id }))
    ok('บันทึกไม่มาตามนัดแล้ว')
    await load()
  } catch (e) {
    fail(e)
  }
}

async function refund(r: StaffBookingRow) {
  const ref = window.prompt(`เลขอ้างอิงการโอนคืนมัดจำ ${formatBaht(Number(r.deposit_required))} ให้ ${r.customer_name}`)
  if (!ref || ref.trim().length < 3) return
  try {
    await run(() => must(supabase.rpc('record_deposit_refund', { p_booking_id: r.booking_id, p_reference: ref.trim() })))
    ok('บันทึกการคืนมัดจำแล้ว')
    await load()
  } catch (e) {
    fail(e)
  }
}

async function editNote(r: StaffBookingRow) {
  const note = window.prompt('หมายเหตุของร้าน (ลูกค้าไม่เห็น)', r.staff_note ?? '')
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
  <div>
    <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
      <h1 class="m-0 text-2xl font-semibold text-cocoa">การจอง · {{ activeBranch?.name }}</h1>
      <div class="flex flex-wrap items-center gap-2">
        <v-btn icon="mdi-chevron-left" variant="text" aria-label="วันก่อน" @click="date = addDays(date, -1)" />
        <v-text-field v-model="date" type="date" hide-details density="compact" class="w-44" />
        <v-btn icon="mdi-chevron-right" variant="text" aria-label="วันถัดไป" @click="date = addDays(date, 1)" />
        <v-btn variant="text" @click="date = bangkokToday()">วันนี้</v-btn>
        <v-btn color="primary" prepend-icon="mdi-calendar-plus" @click="openCreate">สร้างการจอง</v-btn>
      </div>
    </div>

    <v-alert v-if="message" :type="message.type" variant="tonal" class="mb-4" closable :text="message.text" @click:close="message = null" />

    <v-btn-toggle v-model="statusFilter" mandatory color="primary" density="comfortable" class="mb-4">
      <v-btn value="ACTIVE">กำลังดำเนินการ</v-btn>
      <v-btn value="REVIEW">รอตรวจสลิป <v-badge v-if="reviewCount" :content="reviewCount" color="error" inline /></v-btn>
      <v-btn value="ALL">ทั้งหมด</v-btn>
    </v-btn-toggle>

    <v-progress-linear v-if="loading" indeterminate color="primary" />
    <p v-else-if="!visible.length" class="text-light-brown">ไม่มีการจอง</p>

    <div class="grid gap-3">
      <v-card v-for="r in visible" :key="r.booking_id" class="p-4">
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div class="min-w-0">
            <p class="m-0 text-lg font-medium">
              {{ bangkokTime(r.starts_at) }}–{{ bangkokTime(r.ends_at) }} · {{ r.customer_name }}
              <v-chip v-if="r.is_member" size="x-small" color="primary" variant="tonal">สมาชิก</v-chip>
            </p>
            <p class="m-0 text-sm text-light-brown">
              {{ r.booking_code ?? 'ยังไม่มีรหัส' }} · {{ r.phone_masked }} · {{ r.channel === 'ONLINE' ? 'ออนไลน์' : 'พนักงาน' }}
            </p>
            <p class="m-0 mt-1 text-sm">
              {{ r.items.map((i, n) => `คนที่ ${n + 1}: ${i.service_name} ${formatDuration(i.duration_minutes)}`).join(' · ') }}
              — {{ formatBaht(Number(r.total_amount)) }}
            </p>
            <p v-if="r.customer_note" class="m-0 text-sm">ลูกค้า: {{ r.customer_note }}</p>
            <p v-if="r.staff_note" class="m-0 text-sm text-light-brown">ร้าน: {{ r.staff_note }}</p>
            <p v-if="r.cancel_reason" class="m-0 text-sm text-red-700">{{ r.cancel_reason }}</p>
          </div>
          <div class="flex flex-col items-end gap-1">
            <v-chip :color="statusColor(r.status)" variant="tonal" size="small">{{ bookingStatusLabels[r.status] }}</v-chip>
            <v-chip v-if="r.deposit_status !== 'NOT_REQUIRED'" size="small" variant="outlined">
              {{ depositStatusLabels[r.deposit_status] }} {{ formatBaht(Number(r.deposit_required)) }}
            </v-chip>
          </div>
        </div>

        <div v-if="r.deposits?.length" class="mt-2 flex flex-wrap gap-2">
          <v-chip
            v-for="d in r.deposits"
            :key="d.deposit_id"
            size="small"
            :color="d.status === 'VERIFIED' ? 'success' : d.status === 'REJECTED' ? 'error' : 'warning'"
            variant="tonal"
            prepend-icon="mdi-receipt-text-outline"
            @click="openSlip(r, d)"
          >
            สลิป {{ d.status === 'VERIFIED' ? 'ผ่าน' : d.status === 'REJECTED' ? 'ไม่ผ่าน' : 'รอตรวจ' }}
          </v-chip>
        </div>

        <div class="mt-3 flex flex-wrap gap-2">
          <v-btn v-if="['PENDING', 'CONFIRMED'].includes(r.status) && r.deposit_status !== 'PENDING_REVIEW'"
            size="small" variant="text" color="error" @click="openCancel(r)">ยกเลิก</v-btn>
          <v-btn v-if="r.status === 'CONFIRMED'" size="small" variant="text" @click="noShow(r)">ไม่มาตามนัด</v-btn>
          <v-btn v-if="isOwner && r.deposit_status === 'REFUND_PENDING'" size="small" variant="tonal" color="primary" @click="refund(r)">
            บันทึกคืนมัดจำ
          </v-btn>
          <v-btn size="small" variant="text" prepend-icon="mdi-note-edit-outline" @click="editNote(r)">หมายเหตุ</v-btn>
        </div>
      </v-card>
    </div>

    <!-- ตรวจสลิป -->
    <v-dialog v-model="slipDialog" max-width="560" scrollable>
      <v-card v-if="slipDeposit" class="p-6">
        <p class="m-0 mb-2 text-lg font-medium">สลิปมัดจำ · {{ slipRow?.customer_name }}</p>
        <img v-if="slipUrl" :src="slipUrl" alt="สลิป" class="mx-auto mb-3 max-h-[50vh] rounded-lg" >
        <div class="grid grid-cols-2 gap-1 text-sm">
          <span class="text-light-brown">ยอดมัดจำ</span><span>{{ formatBaht(Number(slipDeposit.amount)) }}</span>
          <span class="text-light-brown">ยอดในสลิป</span><span>{{ slipDeposit.slip_amount != null ? formatBaht(Number(slipDeposit.slip_amount)) : '-' }}</span>
          <span class="text-light-brown">เลขอ้างอิง</span><span>{{ slipDeposit.slip_trans_ref ?? '-' }}</span>
          <span class="text-light-brown">ผู้โอน</span><span>{{ slipDeposit.slip_sender_name ?? '-' }}</span>
          <span class="text-light-brown">ผู้รับ</span><span>{{ slipDeposit.slip_receiver_name ?? '-' }}</span>
          <span class="text-light-brown">ผลตรวจอัตโนมัติ</span><span>{{ slipDeposit.provider_message ?? '-' }}</span>
        </div>
        <template v-if="slipDeposit.status === 'PENDING_REVIEW'">
          <p class="m-0 mt-3 text-xs text-light-brown">ตรวจยอดเงินเข้าบัญชีของสาขาจริงก่อนอนุมัติ</p>
          <v-textarea v-model="reviewNote" class="mt-2" label="หมายเหตุ (บังคับเมื่อปฏิเสธ)" rows="2" variant="outlined" />
          <div class="flex justify-end gap-2">
            <v-btn variant="text" color="error" :loading="saving" @click="review(false)">ปฏิเสธ</v-btn>
            <v-btn color="primary" :loading="saving" @click="review(true)">อนุมัติ</v-btn>
          </div>
        </template>
        <div v-else class="mt-3 flex justify-end"><v-btn variant="text" @click="slipDialog = false">ปิด</v-btn></div>
      </v-card>
    </v-dialog>

    <!-- ยกเลิก -->
    <v-dialog v-model="cancelDialog" max-width="480">
      <v-card class="p-6">
        <p class="m-0 mb-2 text-lg font-medium">ยกเลิกการจอง {{ cancelRow?.customer_name }}</p>
        <p v-if="cancelRow?.deposit_status === 'PAID'" class="m-0 mb-3 text-sm text-light-brown">
          ยกเลิกก่อนนัดตามนโยบาย = คืนมัดจำ, ช้ากว่านั้น = ริบมัดจำ
        </p>
        <v-textarea v-model="cancelForm.reason" label="เหตุผล (บังคับ)" rows="2" variant="outlined" />
        <v-checkbox v-if="isOwner && cancelRow?.deposit_status === 'PAID'" v-model="cancelForm.forceRefund" color="primary" hide-details
          label="คืนมัดจำแม้ยกเลิกช้า (เช่น ร้านปิดฉุกเฉิน) — ต้องยืนยันตัวตน" />
        <div class="mt-3 flex justify-end gap-2">
          <v-btn variant="text" @click="cancelDialog = false">ปิด</v-btn>
          <v-btn color="error" :loading="saving" @click="submitCancel">ยืนยันยกเลิก</v-btn>
        </div>
      </v-card>
    </v-dialog>

    <!-- สร้างการจอง -->
    <v-dialog v-model="createDialog" max-width="620" scrollable>
      <v-card class="p-6">
        <p class="m-0 mb-4 text-lg font-medium">สร้างการจอง · {{ activeBranch?.name }}</p>

        <template v-if="step === 1">
          <p class="m-0 mb-2 text-sm font-medium">1. ลูกค้า</p>
          <v-form class="flex gap-2" @submit.prevent="searchCustomer">
            <v-text-field v-model="phone" label="เบอร์โทรเต็ม" type="tel" hide-details />
            <v-btn type="submit" color="primary" class="!h-auto">ค้นหา</v-btn>
          </v-form>
          <v-list v-if="found?.length" class="mt-2">
            <v-list-item
              v-for="c in found"
              :key="c.customer_id"
              :title="c.display_name"
              :subtitle="`${c.phone_masked} · ${c.is_member ? 'สมาชิก' : 'Guest'}`"
              :active="customerId === c.customer_id"
              rounded="lg"
              @click="customerId = c.customer_id"
            />
          </v-list>
          <p v-else-if="found" class="m-0 mt-2 text-sm text-light-brown">ไม่พบลูกค้า เพิ่มลูกค้าใหม่ได้ที่เมนู “ลูกค้า”</p>
          <div class="mt-4 flex justify-end gap-2">
            <v-btn variant="text" @click="createDialog = false">ยกเลิก</v-btn>
            <v-btn color="primary" :disabled="!customerId" @click="step = 2">ถัดไป</v-btn>
          </div>
        </template>

        <template v-else-if="step === 2">
          <p class="m-0 mb-2 text-sm font-medium">2. บริการ (คนละ 1 รายการ)</p>
          <div v-for="(p, idx) in people" :key="idx" class="flex items-center gap-2">
            <v-select v-model="p.option_id" :items="optionItems" :label="`คนที่ ${idx + 1}`" hide-details class="mb-2" />
            <v-btn v-if="people.length > 1" icon="mdi-close" variant="text" size="small" aria-label="ลบ" @click="people.splice(idx, 1)" />
          </div>
          <v-btn v-if="people.length < 4" variant="text" size="small" prepend-icon="mdi-plus" @click="people.push({ option_id: null })">เพิ่มคน</v-btn>

          <p class="m-0 mb-2 mt-4 text-sm font-medium">3. วันและเวลา</p>
          <v-text-field v-model="newDate" type="date" label="วันที่" :min="bangkokToday()" />
          <div class="grid grid-cols-5 gap-2">
            <v-btn v-for="s in slots" :key="s.starts_at" size="small"
              :color="slot?.starts_at === s.starts_at ? 'primary' : undefined"
              :variant="slot?.starts_at === s.starts_at ? 'flat' : 'outlined'" @click="slot = s">{{ s.time }}</v-btn>
          </div>
          <p v-if="optionIds.length === people.length && !slots.length" class="m-0 text-sm text-light-brown">ไม่มีเวลาว่าง</p>

          <v-textarea v-model="newNote" class="mt-3" label="หมายเหตุ" rows="2" variant="outlined" />
          <v-switch v-model="collectDeposit" color="primary" hide-details
            label="เก็บมัดจำ (ส่งลิงก์ให้ลูกค้าชำระและส่งสลิป)" />
          <div class="mt-4 flex justify-end gap-2">
            <v-btn variant="text" @click="step = 1">ย้อนกลับ</v-btn>
            <v-btn color="primary" :disabled="!slot" :loading="saving" @click="submitCreate">สร้างการจอง</v-btn>
          </div>
        </template>

        <template v-else>
          <v-alert type="success" variant="tonal" class="mb-3" text="สร้างการจองแล้ว ส่งลิงก์นี้ให้ลูกค้าเพื่อชำระมัดจำ (ลิงก์ใช้ได้เฉพาะดูสถานะและชำระมัดจำ)" />
          <v-text-field :model-value="trackingLink" readonly label="ลิงก์ชำระมัดจำ" />
          <div class="flex justify-end gap-2">
            <v-btn variant="tonal" prepend-icon="mdi-content-copy" @click="copyLink">คัดลอก</v-btn>
            <v-btn color="primary" @click="createDialog = false">เสร็จสิ้น</v-btn>
          </div>
        </template>
      </v-card>
    </v-dialog>
  </div>
</template>
