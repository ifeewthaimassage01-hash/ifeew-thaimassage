<script setup lang="ts">
// ปิดยอดรายวัน: พนักงานดูสรุปและส่ง (ระบบปิดกะภายในให้เอง — migration 034) → OWNER อนุมัติ (+ยอดปรับปรุง) / ปฏิเสธพร้อมเหตุผล
import { addDays, bangkokToday, formatBaht, type DailyClosingFigures, type DailyClosingRow } from '@ifeew/shared'

const supabase = useSupabaseClient()
const { activeBranch, company, isOwner } = useAccess()

const date = ref(bangkokToday())
const preview = ref<(DailyClosingFigures & { closing: { status: string; review_note: string | null } | null }) | null>(null)
const list = ref<DailyClosingRow[]>([])
const note = ref('')
const saving = ref(false)
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)
const fail = (e: unknown) => (message.value = { type: 'error', text: errorText(e) })

async function load() {
  if (!activeBranch.value || !company.value) return
  try {
    const [p, l] = await Promise.all([
      must(supabase.rpc('daily_closing_preview', { p_branch_id: activeBranch.value.branch_id, p_date: date.value })),
      must(supabase.rpc('daily_closings_list', {
        p_company_id: company.value.company_id, p_branch_id: isOwner.value ? null : activeBranch.value.branch_id,
        p_from: addDays(bangkokToday(), -30), p_to: bangkokToday(),
      })),
    ])
    preview.value = p as unknown as typeof preview.value
    list.value = l as unknown as DailyClosingRow[]
  } catch (e) {
    fail(e)
  }
}
watch([date, () => activeBranch.value?.branch_id], load, { immediate: true })

const canSubmit = computed(() =>
  !!preview.value
  && (!preview.value.closing || preview.value.closing.status === 'REJECTED'))

async function submit() {
  if (!activeBranch.value) return
  saving.value = true
  try {
    await must(supabase.rpc('submit_daily_closing', { p_branch_id: activeBranch.value.branch_id, p_date: date.value, p_note: note.value.trim() || null }))
    message.value = { type: 'success', text: 'ส่งปิดยอดแล้ว รอเจ้าของร้านตรวจ' }
    note.value = ''
    await load()
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}

const reviewDialog = ref(false)
const reviewRow = ref<DailyClosingRow | null>(null)
const reviewForm = reactive({ note: '', adjustment: '' as number | string, adjustmentNote: '' })
function openReview(r: DailyClosingRow) {
  reviewRow.value = r
  Object.assign(reviewForm, { note: '', adjustment: '', adjustmentNote: '' })
  reviewDialog.value = true
}
async function review(approve: boolean) {
  if (!reviewRow.value) return
  saving.value = true
  try {
    await must(supabase.rpc('review_daily_closing', {
      p_closing_id: reviewRow.value.closing_id, p_approve: approve, p_note: reviewForm.note.trim() || null,
      p_adjustment_amount: Number(reviewForm.adjustment) || 0, p_adjustment_note: reviewForm.adjustmentNote.trim() || null,
    }))
    reviewDialog.value = false
    await load()
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}
const statusLabels = { SUBMITTED: 'รอตรวจ', APPROVED: 'อนุมัติแล้ว', REJECTED: 'ปฏิเสธ' } as const
const lines = (f: DailyClosingFigures): Array<[string, number]> => [
  ['เงินสด', f.cash_sales], ['โอน', f.transfer_sales], ['QR', f.qr_sales], ['มัดจำที่หัก', f.deposit_applied],
  ['มัดจำที่ริบ', f.forfeited_deposits], ['คืนเงิน', -f.refunds], ['รายรับสุทธิ', f.net_revenue], ['รายจ่าย', f.expenses],
  ['ผลต่างเงินสดของกะ', f.cash_difference], ['ทิป (ไม่ใช่รายได้)', f.tips], ['ค่ามือของวัน', f.service_commission], ['ค้างชำระ', f.outstanding],
]
</script>

<template>
  <div class="max-w-5xl">
    <PageHeader title="ปิดยอดรายวัน" :description="`${activeBranch?.name ?? ''} · ตรวจยอดของวัน แล้วส่งสรุปให้เจ้าของร้านตรวจ`" />
    <MessageAlert :message="message" class="mb-4" @close="message = null" />

    <div class="grid gap-6">
      <SectionCard>
        <template #header>
          <div class="flex flex-wrap items-end gap-3">
            <TextField v-model="date" type="date" label="วันทำการ" :max="bangkokToday()" class="w-48" />
            <Badge v-if="preview?.closing" class="mb-2.5" dot
              :variant="preview.closing.status === 'APPROVED' ? 'success' : preview.closing.status === 'REJECTED' ? 'danger' : 'pending'">
              {{ statusLabels[preview.closing.status as 'SUBMITTED'] }}
            </Badge>
          </div>
        </template>

        <LoadingBar v-if="!preview" />
        <div v-else class="grid gap-5">
          <dl class="m-0 grid gap-x-8 gap-y-2 text-[15px] sm:grid-cols-2 lg:grid-cols-3">
            <div v-for="[l, v] in lines(preview)" :key="l" class="flex justify-between gap-3 border-b border-border/70 pb-2">
              <dt class="text-muted-foreground">{{ l }}</dt>
              <dd class="num m-0 font-medium" :class="l === 'รายรับสุทธิ' ? 'text-heading' : ''">{{ formatBaht(Number(v)) }}</dd>
            </div>
          </dl>

          <div v-if="preview.guarantee_topups.length" class="rounded-lg bg-background/70 p-4">
            <h3 class="m-0 mb-2 text-[15px] font-semibold">ประกันมือ (คำนวณอัตโนมัติ)</h3>
            <ul class="m-0 grid list-none gap-1 p-0 text-[15px]">
              <li v-for="g in preview.guarantee_topups" :key="g.employee_id" class="flex flex-wrap justify-between gap-2">
                <span>{{ g.nickname }} · ค่ามือ <span class="num">{{ formatBaht(Number(g.earned)) }}</span> / ประกัน <span class="num">{{ formatBaht(Number(g.rate)) }}</span></span>
                <span :class="g.qualified ? 'font-medium text-heading' : 'text-muted-foreground'">{{ g.qualified ? `เติม ${formatBaht(Number(g.topup))}` : 'ไม่ครบกะ ไม่ได้ประกัน' }}</span>
              </li>
            </ul>
          </div>

          <p v-if="preview.closing?.review_note" class="m-0 text-[15px]"><span class="text-muted-foreground">ผลตรวจ:</span> {{ preview.closing.review_note }}</p>

          <form v-if="canSubmit" class="flex flex-wrap items-end gap-3" @submit.prevent="submit">
            <TextField v-model="note" label="หมายเหตุ (ถ้ามี)" class="min-w-60 flex-1" />
            <Button type="submit" :disabled="saving">{{ saving ? 'กำลังส่ง…' : 'ส่งปิดยอด' }}</Button>
          </form>
        </div>
      </SectionCard>

      <SectionCard title="ประวัติ 30 วัน" flush>
        <EmptyState v-if="!list.length" compact title="ยังไม่มีการปิดยอดใน 30 วันที่ผ่านมา" class="m-5" />
        <ul v-else class="m-0 grid list-none p-0">
          <li v-for="r in list" :key="r.closing_id" class="flex flex-wrap items-center justify-between gap-3 border-b border-border px-5 py-3.5 last:border-0">
            <div class="min-w-0">
              <p class="m-0 font-medium text-heading">
                <span class="num">{{ r.business_date }}</span> · {{ r.branch_name }} · รายรับสุทธิ <span class="num">{{ formatBaht(Number(r.figures.net_revenue)) }}</span>
              </p>
              <p class="m-0 text-sm text-muted-foreground">
                ส่งโดย {{ r.submitted_by_name ?? '—' }}<template v-if="r.submit_note"> · {{ r.submit_note }}</template>
                <template v-if="Number(r.adjustment_amount)"> · ปรับปรุง <span class="num">{{ formatBaht(Number(r.adjustment_amount)) }}</span> ({{ r.adjustment_note }})</template>
                <template v-if="r.review_note"> · {{ r.review_note }}</template>
              </p>
            </div>
            <div class="flex items-center gap-2">
              <Badge dot :variant="r.status === 'APPROVED' ? 'success' : r.status === 'REJECTED' ? 'danger' : 'pending'">{{ statusLabels[r.status] }}</Badge>
              <Button v-if="isOwner && r.status === 'SUBMITTED'" size="sm" @click="openReview(r)">ตรวจ</Button>
            </div>
          </li>
        </ul>
      </SectionCard>
    </div>

    <Dialog v-model:open="reviewDialog">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>ตรวจปิดยอด</DialogTitle>
          <DialogDescription v-if="reviewRow">{{ reviewRow.business_date }} · {{ reviewRow.branch_name }} · รายรับสุทธิ {{ formatBaht(Number(reviewRow.figures.net_revenue)) }}</DialogDescription>
        </DialogHeader>
        <div class="grid gap-4">
          <TextField v-model="reviewForm.adjustment" type="number" label="ยอดปรับปรุง (ถ้ามี)" hint="เช่น เงินขาดให้ใส่ค่าลบ" suffix="บาท" />
          <TextField v-if="Number(reviewForm.adjustment)" v-model="reviewForm.adjustmentNote" label="เหตุผลของยอดปรับปรุง" />
          <TextareaField v-model="reviewForm.note" label="หมายเหตุ" hint="บังคับเมื่อปฏิเสธ" rows="2" />
        </div>
        <DialogFooter class="gap-2">
          <Button variant="outline" class="text-danger-ink" :disabled="saving" @click="review(false)">ปฏิเสธ</Button>
          <Button :disabled="saving" @click="review(true)">อนุมัติ</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
