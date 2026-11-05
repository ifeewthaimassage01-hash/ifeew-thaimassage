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


const { prompt } = useDialog()
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
  const reason = await prompt({
    title: grant ? 'ให้ประกันมือวันนี้' : 'ไม่ให้ประกันมือวันนี้',
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
    await loadAttendance()
  } catch (e) {
    fail(e)
  }
}
const time = (iso: string | null) => (iso ? bangkokTime(iso) : '-')
</script>

<template>
  <div>
    <PageHeader title="ประกันมือและการลงเวลา" description="หมอประจำที่ลงเวลาเข้า-ออกครบกะ ได้ค่ามือไม่น้อยกว่ายอดประกันต่อวัน (ไม่นับทิป) ระบบเติมส่วนต่างอัตโนมัติ · หมอวิ่งได้ค่ามือตามงานจริง" />
    <MessageAlert :message="message" class="mb-4" @close="message = null" />

    <div class="grid gap-6">
      <SectionCard title="ประเภทหมอและยอดประกัน" :description="`${employees.length} คน`" flush>
        <div class="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow class="hover:bg-transparent">
                <TableHead>หมอ</TableHead><TableHead>ประเภท</TableHead><TableHead class="text-right">ประกันมือ/วัน</TableHead>
                <TableHead class="text-right"><span class="sr-only">การทำงาน</span></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              <TableRow v-for="e in employees" :key="e.id">
                <TableCell><span class="font-medium text-heading">{{ e.nickname }}</span> <span class="num text-sm text-muted-foreground">{{ e.employee_code }}</span></TableCell>
                <TableCell>
                  <SegmentedControl
                    :model-value="e.employment_type"
                    :items="[{ value: 'REGULAR', label: employmentTypeLabels.REGULAR }, { value: 'FREELANCE', label: employmentTypeLabels.FREELANCE }]"
                    size="sm"
                    :label="`ประเภทของ ${e.nickname}`"
                    @update:model-value="(v) => setType(e, v as EmploymentType)"
                  />
                </TableCell>
                <TableCell class="text-right">
                  <span class="num text-heading">{{ currentRate(e.id) ? formatBaht(Number(currentRate(e.id)!.daily_amount)) : '—' }}</span>
                  <span v-for="f in futureRates(e.id)" :key="f.effective_from" class="block text-sm text-muted-foreground">
                    <span class="num">{{ formatBaht(Number(f.daily_amount)) }}</span> ตั้งแต่ <span class="num">{{ f.effective_from }}</span>
                  </span>
                </TableCell>
                <TableCell class="text-right">
                  <Button v-if="e.employment_type === 'REGULAR'" size="sm" variant="outline" @click="openRate(e)">ตั้งยอด</Button>
                </TableCell>
              </TableRow>
              <TableRow v-if="!employees.length" class="hover:bg-transparent">
                <TableCell colspan="4" class="py-8 text-center text-muted-foreground">ยังไม่มีพนักงาน</TableCell>
              </TableRow>
            </TableBody>
          </Table>
        </div>
      </SectionCard>

      <SectionCard title="การลงเวลาและผลประกันรายวัน" flush>
        <div class="flex flex-wrap items-end gap-3 border-b border-border p-5">
          <SelectField v-model="branchId" :items="branchItems" label="สาขา" class="w-52" />
          <TextField v-model="from" type="date" label="ตั้งแต่" class="w-44" />
          <TextField v-model="to" type="date" label="ถึง" class="w-44" />
        </div>
        <LoadingBar v-if="loading" />
        <div class="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow class="hover:bg-transparent">
                <TableHead>วันที่</TableHead><TableHead>หมอ</TableHead><TableHead>กะ</TableHead><TableHead>ลงเวลา</TableHead>
                <TableHead class="text-right">ค่ามือ</TableHead><TableHead class="text-right">ประกัน</TableHead><TableHead>ผล</TableHead>
                <TableHead class="text-right">เติม</TableHead><TableHead class="text-right"><span class="sr-only">การทำงาน</span></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              <TableRow v-for="r in rows" :key="r.employee_id + r.business_date">
                <TableCell class="num">{{ r.business_date }}</TableCell>
                <TableCell class="text-heading">{{ r.nickname }}</TableCell>
                <TableCell class="num">{{ r.shift_start ? `${time(r.shift_start)}–${time(r.shift_end)}` : 'ไม่มีกะ' }}</TableCell>
                <TableCell class="num">{{ time(r.clock_in_at) }}–{{ time(r.clock_out_at) }}</TableCell>
                <TableCell class="num text-right">{{ formatBaht(Number(r.earned)) }}</TableCell>
                <TableCell class="num text-right">{{ Number(r.rate) ? formatBaht(Number(r.rate)) : '—' }}</TableCell>
                <TableCell>
                  <Badge v-if="Number(r.rate)" :variant="r.qualified ? 'success' : 'neutral'" dot>
                    {{ r.override_grant !== null ? (r.override_grant ? 'เจ้าของให้' : 'เจ้าของไม่ให้') : r.attended ? 'ครบกะ' : 'ไม่ครบกะ' }}
                  </Badge>
                  <span v-if="r.override_reason" class="block max-w-48 truncate text-sm text-muted-foreground" :title="r.override_reason">{{ r.override_reason }}</span>
                </TableCell>
                <TableCell class="num text-right font-semibold text-heading">{{ Number(r.topup) ? formatBaht(Number(r.topup)) : '—' }}</TableCell>
                <TableCell class="text-right">
                  <template v-if="Number(r.rate)">
                    <Button v-if="!r.qualified" size="xs" variant="outline" @click="override(r, true)">ให้</Button>
                    <Button v-else size="xs" variant="ghost" class="text-danger-ink" @click="override(r, false)">ไม่ให้</Button>
                  </template>
                </TableCell>
              </TableRow>
              <TableRow v-if="!loading && !rows.length" class="hover:bg-transparent">
                <TableCell colspan="9" class="py-8 text-center text-muted-foreground">ไม่มีข้อมูลในช่วงนี้</TableCell>
              </TableRow>
            </TableBody>
          </Table>
        </div>
      </SectionCard>
    </div>

    <Dialog v-model:open="rateDialog">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>ประกันมือ · {{ rateEmp?.nickname }}</DialogTitle>
          <DialogDescription>การเปลี่ยนยอดต้องยืนยันตัวตนด้วย Authenticator</DialogDescription>
        </DialogHeader>
        <form class="grid gap-4" @submit.prevent="saveRate">
          <TextField v-model="rateForm.amount" type="number" label="ยอดประกันต่อวัน" hint="ใส่ 0 เพื่อเลิกประกัน" suffix="บาท" />
          <TextField v-model="rateForm.from" type="date" label="มีผลตั้งแต่" :min="today" />
          <TextField v-model="rateForm.reason" label="เหตุผล" hint="บังคับ อย่างน้อย 3 ตัวอักษร" />
          <DialogFooter class="gap-2">
            <Button type="button" variant="outline" @click="rateDialog = false">ปิด</Button>
            <Button type="submit" :disabled="rateForm.reason.trim().length < 3">บันทึก</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  </div>
</template>
