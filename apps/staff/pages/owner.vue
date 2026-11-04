<script setup lang="ts">
// แดชบอร์ดเจ้าของร้าน: ยอดทุกสาขา (วันนี้/เดือนนี้/ปีนี้ เทียบช่วงก่อน), กราฟ, เทียบสาขา, รายการที่ต้องทำ
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
    <h1 class="m-0 mb-4 text-2xl font-semibold text-cocoa">ภาพรวมทุกสาขา</h1>
    <v-alert v-if="error" type="error" variant="tonal" class="mb-4" :text="error" />

    <template v-if="dash">
      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <v-card class="p-5">
          <p class="m-0 text-sm text-light-brown">รายรับวันนี้</p>
          <p class="m-0 mt-1 text-3xl font-semibold">{{ baht(dash.kpis.today.revenue) }}</p>
          <p class="m-0 text-sm">เมื่อวาน {{ baht(dash.kpis.yesterday.revenue) }}</p>
        </v-card>
        <v-card class="p-5">
          <p class="m-0 text-sm text-light-brown">รายรับเดือนนี้</p>
          <p class="m-0 mt-1 text-3xl font-semibold">{{ baht(dash.kpis.month.revenue) }}</p>
          <p class="m-0 text-sm">{{ change(dash.kpis.month.revenue, dash.kpis.prev_month_same_period.revenue) ?? '-' }} เทียบช่วงเดียวกันเดือนก่อน</p>
        </v-card>
        <v-card class="p-5">
          <p class="m-0 text-sm text-light-brown">กำไรเบื้องต้นเดือนนี้</p>
          <p class="m-0 mt-1 text-3xl font-semibold">{{ baht(Number(dash.kpis.month.profit) - Number(dash.hq_expenses_month)) }}</p>
          <p class="m-0 text-sm">รายจ่าย {{ baht(Number(dash.kpis.month.expenses) + Number(dash.hq_expenses_month)) }} · ค่ามือ {{ baht(dash.kpis.month.commission) }}</p>
        </v-card>
        <v-card class="p-5">
          <p class="m-0 text-sm text-light-brown">รายรับปีนี้</p>
          <p class="m-0 mt-1 text-3xl font-semibold">{{ baht(dash.kpis.year.revenue) }}</p>
          <p class="m-0 text-sm">{{ change(dash.kpis.year.revenue, dash.kpis.prev_year_same_period.revenue) ?? '-' }} เทียบปีก่อน</p>
        </v-card>
      </div>

      <!-- ต้องดำเนินการ -->
      <v-card class="mt-4 p-4">
        <p class="m-0 mb-2 font-medium">ต้องดำเนินการ</p>
        <div class="flex flex-wrap gap-2">
          <v-chip to="/sessions" :color="dash.actions.sessions_pending ? 'warning' : undefined" variant="tonal">กะรอตรวจ {{ dash.actions.sessions_pending }}</v-chip>
          <v-chip to="/daily-closings" :color="dash.actions.closings_pending ? 'warning' : undefined" variant="tonal">ปิดยอดรอตรวจ {{ dash.actions.closings_pending }}</v-chip>
          <v-chip to="/expenses" :color="dash.actions.expense_void_requests ? 'warning' : undefined" variant="tonal">คำขอยกเลิกรายจ่าย {{ dash.actions.expense_void_requests }}</v-chip>
          <v-chip to="/reports/finance" variant="tonal">รายจ่ายสูงเดือนนี้ {{ dash.actions.large_expenses_month }}</v-chip>
          <v-chip to="/commissions" variant="tonal">ค่ามือค้างจ่าย {{ baht(dash.actions.unpaid_commission) }}</v-chip>
          <v-chip to="/bookings" :color="dash.actions.deposits_to_refund ? 'warning' : undefined" variant="tonal">มัดจำรอคืน {{ dash.actions.deposits_to_refund }}</v-chip>
        </div>
      </v-card>

      <div class="mt-4 grid gap-4 lg:grid-cols-2">
        <v-card class="p-4"><BarChart title="รายรับรายวัน (30 วัน)" :points="daily" :format="shortBaht" :label-every="5" /></v-card>
        <v-card class="p-4"><BarChart title="รายรับรายเดือน (12 เดือน)" :points="monthly" :format="shortBaht" /></v-card>
      </div>

      <v-card class="mt-4 p-2">
        <p class="m-0 px-3 pt-2 font-medium">เทียบสาขา (เดือนนี้)</p>
        <v-table density="comfortable">
          <thead>
            <tr>
              <th>สาขา</th><th class="text-right">รายรับ</th><th class="text-right">รายจ่าย</th><th class="text-right">ค่ามือ</th>
              <th class="text-right">กำไรเบื้องต้น</th><th class="text-right">ค้างชำระ</th><th class="text-right">ลูกค้า</th>
              <th class="text-right">Walk-in / การจอง</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="b in dash.branches" :key="b.branch_id">
              <td>{{ b.branch_name }}</td>
              <td class="text-right">{{ baht(b.revenue) }}</td>
              <td class="text-right">{{ baht(b.expenses) }}</td>
              <td class="text-right">{{ baht(b.commission) }}</td>
              <td class="text-right font-medium">{{ baht(b.profit) }}</td>
              <td class="text-right">{{ baht(b.outstanding) }}</td>
              <td class="text-right">{{ b.customers }}</td>
              <td class="text-right">{{ b.walk_ins }} / {{ b.bookings }}</td>
            </tr>
          </tbody>
        </v-table>
        <p class="m-0 px-3 pb-2 text-xs text-light-brown">
          รายจ่ายสำนักงานใหญ่เดือนนี้ {{ baht(dash.hq_expenses_month) }} (หักในกำไรรวมด้านบน ไม่แยกสาขา) · รายรับไม่รวมทิป
        </p>
      </v-card>
    </template>
  </div>
</template>
