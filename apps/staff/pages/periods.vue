<script setup lang="ts">
// OWNER: งวดบัญชีรายเดือน — ล็อก (ปิดยอดทุกวันต้องอนุมัติครบ) / เปิดใหม่พร้อมเหตุผล (ยืนยันตัวตนซ้ำ)
import { type FinancialPeriodRow } from '@ifeew/shared'

definePageMeta({ ownerOnly: true })

const supabase = useSupabaseClient()
const { company } = useAccess()
const { run } = useStepUp()
const rows = ref<FinancialPeriodRow[]>([])
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)

async function load() {
  if (!company.value) return
  try {
    rows.value = (await must(supabase.rpc('financial_periods_list', { p_company_id: company.value.company_id }))) as unknown as FinancialPeriodRow[]
  } catch (e) {
    message.value = { type: 'error', text: errorText(e) }
  }
}
watch(() => company.value?.company_id, load, { immediate: true })

const monthLabel = (d: string) => new Date(`${d}T00:00:00+07:00`).toLocaleDateString('th-TH', { month: 'long', year: 'numeric' })

async function lock(r: FinancialPeriodRow) {
  if (!company.value || !window.confirm(`ล็อกงวด ${monthLabel(r.period_start)}? หลังล็อกจะแก้ข้อมูลการเงินของเดือนนี้ไม่ได้`)) return
  const companyId = company.value.company_id
  try {
    await run(() => must(supabase.rpc('lock_financial_period', { p_company_id: companyId, p_month: r.period_start })))
    message.value = { type: 'success', text: `ล็อกงวด ${monthLabel(r.period_start)} แล้ว` }
    await load()
  } catch (e) {
    message.value = { type: 'error', text: errorText(e) }
  }
}

async function reopen(r: FinancialPeriodRow) {
  const reason = window.prompt(`เหตุผลที่เปิดงวด ${monthLabel(r.period_start)}`, '')
  if (!company.value || !reason || reason.trim().length < 3) return
  const companyId = company.value.company_id
  try {
    await run(() => must(supabase.rpc('reopen_financial_period', { p_company_id: companyId, p_month: r.period_start, p_reason: reason.trim() })))
    message.value = { type: 'success', text: 'เปิดงวดแล้ว' }
    await load()
  } catch (e) {
    message.value = { type: 'error', text: errorText(e) }
  }
}
</script>

<template>
  <div class="max-w-3xl">
    <h1 class="m-0 mb-4 text-2xl font-semibold text-cocoa">งวดบัญชี</h1>
    <v-alert v-if="message" :type="message.type" variant="tonal" class="mb-4" closable :text="message.text" @click:close="message = null" />
    <v-card class="p-2">
      <v-table>
        <thead><tr><th>เดือน</th><th>สถานะ</th><th>ปิดยอดที่ยังไม่อนุมัติ</th><th /></tr></thead>
        <tbody>
          <tr v-for="(r, n) in rows" :key="r.period_start">
            <td>{{ monthLabel(r.period_start) }}</td>
            <td>
              <v-chip size="small" variant="tonal" :color="r.status === 'LOCKED' ? 'primary' : undefined">
                {{ r.status === 'LOCKED' ? 'ล็อกแล้ว' : 'เปิด' }}</v-chip>
              <div v-if="r.reopen_reason && r.status === 'OPEN'" class="text-xs text-light-brown">เปิดใหม่: {{ r.reopen_reason }}</div>
            </td>
            <td>{{ r.pending_closings || '-' }}</td>
            <td class="text-right">
              <v-btn v-if="r.status === 'LOCKED'" size="small" variant="text" @click="reopen(r)">เปิดงวด</v-btn>
              <v-btn v-else-if="n > 0" size="small" color="primary" variant="tonal" :disabled="r.pending_closings > 0" @click="lock(r)">ล็อก</v-btn>
            </td>
          </tr>
        </tbody>
      </v-table>
    </v-card>
    <p class="m-0 mt-2 text-xs text-light-brown">ล็อกได้เฉพาะเดือนที่จบแล้ว และทุกวันที่มีการขายต้องปิดยอดรายวันที่อนุมัติแล้ว</p>
  </div>
</template>
