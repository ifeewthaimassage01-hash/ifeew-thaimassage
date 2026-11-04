<script setup lang="ts">
// รายจ่าย: จำนวนเงิน + หมายเหตุ + รูปหลักฐาน (บังคับ) — จ่ายจากลิ้นชักต้องมีกะเปิด
// ยกเลิก: กะยังเปิด = ยกเลิกทันที (เงินคืนลิ้นชัก); นอกนั้นส่งคำขอให้เจ้าของร้าน
// OWNER: รายจ่ายสำนักงานใหญ่, อนุมัติ/ปฏิเสธคำขอยกเลิก
import { addDays, bangkokToday, formatBaht, type ExpenseRow } from '@ifeew/shared'

const supabase = useSupabaseClient()
const { activeBranch, company, isOwner } = useAccess()

const scope = ref<'BRANCH' | 'HQ'>('BRANCH')
const from = ref(addDays(bangkokToday(), -6))
const to = ref(bangkokToday())
const rows = ref<ExpenseRow[]>([])
const loading = ref(false)
const saving = ref(false)
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)
const fail = (e: unknown) => (message.value = { type: 'error', text: errorText(e) })

const branchId = computed(() => (scope.value === 'HQ' ? null : activeBranch.value?.branch_id ?? null))
const total = computed(() => rows.value.filter((r) => r.status === 'RECORDED').reduce((s, r) => s + Number(r.amount), 0))
const threshold = ref(5000)

async function load() {
  if (!company.value || (scope.value === 'BRANCH' && !activeBranch.value)) return
  loading.value = true
  try {
    rows.value = (await must(supabase.rpc('expenses_list', {
      p_company_id: company.value.company_id, p_branch_id: branchId.value, p_from: from.value, p_to: to.value,
    }))) as unknown as ExpenseRow[]
  } catch (e) {
    fail(e)
  } finally {
    loading.value = false
  }
}
watch([scope, from, to, () => activeBranch.value?.branch_id, () => company.value?.company_id], load, { immediate: true })
watch(() => company.value?.company_id, async (id) => {
  if (!id) return
  const { data } = await supabase.from('company_settings').select('large_expense_threshold').eq('company_id', id).maybeSingle()
  if (data) threshold.value = Number(data.large_expense_threshold)
}, { immediate: true })

// ---------------------------------------------------------------------------
// บันทึกรายจ่าย
// ---------------------------------------------------------------------------
const dialog = ref(false)
const form = reactive({ amount: '' as number | string, note: '', fromDrawer: true, occurredOn: bangkokToday() })
const photo = ref<File | null>(null)
const photoPreview = ref<string | null>(null)

function openNew() {
  Object.assign(form, { amount: '', note: '', fromDrawer: scope.value === 'BRANCH', occurredOn: bangkokToday() })
  photo.value = null
  photoPreview.value = null
  dialog.value = true
}

function onPhoto(e: Event) {
  const file = (e.target as HTMLInputElement).files?.[0] ?? null
  if (file && (file.size > 5 * 1024 * 1024 || !['image/jpeg', 'image/png', 'image/webp'].includes(file.type))) {
    message.value = { type: 'error', text: 'รองรับรูป JPG/PNG/WebP ไม่เกิน 5 MB' }
    return
  }
  photo.value = file
  photoPreview.value = file ? URL.createObjectURL(file) : null
}

async function save() {
  if (!company.value || !photo.value || !(Number(form.amount) > 0) || !form.note.trim()) {
    message.value = { type: 'error', text: 'กรุณากรอกจำนวนเงิน หมายเหตุ และแนบรูป' }
    return
  }
  saving.value = true
  try {
    const ext = photo.value.type === 'image/png' ? 'png' : photo.value.type === 'image/webp' ? 'webp' : 'jpg'
    const path = `${company.value.company_id}/${branchId.value ?? 'hq'}/${crypto.randomUUID()}.${ext}`
    const { error: upErr } = await supabase.storage.from('expense-photos').upload(path, photo.value, { contentType: photo.value.type })
    if (upErr) throw upErr
    await must(supabase.rpc('pos_record_expense', {
      p_company_id: company.value.company_id,
      p_branch_id: branchId.value,
      p_amount: Number(form.amount),
      p_note: form.note.trim(),
      p_photo_path: path,
      p_from_drawer: scope.value === 'BRANCH' && form.fromDrawer,
      p_occurred_on: form.occurredOn,
    }))
    dialog.value = false
    message.value = { type: 'success', text: Number(form.amount) > threshold.value ? 'บันทึกแล้ว (รายจ่ายสูง แจ้งเจ้าของร้าน)' : 'บันทึกรายจ่ายแล้ว' }
    await load()
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}

async function viewPhoto(r: ExpenseRow) {
  const { data } = await supabase.storage.from('expense-photos').createSignedUrl(r.photo_path, 300)
  if (data?.signedUrl) window.open(data.signedUrl, '_blank', 'noopener')
}

async function voidExpense(r: ExpenseRow) {
  const reason = window.prompt(r.void_requested_at ? 'อนุมัติยกเลิก: เหตุผล' : 'เหตุผลที่ยกเลิก (บังคับ)', r.void_request_reason ?? '')
  if (!reason || reason.trim().length < 3) return
  try {
    const res = (await must(supabase.rpc('pos_void_expense', { p_expense_id: r.expense_id, p_reason: reason.trim() }))) as string
    message.value = { type: 'success', text: res === 'REQUESTED' ? 'ส่งคำขอยกเลิกให้เจ้าของร้านแล้ว' : 'ยกเลิกรายจ่ายแล้ว' }
    await load()
  } catch (e) {
    fail(e)
  }
}

async function rejectVoid(r: ExpenseRow) {
  const note = window.prompt('เหตุผลที่ไม่อนุมัติ', '')
  if (note === null) return
  try {
    await must(supabase.rpc('pos_reject_expense_void', { p_expense_id: r.expense_id, p_note: note.trim() || null }))
    await load()
  } catch (e) {
    fail(e)
  }
}
</script>

<template>
  <div class="max-w-4xl">
    <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
      <h1 class="m-0 text-2xl font-semibold text-cocoa">รายจ่าย · {{ scope === 'HQ' ? 'สำนักงานใหญ่' : activeBranch?.name }}</h1>
      <v-btn color="primary" prepend-icon="mdi-plus" @click="openNew">บันทึกรายจ่าย</v-btn>
    </div>
    <div class="mb-4 flex flex-wrap items-center gap-2">
      <v-btn-toggle v-if="isOwner" v-model="scope" mandatory color="primary" density="comfortable">
        <v-btn value="BRANCH">สาขา</v-btn>
        <v-btn value="HQ">สำนักงานใหญ่</v-btn>
      </v-btn-toggle>
      <v-text-field v-model="from" type="date" label="ตั้งแต่" hide-details density="compact" class="max-w-44" />
      <v-text-field v-model="to" type="date" label="ถึง" hide-details density="compact" class="max-w-44" />
      <span class="ml-auto font-medium">รวม {{ formatBaht(total) }}</span>
    </div>

    <v-alert v-if="message" :type="message.type" variant="tonal" class="mb-4" closable :text="message.text" @click:close="message = null" />
    <v-progress-linear v-if="loading" indeterminate color="primary" />
    <p v-if="!loading && !rows.length" class="text-light-brown">ไม่มีรายจ่ายในช่วงนี้</p>

    <div class="grid gap-2">
      <v-card v-for="r in rows" :key="r.expense_id" class="p-4" :class="{ 'opacity-60': r.status === 'VOID' }">
        <div class="flex flex-wrap items-start justify-between gap-2">
          <div class="min-w-0">
            <p class="m-0 font-medium" :class="{ 'line-through': r.status === 'VOID' }">
              {{ formatBaht(Number(r.amount)) }} · {{ r.note }}
              <v-chip v-if="r.is_large" size="x-small" color="error" variant="tonal">รายจ่ายสูง</v-chip>
            </p>
            <p class="m-0 text-sm text-light-brown">
              {{ r.occurred_on }} · {{ r.payment_source === 'CASH_DRAWER' ? 'จ่ายจากลิ้นชัก' : 'จ่ายทางอื่น' }} · {{ r.recorded_by_name ?? '-' }}
            </p>
            <p v-if="r.void_requested_at && r.status === 'RECORDED'" class="m-0 text-sm text-orange-800">ขอยกเลิก: {{ r.void_request_reason }}</p>
            <p v-if="r.void_reason" class="m-0 text-sm text-red-700">ยกเลิก: {{ r.void_reason }}</p>
          </div>
          <div class="flex flex-wrap gap-1">
            <v-btn size="small" variant="text" prepend-icon="mdi-image-outline" @click="viewPhoto(r)">รูป</v-btn>
            <template v-if="r.status === 'RECORDED'">
              <template v-if="isOwner && r.void_requested_at">
                <v-btn size="small" color="error" variant="tonal" @click="voidExpense(r)">อนุมัติยกเลิก</v-btn>
                <v-btn size="small" variant="text" @click="rejectVoid(r)">ไม่อนุมัติ</v-btn>
              </template>
              <v-btn v-else-if="!r.void_requested_at" size="small" variant="text" color="error" @click="voidExpense(r)">
                {{ isOwner || r.session_open ? 'ยกเลิก' : 'ขอยกเลิก' }}
              </v-btn>
            </template>
          </div>
        </div>
      </v-card>
    </div>

    <v-dialog v-model="dialog" max-width="460" scrollable>
      <v-card class="p-6">
        <p class="m-0 mb-3 text-lg font-medium">บันทึกรายจ่าย</p>
        <v-text-field v-model="form.amount" type="number" label="จำนวนเงิน (บาท)" />
        <v-textarea v-model="form.note" label="หมายเหตุ" rows="2" variant="outlined" />
        <label class="mb-3 block">
          <input type="file" accept="image/*" capture="environment" class="hidden" @change="onPhoto" >
          <v-btn tag="span" prepend-icon="mdi-camera" variant="tonal">{{ photo ? 'เปลี่ยนรูป' : 'ถ่าย/เลือกรูปหลักฐาน' }}</v-btn>
        </label>
        <img v-if="photoPreview" :src="photoPreview" alt="รูปหลักฐาน" class="mb-3 max-h-48 rounded-lg" >
        <v-text-field v-model="form.occurredOn" type="date" label="วันที่จ่าย" :max="bangkokToday()" />
        <v-switch v-if="scope === 'BRANCH'" v-model="form.fromDrawer" color="primary" hide-details
          label="จ่ายจากเงินสดในลิ้นชัก (ต้องเปิดกะอยู่)" />
        <p v-if="Number(form.amount) > threshold" class="m-0 mt-2 text-sm text-red-700">
          เกิน {{ formatBaht(threshold) }} = รายจ่ายสูง ระบบจะแจ้งเจ้าของร้าน
        </p>
        <div class="mt-4 flex justify-end gap-2">
          <v-btn variant="text" @click="dialog = false">ยกเลิก</v-btn>
          <v-btn color="primary" :loading="saving" @click="save">บันทึก</v-btn>
        </div>
      </v-card>
    </v-dialog>
  </div>
</template>
