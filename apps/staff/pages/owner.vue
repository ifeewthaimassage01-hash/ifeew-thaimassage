<script setup lang="ts">
// แดชบอร์ดเจ้าของร้าน: ยอดทุกสาขา (วันนี้/เดือนนี้/ปีนี้ เทียบช่วงก่อน), กราฟ, เทียบสาขา, รายการที่ต้องทำ
import { Banknote, CalendarRange, ChartColumn, TrendingUp } from '@lucide/vue'
import { formatBaht, type OwnerDashboard } from '@ifeew/shared'

definePageMeta({ ownerOnly: true })

const supabase = useSupabaseClient()
const { company } = useAccess()
const dash = ref<OwnerDashboard | null>(null)
const error = ref<string | null>(null)

async function load() {
  if (!company.value) return
  try {
    dash.value = (await must(supabase.rpc('owner_dashboard', { p_company_id: company.value.company_id }))) as unknown as OwnerDashboard
    error.value = null
  } catch (e) {
    error.value = errorText(e, 'โหลดแดชบอร์ดไม่สำเร็จ')
  }
}
watch(() => company.value?.company_id, load, { immediate: true })

const baht = (v: number) => formatBaht(Number(v))
const shortBaht = (v: number) => (Math.abs(v) >= 1000 ? `${(v / 1000).toFixed(v % 1000 === 0 ? 0 : 1)}k` : String(Math.round(v)))
function change(cur: number, prev: number): string | null {
  if (!Number(prev)) return null
  const pct = ((Number(cur) - Number(prev)) / Math.abs(Number(prev))) * 100
  return `${pct >= 0 ? '▲' : '▼'} ${Math.abs(pct).toFixed(0)}%`
}
const daily = computed(() => (dash.value?.daily ?? []).map((d) => ({ label: d.date.slice(8, 10) + '/' + d.date.slice(5, 7), value: Number(d.revenue) })))
const monthly = computed(() => (dash.value?.monthly ?? []).map((d) => ({ label: d.month.slice(5, 7) + '/' + d.month.slice(2, 4), value: Number(d.revenue) })))
</script>

<template>
  <div>
    <PageHeader title="ภาพรวมทุกสาขา" description="รายรับ กำไร และงานที่ต้องตรวจของทุกสาขา (รายรับไม่รวมทิป)">
      <template #actions><Button as-child variant="outline"><NuxtLink to="/reports/finance">รายงานการเงิน</NuxtLink></Button></template>
    </PageHeader>
    <Alert v-if="error" variant="destructive" class="mb-6"><AlertDescription>{{ error }}</AlertDescription></Alert>
    <div v-if="!dash && !error" class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4"><Skeleton v-for="n in 4" :key="n" class="h-32 rounded-xl" /></div>

    <div v-if="dash" class="grid gap-6">
      <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard label="รายรับวันนี้" :icon="Banknote" :value="baht(dash.kpis.today.revenue)" :hint="`เมื่อวาน ${baht(dash.kpis.yesterday.revenue)}`" />
        <StatCard label="รายรับเดือนนี้" :icon="CalendarRange" :value="baht(dash.kpis.month.revenue)">
          <template #hint><span class="num font-medium text-heading">{{ change(dash.kpis.month.revenue, dash.kpis.prev_month_same_period.revenue) ?? '—' }}</span> เทียบช่วงเดียวกันเดือนก่อน</template>
        </StatCard>
        <StatCard label="กำไรเบื้องต้นเดือนนี้" :icon="TrendingUp" :value="baht(Number(dash.kpis.month.profit) - Number(dash.hq_expenses_month))"
          :hint="`รายจ่าย ${baht(Number(dash.kpis.month.expenses) + Number(dash.hq_expenses_month))} · ค่ามือ ${baht(dash.kpis.month.commission)}`" />
        <StatCard label="รายรับปีนี้" :icon="ChartColumn" :value="baht(dash.kpis.year.revenue)">
          <template #hint><span class="num font-medium text-heading">{{ change(dash.kpis.year.revenue, dash.kpis.prev_year_same_period.revenue) ?? '—' }}</span> เทียบปีก่อน</template>
        </StatCard>
      </div>

      <!-- ต้องดำเนินการ -->
      <SectionCard title="ต้องดำเนินการ" flush>
        <div class="grid sm:grid-cols-2 xl:grid-cols-3">
          <NuxtLink
            v-for="a in [
              { to: '/daily-closings', label: 'ปิดยอดรอตรวจ', value: String(dash.actions.closings_pending), alert: !!dash.actions.closings_pending },
              { to: '/expenses', label: 'คำขอยกเลิกรายจ่าย', value: String(dash.actions.expense_void_requests), alert: !!dash.actions.expense_void_requests },
              { to: '/reports/finance', label: 'รายจ่ายสูงเดือนนี้', value: String(dash.actions.large_expenses_month), alert: false },
              { to: '/commissions', label: 'ค่ามือค้างจ่าย', value: baht(dash.actions.unpaid_commission), alert: false },
              { to: '/bookings', label: 'มัดจำรอคืน', value: String(dash.actions.deposits_to_refund), alert: !!dash.actions.deposits_to_refund },
            ]"
            :key="a.label"
            :to="a.to"
            class="flex items-center justify-between gap-3 border-b border-border px-5 py-3.5 text-foreground no-underline transition-colors hover:bg-muted sm:border-r"
          >
            <span class="flex items-center gap-2">
              <span class="size-2 rounded-full" :class="a.alert ? 'bg-brand-accent' : 'bg-secondary'" aria-hidden="true" />{{ a.label }}
            </span>
            <span class="num font-semibold" :class="a.alert ? 'text-pending-ink' : 'text-heading'">{{ a.value }}</span>
          </NuxtLink>
        </div>
      </SectionCard>

      <div class="grid gap-6 xl:grid-cols-2">
        <SectionCard><BarChart title="รายรับรายวัน (30 วัน)" :points="daily" :format="shortBaht" :label-every="5" /></SectionCard>
        <SectionCard><BarChart title="รายรับรายเดือน (12 เดือน)" :points="monthly" :format="shortBaht" /></SectionCard>
      </div>

      <SectionCard title="เทียบสาขา (เดือนนี้)" flush>
        <div class="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow class="hover:bg-transparent">
                <TableHead>สาขา</TableHead>
                <TableHead class="text-right">รายรับ</TableHead>
                <TableHead class="text-right">รายจ่าย</TableHead>
                <TableHead class="text-right">ค่ามือ</TableHead>
                <TableHead class="text-right">กำไรเบื้องต้น</TableHead>
                <TableHead class="text-right">ค้างชำระ</TableHead>
                <TableHead class="text-right">ลูกค้า</TableHead>
                <TableHead class="text-right">Walk-in / การจอง</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              <TableRow v-for="b in dash.branches" :key="b.branch_id">
                <TableCell class="font-medium text-heading">{{ b.branch_name }}</TableCell>
                <TableCell class="num text-right">{{ baht(b.revenue) }}</TableCell>
                <TableCell class="num text-right">{{ baht(b.expenses) }}</TableCell>
                <TableCell class="num text-right">{{ baht(b.commission) }}</TableCell>
                <TableCell class="num text-right font-semibold text-heading">{{ baht(b.profit) }}</TableCell>
                <TableCell class="num text-right">{{ baht(b.outstanding) }}</TableCell>
                <TableCell class="num text-right">{{ b.customers }}</TableCell>
                <TableCell class="num text-right">{{ b.walk_ins }} / {{ b.bookings }}</TableCell>
              </TableRow>
            </TableBody>
          </Table>
        </div>
        <template #footer>รายจ่ายสำนักงานใหญ่เดือนนี้ <span class="num">{{ baht(dash.hq_expenses_month) }}</span> (หักในกำไรรวมด้านบน ไม่แยกสาขา) · รายรับไม่รวมทิป</template>
      </SectionCard>
    </div>
  </div>
</template>
