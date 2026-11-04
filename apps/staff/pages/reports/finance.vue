<script setup lang="ts">
// OWNER: รายงานการเงิน (รายวัน/เดือน/ปี, รายสาขา) + รายจ่ายผิดปกติ — ส่งออก CSV
import {
  abnormalFlagLabels,
  addDays,
  bangkokToday,
  formatBaht,
  toCsv,
  type AbnormalExpenseRow,
  type FinanceReport,
  type FinanceReportRow,
} from '@ifeew/shared'

definePageMeta({ ownerOnly: true })

const supabase = useSupabaseClient()
const { company, branches } = useAccess()

const tab = ref<'finance' | 'abnormal'>('finance')
const branchId = ref<string | null>(null)
const from = ref(`${bangkokToday().slice(0, 7)}-01`)
const to = ref(bangkokToday())
const group = ref<'DAY' | 'MONTH' | 'YEAR'>('DAY')
const report = ref<FinanceReport | null>(null)
const abnormal = ref<AbnormalExpenseRow[]>([])
const loading = ref(false)
const error = ref<string | null>(null)

const branchItems = computed(() => [{ value: null, title: 'ทุกสาขา' }, ...branches.value.map((b) => ({ value: b.branch_id, title: b.name }))])
const cols: Array<[keyof FinanceReportRow, string]> = [
  ['cash_sales', 'เงินสด'], ['transfer_sales', 'โอน'], ['qr_sales', 'QR'], ['deposit_applied', 'มัดจำที่หัก'],
  ['forfeited_deposits', 'มัดจำที่ริบ'], ['refunds', 'คืนเงิน'], ['net_revenue', 'รายรับสุทธิ'],
  ['expenses', 'รายจ่าย'], ['commission_cost', 'ค่ามือ'], ['gross_profit', 'กำไรเบื้องต้น'],
]
const totals = computed(() => {
  const t: Record<string, number> = {}
  for (const [k] of cols) t[k] = (report.value?.rows ?? []).reduce((s, r) => s + Number(r[k]), 0)
  return t
})
const profitAll = computed(() =>
  report.value
    ? totals.value.gross_profit! - Number(report.value.hq_expenses) - Number(report.value.hq_commission_adjustments)
      + Number(report.value.daily_adjustments)
    : 0,
)

async function load() {
  if (!company.value) return
  loading.value = true
  try {
    if (tab.value === 'finance') {
      report.value = (await must(supabase.rpc('finance_report', {
        p_company_id: company.value.company_id, p_branch_id: branchId.value, p_from: from.value, p_to: to.value, p_group: group.value,
      }))) as unknown as FinanceReport
    } else {
      abnormal.value = (await must(supabase.rpc('abnormal_expenses', {
        p_company_id: company.value.company_id, p_from: from.value, p_to: to.value,
      }))) as unknown as AbnormalExpenseRow[]
    }
    error.value = null
  } catch (e) {
    error.value = errorText(e, 'โหลดรายงานไม่สำเร็จ')
  } finally {
    loading.value = false
  }
}
watch([tab, branchId, from, to, group, () => company.value?.company_id], load, { immediate: true })

function download(name: string, csv: string) {
  const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }))
  const a = document.createElement('a')
  a.href = url
  a.download = name
  a.click()
  URL.revokeObjectURL(url)
}
function exportCsv() {
  if (tab.value === 'finance' && report.value) {
    download(`finance_${from.value}_${to.value}.csv`,
      toCsv([['period', 'งวด'], ['branch_name', 'สาขา'], ...cols], report.value.rows as unknown as Array<Record<string, unknown>>))
  } else {
    download(`abnormal_expenses_${from.value}_${to.value}.csv`, toCsv(
      [['occurred_on', 'วันที่'], ['branch_name', 'สาขา'], ['amount', 'จำนวนเงิน'], ['note', 'หมายเหตุ'], ['status', 'สถานะ'],
       ['recorded_by_name', 'ผู้บันทึก'], ['flags_th', 'ข้อสังเกต']],
      abnormal.value.map((r) => ({ ...r, flags_th: r.flags.map((f) => abnormalFlagLabels[f]).join(' / ') }))))
  }
}
</script>

<template>
  <div>
    <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
      <h1 class="m-0 text-2xl font-semibold text-cocoa">รายงาน</h1>
      <v-btn variant="tonal" prepend-icon="mdi-download" @click="exportCsv">ส่งออก CSV</v-btn>
    </div>
    <v-btn-toggle v-model="tab" mandatory color="primary" density="comfortable" class="mb-4">
      <v-btn value="finance">การเงิน</v-btn>
      <v-btn value="abnormal">รายจ่ายผิดปกติ</v-btn>
    </v-btn-toggle>
    <div class="mb-4 flex flex-wrap items-center gap-2">
      <v-select v-if="tab === 'finance'" v-model="branchId" :items="branchItems" label="สาขา" hide-details density="compact" class="max-w-52" />
      <v-text-field v-model="from" type="date" label="ตั้งแต่" hide-details density="compact" class="max-w-44" />
      <v-text-field v-model="to" type="date" label="ถึง" hide-details density="compact" class="max-w-44" />
      <v-btn-toggle v-if="tab === 'finance'" v-model="group" mandatory density="compact">
        <v-btn value="DAY">รายวัน</v-btn><v-btn value="MONTH">รายเดือน</v-btn><v-btn value="YEAR">รายปี</v-btn>
      </v-btn-toggle>
      <v-btn variant="text" size="small" @click="from = addDays(bangkokToday(), -6); to = bangkokToday()">7 วัน</v-btn>
    </div>
    <v-alert v-if="error" type="error" variant="tonal" class="mb-4" :text="error" />
    <v-progress-linear v-if="loading" indeterminate color="primary" />

    <template v-if="tab === 'finance' && report">
      <v-card class="overflow-x-auto p-2">
        <v-table density="compact">
          <thead>
            <tr><th>งวด</th><th>สาขา</th><th v-for="[k, l] in cols" :key="k" class="text-right">{{ l }}</th></tr>
          </thead>
          <tbody>
            <tr v-for="r in report.rows" :key="r.period + r.branch_id">
              <td>{{ r.period }}</td><td>{{ r.branch_name }}</td>
              <td v-for="[k] in cols" :key="k" class="text-right" :class="{ 'font-medium': k === 'net_revenue' || k === 'gross_profit' }">
                {{ formatBaht(Number(r[k])) }}</td>
            </tr>
            <tr class="font-semibold">
              <td colspan="2">รวม</td>
              <td v-for="[k] in cols" :key="k" class="text-right">{{ formatBaht(totals[k] ?? 0) }}</td>
            </tr>
          </tbody>
        </v-table>
      </v-card>
      <v-card class="mt-4 p-4 text-sm">
        <div class="grid max-w-md grid-cols-2 gap-1">
          <span>กำไรเบื้องต้นของสาขา</span><span class="text-right">{{ formatBaht(totals.gross_profit ?? 0) }}</span>
          <template v-if="!branchId">
            <span>รายจ่ายสำนักงานใหญ่</span><span class="text-right">−{{ formatBaht(Number(report.hq_expenses)) }}</span>
            <span>ปรับค่ามือ (ไม่ระบุสาขา)</span><span class="text-right">−{{ formatBaht(Number(report.hq_commission_adjustments)) }}</span>
          </template>
          <span>ยอดปรับปรุงจากการปิดยอดรายวัน</span><span class="text-right">{{ formatBaht(Number(report.daily_adjustments)) }}</span>
          <span class="font-semibold">กำไรเบื้องต้นรวม</span><span class="text-right font-semibold">{{ formatBaht(profitAll) }}</span>
          <span>ยอดค้างชำระตอนนี้</span><span class="text-right">{{ formatBaht(Number(report.outstanding)) }}</span>
        </div>
        <p class="m-0 mt-2 text-xs text-light-brown">รายรับนับตามวันที่รับเงินจริง ไม่รวมทิป · ค่ามือรวมเงินเติมประกันมือและรายการปรับ</p>
      </v-card>
    </template>

    <template v-else-if="tab === 'abnormal'">
      <p v-if="!loading && !abnormal.length" class="text-light-brown">ไม่พบรายจ่ายผิดปกติในช่วงนี้</p>
      <div class="grid gap-2">
        <v-card v-for="r in abnormal" :key="r.expense_id" class="p-4">
          <div class="flex flex-wrap items-start justify-between gap-2">
            <div>
              <p class="m-0 font-medium" :class="{ 'line-through': r.status === 'VOID' }">{{ formatBaht(Number(r.amount)) }} · {{ r.note }}</p>
              <p class="m-0 text-sm text-light-brown">{{ r.occurred_on }} · {{ r.branch_name }} · {{ r.recorded_by_name ?? '-' }}</p>
            </div>
            <div class="flex flex-wrap gap-1">
              <v-chip v-for="f in r.flags" :key="f" size="small" color="warning" variant="tonal">{{ abnormalFlagLabels[f] }}</v-chip>
            </div>
          </div>
        </v-card>
      </div>
    </template>
  </div>
</template>
