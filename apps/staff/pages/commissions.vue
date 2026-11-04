<script setup lang="ts">
// OWNER: ค่ามือ — สรุปรายหมอ, สร้าง/ยืนยัน/ยกเลิกรอบจ่าย, ปรับค่ามือ (+/−) พร้อมเหตุผล
import {
  adjustmentSourceLabels,
  addDays,
  bangkokToday,
  employmentTypeLabels,
  formatBaht,
  type CommissionSummary,
  type PayoutView,
} from '@ifeew/shared'

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
  if (!window.confirm('ยกเลิกร่างรอบจ่ายนี้?')) return
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
  <div class="max-w-5xl">
    <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
      <h1 class="m-0 text-2xl font-semibold text-cocoa">ค่ามือหมอ</h1>
      <v-btn variant="tonal" prepend-icon="mdi-plus-minus-variant" @click="adjDialog = true; Object.assign(adjForm, { employee_id: null, amount: '', reason: '' })">ปรับค่ามือ</v-btn>
    </div>
    <v-alert v-if="message" :type="message.type" variant="tonal" class="mb-4" closable :text="message.text" @click:close="message = null" />

    <!-- รอบจ่าย -->
    <v-card class="mb-4 p-4">
      <p class="m-0 mb-2 font-medium">รอบจ่าย</p>
      <template v-if="draft">
        <p class="m-0 mb-2 text-sm">ร่างรอบจ่ายถึงวันที่ {{ draft.period_to }} · รวม <b>{{ formatBaht(Number(draft.total)) }}</b></p>
        <v-table density="compact">
          <thead><tr><th>หมอ</th><th class="text-right">ค่ามือ</th><th class="text-right">ประกันมือ</th><th class="text-right">ปรับ</th><th class="text-right">ทิป (โอน/QR)</th><th class="text-right">สุทธิ</th></tr></thead>
          <tbody>
            <tr v-for="i in draft.items" :key="i.employee_id">
              <td>{{ i.nickname }}</td>
              <td class="text-right">{{ formatBaht(Number(i.service_total)) }}</td>
              <td class="text-right">{{ formatBaht(Number(i.guarantee_total)) }}</td>
              <td class="text-right">{{ formatBaht(Number(i.adjustment_total)) }}</td>
              <td class="text-right">{{ formatBaht(Number(i.tip_total)) }}</td>
              <td class="text-right font-medium">{{ formatBaht(Number(i.net_amount)) }}</td>
            </tr>
            <tr v-if="!draft.items.length"><td colspan="6" class="text-center text-light-brown">ไม่มียอดที่ต้องจ่าย</td></tr>
          </tbody>
        </v-table>
        <div class="mt-3 flex justify-end gap-2">
          <v-btn variant="text" color="error" @click="cancelPayout(draft)">ยกเลิกร่าง</v-btn>
          <v-btn color="primary" :disabled="!draft.items.length" @click="confirmDialog = true; Object.assign(confirmForm, { method: 'BANK_TRANSFER', reference: '', note: '' })">ยืนยันจ่าย</v-btn>
        </div>
      </template>
      <div v-else class="flex flex-wrap items-center gap-2">
        <v-text-field v-model="periodTo" type="date" label="รวมยอดถึงวันที่" :max="addDays(bangkokToday(), -1)" hide-details density="compact" class="max-w-52" />
        <v-btn color="primary" :loading="saving" @click="createPayout">สร้างรอบจ่าย</v-btn>
        <span class="text-xs text-light-brown">รวมค่ามือที่ถึงเกณฑ์ เงินเติมประกันมือ รายการปรับ และทิปที่ไม่ใช่เงินสดที่ยังไม่จ่าย (ยอดติดลบยกไปรอบหน้า)</span>
      </div>
      <div v-if="paid.length" class="mt-3">
        <p class="m-0 mb-1 text-sm font-medium">จ่ายแล้ว</p>
        <p v-for="p in paid" :key="p.payout_id" class="m-0 text-sm">
          {{ p.paid_at?.slice(0, 10) }} · ถึง {{ p.period_to }} · {{ formatBaht(Number(p.total)) }} · {{ p.method === 'CASH' ? 'เงินสด' : 'โอน' }} {{ p.reference ?? '' }}
        </p>
      </div>
    </v-card>

    <!-- สรุปรายหมอ -->
    <div class="mb-2 flex flex-wrap items-center gap-2">
      <v-text-field v-model="from" type="date" label="ตั้งแต่" hide-details density="compact" class="max-w-44" />
      <v-text-field v-model="to" type="date" label="ถึง" hide-details density="compact" class="max-w-44" />
    </div>
    <v-progress-linear v-if="loading" indeterminate color="primary" />
    <v-card v-if="data" class="mb-4 p-2">
      <v-table density="comfortable">
        <thead><tr><th>หมอ</th><th class="text-right">ค่ามือ</th><th class="text-right">ประกันมือ</th><th class="text-right">ปรับ</th><th class="text-right">ค้างจ่าย</th><th class="text-right">จ่ายแล้ว</th><th class="text-right">ทิปค้างจ่าย</th></tr></thead>
        <tbody>
          <tr v-for="e in data.employees" :key="e.employee_id">
            <td>{{ e.nickname }} <span class="text-xs text-light-brown">{{ employmentTypeLabels[e.employment_type] }}</span></td>
            <td class="text-right">{{ formatBaht(Number(e.service)) }}</td>
            <td class="text-right">{{ formatBaht(Number(e.guarantee)) }}</td>
            <td class="text-right">{{ formatBaht(Number(e.adjustments)) }}</td>
            <td class="text-right font-medium">{{ formatBaht(Number(e.unpaid)) }}</td>
            <td class="text-right">{{ formatBaht(Number(e.paid)) }}</td>
            <td class="text-right">{{ formatBaht(Number(e.unpaid_tips)) }}</td>
          </tr>
          <tr v-if="!data.employees.length"><td colspan="7" class="text-center text-light-brown">ไม่มีข้อมูลในช่วงนี้</td></tr>
        </tbody>
      </v-table>
    </v-card>

    <v-card v-if="data?.adjustments.length" class="p-4">
      <p class="m-0 mb-2 font-medium">รายการปรับ</p>
      <p v-for="a in data.adjustments" :key="a.adjustment_id" class="m-0 text-sm">
        {{ a.business_date }} · {{ a.nickname }} · <b>{{ formatBaht(Number(a.amount)) }}</b> · {{ adjustmentSourceLabels[a.source] }} · {{ a.reason }}
        <v-chip size="x-small" variant="tonal">{{ a.status === 'PAID' ? 'จ่ายแล้ว' : 'รอรอบจ่าย' }}</v-chip>
      </p>
    </v-card>

    <v-dialog v-model="confirmDialog" max-width="440">
      <v-card v-if="draft" class="p-6">
        <p class="m-0 mb-3 text-lg font-medium">ยืนยันจ่ายค่ามือ {{ formatBaht(Number(draft.total)) }}</p>
        <v-btn-toggle v-model="confirmForm.method" mandatory color="primary" class="mb-3">
          <v-btn value="BANK_TRANSFER">โอน</v-btn><v-btn value="CASH">เงินสด (ส่วนกลาง)</v-btn>
        </v-btn-toggle>
        <v-text-field v-model="confirmForm.reference" :label="confirmForm.method === 'BANK_TRANSFER' ? 'เลขอ้างอิงการโอน' : 'เลขอ้างอิง (ถ้ามี)'" />
        <v-text-field v-model="confirmForm.note" label="หมายเหตุ" />
        <p class="m-0 mb-3 text-xs text-light-brown">ระบบจะขอรหัสจากแอป Authenticator และคำนวณยอดใหม่ก่อนบันทึก</p>
        <div class="flex justify-end gap-2">
          <v-btn variant="text" @click="confirmDialog = false">ปิด</v-btn>
          <v-btn color="primary" :loading="saving" @click="confirmPayout(draft)">ยืนยันจ่าย</v-btn>
        </div>
      </v-card>
    </v-dialog>

    <v-dialog v-model="adjDialog" max-width="420">
      <v-card class="p-6">
        <p class="m-0 mb-3 text-lg font-medium">ปรับค่ามือ</p>
        <v-select v-model="adjForm.employee_id" :items="employeeItems" label="หมอ" />
        <v-text-field v-model="adjForm.amount" type="number" label="จำนวนเงิน (ลบ = หัก)" />
        <v-text-field v-model="adjForm.reason" label="เหตุผล (บังคับ)" />
        <div class="flex justify-end gap-2">
          <v-btn variant="text" @click="adjDialog = false">ปิด</v-btn>
          <v-btn color="primary" :loading="saving" :disabled="!adjForm.employee_id || !Number(adjForm.amount) || adjForm.reason.trim().length < 3" @click="saveAdjustment">บันทึก</v-btn>
        </div>
      </v-card>
    </v-dialog>
  </div>
</template>
