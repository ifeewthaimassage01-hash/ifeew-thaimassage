<script setup lang="ts">
// OWNER: สรุปงานรายหมอ (จำนวนบริการ เวลา นอกกะ ส่งต่อ ค่ามือประมาณการ)
import { addDays, bangkokToday, formatBaht, formatDuration, type TherapistSummaryRow } from '@ifeew/shared'

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
</script>

<template>
  <div>
    <PageHeader title="สรุปงานหมอ" description="จำนวนบริการ เวลาทำงาน งานก่อนเช็คชื่อ การส่งต่อ และค่ามือประมาณการของหมอแต่ละคน" />

    <div class="mb-6 grid gap-3 rounded-xl border border-border bg-card p-4 sm:grid-cols-2 lg:grid-cols-[220px_180px_180px_auto] lg:items-end">
      <SelectField v-model="branchId" :items="branchItems" label="สาขา" />
      <TextField v-model="from" type="date" label="ตั้งแต่" />
      <TextField v-model="to" type="date" label="ถึง" />
      <Button variant="outline" class="w-fit" @click="from = addDays(bangkokToday(), -6); to = bangkokToday()">7 วันล่าสุด</Button>
    </div>

    <Alert v-if="error" variant="destructive" class="mb-4"><AlertDescription>{{ error }}</AlertDescription></Alert>
    <LoadingBar v-if="loading" class="mb-3" />

    <SectionCard flush>
      <div class="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow class="hover:bg-transparent">
              <TableHead>หมอ</TableHead>
              <TableHead class="text-right">บริการ</TableHead>
              <TableHead class="text-right">เวลาทำงาน</TableHead>
              <TableHead class="text-right">ก่อนเช็คชื่อ</TableHead>
              <TableHead class="text-right">ส่งต่อ</TableHead>
              <TableHead class="text-right">ค่ามือ (ประมาณการ)</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow v-for="r in rows" :key="r.employee_id">
              <TableCell><span class="text-heading">{{ r.nickname }}</span> <span class="text-sm text-muted-foreground">{{ r.employee_code }}</span></TableCell>
              <TableCell class="num text-right">{{ r.services }}</TableCell>
              <TableCell class="num text-right">{{ formatDuration(r.worked_minutes) }}</TableCell>
              <TableCell class="num text-right">{{ r.off_shift_count }}</TableCell>
              <TableCell class="num text-right">{{ r.handover_count }}</TableCell>
              <TableCell class="num text-right text-heading">{{ formatBaht(Number(r.fee_estimate)) }}</TableCell>
            </TableRow>
            <TableRow v-if="!rows.length" class="hover:bg-transparent">
              <TableCell colspan="6" class="py-8 text-center text-muted-foreground">ไม่มีข้อมูลในช่วงนี้</TableCell>
            </TableRow>
          </TableBody>
          <TableFooter v-if="rows.length">
            <TableRow class="hover:bg-transparent">
              <TableCell class="font-semibold text-heading">รวม</TableCell>
              <TableCell class="num text-right font-semibold text-heading">{{ totals.services }}</TableCell>
              <TableCell class="num text-right font-semibold text-heading">{{ formatDuration(totals.minutes) }}</TableCell>
              <TableCell />
              <TableCell />
              <TableCell class="num text-right font-semibold text-heading">{{ formatBaht(totals.fee) }}</TableCell>
            </TableRow>
          </TableFooter>
        </Table>
      </div>
      <template #footer>ค่ามือคิดจากราคาที่ตั้งไว้ต่อบริการ ไม่หักส่วนลด ยอดจ่ายจริงยืนยันในระบบคอมมิชชัน</template>
    </SectionCard>
  </div>
</template>
