<script setup lang="ts">
// ค่าแรงหมอวันนี้ (OWNER): ตัวกรองสาขา + ประเภท (หมอประจำ/หมอวิ่ง)
//   รวม = ค่ามือ + ประกันมือ + ทิป (ไม่แสดงรายการปรับ) · ทิปแสดงเฉพาะเมื่อมียอด
//   มือถือ: แถวละคน (ชื่อ + ยอดรวมตัวใหญ่ · ด้านล่างเฉพาะยอดที่มี) · แท็บเล็ต/จอใหญ่: ตาราง
//   ข้อมูลจาก therapist_work_summary (migration 073/075)
import { ChevronRight } from '@lucide/vue'
import { bangkokToday, formatBaht, type TherapistSummaryRow } from '@ifeew/shared'

const props = defineProps<{ branchId: string; tick?: number }>()
const supabase = useSupabaseClient()
const { company, branches } = useAccess()

const branch = ref<string | null>(null) // null = ทุกสาขา
const kind = ref<'ALL' | 'REGULAR' | 'WALK_IN'>('ALL')
const rows = ref<TherapistSummaryRow[] | null>(null)
const error = ref<string | null>(null)

let seq = 0
async function load() {
  if (!company.value) return
  const s = ++seq
  const today = bangkokToday()
  try {
    const res = await must(supabase.rpc('therapist_work_summary', {
      p_company_id: company.value.company_id, p_branch_id: branch.value, p_from: today, p_to: today,
    }))
    if (s === seq) {
      rows.value = res as unknown as TherapistSummaryRow[]
      error.value = null
    }
  } catch (e) {
    if (s === seq) error.value = errorText(e, 'โหลดค่าแรงหมอไม่สำเร็จ')
  }
}
watch([branch, () => company.value?.company_id], load, { immediate: true })
watch(() => props.tick, load) // realtime จากแดชบอร์ด
useLiveInterval(load, 60_000)

const n = (v: unknown) => Number(v) || 0
const pay = (r: TherapistSummaryRow) => n(r.fee_estimate) + n(r.guarantee) + n(r.tips)

const branchItems = computed(() => [{ value: null, title: 'ทุกสาขา' }, ...branches.value.map((b) => ({ value: b.branch_id, title: b.name }))])
const kindItems = [
  { value: 'ALL', title: 'ทุกประเภท' },
  { value: 'REGULAR', title: 'หมอประจำ' },
  { value: 'WALK_IN', title: 'หมอวิ่ง' },
]

// เรียงตามรวม (ไม่นับรายการปรับ) มากไปน้อย
const shown = computed(() =>
  (rows.value ?? [])
    .filter((r) => kind.value === 'ALL' || (r.kind ?? 'REGULAR') === kind.value)
    .filter((r) => pay(r) > 0 || n(r.services) > 0)
    .sort((a, b) => pay(b) - pay(a) || a.nickname.localeCompare(b.nickname, 'th')),
)
const hasTips = computed(() => shown.value.some((r) => n(r.tips) > 0))
const totals = computed(() => ({
  services: shown.value.reduce((s, r) => s + n(r.services), 0),
  fee: shown.value.reduce((s, r) => s + n(r.fee_estimate), 0),
  guarantee: shown.value.reduce((s, r) => s + n(r.guarantee), 0),
  tips: shown.value.reduce((s, r) => s + n(r.tips), 0),
  pay: shown.value.reduce((s, r) => s + pay(r), 0),
}))
const rank = (i: number) => String(i + 1).padStart(2, '0')
const rowKey = (r: TherapistSummaryRow) => r.employee_id ?? `walkin:${r.nickname}`
const emptyText = computed(() => (rows.value?.length ? 'ไม่มีหมอประเภทนี้ทำงานวันนี้' : 'วันนี้ยังไม่มีหมอทำงาน'))

// มือถือ: แสดงเฉพาะยอดที่มี (งานแสดงเสมอ)
function mobileParts(r: TherapistSummaryRow) {
  const out: Array<{ label: string; value: string }> = [{ label: 'งาน', value: String(n(r.services)) }]
  if (n(r.fee_estimate)) out.push({ label: 'ค่ามือ', value: formatBaht(n(r.fee_estimate)) })
  if (n(r.guarantee)) out.push({ label: 'ประกันมือ', value: formatBaht(n(r.guarantee)) })
  if (n(r.tips)) out.push({ label: 'ทิป', value: formatBaht(n(r.tips)) })
  return out
}
</script>

<template>
  <section class="rounded-xl border border-border bg-card shadow-soft" aria-labelledby="pay-h">
    <!-- หัว: คำตอบก่อน (ยอดรวมวันนี้ตัวใหญ่) แล้วจึงตัวกรอง -->
    <div class="flex flex-wrap items-end justify-between gap-4 border-b border-border p-4 sm:px-5">
      <div class="grid gap-1">
        <h2 id="pay-h" class="m-0 text-[15px] font-semibold text-muted-foreground">ค่าแรงหมอวันนี้</h2>
        <p v-if="rows" class="num m-0 text-3xl leading-none font-semibold text-heading" aria-live="polite">{{ formatBaht(totals.pay) }}</p>
        <Skeleton v-else class="h-8 w-28" />
        <p v-if="shown.length" class="m-0 text-sm text-muted-foreground">
          <span class="num">{{ shown.length }}</span> คน ทำ <span class="num">{{ totals.services }}</span> งาน
        </p>
      </div>
      <div class="grid w-full grid-cols-2 gap-2 sm:w-auto sm:grid-cols-[11rem_10rem]">
        <SelectField v-model="branch" :items="branchItems" aria-label="สาขา" />
        <SelectField v-model="kind" :items="kindItems" aria-label="ประเภทหมอ" />
      </div>
    </div>

    <p v-if="error" class="m-0 p-5 text-sm text-danger-ink">{{ error }}</p>
    <div v-else-if="!rows" class="grid gap-2 p-5"><Skeleton v-for="i in 3" :key="i" class="h-9" /></div>
    <p v-else-if="!shown.length" class="m-0 px-4 py-8 text-center text-sm text-muted-foreground">{{ emptyText }}</p>
    <template v-else>
      <!-- มือถือ: แถวละคน — วงอักษรแรกของชื่อ (หมอวิ่ง = วงเส้นประ) · ยอดชิดขวา -->
      <ul class="m-0 grid list-none divide-y divide-border p-0 md:hidden">
        <li v-for="r in shown" :key="rowKey(r)" class="flex items-center gap-3 px-4 py-3.5">
          <span
            class="grid size-10 shrink-0 place-items-center rounded-full text-base font-semibold"
            :class="r.kind === 'WALK_IN' ? 'border border-dashed border-brand-accent text-brand-accent' : 'bg-secondary text-heading'"
            aria-hidden="true"
          >{{ r.nickname.slice(0, 1) }}</span>
          <div class="min-w-0 flex-1">
            <div class="flex items-baseline justify-between gap-3">
              <p class="m-0 min-w-0 truncate text-base font-semibold text-heading">
                {{ r.nickname }}<span v-if="r.kind === 'WALK_IN'" class="ml-1.5 text-xs font-normal text-brand-accent">หมอวิ่ง</span>
              </p>
              <span class="num shrink-0 text-lg font-semibold text-heading">{{ formatBaht(pay(r)) }}</span>
            </div>
            <p class="m-0 mt-0.5 flex flex-wrap gap-x-3 gap-y-0.5 text-[13px] text-muted-foreground">
              <span><span class="num">{{ n(r.services) }}</span> งาน</span>
              <span v-for="m in mobileParts(r).slice(1)" :key="m.label">{{ m.label }} <span class="num text-foreground">{{ m.value }}</span></span>
            </p>
          </div>
        </li>
      </ul>

      <!-- แท็บเล็ต/จอใหญ่: ตาราง -->
      <div class="hidden overflow-x-auto md:block">
        <Table>
          <TableHeader>
            <TableRow class="hover:bg-transparent">
              <TableHead class="w-16">ลำดับ</TableHead>
              <TableHead>ชื่อหมอ</TableHead>
              <TableHead class="text-right">จำนวนงาน</TableHead>
              <TableHead class="text-right">ค่ามือ</TableHead>
              <TableHead class="text-right">ประกันมือ</TableHead>
              <TableHead v-if="hasTips" class="text-right">ทิป</TableHead>
              <TableHead class="text-right">รวม</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow v-for="(r, i) in shown" :key="rowKey(r)">
              <TableCell class="num text-muted-foreground">{{ rank(i) }}</TableCell>
              <TableCell>
                <span class="font-medium text-heading">{{ r.nickname }}</span>
                <Badge v-if="r.kind === 'WALK_IN'" variant="outline" class="ml-2">หมอวิ่ง</Badge>
              </TableCell>
              <TableCell class="num text-right">{{ n(r.services) }}</TableCell>
              <TableCell class="num text-right">{{ formatBaht(n(r.fee_estimate)) }}</TableCell>
              <TableCell class="num text-right">{{ formatBaht(n(r.guarantee)) }}</TableCell>
              <TableCell v-if="hasTips" class="num text-right">{{ formatBaht(n(r.tips)) }}</TableCell>
              <TableCell class="num text-right font-semibold text-heading">{{ formatBaht(pay(r)) }}</TableCell>
            </TableRow>
          </TableBody>
          <TableFooter>
            <TableRow class="hover:bg-transparent">
              <TableCell />
              <TableCell class="font-semibold text-heading">รวม</TableCell>
              <TableCell class="num text-right font-semibold text-heading">{{ totals.services }}</TableCell>
              <TableCell class="num text-right font-semibold text-heading">{{ formatBaht(totals.fee) }}</TableCell>
              <TableCell class="num text-right font-semibold text-heading">{{ formatBaht(totals.guarantee) }}</TableCell>
              <TableCell v-if="hasTips" class="num text-right font-semibold text-heading">{{ formatBaht(totals.tips) }}</TableCell>
              <TableCell class="num text-right font-semibold text-heading">{{ formatBaht(totals.pay) }}</TableCell>
            </TableRow>
          </TableFooter>
        </Table>
      </div>
    </template>

    <NuxtLink
      to="/reports/therapists"
      class="flex items-center justify-between gap-2 rounded-b-xl border-t border-border px-4 py-3 text-sm font-medium text-primary no-underline transition-colors hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none sm:px-5"
    >
      ดูค่าแรงย้อนหลัง <ChevronRight class="size-4" aria-hidden="true" />
    </NuxtLink>
  </section>
</template>
