<script setup lang="ts">
// กะ POS ของสาขา: ยอดปิดกะ ผลต่างเงินสด และการตรวจของเจ้าของร้าน (อนุมัติ/ปฏิเสธพร้อมเหตุผล)
import { addDays, bangkokTime, bangkokToday, formatBaht, type SessionRow } from '@ifeew/shared'



const { prompt } = useDialog()
const supabase = useSupabaseClient()
const { activeBranch, isOwner } = useAccess()

const from = ref(addDays(bangkokToday(), -6))
const to = ref(bangkokToday())
const rows = ref<SessionRow[]>([])
const loading = ref(false)
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)

async function load() {
  if (!activeBranch.value) return
  loading.value = true
  try {
    rows.value = (await must(supabase.rpc('pos_sessions_list', {
      p_branch_id: activeBranch.value.branch_id, p_from: from.value, p_to: to.value,
    }))) as unknown as SessionRow[]
  } catch (e) {
    message.value = { type: 'error', text: errorText(e, 'โหลดไม่สำเร็จ') }
  } finally {
    loading.value = false
  }
}
watch([from, to, () => activeBranch.value?.branch_id], load, { immediate: true })

const reviewLabels = { PENDING: 'รอตรวจ', APPROVED: 'อนุมัติแล้ว', REJECTED: 'ปฏิเสธ' } as const

async function review(r: SessionRow, approve: boolean) {
  const note = await prompt(
    approve
      ? { title: 'อนุมัติกะ', label: 'หมายเหตุ (ถ้ามี)', confirmText: 'อนุมัติ' }
      : { title: 'ปฏิเสธกะ', label: 'เหตุผล', minLength: 3, confirmText: 'ปฏิเสธ', destructive: true },
  )
  if (note === null) return
  try {
    await must(supabase.rpc('pos_review_session', { p_session_id: r.session_id, p_approve: approve, p_note: note.trim() || null }))
    message.value = { type: 'success', text: approve ? 'อนุมัติกะแล้ว' : 'ปฏิเสธกะแล้ว' }
    await load()
  } catch (e) {
    message.value = { type: 'error', text: errorText(e) }
  }
}
</script>

<template>
  <div class="max-w-5xl">
    <PageHeader title="กะและเงินสด" :description="`${activeBranch?.name ?? ''} · ยอดปิดกะ ผลต่างเงินสด และผลตรวจของเจ้าของร้าน`" />

    <div class="mb-6 grid gap-3 rounded-xl border border-border bg-card p-4 sm:grid-cols-[180px_180px]">
      <TextField v-model="from" type="date" label="ตั้งแต่" />
      <TextField v-model="to" type="date" label="ถึง" />
    </div>
    <MessageAlert :message="message" class="mb-4" @close="message = null" />
    <LoadingBar v-if="loading" class="mb-3" />
    <EmptyState v-if="!loading && !rows.length" title="ไม่มีกะในช่วงนี้" description="ลองเลือกช่วงวันที่อื่น" />

    <div class="grid gap-4">
      <SectionCard v-for="r in rows" :key="r.session_id" as="h3">
        <template #header>
          <div class="min-w-0">
            <h3 class="m-0 text-base font-semibold">
              <span class="num">{{ r.business_date }}</span> · <span class="num">{{ bangkokTime(r.opened_at) }}–{{ r.closed_at ? bangkokTime(r.closed_at) : 'ยังเปิดอยู่' }}</span>
            </h3>
            <p class="m-0 mt-0.5 text-sm text-muted-foreground">
              เปิดโดย {{ r.opened_by_name ?? '—' }}<template v-if="r.closed_by_name"> · ปิดโดย {{ r.closed_by_name }}</template>
            </p>
          </div>
        </template>
        <template #actions>
          <Badge v-if="r.review_status" dot :variant="r.review_status === 'APPROVED' ? 'success' : r.review_status === 'REJECTED' ? 'danger' : 'pending'">
            {{ reviewLabels[r.review_status] }}
          </Badge>
          <Badge v-else variant="default" dot>เปิดอยู่</Badge>
        </template>

        <dl v-if="r.expected_cash !== undefined" class="m-0 grid grid-cols-2 gap-x-6 gap-y-2 text-[15px] md:grid-cols-4">
          <div v-for="[label, v] in ([
            ['เงินเริ่มต้น', r.opening_cash], ['ขายเงินสด', r.cash_sales], ['โอน', r.transfer_sales], ['QR', r.qr_sales],
            ['ทิปเงินสด', r.cash_tips], ['เงินเข้า', r.cash_in], ['เงินออก', r.cash_out], ['คืนเงินสด', r.cash_refunds],
          ] as const)" :key="label" class="flex justify-between gap-2">
            <dt class="text-muted-foreground">{{ label }}</dt><dd class="num m-0">{{ formatBaht(Number(v)) }}</dd>
          </div>
        </dl>
        <div v-if="r.expected_cash !== undefined" class="mt-4 grid gap-2 rounded-lg bg-background/70 p-4 sm:grid-cols-3">
          <div><p class="m-0 text-sm text-muted-foreground">ควรมีในลิ้นชัก</p><p class="num m-0 text-lg font-semibold text-heading">{{ formatBaht(Number(r.expected_cash)) }}</p></div>
          <template v-if="r.actual_cash !== null">
            <div><p class="m-0 text-sm text-muted-foreground">นับได้</p><p class="num m-0 text-lg font-semibold text-heading">{{ formatBaht(Number(r.actual_cash)) }}</p></div>
            <div>
              <p class="m-0 text-sm text-muted-foreground">ผลต่าง</p>
              <p class="num m-0 text-lg font-semibold" :class="Number(r.cash_difference) === 0 ? 'text-success-ink' : 'text-danger-ink'">{{ formatBaht(Number(r.cash_difference)) }}</p>
            </div>
          </template>
        </div>
        <p v-if="r.close_note" class="m-0 mt-3 text-[15px]"><span class="text-muted-foreground">หมายเหตุปิดกะ:</span> {{ r.close_note }}</p>
        <p v-if="r.review_note" class="m-0 mt-1 text-[15px]"><span class="text-muted-foreground">ผลตรวจ:</span> {{ r.review_note }}</p>

        <template v-if="isOwner && r.review_status === 'PENDING'" #footer>
          <div class="flex flex-wrap justify-end gap-2">
            <Button size="sm" variant="ghost" class="text-danger-ink" @click="review(r, false)">ปฏิเสธ</Button>
            <Button size="sm" @click="review(r, true)">อนุมัติ</Button>
          </div>
        </template>
      </SectionCard>
    </div>
  </div>
</template>
