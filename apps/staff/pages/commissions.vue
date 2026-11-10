<script setup lang="ts">
// OWNER: ค่ามือ — สรุปรายหมอ, สร้าง/ยืนยัน/ยกเลิกรอบจ่าย, ปรับค่ามือ (+/−) พร้อมเหตุผล
import { Diff as PlusMinus } from '@lucide/vue'
import {
  adjustmentSourceLabels,
  addDays,
  bangkokToday,
  employmentTypeLabels,
  formatBaht,
  type CommissionSummary,
  type PayoutView,
} from '@ifeew/shared'


const { confirm } = useDialog()
definePageMeta({ ownerOnly: true })

const supabase = useSupabaseClient()
const { company } = useAccess()
const { run } = useStepUp()

const from = ref(`${bangkokToday().slice(0, 7)}-01`)
const to = ref(bangkokToday())
const data = ref<CommissionSummary | null>(null)
const loading = ref(false)
const saving = ref(false)
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)
const fail = (e: unknown) => (message.value = { type: 'error', text: errorText(e) })

async function load() {
  if (!company.value) return
  loading.value = true
  try {
    data.value = (await must(supabase.rpc('commission_summary', {
      p_company_id: company.value.company_id, p_branch_id: null, p_from: from.value, p_to: to.value,
    }))) as unknown as CommissionSummary
  } catch (e) {
    fail(e)
  } finally {
    loading.value = false
  }
}
watch([from, to, () => company.value?.company_id], load, { immediate: true })

const draft = computed(() => data.value?.payouts.find((p) => p.status === 'DRAFT') ?? null)
const paid = computed(() => (data.value?.payouts ?? []).filter((p) => p.status === 'PAID'))

// รอบจ่าย
const periodTo = ref(addDays(bangkokToday(), -1))
async function createPayout() {
  if (!company.value) return
  saving.value = true
  try {
    await must(supabase.rpc('create_commission_payout', { p_company_id: company.value.company_id, p_period_to: periodTo.value }))
    await load()
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}

const confirmDialog = ref(false)
const confirmForm = reactive({ method: 'BANK_TRANSFER' as 'BANK_TRANSFER' | 'CASH', reference: '', note: '' })
async function confirmPayout(p: PayoutView) {
  saving.value = true
  try {
    await run(() => must(supabase.rpc('confirm_commission_payout', {
      p_payout_id: p.payout_id, p_method: confirmForm.method,
      p_reference: confirmForm.reference.trim() || null, p_note: confirmForm.note.trim() || null,
    })))
    confirmDialog.value = false
    message.value = { type: 'success', text: `บันทึกการจ่ายค่ามือ ${formatBaht(Number(p.total))} แล้ว` }
    await load()
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}
async function cancelPayout(p: PayoutView) {
  if (!(await confirm({ title: 'ยกเลิกร่างรอบจ่ายนี้?', confirmText: 'ยกเลิกร่าง', cancelText: 'ไม่ใช่', destructive: true }))) return
  try {
    await must(supabase.rpc('cancel_commission_payout', { p_payout_id: p.payout_id }))
    await load()
  } catch (e) {
    fail(e)
  }
}

// ปรับค่ามือ
const adjDialog = ref(false)
const adjForm = reactive({ employee_id: null as string | null, amount: '' as number | string, reason: '' })
async function saveAdjustment() {
  if (!adjForm.employee_id) return
  saving.value = true
  try {
    await must(supabase.rpc('add_commission_adjustment', {
      p_employee_id: adjForm.employee_id, p_branch_id: null, p_amount: Number(adjForm.amount), p_reason: adjForm.reason.trim(),
    }))
    adjDialog.value = false
    await load()
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}
const employeeItems = ref<Array<{ value: string; title: string }>>([])
watch(() => company.value?.company_id, async (id) => {
  if (!id) return
  const { data: rows } = await supabase.from('employees').select('id, nickname, status').eq('company_id', id).neq('status', 'RESIGNED').order('nickname')
  employeeItems.value = (rows ?? []).map((r) => ({ value: r.id, title: r.nickname }))
}, { immediate: true })
</script>

<template>
  <div>
    <PageHeader title="ค่ามือหมอ" description="สรุปค่ามือรายหมอ สร้างและยืนยันรอบจ่าย และปรับค่ามือพร้อมเหตุผล">
      <template #actions>
        <Button variant="outline" @click="adjDialog = true; Object.assign(adjForm, { employee_id: null, amount: '', reason: '' })"><PlusMinus /> ปรับค่ามือ</Button>
      </template>
    </PageHeader>
    <MessageAlert :message="message" class="mb-4" @close="message = null" />

    <div class="grid gap-6">
      <!-- รอบจ่าย -->
      <SectionCard title="รอบจ่าย" :description="draft ? `ร่างรอบจ่ายถึงวันที่ ${draft.period_to}` : 'รวมค่ามือที่ถึงเกณฑ์ เงินเติมประกันมือ รายการปรับ และทิปที่ไม่ใช่เงินสดที่ยังไม่จ่าย (ยอดติดลบยกไปรอบหน้า)'" flush>
        <template v-if="draft" #actions>
          <span class="text-sm text-muted-foreground">รวม</span>
          <span class="num text-lg font-semibold text-heading">{{ formatBaht(Number(draft.total)) }}</span>
        </template>

        <template v-if="draft">
          <div class="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow class="hover:bg-transparent">
                  <TableHead>หมอ</TableHead><TableHead class="text-right">ค่ามือ</TableHead><TableHead class="text-right">ประกันมือ</TableHead>
                  <TableHead class="text-right">ปรับ</TableHead><TableHead class="text-right">ทิป (โอน/QR)</TableHead><TableHead class="text-right">สุทธิ</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                <TableRow v-for="i in draft.items" :key="i.employee_id">
                  <TableCell class="text-heading">{{ i.nickname }}</TableCell>
                  <TableCell class="num text-right">{{ formatBaht(Number(i.service_total)) }}</TableCell>
                  <TableCell class="num text-right">{{ formatBaht(Number(i.guarantee_total)) }}</TableCell>
                  <TableCell class="num text-right">{{ formatBaht(Number(i.adjustment_total)) }}</TableCell>
                  <TableCell class="num text-right">{{ formatBaht(Number(i.tip_total)) }}</TableCell>
                  <TableCell class="num text-right font-semibold text-heading">{{ formatBaht(Number(i.net_amount)) }}</TableCell>
                </TableRow>
                <TableRow v-if="!draft.items.length" class="hover:bg-transparent">
                  <TableCell colspan="6" class="py-8 text-center text-muted-foreground">ไม่มียอดที่ต้องจ่าย</TableCell>
                </TableRow>
              </TableBody>
            </Table>
          </div>
          <div class="flex justify-end gap-2 px-5 py-4">
            <Button variant="ghost" class="text-danger-ink" @click="cancelPayout(draft)">ยกเลิกร่าง</Button>
            <Button :disabled="!draft.items.length" @click="confirmDialog = true; Object.assign(confirmForm, { method: 'BANK_TRANSFER', reference: '', note: '' })">ยืนยันจ่าย</Button>
          </div>
        </template>
        <form v-else class="flex flex-wrap items-end gap-3 p-5" @submit.prevent="createPayout">
          <TextField v-model="periodTo" type="date" label="รวมยอดถึงวันที่" :max="addDays(bangkokToday(), -1)" class="w-52" />
          <Button type="submit" :disabled="saving">สร้างรอบจ่าย</Button>
        </form>

        <template v-if="paid.length" #footer>
          <p class="m-0 mb-1 font-medium text-heading">จ่ายแล้ว</p>
          <ul class="m-0 grid list-none gap-0.5 p-0">
            <li v-for="p in paid" :key="p.payout_id">
              <span class="num">{{ p.paid_at?.slice(0, 10) }}</span> · ถึง <span class="num">{{ p.period_to }}</span> · <span class="num text-heading">{{ formatBaht(Number(p.total)) }}</span> · {{ p.method === 'CASH' ? 'เงินสด' : 'โอน' }} {{ p.reference ?? '' }}
            </li>
          </ul>
        </template>
      </SectionCard>

      <!-- สรุปรายหมอ -->
      <SectionCard title="สรุปรายหมอ" flush>
        <template #actions>
          <TextField v-model="from" type="date" aria-label="ตั้งแต่" class="w-40" />
          <span class="text-muted-foreground">ถึง</span>
          <TextField v-model="to" type="date" aria-label="ถึง" class="w-40" />
        </template>
        <LoadingBar v-if="loading" />
        <div v-if="data" class="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow class="hover:bg-transparent">
                <TableHead>หมอ</TableHead><TableHead class="text-right">ค่ามือ</TableHead><TableHead class="text-right">ประกันมือ</TableHead>
                <TableHead class="text-right">ปรับ</TableHead><TableHead class="text-right">ค้างจ่าย</TableHead><TableHead class="text-right">จ่ายแล้ว</TableHead>
                <TableHead class="text-right">ทิปค้างจ่าย</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              <TableRow v-for="e in data.employees" :key="e.employee_id">
                <TableCell><span class="text-heading">{{ e.nickname }}</span> <span class="text-sm text-muted-foreground">{{ employmentTypeLabels[e.employment_type] }}</span></TableCell>
                <TableCell class="num text-right">{{ formatBaht(Number(e.service)) }}</TableCell>
                <TableCell class="num text-right">{{ formatBaht(Number(e.guarantee)) }}</TableCell>
                <TableCell class="num text-right">{{ formatBaht(Number(e.adjustments)) }}</TableCell>
                <TableCell class="num text-right font-semibold text-heading">{{ formatBaht(Number(e.unpaid)) }}</TableCell>
                <TableCell class="num text-right">{{ formatBaht(Number(e.paid)) }}</TableCell>
                <TableCell class="num text-right">{{ formatBaht(Number(e.unpaid_tips)) }}</TableCell>
              </TableRow>
              <TableRow v-if="!data.employees.length" class="hover:bg-transparent">
                <TableCell colspan="7" class="py-8 text-center text-muted-foreground">ไม่มีข้อมูลในช่วงนี้</TableCell>
              </TableRow>
            </TableBody>
          </Table>
        </div>
      </SectionCard>

      <SectionCard v-if="data?.adjustments.length" title="รายการปรับ" flush>
        <ul class="m-0 grid list-none p-0">
          <li v-for="a in data.adjustments" :key="a.adjustment_id" class="flex flex-wrap items-center justify-between gap-2 border-b border-border px-5 py-3 text-[15px] last:border-0">
            <span><span class="num">{{ a.business_date }}</span> · <span class="text-heading">{{ a.nickname }}</span> · {{ adjustmentSourceLabels[a.source] }} · {{ a.reason }}</span>
            <span class="flex items-center gap-2">
              <span class="num font-semibold text-heading">{{ formatBaht(Number(a.amount)) }}</span>
              <Badge :variant="a.status === 'PAID' ? 'success' : 'pending'">{{ a.status === 'PAID' ? 'จ่ายแล้ว' : 'รอรอบจ่าย' }}</Badge>
            </span>
          </li>
        </ul>
      </SectionCard>
    </div>

    <Dialog v-model:open="confirmDialog">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>ยืนยันจ่ายค่ามือ {{ draft ? formatBaht(Number(draft.total)) : '' }}</DialogTitle>
          <DialogDescription>ระบบจะขอรหัสจากแอป Authenticator และคำนวณยอดใหม่ก่อนบันทึก</DialogDescription>
        </DialogHeader>
        <div class="grid gap-4">
          <SegmentedControl v-model="confirmForm.method" :items="[{ value: 'BANK_TRANSFER', label: 'โอน' }, { value: 'CASH', label: 'เงินสด (ส่วนกลาง)' }]" label="วิธีจ่าย" />
          <TextField v-model="confirmForm.reference" :label="confirmForm.method === 'BANK_TRANSFER' ? 'เลขอ้างอิงการโอน' : 'เลขอ้างอิง (ถ้ามี)'" />
          <TextField v-model="confirmForm.note" label="หมายเหตุ" />
        </div>
        <DialogFooter class="gap-2">
          <Button variant="outline" @click="confirmDialog = false">ปิด</Button>
          <Button :disabled="saving || !draft" @click="draft && confirmPayout(draft)">ยืนยันจ่าย</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>

    <Dialog v-model:open="adjDialog">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>ปรับค่ามือ</DialogTitle>
          <DialogDescription>ยอดบวกเพิ่ม ยอดลบหัก รวมเข้ารอบจ่ายถัดไป</DialogDescription>
        </DialogHeader>
        <form class="grid gap-4" @submit.prevent="saveAdjustment">
          <SelectField v-model="adjForm.employee_id" :items="employeeItems" label="หมอ" placeholder="เลือกหมอ" />
          <TextField v-model="adjForm.amount" numeric="signed" label="จำนวนเงิน" hint="ใส่ค่าลบเพื่อหัก" suffix="บาท" />
          <TextField v-model="adjForm.reason" label="เหตุผล" hint="บังคับ อย่างน้อย 3 ตัวอักษร" />
          <DialogFooter class="gap-2">
            <Button type="button" variant="outline" @click="adjDialog = false">ปิด</Button>
            <Button type="submit" :disabled="saving || !adjForm.employee_id || !Number(adjForm.amount) || adjForm.reason.trim().length < 3">บันทึก</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  </div>
</template>
