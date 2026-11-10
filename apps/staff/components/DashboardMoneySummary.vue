<script setup lang="ts">
// สรุปการเงินของสาขา (OWNER): รายได้ · รายจ่าย (รวมค่าแรง/ค่าน้ำมันหมอวิ่ง) · ยอดสุทธิ · ลูกค้าแยกตามประเภทหมอ
// ข้อมูลจาก RPC branch_money_summary (migration 045) — สูตรรายได้/รายจ่ายเดียวกับหน้ารายงานการเงิน
import { HandCoins, ReceiptText, TrendingUp, Users } from '@lucide/vue'
import { addDays, bangkokToday, formatBaht } from '@ifeew/shared'

interface MoneySummary {
  revenue: number
  expenses: number
  freelance_fuel: number
  freelance_fee: number
  commission: number
  total_expenses: number
  net: number
  customers: { total: number; REGULAR: number; FREELANCE: number; WALK_IN: number }
}

const props = defineProps<{ branchId: string }>()
const supabase = useSupabaseClient()

const period = ref<'today' | '7d' | 'month'>('today')
const data = ref<MoneySummary | null>(null)
const loading = ref(false)
const error = ref<string | null>(null)

const range = computed(() => {
  const today = bangkokToday()
  if (period.value === '7d') return { from: addDays(today, -6), to: today }
  if (period.value === 'month') return { from: `${today.slice(0, 8)}01`, to: today }
  return { from: today, to: today }
})

let seq = 0
async function load() {
  const s = ++seq
  loading.value = true
  try {
    const res = await must(supabase.rpc('branch_money_summary', { p_branch_id: props.branchId, p_from: range.value.from, p_to: range.value.to }))
    if (s === seq) {
      data.value = res as unknown as MoneySummary
      error.value = null
    }
  } catch (e) {
    if (s === seq) error.value = errorText(e, 'โหลดสรุปการเงินไม่สำเร็จ')
  } finally {
    if (s === seq) loading.value = false
  }
}
watch([() => props.branchId, period], load, { immediate: true })
useIntervalFn(load, 60_000)

const n = (v: unknown) => Number(v) || 0
const expenseLines = computed(() => {
  const d = data.value
  if (!d) return []
  return [
    { label: 'รายจ่ายร้าน', value: n(d.expenses) },
    { label: 'ค่ามือหมอพนักงาน', value: n(d.commission) },
    { label: 'ค่าแรงหมอวิ่ง', value: n(d.freelance_fee) },
    { label: 'ค่าน้ำมันหมอวิ่ง', value: n(d.freelance_fuel) },
  ]
})
const customerLines = computed(() => {
  const c = data.value?.customers
  return [
    { key: 'REGULAR', label: 'หมอประจำ', n: n(c?.REGULAR) },
    { key: 'FREELANCE', label: 'หมอฟรีแลนซ์', n: n(c?.FREELANCE) },
    { key: 'WALK_IN', label: 'หมอวิ่ง', n: n(c?.WALK_IN) },
  ]
})
const periodLabel = computed(() => ({ today: 'วันนี้', '7d': '7 วันล่าสุด', month: 'เดือนนี้' })[period.value])
</script>

<template>
  <section class="rounded-xl border border-border bg-card p-4 shadow-soft sm:p-5" aria-labelledby="money-h">
    <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
      <h2 id="money-h" class="m-0 text-[15px] font-semibold">
        สรุปการเงิน<span class="font-normal text-muted-foreground"> · {{ periodLabel }}</span>
      </h2>
      <SegmentedControl
        v-model="period"
        size="sm"
        :items="[{ value: 'today', label: 'วันนี้' }, { value: '7d', label: '7 วัน' }, { value: 'month', label: 'เดือนนี้' }]"
        label="ช่วงเวลา"
      />
    </div>

    <Alert v-if="error" variant="destructive" class="mb-4"><AlertDescription>{{ error }}</AlertDescription></Alert>

    <div v-if="!data && loading" class="grid grid-cols-2 gap-3 lg:grid-cols-4">
      <Skeleton v-for="i in 4" :key="i" class="h-32 rounded-lg" />
    </div>

    <div v-else-if="data" class="grid grid-cols-2 gap-3 lg:grid-cols-4" :class="loading ? 'opacity-60 transition-opacity' : ''">
      <!-- รายได้ -->
      <div class="grid content-start gap-1 rounded-lg bg-muted/60 p-4">
        <span class="flex items-center gap-2 text-[14px] text-muted-foreground"><TrendingUp class="size-4 text-brand-accent" /> รายได้</span>
        <span class="num text-[24px] leading-tight text-heading sm:text-[26px]">{{ formatBaht(n(data.revenue)) }}</span>
        <span class="text-[12px] text-muted-foreground">รับเงินสุทธิ (หักคืนเงิน)</span>
      </div>

      <!-- รายจ่าย -->
      <div class="grid content-start gap-1 rounded-lg bg-muted/60 p-4">
        <span class="flex items-center gap-2 text-[14px] text-muted-foreground"><ReceiptText class="size-4 text-brand-accent" /> รายจ่าย</span>
        <span class="num text-[24px] leading-tight text-heading sm:text-[26px]">{{ formatBaht(n(data.total_expenses)) }}</span>
        <dl class="m-0 mt-1 grid gap-0.5 text-[12px]">
          <div v-for="l in expenseLines" :key="l.label" class="flex justify-between gap-2">
            <dt class="text-muted-foreground">{{ l.label }}</dt><dd class="num m-0 text-foreground">{{ formatBaht(l.value) }}</dd>
          </div>
        </dl>
      </div>

      <!-- ยอดสุทธิ -->
      <div class="grid content-start gap-1 rounded-lg p-4" :class="n(data.net) < 0 ? 'bg-danger-soft' : 'bg-success-soft'">
        <span class="flex items-center gap-2 text-[14px] text-muted-foreground"><HandCoins class="size-4 text-brand-accent" /> ยอดสุทธิ</span>
        <span class="num text-[24px] leading-tight sm:text-[26px]" :class="n(data.net) < 0 ? 'text-danger-ink' : 'text-success-ink'">
          {{ n(data.net) < 0 ? '−' : '' }}{{ formatBaht(Math.abs(n(data.net))) }}
        </span>
        <span class="text-[12px] text-muted-foreground">รายได้ − รายจ่ายทั้งหมด</span>
      </div>

      <!-- ลูกค้าแยกตามประเภทหมอ -->
      <div class="grid content-start gap-1 rounded-lg bg-muted/60 p-4">
        <span class="flex items-center gap-2 text-[14px] text-muted-foreground"><Users class="size-4 text-brand-accent" /> ลูกค้าที่ใช้บริการ</span>
        <span class="num text-[24px] leading-tight text-heading sm:text-[26px]">{{ n(data.customers?.total) }} <span class="text-[14px] text-muted-foreground">คน</span></span>
        <dl class="m-0 mt-1 grid gap-0.5 text-[12px]">
          <div v-for="c in customerLines" :key="c.key" class="flex justify-between gap-2">
            <dt class="text-muted-foreground">{{ c.label }}</dt><dd class="num m-0 text-foreground">{{ c.n }}</dd>
          </div>
        </dl>
      </div>
    </div>
  </section>
</template>
