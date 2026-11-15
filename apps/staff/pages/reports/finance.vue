<script setup lang="ts">
// OWNER: รายงานการเงิน (รายวัน/เดือน/ปี, รายสาขา) + รายจ่ายผิดปกติ — ส่งออก CSV
import { Download } from '@lucide/vue'
import {
  abnormalFlagLabels,
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
    <PageHeader title="รายงานการเงิน" description="รายรับนับตามวันที่รับเงินจริง ไม่รวมทิป · ค่ามือรวมเงินเติมประกันมือและรายการปรับ">
      <template #actions><Button variant="outline" @click="exportCsv"><Download /> ส่งออก CSV</Button></template>
    </PageHeader>

    <SegmentedControl
      v-model="tab"
      :items="[{ value: 'finance', label: 'การเงิน' }, { value: 'abnormal', label: 'รายจ่ายผิดปกติ' }]"
      label="ประเภทรายงาน"
      class="mb-4"
    />

    <FilterPanel label="ตัวกรองรายงาน">
      <FilterRow v-if="tab === 'finance'" label="สาขา">
        <SelectField v-model="branchId" :items="branchItems" aria-label="สาขา" class="w-full sm:w-64" />
      </FilterRow>
      <FilterRow label="ช่วงวันที่">
        <DateRangeFilter v-model:from="from" v-model:to="to" :presets="['month', 'last-month', 'year']" />
      </FilterRow>
      <FilterRow v-if="tab === 'finance'" label="แสดงเป็น">
        <SegmentedControl v-model="group" :items="[{ value: 'DAY', label: 'รายวัน' }, { value: 'MONTH', label: 'รายเดือน' }, { value: 'YEAR', label: 'รายปี' }]" label="จัดกลุ่ม" fill />
      </FilterRow>
    </FilterPanel>

    <Alert v-if="error" variant="destructive" class="mb-4"><AlertDescription>{{ error }}</AlertDescription></Alert>
    <LoadingBar v-if="loading" class="mb-3" />

    <div v-if="tab === 'finance' && report" class="grid gap-6">
      <SectionCard flush>
        <!-- งวดละรายการ: หัว = งวด + สาขา | กำไรเบื้องต้น · ด้านล่าง = ตัวเลขย่อย (ซ่อนช่องที่เป็น 0) -->
        <p v-if="!report.rows.length" class="m-0 px-4 py-10 text-center text-sm text-muted-foreground">ไม่มีข้อมูลในช่วงนี้</p>
        <ul v-else class="m-0 grid list-none divide-y divide-border p-0">
          <li v-for="r in report.rows" :key="r.period + r.branch_id" class="grid gap-3 px-4 py-4 sm:px-5">
            <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
              <p class="m-0"><span class="num font-semibold text-heading">{{ r.period }}</span> <span class="text-sm text-muted-foreground">{{ r.branch_name }}</span></p>
              <p class="m-0 text-sm text-muted-foreground">กำไรเบื้องต้น <span class="num text-lg font-semibold" :class="Number(r.gross_profit) < 0 ? 'text-danger-ink' : 'text-heading'">{{ formatBaht(Number(r.gross_profit)) }}</span></p>
            </div>
            <dl class="m-0 grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3 lg:grid-cols-5">
              <div v-for="[k, l] in cols.filter(([k]) => k !== 'gross_profit' && (Number(r[k]) || k === 'net_revenue'))" :key="k" class="grid gap-0.5">
                <dt class="text-[13px] text-muted-foreground">{{ l }}</dt>
                <dd class="num m-0" :class="k === 'net_revenue' ? 'font-semibold text-heading' : 'text-foreground'">{{ formatBaht(Number(r[k])) }}</dd>
              </div>
            </dl>
          </li>
          <!-- รวมทั้งช่วง -->
          <li class="grid gap-3 bg-muted/60 px-4 py-4 sm:px-5">
            <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
              <p class="m-0 font-semibold text-heading">รวม</p>
              <p class="m-0 text-sm text-muted-foreground">กำไรเบื้องต้น <span class="num text-lg font-semibold" :class="(totals.gross_profit ?? 0) < 0 ? 'text-danger-ink' : 'text-heading'">{{ formatBaht(totals.gross_profit ?? 0) }}</span></p>
            </div>
            <dl class="m-0 grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3 lg:grid-cols-5">
              <div v-for="[k, l] in cols.filter(([k]) => k !== 'gross_profit' && ((totals[k] ?? 0) || k === 'net_revenue'))" :key="k" class="grid gap-0.5">
                <dt class="text-[13px] text-muted-foreground">{{ l }}</dt>
                <dd class="num m-0 font-semibold text-heading">{{ formatBaht(totals[k] ?? 0) }}</dd>
              </div>
            </dl>
          </li>
        </ul>
      </SectionCard>

      <SectionCard title="สรุปกำไร" class="max-w-xl">
        <dl class="m-0 grid gap-2 text-[15px]">
          <div class="flex justify-between gap-3"><dt class="text-muted-foreground">กำไรเบื้องต้นของสาขา</dt><dd class="num m-0">{{ formatBaht(totals.gross_profit ?? 0) }}</dd></div>
          <template v-if="!branchId">
            <div class="flex justify-between gap-3"><dt class="text-muted-foreground">รายจ่ายสำนักงานใหญ่</dt><dd class="num m-0">−{{ formatBaht(Number(report.hq_expenses)) }}</dd></div>
            <div class="flex justify-between gap-3"><dt class="text-muted-foreground">ปรับค่ามือ (ไม่ระบุสาขา)</dt><dd class="num m-0">−{{ formatBaht(Number(report.hq_commission_adjustments)) }}</dd></div>
          </template>
          <div class="flex justify-between gap-3"><dt class="text-muted-foreground">ยอดปรับปรุงจากการปิดยอดรายวัน</dt><dd class="num m-0">{{ formatBaht(Number(report.daily_adjustments)) }}</dd></div>
          <div class="flex justify-between gap-3 border-t border-border pt-3"><dt class="font-semibold text-heading">กำไรเบื้องต้นรวม</dt><dd class="num m-0 text-lg font-semibold text-heading">{{ formatBaht(profitAll) }}</dd></div>
          <div class="flex justify-between gap-3"><dt class="text-muted-foreground">ยอดค้างชำระตอนนี้</dt><dd class="num m-0">{{ formatBaht(Number(report.outstanding)) }}</dd></div>
        </dl>
      </SectionCard>
    </div>

    <template v-else-if="tab === 'abnormal'">
      <EmptyState v-if="!loading && !abnormal.length" title="ไม่พบรายจ่ายผิดปกติในช่วงนี้" />
      <SectionCard v-else-if="abnormal.length" flush>
        <ul class="m-0 grid list-none p-0">
          <li v-for="r in abnormal" :key="r.expense_id" class="flex flex-wrap items-start justify-between gap-3 border-b border-border px-5 py-3.5 last:border-0">
            <div class="min-w-0">
              <p class="m-0 font-medium text-heading" :class="{ 'line-through': r.status === 'VOID' }"><span class="num">{{ formatBaht(Number(r.amount)) }}</span> · {{ r.note }}</p>
              <p class="m-0 text-sm text-muted-foreground"><span class="num">{{ r.occurred_on }}</span> · {{ r.branch_name }} · {{ r.recorded_by_name ?? '—' }}</p>
            </div>
            <div class="flex flex-wrap gap-1.5">
              <Badge v-for="f in r.flags" :key="f" variant="pending">{{ abnormalFlagLabels[f] }}</Badge>
            </div>
          </li>
        </ul>
      </SectionCard>
    </template>
  </div>
</template>
