<script setup lang="ts">
// รายจ่าย: จำนวนเงิน + หมายเหตุ + รูปหลักฐาน (บังคับ) — ไม่ผูกกับลิ้นชัก (migration 034)
// ยกเลิก: เจ้าของร้านยกเลิกได้ทันที; พนักงานส่งคำขอให้เจ้าของร้าน
// OWNER: รายจ่ายสำนักงานใหญ่, อนุมัติ/ปฏิเสธคำขอยกเลิก
import { Camera, Image as ImageIcon, Plus } from '@lucide/vue'
import { addDays, bangkokToday, formatBaht, type ExpenseRow } from '@ifeew/shared'



const { prompt } = useDialog()
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
const form = reactive({ amount: '' as number | string, note: '', occurredOn: bangkokToday() })
const photo = ref<File | null>(null)
const photoPreview = ref<string | null>(null)

function openNew() {
  Object.assign(form, { amount: '', note: '', occurredOn: bangkokToday() })
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
      p_from_drawer: false,
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
  if (!r.photo_path) return
  const { data } = await supabase.storage.from('expense-photos').createSignedUrl(r.photo_path, 300)
  if (data?.signedUrl) window.open(data.signedUrl, '_blank', 'noopener')
}

async function voidExpense(r: ExpenseRow) {
  const reason = await prompt({
    title: r.void_requested_at ? 'อนุมัติยกเลิกรายจ่าย' : 'ยกเลิกรายจ่าย',
    label: 'เหตุผล',
    defaultValue: r.void_request_reason ?? '',
    minLength: 3,
    confirmText: r.void_requested_at ? 'อนุมัติยกเลิก' : 'ยกเลิกรายจ่าย',
    cancelText: 'ปิด',
    destructive: true,
  })
  if (reason === null) return
  try {
    const res = (await must(supabase.rpc('pos_void_expense', { p_expense_id: r.expense_id, p_reason: reason.trim() }))) as string
    message.value = { type: 'success', text: res === 'REQUESTED' ? 'ส่งคำขอยกเลิกให้เจ้าของร้านแล้ว' : 'ยกเลิกรายจ่ายแล้ว' }
    await load()
  } catch (e) {
    fail(e)
  }
}

async function rejectVoid(r: ExpenseRow) {
  const note = await prompt({ title: 'ไม่อนุมัติการยกเลิก', label: 'เหตุผล (ถ้ามี)', confirmText: 'ไม่อนุมัติ' })
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
  <div class="max-w-5xl">
    <PageHeader title="รายจ่าย" :description="`${scope === 'HQ' ? 'สำนักงานใหญ่' : activeBranch?.name ?? ''} · ทุกรายการต้องแนบรูปหลักฐาน`">
      <template #actions><Button @click="openNew"><Plus /> บันทึกรายจ่าย</Button></template>
    </PageHeader>

    <div class="mb-6 flex flex-wrap items-end gap-3 rounded-xl border border-border bg-card p-4">
      <div v-if="isOwner" class="grid gap-1.5">
        <span class="text-sm font-medium text-heading">ของ</span>
        <SegmentedControl v-model="scope" :items="[{ value: 'BRANCH', label: 'สาขา' }, { value: 'HQ', label: 'สำนักงานใหญ่' }]" label="รายจ่ายของ" />
      </div>
      <TextField v-model="from" type="date" label="ตั้งแต่" class="w-44" />
      <TextField v-model="to" type="date" label="ถึง" class="w-44" />
      <div class="ml-auto text-right">
        <p class="m-0 text-sm text-muted-foreground">รวมรายจ่าย (ไม่นับที่ยกเลิก)</p>
        <p class="num m-0 text-xl font-semibold text-heading">{{ formatBaht(total) }}</p>
      </div>
    </div>

    <MessageAlert :message="message" class="mb-4" @close="message = null" />
    <LoadingBar v-if="loading" class="mb-3" />
    <EmptyState v-if="!loading && !rows.length" title="ไม่มีรายจ่ายในช่วงนี้">
      <Button variant="outline" @click="openNew"><Plus /> บันทึกรายจ่าย</Button>
    </EmptyState>

    <SectionCard v-if="rows.length" flush>
      <ul class="m-0 grid list-none p-0">
        <li v-for="r in rows" :key="r.expense_id" class="flex flex-wrap items-start justify-between gap-3 border-b border-border px-5 py-4 last:border-0" :class="{ 'opacity-60': r.status === 'VOID' }">
          <div class="min-w-0">
            <p class="m-0 flex flex-wrap items-center gap-2 font-medium text-heading">
              <span :class="{ 'line-through': r.status === 'VOID' }"><span class="num">{{ formatBaht(Number(r.amount)) }}</span> · {{ r.note }}</span>
              <Badge v-if="r.category === 'FREELANCE_FUEL'" variant="outline">หมอวิ่ง</Badge>
              <Badge v-if="r.is_large" variant="danger">รายจ่ายสูง</Badge>
              <Badge v-if="r.status === 'VOID'" variant="neutral">ยกเลิกแล้ว</Badge>
            </p>
            <p class="m-0 text-sm text-muted-foreground">
              <span class="num">{{ r.occurred_on }}</span> · {{ r.recorded_by_name ?? '—' }}
            </p>
            <p v-if="r.void_requested_at && r.status === 'RECORDED'" class="m-0 mt-1 text-sm text-pending-ink">ขอยกเลิก: {{ r.void_request_reason }}</p>
            <p v-if="r.void_reason" class="m-0 mt-1 text-sm text-danger-ink">ยกเลิก: {{ r.void_reason }}</p>
          </div>
          <div class="flex flex-wrap gap-1">
            <Button v-if="r.photo_path" size="sm" variant="ghost" @click="viewPhoto(r)"><ImageIcon /> รูป</Button>
            <template v-if="r.status === 'RECORDED'">
              <template v-if="isOwner && r.void_requested_at">
                <Button size="sm" variant="outline" class="text-danger-ink" @click="voidExpense(r)">อนุมัติยกเลิก</Button>
                <Button size="sm" variant="ghost" @click="rejectVoid(r)">ไม่อนุมัติ</Button>
              </template>
              <Button v-else-if="!r.void_requested_at" size="sm" variant="ghost" class="text-danger-ink" @click="voidExpense(r)">
                {{ isOwner || r.session_open ? 'ยกเลิก' : 'ขอยกเลิก' }}
              </Button>
            </template>
          </div>
        </li>
      </ul>
    </SectionCard>

    <Dialog v-model:open="dialog">
      <DialogContent class="max-h-[90dvh] overflow-y-auto sm:max-w-md">
        <DialogHeader>
          <DialogTitle>บันทึกรายจ่าย</DialogTitle>
          <DialogDescription>{{ scope === 'HQ' ? 'สำนักงานใหญ่' : activeBranch?.name }}</DialogDescription>
        </DialogHeader>
        <form class="grid gap-4" @submit.prevent="save">
          <TextField v-model="form.amount" type="number" label="จำนวนเงิน" suffix="บาท" class="num" />
          <TextareaField v-model="form.note" label="หมายเหตุ" rows="2" placeholder="ซื้ออะไร ให้ใคร" />
          <div class="grid gap-2">
            <span class="text-sm font-medium text-heading">รูปหลักฐาน</span>
            <label class="flex cursor-pointer items-center justify-center gap-2 rounded-lg border border-dashed border-input bg-background/60 px-4 py-4 text-[15px] text-heading hover:bg-muted focus-within:ring-3 focus-within:ring-ring/50">
              <input type="file" accept="image/*" capture="environment" class="sr-only" @change="onPhoto">
              <Camera class="size-5 text-brand-accent" /> {{ photo ? 'เปลี่ยนรูป' : 'ถ่าย/เลือกรูปหลักฐาน' }}
            </label>
            <img v-if="photoPreview" :src="photoPreview" alt="รูปหลักฐาน" class="max-h-48 rounded-lg border border-border object-contain">
          </div>
          <TextField v-model="form.occurredOn" type="date" label="วันที่จ่าย" :max="bangkokToday()" />
          <Alert v-if="Number(form.amount) > threshold" variant="warning">
            <AlertDescription>เกิน {{ formatBaht(threshold) }} ถือเป็นรายจ่ายสูง ระบบจะแจ้งเจ้าของร้าน</AlertDescription>
          </Alert>
          <DialogFooter class="gap-2">
            <Button type="button" variant="outline" @click="dialog = false">ยกเลิก</Button>
            <Button type="submit" :disabled="saving">{{ saving ? 'กำลังบันทึก…' : 'บันทึก' }}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  </div>
</template>
