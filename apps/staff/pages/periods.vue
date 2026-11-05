<script setup lang="ts">
// OWNER: งวดบัญชีรายเดือน — ล็อก (ปิดยอดทุกวันต้องอนุมัติครบ) / เปิดใหม่พร้อมเหตุผล (ยืนยันตัวตนซ้ำ)
import { type FinancialPeriodRow } from '@ifeew/shared'



const { confirm, prompt } = useDialog()
definePageMeta({ ownerOnly: true })

const supabase = useSupabaseClient()
const { company } = useAccess()
const { run } = useStepUp()
const rows = ref<FinancialPeriodRow[]>([])
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)

async function load() {
  if (!company.value) return
  try {
    rows.value = (await must(supabase.rpc('financial_periods_list', { p_company_id: company.value.company_id }))) as unknown as FinancialPeriodRow[]
  } catch (e) {
    message.value = { type: 'error', text: errorText(e) }
  }
}
watch(() => company.value?.company_id, load, { immediate: true })

const monthLabel = (d: string) => new Date(`${d}T00:00:00+07:00`).toLocaleDateString('th-TH', { month: 'long', year: 'numeric' })

async function lock(r: FinancialPeriodRow) {
  if (!company.value || !(await confirm({ title: `ล็อกงวด ${monthLabel(r.period_start)}?`, description: 'หลังล็อกจะแก้ข้อมูลการเงินของเดือนนี้ไม่ได้', confirmText: 'ล็อกงวด' }))) return
  const companyId = company.value.company_id
  try {
    await run(() => must(supabase.rpc('lock_financial_period', { p_company_id: companyId, p_month: r.period_start })))
    message.value = { type: 'success', text: `ล็อกงวด ${monthLabel(r.period_start)} แล้ว` }
    await load()
  } catch (e) {
    message.value = { type: 'error', text: errorText(e) }
  }
}

async function reopen(r: FinancialPeriodRow) {
  const reason = await prompt({ title: `เปิดงวด ${monthLabel(r.period_start)}`, label: 'เหตุผล', minLength: 3, confirmText: 'เปิดงวด' })
  if (!company.value || reason === null) return
  const companyId = company.value.company_id
  try {
    await run(() => must(supabase.rpc('reopen_financial_period', { p_company_id: companyId, p_month: r.period_start, p_reason: reason.trim() })))
    message.value = { type: 'success', text: 'เปิดงวดแล้ว' }
    await load()
  } catch (e) {
    message.value = { type: 'error', text: errorText(e) }
  }
}
</script>

<template>
  <div class="max-w-4xl">
    <PageHeader title="งวดบัญชี" description="ล็อกงวดรายเดือนเมื่อปิดยอดรายวันอนุมัติครบ หลังล็อกจะแก้ข้อมูลการเงินของเดือนนั้นไม่ได้" />
    <MessageAlert :message="message" class="mb-4" @close="message = null" />
    <SectionCard flush>
      <Table>
        <TableHeader>
          <TableRow class="hover:bg-transparent">
            <TableHead>เดือน</TableHead>
            <TableHead>สถานะ</TableHead>
            <TableHead class="text-right">ปิดยอดที่ยังไม่อนุมัติ</TableHead>
            <TableHead class="text-right"><span class="sr-only">การทำงาน</span></TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          <TableRow v-for="(r, n) in rows" :key="r.period_start">
            <TableCell class="font-medium text-heading">{{ monthLabel(r.period_start) }}</TableCell>
            <TableCell>
              <Badge :variant="r.status === 'LOCKED' ? 'default' : 'success'" dot>{{ r.status === 'LOCKED' ? 'ล็อกแล้ว' : 'เปิด' }}</Badge>
              <span v-if="r.reopen_reason && r.status === 'OPEN'" class="mt-1 block text-sm whitespace-normal text-muted-foreground">เปิดใหม่: {{ r.reopen_reason }}</span>
            </TableCell>
            <TableCell class="num text-right" :class="r.pending_closings ? 'font-medium text-pending-ink' : 'text-muted-foreground'">{{ r.pending_closings || '—' }}</TableCell>
            <TableCell class="text-right">
              <Button v-if="r.status === 'LOCKED'" size="sm" variant="ghost" @click="reopen(r)">เปิดงวด</Button>
              <Button v-else-if="n > 0" size="sm" variant="outline" :disabled="r.pending_closings > 0" @click="lock(r)">ล็อก</Button>
            </TableCell>
          </TableRow>
          <TableRow v-if="!rows.length" class="hover:bg-transparent">
            <TableCell colspan="4" class="py-8 text-center text-muted-foreground">ยังไม่มีงวดบัญชี</TableCell>
          </TableRow>
        </TableBody>
      </Table>
      <template #footer>ล็อกได้เฉพาะเดือนที่จบแล้ว และทุกวันที่มีการขายต้องปิดยอดรายวันที่อนุมัติแล้ว</template>
    </SectionCard>
  </div>
</template>
