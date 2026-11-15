<script setup lang="ts">
// ตารางเข้างานรายเดือน (OWNER) — แถว = พนักงาน, คอลัมน์ = วัน, ช่อง = เวลาเช็คชื่อเข้างาน (เข้าระบบครั้งแรกของวัน)
// ย้ายมาจากหน้า /attendance เดิม · ใช้ในหน้า ข้อมูลหมอ (/reports/therapists) แท็บ "ตารางเข้างาน"
import { bangkokTime, bangkokToday, formatBaht, type AttendanceRow } from '@ifeew/shared'

const props = defineProps<{ month: string; branchId: string | null }>()
const supabase = useSupabaseClient()
const { company } = useAccess()

const today = bangkokToday()
const rows = ref<AttendanceRow[]>([])
const employees = ref<Array<{ id: string; nickname: string }>>([])
const loading = ref(false)
const error = ref<string | null>(null)

// วันของเดือน (เดือนนี้ = ถึงวันนี้)
const days = computed(() => {
  const [y, m] = props.month.split('-').map(Number) as [number, number]
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate()
  const out: Array<{ date: string; day: number; weekday: string; weekend: boolean }> = []
  for (let d = 1; d <= last; d++) {
    const date = `${props.month}-${String(d).padStart(2, '0')}`
    if (date > today) break
    const dow = new Date(Date.UTC(y, m - 1, d)).getUTCDay()
    out.push({ date, day: d, weekday: ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'][dow]!, weekend: dow === 0 || dow === 6 })
  }
  return out
})

async function load() {
  if (!company.value || !days.value.length) {
    rows.value = []
    return
  }
  loading.value = true
  try {
    const [r, e] = await Promise.all([
      must(supabase.rpc('attendance_report', {
        p_company_id: company.value.company_id, p_branch_id: props.branchId,
        p_from: days.value[0]!.date, p_to: days.value[days.value.length - 1]!.date,
      })),
      supabase.from('employees').select('id, nickname').eq('company_id', company.value.company_id).eq('status', 'ACTIVE').order('nickname'),
    ])
    rows.value = (r ?? []) as unknown as AttendanceRow[]
    employees.value = e.data ?? []
    error.value = null
  } catch (err) {
    error.value = errorText(err, 'โหลดข้อมูลการเข้างานไม่สำเร็จ')
  } finally {
    loading.value = false
  }
}
watch([() => props.month, () => props.branchId, () => company.value?.company_id], load, { immediate: true })

// ดัชนี: พนักงาน → วันที่ → แถว (เฉพาะวันที่เช็คชื่อจริง)
const byEmp = computed(() => {
  const m = new Map<string, Map<string, AttendanceRow>>()
  for (const r of rows.value) {
    if (!r.clock_in_at) continue
    if (!m.has(r.employee_id)) m.set(r.employee_id, new Map())
    m.get(r.employee_id)!.set(r.business_date, r)
  }
  return m
})
// พนักงานที่แสดง: พนักงานที่ยังทำงาน + คนที่มีประวัติเข้างานในเดือนนี้
const people = computed(() => {
  const list = new Map(employees.value.map((e) => [e.id, e.nickname]))
  for (const r of rows.value) if (r.clock_in_at && !list.has(r.employee_id)) list.set(r.employee_id, r.nickname)
  return [...list.entries()].map(([id, nickname]) => ({ id, nickname, count: byEmp.value.get(id)?.size ?? 0 }))
})
const cellTitle = (r: AttendanceRow) =>
  `${r.nickname} ${r.business_date} เข้างาน ${bangkokTime(r.clock_in_at!)} น.${Number(r.topup) ? ` ประกันมือเติม ${formatBaht(Number(r.topup))}` : ''}`
</script>

<template>
  <div class="grid gap-3">
    <Alert v-if="error" variant="destructive"><AlertDescription>{{ error }}</AlertDescription></Alert>
    <LoadingBar v-if="loading" />

    <p v-if="!days.length" class="m-0 rounded-xl border border-dashed border-input px-4 py-10 text-center text-muted-foreground">ยังไม่ถึงเดือนนี้</p>
    <div v-else class="overflow-x-auto rounded-xl border border-border bg-card shadow-soft">
      <table class="w-max min-w-full border-collapse text-sm">
        <thead>
          <tr class="border-b border-border">
            <th scope="col" class="sticky left-0 z-10 bg-card px-4 py-2 text-left font-medium text-muted-foreground">หมอ</th>
            <th scope="col" class="px-3 py-2 text-right font-medium text-muted-foreground">มา</th>
            <th
              v-for="d in days"
              :key="d.date"
              scope="col"
              class="min-w-12 px-1 py-2 text-center font-normal"
              :class="[d.weekend ? 'bg-muted/60' : '', d.date === today ? 'text-primary' : 'text-muted-foreground']"
            >
              <span class="block text-[13px]">{{ d.weekday }}</span>
              <span class="num block font-medium" :class="d.date === today ? 'text-primary' : 'text-heading'">{{ d.day }}</span>
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="p in people" :key="p.id" class="border-b border-border last:border-0">
            <th scope="row" class="sticky left-0 z-10 bg-card px-4 py-2 text-left font-medium whitespace-nowrap text-heading">{{ p.nickname }}</th>
            <td class="num px-3 py-2 text-right font-semibold text-heading">{{ p.count }}</td>
            <td v-for="d in days" :key="d.date" class="px-1 py-1.5 text-center" :class="d.weekend ? 'bg-muted/60' : ''">
              <span
                v-if="byEmp.get(p.id)?.get(d.date)"
                class="num inline-block rounded-md bg-success-soft px-1.5 py-0.5 text-[13px] font-medium text-success-ink"
                :title="cellTitle(byEmp.get(p.id)!.get(d.date)!)"
              >{{ bangkokTime(byEmp.get(p.id)!.get(d.date)!.clock_in_at!) }}</span>
              <span v-else class="text-muted-soft" aria-label="ไม่ได้มา">–</span>
            </td>
          </tr>
          <tr v-if="!people.length">
            <td :colspan="days.length + 2" class="px-4 py-8 text-center text-muted-foreground">ยังไม่มีพนักงาน</td>
          </tr>
        </tbody>
      </table>
    </div>
    <p class="m-0 text-sm text-muted-foreground">ช่องสีเขียวคือเวลาเช็คชื่อเข้างาน วางเมาส์บนเวลาเพื่อดูยอดประกันมือของวันนั้น</p>
  </div>
</template>
