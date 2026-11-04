<script setup lang="ts">
// กะ POS ของสาขา: ยอดปิดกะ ผลต่างเงินสด และการตรวจของเจ้าของร้าน (อนุมัติ/ปฏิเสธพร้อมเหตุผล)
import { addDays, bangkokTime, bangkokToday, formatBaht, type SessionRow } from '@ifeew/shared'

const supabase = useSupabaseClient()
const { activeBranch, isOwner } = useAccess()

const from = ref(addDays(bangkokToday(), -6))
const to = ref(bangkokToday())
const rows = ref<SessionRow[]>([])
const loading = ref(false)
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)

async function load() {
  if (!activeBranch.value) return
  loading.value = true
  try {
    rows.value = (await must(supabase.rpc('pos_sessions_list', {
      p_branch_id: activeBranch.value.branch_id, p_from: from.value, p_to: to.value,
    }))) as unknown as SessionRow[]
  } catch (e) {
    message.value = { type: 'error', text: errorText(e, 'โหลดไม่สำเร็จ') }
  } finally {
    loading.value = false
  }
}
watch([from, to, () => activeBranch.value?.branch_id], load, { immediate: true })

const reviewLabels = { PENDING: 'รอตรวจ', APPROVED: 'อนุมัติแล้ว', REJECTED: 'ปฏิเสธ' } as const

async function review(r: SessionRow, approve: boolean) {
  const note = approve ? window.prompt('หมายเหตุ (ถ้ามี)', '') : window.prompt('เหตุผลที่ปฏิเสธ (บังคับ)', '')
  if (note === null) return
  try {
    await must(supabase.rpc('pos_review_session', { p_session_id: r.session_id, p_approve: approve, p_note: note.trim() || null }))
    message.value = { type: 'success', text: approve ? 'อนุมัติกะแล้ว' : 'ปฏิเสธกะแล้ว' }
    await load()
  } catch (e) {
    message.value = { type: 'error', text: errorText(e) }
  }
}
</script>

<template>
  <div class="max-w-5xl">
    <h1 class="m-0 mb-4 text-2xl font-semibold text-cocoa">กะและเงินสด · {{ activeBranch?.name }}</h1>
    <div class="mb-4 flex flex-wrap gap-2">
      <v-text-field v-model="from" type="date" label="ตั้งแต่" hide-details density="compact" class="max-w-44" />
      <v-text-field v-model="to" type="date" label="ถึง" hide-details density="compact" class="max-w-44" />
    </div>
    <v-alert v-if="message" :type="message.type" variant="tonal" class="mb-4" closable :text="message.text" @click:close="message = null" />
    <v-progress-linear v-if="loading" indeterminate color="primary" />
    <p v-if="!loading && !rows.length" class="text-light-brown">ไม่มีกะในช่วงนี้</p>

    <div class="grid gap-3">
      <v-card v-for="r in rows" :key="r.session_id" class="p-4">
        <div class="flex flex-wrap items-start justify-between gap-2">
          <div>
            <p class="m-0 font-medium">
              {{ r.business_date }} · {{ bangkokTime(r.opened_at) }}–{{ r.closed_at ? bangkokTime(r.closed_at) : 'ยังเปิดอยู่' }}
            </p>
            <p class="m-0 text-sm text-light-brown">
              เปิดโดย {{ r.opened_by_name ?? '-' }}<template v-if="r.closed_by_name"> · ปิดโดย {{ r.closed_by_name }}</template>
            </p>
          </div>
          <v-chip v-if="r.review_status" size="small" variant="tonal"
            :color="r.review_status === 'APPROVED' ? 'success' : r.review_status === 'REJECTED' ? 'error' : 'warning'">
            {{ reviewLabels[r.review_status] }}
          </v-chip>
          <v-chip v-else size="small" color="primary" variant="tonal">เปิดอยู่</v-chip>
        </div>

        <div v-if="r.expected_cash !== undefined" class="mt-3 grid grid-cols-2 gap-x-6 gap-y-1 text-sm md:grid-cols-4">
          <span>เงินเริ่มต้น {{ formatBaht(Number(r.opening_cash)) }}</span>
          <span>ขายเงินสด {{ formatBaht(Number(r.cash_sales)) }}</span>
          <span>โอน {{ formatBaht(Number(r.transfer_sales)) }}</span>
          <span>QR {{ formatBaht(Number(r.qr_sales)) }}</span>
          <span>ทิปเงินสด {{ formatBaht(Number(r.cash_tips)) }}</span>
          <span>เงินเข้า {{ formatBaht(Number(r.cash_in)) }}</span>
          <span>เงินออก {{ formatBaht(Number(r.cash_out)) }}</span>
          <span>คืนเงินสด {{ formatBaht(Number(r.cash_refunds)) }}</span>
          <span class="font-medium">ควรมี {{ formatBaht(Number(r.expected_cash)) }}</span>
          <template v-if="r.actual_cash !== null">
            <span class="font-medium">นับได้ {{ formatBaht(Number(r.actual_cash)) }}</span>
            <span class="font-semibold" :class="Number(r.cash_difference) === 0 ? 'text-green-800' : 'text-red-700'">
              ผลต่าง {{ formatBaht(Number(r.cash_difference)) }}</span>
          </template>
        </div>
        <p v-if="r.close_note" class="m-0 mt-2 text-sm">หมายเหตุปิดกะ: {{ r.close_note }}</p>
        <p v-if="r.review_note" class="m-0 text-sm text-light-brown">ผลตรวจ: {{ r.review_note }}</p>

        <div v-if="isOwner && r.review_status === 'PENDING'" class="mt-3 flex gap-2">
          <v-btn size="small" color="primary" @click="review(r, true)">อนุมัติ</v-btn>
          <v-btn size="small" variant="text" color="error" @click="review(r, false)">ปฏิเสธ</v-btn>
        </div>
      </v-card>
    </div>
  </div>
</template>
