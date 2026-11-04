<script setup lang="ts">
// OWNER: ประกันมือ — ประเภทหมอ (ประจำ/วิ่ง), ยอดประกันต่อวัน (มีประวัติ), การลงเวลา + ผลประกันรายวัน, ให้/ไม่ให้เป็นรายวัน
import {
  addDays,
  bangkokTime,
  bangkokToday,
  employmentTypeLabels,
  formatBaht,
  type AttendanceRow,
  type EmploymentType,
} from '@ifeew/shared'

definePageMeta({ ownerOnly: true })

const supabase = useSupabaseClient()
const { company, branches } = useAccess()
const { run } = useStepUp()

type Emp = { id: string; nickname: string; employee_code: string; employment_type: EmploymentType; status: string }
type Rate = { employee_id: string; daily_amount: number; effective_from: string; effective_to: string | null }

const employees = ref<Emp[]>([])
const rates = ref<Rate[]>([])
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)
const fail = (e: unknown) => (message.value = { type: 'error', text: errorText(e) })
const today = bangkokToday()

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

async function setType(emp: Emp, type: EmploymentType) {
  try {
    await must(supabase.from('employees').update({ employment_type: type }).eq('id', emp.id))
    await loadEmployees()
  } catch (e) {
    fail(e)
  }
}

const rateDialog = ref(false)
const rateEmp = ref<Emp | null>(null)
const rateForm = reactive({ amount: '' as number | string, from: today, reason: '' })
function openRate(emp: Emp) {
  rateEmp.value = emp
  Object.assign(rateForm, { amount: currentRate(emp.id)?.daily_amount ?? '', from: today, reason: '' })
  rateDialog.value = true
}
async function saveRate() {
  if (!rateEmp.value) return
  const empId = rateEmp.value.id
  try {
    await run(() => must(supabase.rpc('set_employee_guarantee', {
      p_employee_id: empId, p_daily_amount: Number(rateForm.amount) || 0, p_effective_from: rateForm.from, p_reason: rateForm.reason.trim(),
    })))
    rateDialog.value = false
    message.value = { type: 'success', text: 'บันทึกยอดประกันมือแล้ว' }
    await loadEmployees()
  } catch (e) {
    fail(e)
  }
}

// การลงเวลา + ผลประกันมือรายวัน
const branchId = ref<string | null>(null)
const from = ref(addDays(today, -6))
const to = ref(today)
const rows = ref<AttendanceRow[]>([])
const loading = ref(false)
const branchItems = computed(() => [{ value: null, title: 'ทุกสาขา' }, ...branches.value.map((b) => ({ value: b.branch_id, title: b.name }))])

async function loadAttendance() {
  if (!company.value) return
  loading.value = true
  try {
    rows.value = (await must(supabase.rpc('attendance_report', {
      p_company_id: company.value.company_id, p_branch_id: branchId.value, p_from: from.value, p_to: to.value,
    }))) as unknown as AttendanceRow[]
  } catch (e) {
    fail(e)
  } finally {
    loading.value = false
  }
}
watch([branchId, from, to, () => company.value?.company_id], loadAttendance, { immediate: true })

async function override(r: AttendanceRow, grant: boolean) {
  const reason = window.prompt(grant ? 'เหตุผลที่ให้ประกันมือวันนี้' : 'เหตุผลที่ไม่ให้ประกันมือวันนี้', '')
  if (!reason || reason.trim().length < 3) return
  try {
    await must(supabase.rpc('set_guarantee_override', {
      p_employee_id: r.employee_id, p_branch_id: r.branch_id, p_date: r.business_date, p_grant: grant, p_reason: reason.trim(),
    }))
    await loadAttendance()
  } catch (e) {
    fail(e)
  }
}
const time = (iso: string | null) => (iso ? bangkokTime(iso) : '-')
</script>

<template>
  <div class="max-w-5xl">
    <h1 class="m-0 mb-4 text-2xl font-semibold text-cocoa">ประกันมือและการลงเวลา</h1>
    <v-alert v-if="message" :type="message.type" variant="tonal" class="mb-4" closable :text="message.text" @click:close="message = null" />

    <v-card class="mb-6 p-2">
      <v-table density="comfortable">
        <thead><tr><th>หมอ</th><th>ประเภท</th><th class="text-right">ประกันมือ/วัน</th><th /></tr></thead>
        <tbody>
          <tr v-for="e in employees" :key="e.id">
            <td>{{ e.nickname }} <span class="text-xs text-light-brown">{{ e.employee_code }}</span></td>
            <td>
              <v-btn-toggle :model-value="e.employment_type" density="compact" mandatory color="primary"
                @update:model-value="(v: EmploymentType) => setType(e, v)">
                <v-btn value="REGULAR" size="small">{{ employmentTypeLabels.REGULAR }}</v-btn>
                <v-btn value="FREELANCE" size="small">{{ employmentTypeLabels.FREELANCE }}</v-btn>
              </v-btn-toggle>
            </td>
            <td class="text-right">
              {{ currentRate(e.id) ? formatBaht(Number(currentRate(e.id)!.daily_amount)) : '-' }}
              <div v-for="f in futureRates(e.id)" :key="f.effective_from" class="text-xs text-light-brown">
                {{ formatBaht(Number(f.daily_amount)) }} ตั้งแต่ {{ f.effective_from }}
              </div>
            </td>
            <td class="text-right">
              <v-btn v-if="e.employment_type === 'REGULAR'" size="small" variant="text" @click="openRate(e)">ตั้งยอด</v-btn>
            </td>
          </tr>
        </tbody>
      </v-table>
      <p class="m-0 px-3 pb-2 text-xs text-light-brown">
        หมอประจำที่ลงเวลาเข้า-ออกครบกะ ได้ค่ามือไม่น้อยกว่ายอดประกันต่อวัน (ไม่นับทิป) ระบบเติมส่วนต่างอัตโนมัติ · หมอวิ่งได้ค่ามือตามงานจริง
      </p>
    </v-card>

    <div class="mb-2 flex flex-wrap items-center gap-2">
      <v-select v-model="branchId" :items="branchItems" label="สาขา" hide-details density="compact" class="max-w-52" />
      <v-text-field v-model="from" type="date" label="ตั้งแต่" hide-details density="compact" class="max-w-44" />
      <v-text-field v-model="to" type="date" label="ถึง" hide-details density="compact" class="max-w-44" />
    </div>
    <v-progress-linear v-if="loading" indeterminate color="primary" />
    <v-card class="overflow-x-auto p-2">
      <v-table density="compact">
        <thead><tr><th>วันที่</th><th>หมอ</th><th>กะ</th><th>ลงเวลา</th><th class="text-right">ค่ามือ</th><th class="text-right">ประกัน</th><th>ผล</th><th class="text-right">เติม</th><th /></tr></thead>
        <tbody>
          <tr v-for="r in rows" :key="r.employee_id + r.business_date">
            <td>{{ r.business_date }}</td>
            <td>{{ r.nickname }}</td>
            <td>{{ r.shift_start ? `${time(r.shift_start)}–${time(r.shift_end)}` : 'ไม่มีกะ' }}</td>
            <td>{{ time(r.clock_in_at) }}–{{ time(r.clock_out_at) }}</td>
            <td class="text-right">{{ formatBaht(Number(r.earned)) }}</td>
            <td class="text-right">{{ Number(r.rate) ? formatBaht(Number(r.rate)) : '-' }}</td>
            <td>
              <v-chip v-if="Number(r.rate)" size="x-small" variant="tonal" :color="r.qualified ? 'success' : 'grey'">
                {{ r.override_grant !== null ? (r.override_grant ? 'OWNER ให้' : 'OWNER ไม่ให้') : r.attended ? 'ครบกะ' : 'ไม่ครบกะ' }}
              </v-chip>
              <div v-if="r.override_reason" class="text-xs text-light-brown">{{ r.override_reason }}</div>
            </td>
            <td class="text-right font-medium">{{ Number(r.topup) ? formatBaht(Number(r.topup)) : '-' }}</td>
            <td class="whitespace-nowrap text-right">
              <template v-if="Number(r.rate)">
                <v-btn v-if="!r.qualified" size="x-small" variant="text" @click="override(r, true)">ให้</v-btn>
                <v-btn v-else size="x-small" variant="text" color="error" @click="override(r, false)">ไม่ให้</v-btn>
              </template>
            </td>
          </tr>
          <tr v-if="!rows.length"><td colspan="9" class="text-center text-light-brown">ไม่มีข้อมูล</td></tr>
        </tbody>
      </v-table>
    </v-card>

    <v-dialog v-model="rateDialog" max-width="420">
      <v-card v-if="rateEmp" class="p-6">
        <p class="m-0 mb-3 text-lg font-medium">ประกันมือ · {{ rateEmp.nickname }}</p>
        <v-text-field v-model="rateForm.amount" type="number" label="ยอดประกันต่อวัน (บาท, 0 = เลิกประกัน)" />
        <v-text-field v-model="rateForm.from" type="date" label="มีผลตั้งแต่" :min="today" />
        <v-text-field v-model="rateForm.reason" label="เหตุผล (บังคับ)" />
        <div class="flex justify-end gap-2">
          <v-btn variant="text" @click="rateDialog = false">ปิด</v-btn>
          <v-btn color="primary" :disabled="rateForm.reason.trim().length < 3" @click="saveRate">บันทึก</v-btn>
        </div>
      </v-card>
    </v-dialog>
  </div>
</template>
