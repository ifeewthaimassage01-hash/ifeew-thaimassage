<script setup lang="ts">
// OWNER: ข้อมูลหมอ — รวมทุกอย่างเกี่ยวกับหมอไว้หน้าเดียว (รวมหน้า /attendance เดิมเข้ามา)
//   แท็บ ภาพรวม      : หมอแต่ละคน = ค่าแรงเดือนนี้ + แถบวันที่มาทำงาน (ช่องละวัน) + งาน/ค่ามือ/ประกันมือ/ทิป · แตะเพื่อดูรายวัน
//   แท็บ ตารางเข้างาน : เวลาเช็คชื่อรายวัน (components/AttendanceGrid.vue)
//   แท็บ ประกันมือ    : ตั้งยอดประกัน/ให้-ไม่ให้รายวัน (components/GuaranteePanel.vue)
//   ตัวเลือกเดือน + สาขา ใช้ร่วมกันทุกแท็บ
import { ChevronRight } from '@lucide/vue'
import {
  bangkokToday,
  formatBaht,
  formatDuration,
  type AttendanceRow,
  type TherapistPayDay,
  type TherapistSummaryRow,
} from '@ifeew/shared'

definePageMeta({ ownerOnly: true })

const route = useRoute()
const router = useRouter()
const supabase = useSupabaseClient()
const { company, branches } = useAccess()

type Tab = 'overview' | 'attendance' | 'guarantee'
const tab = ref<Tab>(['attendance', 'guarantee'].includes(String(route.query.tab)) ? (route.query.tab as Tab) : 'overview')
watch(tab, (t) => router.replace({ query: t === 'overview' ? {} : { tab: t } }))

const today = bangkokToday()
const month = ref(today.slice(0, 7))
const branchId = ref<string | null>(null)
const branchItems = computed(() => [{ value: null, title: 'ทุกสาขา' }, ...branches.value.map((b) => ({ value: b.branch_id, title: b.name }))])

// วันของเดือนที่เลือก (เดือนนี้ = ถึงวันนี้)
const monthDays = computed(() => {
  const [y, m] = month.value.split('-').map(Number) as [number, number]
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate()
  const out: Array<{ date: string; day: number; weekend: boolean }> = []
  for (let d = 1; d <= last; d++) {
    const date = `${month.value}-${String(d).padStart(2, '0')}`
    if (date > today) break
    const dow = new Date(Date.UTC(y, m - 1, d)).getUTCDay()
    out.push({ date, day: d, weekend: dow === 0 || dow === 6 })
  }
  return out
})
const range = computed(() => ({ from: `${month.value}-01`, to: monthDays.value.at(-1)?.date ?? `${month.value}-01` }))

// ---------------------------------------------------------------------------
// ภาพรวม: ค่าแรง (therapist_work_summary) + วันที่มาทำงาน (attendance_report)
// ---------------------------------------------------------------------------
const summary = ref<TherapistSummaryRow[] | null>(null)
const attendance = ref<AttendanceRow[]>([])
const loading = ref(false)
const error = ref<string | null>(null)

let seq = 0
async function load() {
  if (!company.value || !monthDays.value.length) {
    summary.value = []
    attendance.value = []
    return
  }
  const s = ++seq
  loading.value = true
  try {
    const [sum, att] = await Promise.all([
      must(supabase.rpc('therapist_work_summary', {
        p_company_id: company.value.company_id, p_branch_id: branchId.value, p_from: range.value.from, p_to: range.value.to,
      })),
      must(supabase.rpc('attendance_report', {
        p_company_id: company.value.company_id, p_branch_id: branchId.value, p_from: range.value.from, p_to: range.value.to,
      })),
    ])
    if (s !== seq) return
    summary.value = sum as unknown as TherapistSummaryRow[]
    attendance.value = (att ?? []) as unknown as AttendanceRow[]
    error.value = null
  } catch (e) {
    if (s === seq) error.value = errorText(e, 'โหลดข้อมูลหมอไม่สำเร็จ')
  } finally {
    if (s === seq) loading.value = false
  }
}
watch([month, branchId, () => company.value?.company_id], load, { immediate: true })

const n = (v: unknown) => Number(v) || 0
// วันที่มา (เช็คชื่อจริง) ต่อพนักงาน
const presentDays = computed(() => {
  const m = new Map<string, { nickname: string; dates: Set<string> }>()
  for (const r of attendance.value) {
    if (!r.clock_in_at) continue
    if (!m.has(r.employee_id)) m.set(r.employee_id, { nickname: r.nickname, dates: new Set() })
    m.get(r.employee_id)!.dates.add(r.business_date)
  }
  return m
})

type Person = TherapistSummaryRow & { present: Set<string> | null; pay: number }
// คนที่แสดง: มีค่าแรง/งานในเดือนนี้ หรือมาทำงานอย่างน้อย 1 วัน · เรียงตามค่าแรง
const people = computed<Person[]>(() => {
  const out: Person[] = (summary.value ?? []).map((r) => ({
    ...r,
    present: r.employee_id ? presentDays.value.get(r.employee_id)?.dates ?? new Set() : null,
    pay: n(r.fee_estimate) + n(r.guarantee) + n(r.adjustments) + n(r.tips),
  }))
  for (const [id, p] of presentDays.value) {
    if (out.some((x) => x.employee_id === id)) continue
    out.push({
      employee_id: id, employee_code: null, nickname: p.nickname, kind: 'REGULAR', services: 0, worked_minutes: 0,
      off_shift_count: 0, handover_count: 0, fee_estimate: 0, guarantee: 0, adjustments: 0, tips: 0, pay_total: 0,
      present: p.dates, pay: 0,
    })
  }
  return out.sort((a, b) => b.pay - a.pay || a.nickname.localeCompare(b.nickname, 'th'))
})
const totals = computed(() => ({
  pay: people.value.reduce((s, p) => s + p.pay, 0),
  services: people.value.reduce((s, p) => s + n(p.services), 0),
}))
const monthLabel = computed(() => {
  const [y, m] = month.value.split('-').map(Number) as [number, number]
  return month.value === today.slice(0, 7)
    ? 'เดือนนี้'
    : new Date(Date.UTC(y, m - 1, 15)).toLocaleDateString('th-TH', { month: 'long', timeZone: 'UTC' })
})
// ตัวเลขใต้ชื่อ: แสดงเฉพาะที่มี
function parts(p: Person) {
  const out: Array<{ label: string; value: string; tone?: string }> = []
  if (p.present) out.push({ label: 'มา', value: `${p.present.size} วัน` })
  out.push({ label: '', value: `${n(p.services)} งาน` })
  if (n(p.fee_estimate)) out.push({ label: 'ค่ามือ', value: formatBaht(n(p.fee_estimate)) })
  if (n(p.guarantee)) out.push({ label: 'ประกันมือ', value: formatBaht(n(p.guarantee)) })
  if (n(p.adjustments)) out.push({ label: 'ปรับ', value: `${n(p.adjustments) > 0 ? '+' : ''}${formatBaht(n(p.adjustments))}`, tone: n(p.adjustments) < 0 ? 'text-danger-ink' : '' })
  if (n(p.tips)) out.push({ label: 'ทิป', value: formatBaht(n(p.tips)) })
  return out
}
const personKey = (p: Person) => p.employee_id ?? `walkin:${p.nickname}`

// ---------------------------------------------------------------------------
// รายวันของหมอที่เลือก
// ---------------------------------------------------------------------------
const picked = ref<Person | null>(null)
const days = ref<TherapistPayDay[]>([])
const daysLoading = ref(false)
const daysError = ref<string | null>(null)
async function openDays(p: Person) {
  if (!company.value || !p.employee_id) return // หมอวิ่งไม่มีรายวัน
  picked.value = p
  days.value = []
  daysError.value = null
  daysLoading.value = true
  try {
    days.value = (await must(supabase.rpc('therapist_pay_daily', {
      p_company_id: company.value.company_id, p_branch_id: branchId.value, p_employee_id: p.employee_id,
      p_from: range.value.from, p_to: range.value.to,
    }))) as unknown as TherapistPayDay[]
  } catch (e) {
    daysError.value = errorText(e, 'โหลดไม่สำเร็จ')
  } finally {
    daysLoading.value = false
  }
}
const dayLabel = (d: string) =>
  new Date(`${d}T00:00:00+07:00`).toLocaleDateString('th-TH', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'Asia/Bangkok' })
</script>

<template>
  <div>
  <PageHeader title="ข้อมูลหมอ" description="ค่าแรง การเข้างาน และประกันมือของหมอแต่ละคน" />
  <div class="grid gap-5">

    <!-- แท็บ + ตัวเลือกเดือน/สาขา -->
    <div class="grid gap-3">
      <SegmentedControl
        v-model="tab"
        :items="[{ value: 'overview', label: 'ภาพรวม' }, { value: 'attendance', label: 'ตารางเข้างาน' }, { value: 'guarantee', label: 'ประกันมือ' }]"
        label="มุมมอง"
        class="w-full sm:w-auto"
      />
      <div class="flex flex-wrap items-center justify-between gap-2">
        <MonthSwitcher v-model="month" class="w-full sm:w-auto" />
        <SelectField v-if="branches.length > 1" v-model="branchId" :items="branchItems" aria-label="สาขา" class="w-full sm:w-56" />
      </div>
    </div>

    <!-- ======================= ภาพรวม ======================= -->
    <template v-if="tab === 'overview'">
      <Alert v-if="error" variant="destructive"><AlertDescription>{{ error }}</AlertDescription></Alert>

      <section class="rounded-xl border border-border bg-card shadow-soft" aria-labelledby="ov-h">
        <div class="grid gap-1 border-b border-border px-4 py-4 sm:px-5">
          <h2 id="ov-h" class="m-0 text-[15px] font-semibold text-muted-foreground">ค่าแรงหมอ{{ monthLabel }}</h2>
          <p v-if="summary" class="num m-0 text-3xl leading-none font-semibold text-heading" aria-live="polite">{{ formatBaht(totals.pay) }}</p>
          <Skeleton v-else class="h-8 w-32" />
          <p v-if="people.length" class="m-0 text-sm text-muted-foreground">
            หมอ <span class="num">{{ people.length }}</span> คน ทำ <span class="num">{{ totals.services }}</span> งาน
          </p>
        </div>

        <LoadingBar v-if="loading && summary" />
        <div v-if="!summary" class="grid gap-3 p-5"><Skeleton v-for="i in 3" :key="i" class="h-16" /></div>
        <p v-else-if="!monthDays.length" class="m-0 px-4 py-10 text-center text-muted-foreground">ยังไม่ถึงเดือนนี้</p>
        <p v-else-if="!people.length" class="m-0 px-4 py-10 text-center text-muted-foreground">ยังไม่มีหมอทำงานใน{{ monthLabel }}</p>

        <ul v-else class="m-0 grid list-none divide-y divide-border p-0">
          <li v-for="p in people" :key="personKey(p)">
            <component
              :is="p.employee_id ? 'button' : 'div'"
              :type="p.employee_id ? 'button' : undefined"
              class="flex w-full gap-3 px-4 py-4 text-left sm:px-5"
              :class="p.employee_id ? 'transition-colors hover:bg-muted/60 focus-visible:bg-muted/60 focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none focus-visible:ring-inset' : ''"
              :aria-label="p.employee_id ? `ดูค่าแรงรายวันของ ${p.nickname}` : undefined"
              @click="openDays(p)"
            >
              <span
                class="grid size-10 shrink-0 place-items-center rounded-full text-base font-semibold"
                :class="p.kind === 'WALK_IN' ? 'border border-dashed border-brand-accent text-brand-accent' : 'bg-secondary text-heading'"
                aria-hidden="true"
              >{{ p.nickname.slice(0, 1) }}</span>

              <span class="grid min-w-0 flex-1 gap-2">
                <!-- ชื่อ | ค่าแรง -->
                <span class="flex items-baseline justify-between gap-3">
                  <span class="min-w-0 truncate text-base font-semibold text-heading">
                    {{ p.nickname }}<span v-if="p.kind === 'WALK_IN'" class="ml-1.5 text-xs font-normal text-brand-accent">หมอวิ่ง</span>
                  </span>
                  <span class="flex shrink-0 items-center gap-1">
                    <span class="num text-lg font-semibold text-heading">{{ formatBaht(p.pay) }}</span>
                    <ChevronRight v-if="p.employee_id" class="size-4 text-muted-soft" aria-hidden="true" />
                  </span>
                </span>

                <!-- แถบวันที่มาทำงาน: ช่องละวัน -->
                <span
                  v-if="p.present"
                  class="flex gap-[3px]"
                  role="img"
                  :aria-label="`มาทำงาน ${p.present.size} จาก ${monthDays.length} วัน`"
                >
                  <span
                    v-for="d in monthDays"
                    :key="d.date"
                    class="h-3 max-w-3.5 min-w-0 flex-1 rounded-[3px]"
                    :class="p.present.has(d.date) ? 'bg-success' : d.weekend ? 'bg-muted-soft/40' : 'bg-muted'"
                    :title="`${d.day} ${p.present.has(d.date) ? 'มา' : 'ไม่ได้มา'}`"
                  />
                </span>

                <!-- ตัวเลข -->
                <span class="flex flex-wrap gap-x-4 gap-y-0.5 text-[13px] text-muted-foreground">
                  <span v-for="x in parts(p)" :key="x.label + x.value">
                    <template v-if="x.label">{{ x.label }} </template><span class="num" :class="x.tone || 'text-foreground'">{{ x.value }}</span>
                  </span>
                </span>
              </span>
            </component>
          </li>
        </ul>
      </section>
      <p class="m-0 -mt-2 px-1 text-sm text-muted-foreground">
        ค่าแรง = ค่ามือ + ประกันมือ + รายการปรับ + ทิป · ช่องสีเขียวคือวันที่มาทำงาน · หมอวิ่งไม่มีข้อมูลรายวัน
      </p>
    </template>

    <!-- ======================= ตารางเข้างาน ======================= -->
    <AttendanceGrid v-else-if="tab === 'attendance'" :month="month" :branch-id="branchId" />

    <!-- ======================= ประกันมือ ======================= -->
    <GuaranteePanel v-else :month="month" :branch-id="branchId" />

    <!-- รายวันของหมอที่เลือก -->
    <Dialog :open="!!picked" @update:open="(v) => !v && (picked = null)">
      <DialogContent class="max-h-[85dvh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>ค่าแรง {{ picked?.nickname }} {{ monthLabel }}</DialogTitle>
          <DialogDescription>
            รวม <span class="num font-semibold text-heading">{{ formatBaht(picked?.pay ?? 0) }}</span>
            <template v-if="picked?.present"> มาทำงาน <span class="num">{{ picked.present.size }}</span> วัน</template>
          </DialogDescription>
        </DialogHeader>
        <LoadingBar v-if="daysLoading" />
        <p v-if="daysError" class="m-0 text-sm text-danger-ink">{{ daysError }}</p>
        <p v-else-if="!daysLoading && !days.length" class="m-0 py-6 text-center text-muted-foreground">ไม่มีงานในเดือนนี้</p>
        <div v-else class="grid gap-3">
          <section v-for="d in days" :key="d.date" class="rounded-lg border border-border">
            <header class="flex items-baseline justify-between gap-3 border-b border-border px-4 py-2.5">
              <span class="font-medium text-heading">{{ dayLabel(d.date) }}</span>
              <span class="num font-semibold text-heading">{{ formatBaht(Number(d.total)) }}</span>
            </header>
            <ul class="m-0 grid list-none gap-1 px-4 py-2.5 text-sm">
              <li v-for="(j, i) in d.jobs" :key="i" class="flex justify-between gap-3">
                <span><span class="num text-muted-foreground">{{ j.time ?? '–' }}</span> {{ j.service_name }} {{ formatDuration(j.minutes) }}<span v-if="j.handover" class="text-muted-foreground"> (ส่งต่อ)</span></span>
                <span class="num shrink-0">{{ formatBaht(Number(j.fee)) }}</span>
              </li>
              <li v-if="Number(d.guarantee) > 0" class="flex justify-between gap-3">
                <span>ประกันมือ<span v-if="d.guarantee_base" class="text-muted-foreground"> (เติมให้ครบ {{ formatBaht(Number(d.guarantee_base)) }})</span></span>
                <span class="num shrink-0">{{ formatBaht(Number(d.guarantee)) }}</span>
              </li>
              <li v-if="Number(d.adjustments) !== 0" class="flex justify-between gap-3">
                <span>ปรับ</span><span class="num shrink-0">{{ formatBaht(Number(d.adjustments)) }}</span>
              </li>
              <li v-if="Number(d.tips) > 0" class="flex justify-between gap-3 text-success-ink">
                <span>ทิป</span><span class="num shrink-0">{{ formatBaht(Number(d.tips)) }}</span>
              </li>
            </ul>
          </section>
        </div>
      </DialogContent>
    </Dialog>
  </div>
  </div>
</template>
