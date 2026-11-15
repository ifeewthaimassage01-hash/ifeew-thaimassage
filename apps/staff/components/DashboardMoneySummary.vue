<script setup lang="ts">
// สรุปการเงินของสาขา (OWNER): รายได้ · รายจ่าย (รวมค่าแรง/ค่าน้ำมันหมอวิ่ง) · ยอดสุทธิ · ลูกค้าแยกตามประเภทหมอ
// ข้อมูลจาก RPC branch_money_summary (migration 045) — สูตรรายได้/รายจ่ายเดียวกับหน้ารายงานการเงิน
import { ReceiptText, TrendingUp, Users, Wallet } from '@lucide/vue'
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

const props = defineProps<{ branchId: string; tick?: number }>()
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
watch(() => props.tick, load) // realtime จากแดชบอร์ด (คิว/บิลเปลี่ยน)
useLiveInterval(load, 60_000)

const n = (v: unknown) => Number(v) || 0
const expenseLines = computed(() => {
  const d = data.value
  if (!d) return []
  return [
    { label: 'รายจ่ายร้าน', value: n(d.expenses) },
    { label: 'ค่าแรงหมอ', value: n(d.commission) },
    { label: 'ค่าแรงหมอวิ่ง', value: n(d.freelance_fee) },
    { label: 'ค่าน้ำมันหมอวิ่ง', value: n(d.freelance_fuel) },
  ]
})
const customerLines = computed(() => {
  const c = data.value?.customers
  return [
    // หมอที่มีบัญชีทุกคนเป็นหมอประจำ (เลิกใช้ประเภทหมอฟรีแลนซ์ใน migration 064 · รวมข้อมูลเก่าไว้ที่หมอประจำ)
    { key: 'REGULAR', label: 'หมอประจำ', n: n(c?.REGULAR) + n(c?.FREELANCE) },
    { key: 'WALK_IN', label: 'หมอวิ่ง', n: n(c?.WALK_IN) },
  ]
})
// ช่องสรุป: รายได้ · รายจ่าย (แยกเฉพาะที่มียอด) · ยอดสุทธิ (เขียว/แดง + ข้อความ) · ลูกค้า
const tiles = computed(() => {
  const d = data.value
  if (!d) return []
  const net = n(d.net)
  return [
    {
      key: 'revenue', label: 'รายได้', icon: TrendingUp, value: formatBaht(n(d.revenue)),
      note: 'รับเงินสุทธิ หักคืนเงินแล้ว', lines: [], box: 'border-border bg-muted/40', ink: 'text-heading',
    },
    {
      key: 'expenses', label: 'รายจ่าย', icon: ReceiptText, value: formatBaht(n(d.total_expenses)),
      note: expenseLines.value.some((l) => l.value) ? '' : 'ยังไม่มีรายจ่าย',
      lines: expenseLines.value.filter((l) => l.value).map((l) => ({ label: l.label, value: formatBaht(l.value) })),
      box: 'border-border bg-muted/40', ink: 'text-heading',
    },
    {
      key: 'net', label: 'ยอดสุทธิ', icon: Wallet, value: `${net < 0 ? '−' : ''}${formatBaht(Math.abs(net))}`,
      note: net < 0 ? 'รายจ่ายมากกว่ารายได้' : 'รายได้ − รายจ่าย', noteInk: net < 0 ? 'text-danger-ink' : 'text-success-ink',
      lines: [],
      box: net < 0 ? 'border-danger/30 bg-danger-soft/60' : 'border-success/30 bg-success-soft/60',
      ink: net < 0 ? 'text-danger-ink' : 'text-success-ink',
    },
    {
      key: 'customers', label: 'ลูกค้าที่ใช้บริการ', icon: Users, value: `${n(d.customers?.total)} คน`, note: '',
      lines: customerLines.value.map((c) => ({ label: c.label, value: `${c.n} คน` })),
      box: 'border-border bg-muted/40', ink: 'text-heading',
    },
  ] as Array<{ key: string; label: string; icon: unknown; value: string; note: string; noteInk?: string; lines: Array<{ label: string; value: string }>; box: string; ink: string }>
})
const periodLabel = computed(() => ({ today: 'วันนี้', '7d': ' 7 วันล่าสุด', month: 'เดือนนี้' })[period.value])
</script>

<template>
  <section class="rounded-xl border border-border bg-card p-4 shadow-soft sm:p-5" aria-labelledby="money-h">
    <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
      <h2 id="money-h" class="m-0 text-[15px] font-semibold">สรุปการเงิน{{ periodLabel }}</h2>
      <!-- มือถือ: เต็มแถว ปุ่มแบ่งเท่ากัน กดด้วยนิ้วโป้งได้ง่าย -->
      <SegmentedControl
        v-model="period"
        :items="[{ value: 'today', label: 'วันนี้' }, { value: '7d', label: '7 วัน' }, { value: 'month', label: 'เดือนนี้' }]"
        label="ช่วงเวลา"
      />
    </div>

    <Alert v-if="error" variant="destructive" class="mb-4"><AlertDescription>{{ error }}</AlertDescription></Alert>

    <div v-if="!data && loading" class="grid grid-cols-2 gap-2.5 lg:grid-cols-4">
      <Skeleton v-for="i in 4" :key="i" class="h-32 rounded-lg" />
    </div>

    <!-- ช่องแบบเดียวกับเตียงและอุปกรณ์: มือถือ 2×2 · จอใหญ่ 4 ช่อง -->
    <ul
      v-else-if="data"
      class="m-0 grid list-none grid-cols-2 gap-2.5 p-0 lg:grid-cols-4"
      :class="loading ? 'opacity-60 transition-opacity' : ''"
      aria-live="polite"
    >
      <li v-for="t in tiles" :key="t.key" class="grid content-start gap-1.5 rounded-lg border p-3" :class="t.box">
        <span class="flex items-center gap-2">
          <span class="grid size-7 shrink-0 place-items-center rounded-full bg-card text-brand-accent" aria-hidden="true"><component :is="t.icon" class="size-4" :stroke-width="1.6" /></span>
          <span class="min-w-0 truncate text-sm font-medium text-heading">{{ t.label }}</span>
        </span>
        <span class="num text-2xl leading-tight font-semibold" :class="t.ink">{{ t.value }}</span>
        <span v-if="t.note" class="text-[13px]" :class="t.noteInk ?? 'text-muted-foreground'">{{ t.note }}</span>
        <dl v-if="t.lines.length" class="m-0 grid gap-0.5 text-[13px]">
          <div v-for="l in t.lines" :key="l.label" class="flex justify-between gap-2">
            <dt class="min-w-0 truncate text-muted-foreground">{{ l.label }}</dt><dd class="num m-0 shrink-0 text-foreground">{{ l.value }}</dd>
          </div>
        </dl>
      </li>
    </ul>  </section>
</template>
