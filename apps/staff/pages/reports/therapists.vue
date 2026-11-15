<script setup lang="ts">
// OWNER: ค่าแรงและงานรายหมอ (ค่ามือ + ทิป, จำนวนบริการ เวลา นอกกะ ส่งต่อ) · แตะชื่อหมอเพื่อดูรายวัน
import { ChevronRight } from '@lucide/vue'
import {
  bangkokToday,
  formatBaht,
  formatDuration,
  type TherapistPayDay,
  type TherapistSummaryRow,
} from '@ifeew/shared'

definePageMeta({ ownerOnly: true })

const supabase = useSupabaseClient()
const { company, branches } = useAccess()

const branchId = ref<string | null>(null)
const from = ref(`${bangkokToday().slice(0, 7)}-01`)
const to = ref(bangkokToday())
const rows = ref<TherapistSummaryRow[]>([])
const loading = ref(false)
const error = ref<string | null>(null)

const branchItems = computed(() => [{ value: null, title: 'ทุกสาขา' }, ...branches.value.map((b) => ({ value: b.branch_id, title: b.name }))])
const totals = computed(() => ({
  services: rows.value.reduce((s, r) => s + r.services, 0),
  minutes: rows.value.reduce((s, r) => s + r.worked_minutes, 0),
  fee: rows.value.reduce((s, r) => s + Number(r.fee_estimate), 0),
  tips: rows.value.reduce((s, r) => s + Number(r.tips ?? 0), 0),
  pay: rows.value.reduce((s, r) => s + Number(r.pay_total ?? r.fee_estimate), 0),
}))

async function load() {
  if (!company.value) return
  loading.value = true
  try {
    rows.value = (await must(supabase.rpc('therapist_work_summary', {
      p_company_id: company.value.company_id, p_branch_id: branchId.value, p_from: from.value, p_to: to.value,
    }))) as unknown as TherapistSummaryRow[]
    error.value = null
  } catch (e) {
    error.value = errorText(e, 'โหลดไม่สำเร็จ')
  } finally {
    loading.value = false
  }
}

watch([branchId, from, to, () => company.value?.company_id], load, { immediate: true })

// รายวันของหมอที่เลือก
const picked = ref<TherapistSummaryRow | null>(null)
const days = ref<TherapistPayDay[]>([])
const daysLoading = ref(false)
const daysError = ref<string | null>(null)
async function openDays(r: TherapistSummaryRow) {
  if (!company.value) return
  picked.value = r
  days.value = []
  daysError.value = null
  daysLoading.value = true
  try {
    days.value = (await must(supabase.rpc('therapist_pay_daily', {
      p_company_id: company.value.company_id, p_branch_id: branchId.value, p_employee_id: r.employee_id, p_from: from.value, p_to: to.value,
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
    <PageHeader title="ค่าแรงหมอ" description="ค่ามือ ทิป และงานของหมอแต่ละคน · แตะชื่อหมอเพื่อดูรายวัน" />

    <FilterPanel label="ตัวกรองค่าแรงหมอ">
      <FilterRow label="สาขา">
        <SelectField v-model="branchId" :items="branchItems" aria-label="สาขา" class="w-full sm:w-64" />
      </FilterRow>
      <FilterRow label="ช่วงวันที่">
        <DateRangeFilter v-model:from="from" v-model:to="to" :presets="['today', 'week', 'month', 'last-month']" />
      </FilterRow>
    </FilterPanel>

    <Alert v-if="error" variant="destructive" class="mb-4"><AlertDescription>{{ error }}</AlertDescription></Alert>
    <LoadingBar v-if="loading" class="mb-3" />

    <SectionCard flush>
      <div class="overflow-x-auto">
        <Table stack>
          <TableHeader>
            <TableRow class="hover:bg-transparent">
              <TableHead>หมอ</TableHead>
              <TableHead class="text-right">บริการ</TableHead>
              <TableHead class="text-right">เวลาทำงาน</TableHead>
              <TableHead class="text-right">ค่ามือ</TableHead>
              <TableHead class="text-right">ทิป</TableHead>
              <TableHead class="text-right">ค่าแรงรวม</TableHead>
              <TableHead class="text-right">ก่อนเช็คชื่อ</TableHead>
              <TableHead class="text-right">ส่งต่อ</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow v-for="r in rows" :key="r.employee_id" class="cursor-pointer" @click="openDays(r)">
              <TableCell>
                <button type="button" class="inline-flex items-center gap-1 text-left" :aria-label="`ดูค่าแรงรายวันของ ${r.nickname}`" @click.stop="openDays(r)">
                  <span class="text-heading">{{ r.nickname }}</span>
                  <span class="text-sm text-muted-foreground">{{ r.employee_code }}</span>
                  <ChevronRight class="size-4 text-muted-foreground" aria-hidden="true" />
                </button>
              </TableCell>
              <TableCell class="num text-right">{{ r.services }}</TableCell>
              <TableCell class="num text-right">{{ formatDuration(r.worked_minutes) }}</TableCell>
              <TableCell class="num text-right">{{ formatBaht(Number(r.fee_estimate)) }}</TableCell>
              <TableCell class="num text-right">{{ formatBaht(Number(r.tips ?? 0)) }}</TableCell>
              <TableCell class="num text-right font-semibold text-heading">{{ formatBaht(Number(r.pay_total ?? r.fee_estimate)) }}</TableCell>
              <TableCell class="num text-right">{{ r.off_shift_count }}</TableCell>
              <TableCell class="num text-right">{{ r.handover_count }}</TableCell>
            </TableRow>
            <TableRow v-if="!rows.length" class="hover:bg-transparent">
              <TableCell colspan="8" class="py-8 text-center text-muted-foreground">ไม่มีข้อมูลในช่วงนี้</TableCell>
            </TableRow>
          </TableBody>
          <TableFooter v-if="rows.length">
            <TableRow class="hover:bg-transparent">
              <TableCell class="font-semibold text-heading">รวม</TableCell>
              <TableCell class="num text-right font-semibold text-heading">{{ totals.services }}</TableCell>
              <TableCell class="num text-right font-semibold text-heading">{{ formatDuration(totals.minutes) }}</TableCell>
              <TableCell class="num text-right font-semibold text-heading">{{ formatBaht(totals.fee) }}</TableCell>
              <TableCell class="num text-right font-semibold text-heading">{{ formatBaht(totals.tips) }}</TableCell>
              <TableCell class="num text-right font-semibold text-heading">{{ formatBaht(totals.pay) }}</TableCell>
              <TableCell />
              <TableCell />
            </TableRow>
          </TableFooter>
        </Table>
      </div>
      <template #footer>ค่ามือคิดจากค่ามือที่ตั้งไว้ต่อบริการ (งานที่ส่งต่อแบ่งตามเวลาที่ทำจริง) · ทิปรวมทุกช่องทาง ไม่นับรายการที่ยกเลิก</template>
    </SectionCard>

    <Dialog :open="!!picked" @update:open="(v) => !v && (picked = null)">
      <DialogContent class="max-h-[85dvh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>ค่าแรง {{ picked?.nickname }}</DialogTitle>
          <DialogDescription>
            {{ dayLabel(from) }} – {{ dayLabel(to) }} · รวม <span class="num font-semibold text-heading">{{ formatBaht(Number(picked?.pay_total ?? picked?.fee_estimate ?? 0)) }}</span>
          </DialogDescription>
        </DialogHeader>
        <LoadingBar v-if="daysLoading" />
        <p v-if="daysError" class="m-0 text-sm text-danger-ink">{{ daysError }}</p>
        <p v-else-if="!daysLoading && !days.length" class="m-0 py-6 text-center text-muted-foreground">ไม่มีงานในช่วงนี้</p>
        <div v-else class="grid gap-3">
          <section v-for="d in days" :key="d.date" class="rounded-lg border border-border">
            <header class="flex items-baseline justify-between gap-3 border-b border-border px-4 py-2.5">
              <span class="font-medium text-heading">{{ dayLabel(d.date) }}</span>
              <span class="num font-semibold text-heading">{{ formatBaht(Number(d.total)) }}</span>
            </header>
            <ul class="m-0 grid list-none gap-1 px-4 py-2.5 text-sm">
              <li v-for="(j, i) in d.jobs" :key="i" class="flex justify-between gap-3">
                <span><span class="num text-muted-foreground">{{ j.time ?? '–' }}</span> {{ j.service_name }} {{ formatDuration(j.minutes) }}<span v-if="j.handover" class="text-muted-foreground"> · ส่งต่อ</span></span>
                <span class="num shrink-0">{{ formatBaht(Number(j.fee)) }}</span>
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
</template>
