<script setup lang="ts">
// ปิดยอดรายวัน: พนักงานดูสรุปและส่ง (ต้องปิดกะครบ) → OWNER อนุมัติ (+ยอดปรับปรุง) / ปฏิเสธพร้อมเหตุผล
import { addDays, bangkokToday, formatBaht, type DailyClosingFigures, type DailyClosingRow } from '@ifeew/shared'

const supabase = useSupabaseClient()
const { activeBranch, company, isOwner } = useAccess()

const date = ref(bangkokToday())
const preview = ref<(DailyClosingFigures & { closing: { status: string; review_note: string | null } | null }) | null>(null)
const list = ref<DailyClosingRow[]>([])
const note = ref('')
const saving = ref(false)
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)
const fail = (e: unknown) => (message.value = { type: 'error', text: errorText(e) })

async function load() {
  if (!activeBranch.value || !company.value) return
  try {
    const [p, l] = await Promise.all([
      must(supabase.rpc('daily_closing_preview', { p_branch_id: activeBranch.value.branch_id, p_date: date.value })),
      must(supabase.rpc('daily_closings_list', {
        p_company_id: company.value.company_id, p_branch_id: isOwner.value ? null : activeBranch.value.branch_id,
        p_from: addDays(bangkokToday(), -30), p_to: bangkokToday(),
      })),
    ])
    preview.value = p as unknown as typeof preview.value
    list.value = l as unknown as DailyClosingRow[]
  } catch (e) {
    fail(e)
  }
}
watch([date, () => activeBranch.value?.branch_id], load, { immediate: true })

const canSubmit = computed(() =>
  !!preview.value && preview.value.open_sessions === 0 && preview.value.sessions > 0
  && (!preview.value.closing || preview.value.closing.status === 'REJECTED'))

async function submit() {
  if (!activeBranch.value) return
  saving.value = true
  try {
    await must(supabase.rpc('submit_daily_closing', { p_branch_id: activeBranch.value.branch_id, p_date: date.value, p_note: note.value.trim() || null }))
    message.value = { type: 'success', text: 'ส่งปิดยอดแล้ว รอเจ้าของร้านตรวจ' }
    note.value = ''
    await load()
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}

const reviewDialog = ref(false)
const reviewRow = ref<DailyClosingRow | null>(null)
const reviewForm = reactive({ note: '', adjustment: '' as number | string, adjustmentNote: '' })
function openReview(r: DailyClosingRow) {
  reviewRow.value = r
  Object.assign(reviewForm, { note: '', adjustment: '', adjustmentNote: '' })
  reviewDialog.value = true
}
async function review(approve: boolean) {
  if (!reviewRow.value) return
  saving.value = true
  try {
    await must(supabase.rpc('review_daily_closing', {
      p_closing_id: reviewRow.value.closing_id, p_approve: approve, p_note: reviewForm.note.trim() || null,
      p_adjustment_amount: Number(reviewForm.adjustment) || 0, p_adjustment_note: reviewForm.adjustmentNote.trim() || null,
    }))
    reviewDialog.value = false
    await load()
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}
const statusLabels = { SUBMITTED: 'รอตรวจ', APPROVED: 'อนุมัติแล้ว', REJECTED: 'ปฏิเสธ' } as const
const lines = (f: DailyClosingFigures): Array<[string, number]> => [
  ['เงินสด', f.cash_sales], ['โอน', f.transfer_sales], ['QR', f.qr_sales], ['มัดจำที่หัก', f.deposit_applied],
  ['มัดจำที่ริบ', f.forfeited_deposits], ['คืนเงิน', -f.refunds], ['รายรับสุทธิ', f.net_revenue], ['รายจ่าย', f.expenses],
  ['ผลต่างเงินสดของกะ', f.cash_difference], ['ทิป (ไม่ใช่รายได้)', f.tips], ['ค่ามือของวัน', f.service_commission], ['ค้างชำระ', f.outstanding],
]
</script>

<template>
  <div class="max-w-4xl">
    <h1 class="m-0 mb-4 text-2xl font-semibold text-cocoa">ปิดยอดรายวัน · {{ activeBranch?.name }}</h1>
    <v-alert v-if="message" :type="message.type" variant="tonal" class="mb-4" closable :text="message.text" @click:close="message = null" />

    <v-card class="mb-6 p-5">
      <div class="mb-3 flex flex-wrap items-center gap-2">
        <v-text-field v-model="date" type="date" label="วันทำการ" :max="bangkokToday()" hide-details density="compact" class="max-w-48" />
        <v-chip v-if="preview?.closing" size="small" variant="tonal">{{ statusLabels[preview.closing.status as 'SUBMITTED'] }}</v-chip>
      </div>
      <template v-if="preview">
        <div class="grid grid-cols-2 gap-x-8 gap-y-1 text-sm md:grid-cols-3">
          <span v-for="[l, v] in lines(preview)" :key="l">{{ l }} <b class="float-right">{{ formatBaht(Number(v)) }}</b></span>
        </div>
        <div v-if="preview.guarantee_topups.length" class="mt-3 text-sm">
          <p class="m-0 font-medium">ประกันมือ (คำนวณอัตโนมัติ)</p>
          <p v-for="g in preview.guarantee_topups" :key="g.employee_id" class="m-0">
            {{ g.nickname }}: ค่ามือ {{ formatBaht(Number(g.earned)) }} / ประกัน {{ formatBaht(Number(g.rate)) }}
            → {{ g.qualified ? `เติม ${formatBaht(Number(g.topup))}` : 'ไม่ครบกะ ไม่ได้ประกัน' }}
          </p>
        </div>
        <p v-if="preview.open_sessions" class="m-0 mt-3 text-sm text-red-700">ยังมีกะเปิดอยู่ {{ preview.open_sessions }} กะ — ปิดกะก่อนส่งปิดยอด</p>
        <p v-if="preview.rejected_sessions" class="m-0 mt-1 text-sm text-red-700">มีกะที่เจ้าของร้านปฏิเสธ {{ preview.rejected_sessions }} กะ</p>
        <p v-if="preview.closing?.review_note" class="m-0 mt-1 text-sm">ผลตรวจ: {{ preview.closing.review_note }}</p>
        <div v-if="canSubmit" class="mt-4 flex flex-wrap items-center gap-2">
          <v-text-field v-model="note" label="หมายเหตุ (ถ้ามี)" hide-details density="compact" />
          <v-btn color="primary" :loading="saving" @click="submit">ส่งปิดยอด</v-btn>
        </div>
      </template>
    </v-card>

    <p class="m-0 mb-2 font-medium">ประวัติ 30 วัน</p>
    <div class="grid gap-2">
      <v-card v-for="r in list" :key="r.closing_id" class="p-4">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div>
            <p class="m-0 font-medium">{{ r.business_date }} · {{ r.branch_name }} · รายรับสุทธิ {{ formatBaht(Number(r.figures.net_revenue)) }}</p>
            <p class="m-0 text-sm text-light-brown">
              ส่งโดย {{ r.submitted_by_name ?? '-' }}<template v-if="r.submit_note"> · {{ r.submit_note }}</template>
              <template v-if="Number(r.adjustment_amount)"> · ปรับปรุง {{ formatBaht(Number(r.adjustment_amount)) }} ({{ r.adjustment_note }})</template>
              <template v-if="r.review_note"> · {{ r.review_note }}</template>
            </p>
          </div>
          <div class="flex items-center gap-2">
            <v-chip size="small" variant="tonal" :color="r.status === 'APPROVED' ? 'success' : r.status === 'REJECTED' ? 'error' : 'warning'">
              {{ statusLabels[r.status] }}</v-chip>
            <v-btn v-if="isOwner && r.status === 'SUBMITTED'" size="small" color="primary" @click="openReview(r)">ตรวจ</v-btn>
          </div>
        </div>
      </v-card>
    </div>

    <v-dialog v-model="reviewDialog" max-width="480">
      <v-card v-if="reviewRow" class="p-6">
        <p class="m-0 mb-3 text-lg font-medium">ตรวจปิดยอด {{ reviewRow.business_date }} · {{ reviewRow.branch_name }}</p>
        <v-text-field v-model="reviewForm.adjustment" type="number" label="ยอดปรับปรุง (ถ้ามี เช่น เงินขาด = ลบ)" />
        <v-text-field v-if="Number(reviewForm.adjustment)" v-model="reviewForm.adjustmentNote" label="เหตุผลของยอดปรับปรุง" />
        <v-textarea v-model="reviewForm.note" label="หมายเหตุ (บังคับเมื่อปฏิเสธ)" rows="2" variant="outlined" />
        <div class="flex justify-end gap-2">
          <v-btn variant="text" color="error" :loading="saving" @click="review(false)">ปฏิเสธ</v-btn>
          <v-btn color="primary" :loading="saving" @click="review(true)">อนุมัติ</v-btn>
        </div>
      </v-card>
    </v-dialog>
  </div>
</template>
