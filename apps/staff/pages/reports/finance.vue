<script setup lang="ts">
// OWNER: รายงานการเงิน (รายวัน/เดือน/ปี, รายสาขา) + รายจ่ายผิดปกติ — ส่งออก CSV
import { Download } from '@lucide/vue'
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
    <PageHeader title="รายงานการเงิน" description="รายรับนับตามวันที่รับเงินจริง ไม่รวมทิป · ค่ามือรวมเงินเติมประกันมือและรายการปรับ">
      <template #actions><Button variant="outline" @click="exportCsv"><Download /> ส่งออก CSV</Button></template>
    </PageHeader>

    <SegmentedControl
      v-model="tab"
      :items="[{ value: 'finance', label: 'การเงิน' }, { value: 'abnormal', label: 'รายจ่ายผิดปกติ' }]"
      label="ประเภทรายงาน"
      class="mb-4"
    />

    <div class="mb-6 flex flex-wrap items-end gap-3 rounded-xl border border-border bg-card p-4">
      <SelectField v-if="tab === 'finance'" v-model="branchId" :items="branchItems" label="สาขา" class="w-52" />
      <TextField v-model="from" type="date" label="ตั้งแต่" class="w-44" />
      <TextField v-model="to" type="date" label="ถึง" class="w-44" />
      <div v-if="tab === 'finance'" class="grid gap-1.5">
        <span class="text-sm font-medium text-heading">จัดกลุ่ม</span>
        <SegmentedControl v-model="group" :items="[{ value: 'DAY', label: 'รายวัน' }, { value: 'MONTH', label: 'รายเดือน' }, { value: 'YEAR', label: 'รายปี' }]" label="จัดกลุ่ม" />
      </div>
      <Button variant="ghost" @click="from = addDays(bangkokToday(), -6); to = bangkokToday()">7 วันล่าสุด</Button>
    </div>

    <Alert v-if="error" variant="destructive" class="mb-4"><AlertDescription>{{ error }}</AlertDescription></Alert>
    <LoadingBar v-if="loading" class="mb-3" />

    <div v-if="tab === 'finance' && report" class="grid gap-6">
      <SectionCard flush>
        <div class="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow class="hover:bg-transparent">
                <TableHead>งวด</TableHead><TableHead>สาขา</TableHead>
                <TableHead v-for="[k, l] in cols" :key="k" class="text-right">{{ l }}</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              <TableRow v-for="r in report.rows" :key="r.period + r.branch_id">
                <TableCell class="num text-heading">{{ r.period }}</TableCell><TableCell>{{ r.branch_name }}</TableCell>
                <TableCell v-for="[k] in cols" :key="k" class="num text-right" :class="{ 'font-semibold text-heading': k === 'net_revenue' || k === 'gross_profit' }">
                  {{ formatBaht(Number(r[k])) }}</TableCell>
              </TableRow>
              <TableRow v-if="!report.rows.length" class="hover:bg-transparent">
                <TableCell :colspan="cols.length + 2" class="py-8 text-center text-muted-foreground">ไม่มีข้อมูลในช่วงนี้</TableCell>
              </TableRow>
            </TableBody>
            <TableFooter>
              <TableRow class="hover:bg-transparent">
                <TableCell colspan="2" class="font-semibold text-heading">รวม</TableCell>
                <TableCell v-for="[k] in cols" :key="k" class="num text-right font-semibold text-heading">{{ formatBaht(totals[k] ?? 0) }}</TableCell>
              </TableRow>
            </TableFooter>
          </Table>
        </div>
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
