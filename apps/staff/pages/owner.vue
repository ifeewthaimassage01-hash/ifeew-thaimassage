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
    <div v-if="!dash && !error" class="grid grid-cols-2 gap-3 sm:gap-4 xl:grid-cols-4"><Skeleton v-for="n in 4" :key="n" class="h-32 rounded-xl" /></div>

    <div v-if="dash" class="grid gap-6">
      <div class="grid grid-cols-2 gap-3 sm:gap-4 xl:grid-cols-4">
        <StatCard dense label="รายรับวันนี้" :icon="Banknote" :value="baht(dash.kpis.today.revenue)" :hint="`เมื่อวาน ${baht(dash.kpis.yesterday.revenue)}`" />
        <StatCard dense label="รายรับเดือนนี้" :icon="CalendarRange" :value="baht(dash.kpis.month.revenue)">
          <template #hint><span class="num font-medium text-heading">{{ change(dash.kpis.month.revenue, dash.kpis.prev_month_same_period.revenue) ?? '—' }}</span> เทียบช่วงเดียวกันเดือนก่อน</template>
        </StatCard>
        <StatCard dense label="กำไรเบื้องต้นเดือนนี้" :icon="TrendingUp" :value="baht(Number(dash.kpis.month.profit) - Number(dash.hq_expenses_month))"
          :hint="`รายจ่าย ${baht(Number(dash.kpis.month.expenses) + Number(dash.hq_expenses_month))} · ค่ามือ ${baht(dash.kpis.month.commission)}`" />
        <StatCard dense label="รายรับปีนี้" :icon="ChartColumn" :value="baht(dash.kpis.year.revenue)">
          <template #hint><span class="num font-medium text-heading">{{ change(dash.kpis.year.revenue, dash.kpis.prev_year_same_period.revenue) ?? '—' }}</span> เทียบปีก่อน</template>
        </StatCard>
      </div>

      <!-- ต้องดำเนินการ -->
      <SectionCard title="ต้องดำเนินการ" flush>
        <div class="grid sm:grid-cols-2 xl:grid-cols-3">
          <NuxtLink
            v-for="a in [
              { to: '/expenses', label: 'คำขอยกเลิกรายจ่าย', value: String(dash.actions.expense_void_requests), alert: !!dash.actions.expense_void_requests },
              { to: '/reports/finance', label: 'รายจ่ายสูงเดือนนี้', value: String(dash.actions.large_expenses_month), alert: false },
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
        <!-- สาขาละรายการ: หัว = ชื่อสาขา | กำไรเบื้องต้น · ด้านล่าง = ตัวเลขย่อย -->
        <ul class="m-0 grid list-none divide-y divide-border p-0">
          <li v-for="b in dash.branches" :key="b.branch_id" class="grid gap-3 px-4 py-4 sm:px-5">
            <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
              <p class="m-0 font-semibold text-heading">{{ b.branch_name }}</p>
              <p class="m-0 text-sm text-muted-foreground">กำไรเบื้องต้น <span class="num text-lg font-semibold" :class="Number(b.profit) < 0 ? 'text-danger-ink' : 'text-heading'">{{ baht(b.profit) }}</span></p>
            </div>
            <dl class="m-0 grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3 lg:grid-cols-6">
              <div v-for="s in [
                { l: 'รายรับ', v: baht(b.revenue), warn: false },
                { l: 'รายจ่าย', v: baht(b.expenses), warn: false },
                { l: 'ค่ามือ', v: baht(b.commission), warn: false },
                { l: 'ค้างชำระ', v: baht(b.outstanding), warn: Number(b.outstanding) > 0 },
                { l: 'ลูกค้า', v: `${b.customers} คน`, warn: false },
                { l: 'Walk-in / การจอง', v: `${b.walk_ins} / ${b.bookings}`, warn: false },
              ]" :key="s.l" class="grid gap-0.5">
                <dt class="text-[13px] text-muted-foreground">{{ s.l }}</dt>
                <dd class="num m-0" :class="s.warn ? 'font-semibold text-pending-ink' : 'text-foreground'">{{ s.v }}</dd>
              </div>
            </dl>
          </li>
        </ul>
        <template #footer>รายจ่ายสำนักงานใหญ่เดือนนี้ <span class="num">{{ baht(dash.hq_expenses_month) }}</span> (หักในกำไรรวมด้านบน ไม่แยกสาขา) · รายรับไม่รวมทิป</template>
      </SectionCard>
    </div>
  </div>
</template>
