<script setup lang="ts">
// แท็บ "ประกันมือ" ในหน้า ข้อมูลหมอ (/reports/therapists) — เดิมอยู่ที่ /guarantees และ /attendance
// OWNER: ยอดประกันต่อวันของหมอแต่ละคน (มีประวัติ/ตั้งล่วงหน้าได้) + ผลเติมประกันรายวันของเดือนที่เลือก (ให้/ไม่ให้เป็นรายวันพร้อมเหตุผล)
// เดือนและสาขามาจากตัวเลือกของหน้า
import { PenLine } from '@lucide/vue'
import { bangkokTime, bangkokToday, formatBaht, type AttendanceRow } from '@ifeew/shared'

const props = defineProps<{ month: string; branchId: string | null }>()

const { prompt } = useDialog()
const supabase = useSupabaseClient()
const { company } = useAccess()
const { run } = useStepUp()

type Emp = { id: string; nickname: string; employee_code: string; employment_type: string; status: string }
type Rate = { employee_id: string; daily_amount: number; effective_from: string; effective_to: string | null }

const employees = ref<Emp[]>([])
const rates = ref<Rate[]>([])
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)
const fail = (e: unknown) => (message.value = { type: 'error', text: errorText(e) })
const today = bangkokToday()
const n = (v: unknown) => Number(v) || 0

async function loadEmployees() {
  if (!company.value) return
  const [e, r] = await Promise.all([
    supabase.from('employees').select('id, nickname, employee_code, employment_type, status')
      .eq('company_id', company.value.company_id).neq('status', 'RESIGNED').order('nickname'),
    supabase.from('employee_guarantee_rates').select('employee_id, daily_amount, effective_from, effective_to')
      .eq('company_id', company.value.company_id).eq('status', 'ACTIVE').order('effective_from'),
  ])
  employees.value = (e.data ?? []) as Emp[]
  rates.value = (r.data ?? []) as Rate[]
}
watch(() => company.value?.company_id, loadEmployees, { immediate: true })

const currentRate = (id: string) =>
  rates.value.find((r) => r.employee_id === id && r.effective_from <= today && (!r.effective_to || r.effective_to > today))
const futureRates = (id: string) => rates.value.filter((r) => r.employee_id === id && r.effective_from > today)
const dateLabel = (d: string, weekday = false) =>
  new Date(`${d}T00:00:00+07:00`).toLocaleDateString('th-TH', {
    ...(weekday ? { weekday: 'short' } : {}), day: 'numeric', month: 'short', timeZone: 'Asia/Bangkok',
  })

// ตั้ง/แก้ยอดประกัน
const rateDialog = ref(false)
const rateEmp = ref<Emp | null>(null)
const rateForm = reactive({ amount: '' as number | string, from: today, reason: '' })
const saving = ref(false)
function openRate(emp: Emp) {
  rateEmp.value = emp
  Object.assign(rateForm, { amount: currentRate(emp.id)?.daily_amount ?? '', from: today, reason: '' })
  rateDialog.value = true
}
async function saveRate() {
  if (!rateEmp.value) return
  const empId = rateEmp.value.id
  saving.value = true
  try {
    await run(() => must(supabase.rpc('set_employee_guarantee', {
      p_employee_id: empId, p_daily_amount: Number(rateForm.amount) || 0, p_effective_from: rateForm.from, p_reason: rateForm.reason.trim(),
    })))
    rateDialog.value = false
    message.value = { type: 'success', text: `บันทึกยอดประกันมือของ ${rateEmp.value.nickname} แล้ว` }
    await Promise.all([loadEmployees(), loadDays()])
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}

// ผลประกันรายวันของเดือนที่เลือก (เฉพาะหมอที่มียอดประกันในวันนั้น)
const rows = ref<AttendanceRow[]>([])
const loading = ref(false)
const range = computed(() => {
  const [y, m] = props.month.split('-').map(Number) as [number, number]
  const last = `${props.month}-${String(new Date(Date.UTC(y, m, 0)).getUTCDate()).padStart(2, '0')}`
  return { from: `${props.month}-01`, to: last < today ? last : today }
})
async function loadDays() {
  if (!company.value || range.value.from > today) {
    rows.value = []
    return
  }
  loading.value = true
  try {
    rows.value = (await must(supabase.rpc('attendance_report', {
      p_company_id: company.value.company_id, p_branch_id: props.branchId, p_from: range.value.from, p_to: range.value.to,
    }))) as unknown as AttendanceRow[]
  } catch (e) {
    fail(e)
  } finally {
    loading.value = false
  }
}
watch([() => props.month, () => props.branchId, () => company.value?.company_id], loadDays, { immediate: true })

const byDate = computed(() => {
  const m = new Map<string, AttendanceRow[]>()
  for (const r of rows.value) {
    if (!n(r.rate)) continue
    if (!m.has(r.business_date)) m.set(r.business_date, [])
    m.get(r.business_date)!.push(r)
  }
  return [...m.entries()]
    .sort((a, b) => b[0].localeCompare(a[0]))
    .map(([date, list]) => ({ date, list: list.sort((a, b) => a.nickname.localeCompare(b.nickname, 'th')) }))
})
const topupTotal = computed(() => rows.value.reduce((s, r) => s + n(r.topup), 0))
const monthName = computed(() => {
  const [y, m] = props.month.split('-').map(Number) as [number, number]
  return new Date(Date.UTC(y, m - 1, 15)).toLocaleDateString('th-TH', { month: 'long', timeZone: 'UTC' })
})

function status(r: AttendanceRow): { text: string; tone: string } {
  if (r.override_grant === true) return { text: 'เจ้าของให้ประกัน', tone: 'text-success-ink' }
  if (r.override_grant === false) return { text: 'เจ้าของไม่ให้ประกัน', tone: 'text-danger-ink' }
  if (r.clock_in_at) return { text: `เข้างาน ${bangkokTime(r.clock_in_at)}`, tone: 'text-foreground' }
  return { text: 'ไม่ได้เช็คชื่อ', tone: 'text-muted-foreground' }
}

async function override(r: AttendanceRow, grant: boolean) {
  const reason = await prompt({
    title: `${grant ? 'ให้' : 'ไม่ให้'}ประกันมือ ${r.nickname} วันที่ ${dateLabel(r.business_date)}`,
    label: 'เหตุผล',
    minLength: 3,
    confirmText: grant ? 'ให้ประกันมือ' : 'ไม่ให้ประกันมือ',
    destructive: !grant,
  })
  if (reason === null) return
  try {
    await must(supabase.rpc('set_guarantee_override', {
      p_employee_id: r.employee_id, p_branch_id: r.branch_id, p_date: r.business_date, p_grant: grant, p_reason: reason.trim(),
    }))
    message.value = { type: 'success', text: `${grant ? 'ให้' : 'ไม่ให้'}ประกันมือ ${r.nickname} วันที่ ${dateLabel(r.business_date)} แล้ว` }
    await loadDays()
  } catch (e) {
    fail(e)
  }
}
</script>

<template>
  <div class="grid gap-5">
    <MessageAlert :message="message" @close="message = null" />

    <!-- ยอดประกันต่อวัน -->
    <section class="rounded-xl border border-border bg-card shadow-soft" aria-labelledby="rate-h">
      <header class="border-b border-border px-4 py-4 sm:px-5">
        <h2 id="rate-h" class="m-0 text-[15px] font-semibold text-heading">ยอดประกันต่อวัน</h2>
        <p class="m-0 mt-1 max-w-[65ch] text-sm text-muted-foreground">
          หมอที่เช็คชื่อเข้างานได้เงินอย่างน้อยเท่ายอดนี้ ถ้าค่ามือทั้งวันไม่ถึง ระบบเติมส่วนที่ขาดให้ (ไม่นับทิป)
        </p>
      </header>
      <p v-if="!employees.length" class="m-0 px-4 py-8 text-center text-sm text-muted-foreground">ยังไม่มีพนักงาน</p>
      <ul v-else class="m-0 grid list-none divide-y divide-border p-0">
        <li v-for="e in employees" :key="e.id" class="flex items-center gap-3 px-4 py-3.5 sm:px-5">
          <span class="grid size-10 shrink-0 place-items-center rounded-full bg-secondary text-base font-semibold text-heading" aria-hidden="true">{{ e.nickname.slice(0, 1) }}</span>
          <div class="min-w-0 flex-1">
            <p class="m-0 truncate text-base font-semibold text-heading">{{ e.nickname }}</p>
            <p class="m-0 text-sm">
              <template v-if="currentRate(e.id) && n(currentRate(e.id)!.daily_amount)">
                <span class="num font-medium text-heading">{{ formatBaht(n(currentRate(e.id)!.daily_amount)) }}</span>
                <span class="text-muted-foreground"> ต่อวัน</span>
              </template>
              <span v-else class="text-muted-foreground">ไม่มีประกัน</span>
            </p>
            <p v-for="f in futureRates(e.id)" :key="f.effective_from" class="m-0 text-[13px] text-pending-ink">
              {{ n(f.daily_amount) ? `เปลี่ยนเป็น ${formatBaht(n(f.daily_amount))}` : 'เลิกประกัน' }} ตั้งแต่ {{ dateLabel(f.effective_from) }}
            </p>
          </div>
          <Button size="sm" variant="outline" :aria-label="`แก้ยอดประกันมือของ ${e.nickname}`" @click="openRate(e)">
            <PenLine /> {{ currentRate(e.id) && n(currentRate(e.id)!.daily_amount) ? 'แก้ยอด' : 'ตั้งยอด' }}
          </Button>
        </li>
      </ul>
    </section>

    <!-- เติมประกันมือรายวัน -->
    <section class="rounded-xl border border-border bg-card shadow-soft" aria-labelledby="topup-h">
      <header class="flex flex-wrap items-baseline justify-between gap-2 border-b border-border px-4 py-4 sm:px-5">
        <h2 id="topup-h" class="m-0 text-[15px] font-semibold text-heading">เติมประกันมือ {{ monthName }}</h2>
        <p class="m-0 text-sm text-muted-foreground">รวม <span class="num text-lg font-semibold text-heading">{{ formatBaht(topupTotal) }}</span></p>
      </header>
      <LoadingBar v-if="loading" />
      <p v-if="!loading && !byDate.length" class="m-0 px-4 py-10 text-center text-sm text-muted-foreground">
        ไม่มีหมอที่มียอดประกันใน{{ monthName }} ตั้งยอดได้ที่รายชื่อด้านบน
      </p>

      <div v-for="d in byDate" :key="d.date" class="border-b border-border last:border-0">
        <h3 class="m-0 bg-muted/50 px-4 py-2 text-sm font-semibold text-heading sm:px-5">
          {{ d.date === today ? 'วันนี้' : dateLabel(d.date, true) }}
        </h3>
        <ul class="m-0 grid list-none divide-y divide-border/70 p-0">
          <li v-for="r in d.list" :key="r.employee_id" class="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-3 gap-y-1 px-4 py-3 sm:grid-cols-[8rem_minmax(0,1fr)_7rem_auto] sm:px-5">
            <!-- ชื่อ + สถานะ -->
            <div class="min-w-0 sm:contents">
              <p class="m-0 truncate font-medium text-heading">{{ r.nickname }}</p>
              <div class="min-w-0 text-sm">
                <p class="m-0" :class="status(r).tone">{{ status(r).text }}</p>
                <p class="m-0 text-muted-foreground">
                  ทำได้ <span class="num text-foreground">{{ formatBaht(n(r.earned)) }}</span> จาก <span class="num">{{ formatBaht(n(r.rate)) }}</span>
                </p>
                <p v-if="r.override_reason" class="m-0 truncate text-[13px] text-muted-foreground" :title="r.override_reason">เหตุผล: {{ r.override_reason }}</p>
              </div>
            </div>
            <!-- ยอดเติม -->
            <p class="m-0 text-right sm:order-none">
              <template v-if="n(r.topup)"><span class="text-sm text-muted-foreground">เติม </span><span class="num font-semibold text-heading">{{ formatBaht(n(r.topup)) }}</span></template>
              <span v-else class="text-sm text-muted-foreground">ไม่เติม</span>
            </p>
            <!-- ให้/ไม่ให้ -->
            <div class="col-span-2 flex justify-end sm:col-span-1">
              <Button v-if="!r.qualified" size="sm" variant="outline" @click="override(r, true)">ให้ประกัน</Button>
              <Button v-else size="sm" variant="ghost" class="text-danger-ink hover:bg-danger-soft hover:text-danger-ink" @click="override(r, false)">ไม่ให้</Button>
            </div>
          </li>
        </ul>
      </div>
    </section>

    <Dialog v-model:open="rateDialog">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>ยอดประกันมือของ {{ rateEmp?.nickname }}</DialogTitle>
          <DialogDescription>การเปลี่ยนยอดต้องยืนยันตัวตนด้วยแอป Authenticator</DialogDescription>
        </DialogHeader>
        <form class="grid gap-4" @submit.prevent="saveRate">
          <TextField v-model="rateForm.amount" type="number" inputmode="numeric" label="ยอดประกันต่อวัน" hint="ใส่ 0 เพื่อเลิกประกัน" suffix="บาท" />
          <TextField v-model="rateForm.from" type="date" label="มีผลตั้งแต่" :min="today" />
          <TextField v-model="rateForm.reason" label="เหตุผล" hint="อย่างน้อย 3 ตัวอักษร" />
          <DialogFooter class="gap-2">
            <Button type="button" variant="outline" @click="rateDialog = false">ยกเลิก</Button>
            <Button type="submit" :disabled="saving || rateForm.reason.trim().length < 3">{{ saving ? 'กำลังบันทึก…' : 'บันทึกยอด' }}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  </div>
</template>
