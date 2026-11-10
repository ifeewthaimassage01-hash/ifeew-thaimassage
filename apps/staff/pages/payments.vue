<script setup lang="ts">
// ชำระเงิน: รวมลูกค้าที่ต้องเก็บเงินของสาขาไว้ที่เดียว (วันนี้ + ค้างชำระจากวันก่อน)
// กดเพื่อไปหน้า /checkout/[orderId] (ออก Invoice / ส่วนลด / รับเงิน) — Realtime ผ่าน usePosBoard
import { Banknote, Clock, ReceiptText, Wallet } from '@lucide/vue'
import {
  formatBaht,
  formatDuration,
  formatQueueNumber,
  type FinanceBoard,
  type InvoiceStatus,
  type PosOrder,
} from '@ifeew/shared'

const supabase = useSupabaseClient()
const { activeBranch, isOwner } = useAccess()
const { board, loading, error, load } = usePosBoard()

const finance = ref<FinanceBoard | null>(null)
const financeError = ref<string | null>(null)
async function loadFinance() {
  if (!activeBranch.value) return
  const { data, error: err } = await supabase.rpc('pos_finance_board', { p_branch_id: activeBranch.value.branch_id })
  financeError.value = err ? errorText(err, 'โหลดข้อมูลการชำระไม่สำเร็จ') : null
  finance.value = (data ?? null) as unknown as FinanceBoard | null
}
// โหลดยอดใหม่ทุกครั้งที่กระดานคิวเปลี่ยน (Realtime) และสำรองทุก 30 วินาที
watch(() => [board.value, activeBranch.value?.branch_id], loadFinance, { immediate: true })
useIntervalFn(loadFinance, 30_000)

type Invoice = FinanceBoard['invoices'][number]
type RowStatus = InvoiceStatus | 'NOT_ISSUED'
interface PayRow {
  orderId: string
  customer: string
  order: PosOrder | null
  invoice: Invoice | null
  status: RowStatus
  /** ยอดที่ต้องเก็บ (มี Invoice = balance, ยังไม่ออก = ยังไม่ทราบ) */
  due: number | null
  fromEarlierDay: boolean
}

const invoiceByOrder = computed(() => {
  const m = new Map<string, Invoice>()
  for (const i of finance.value?.invoices ?? []) if (i.status !== 'VOID') m.set(i.service_order_id, i)
  return m
})

// เก็บเงินได้เมื่อเริ่มบริการแล้วอย่างน้อย 1 คิว (เหมือนปุ่ม "ชำระเงิน" ในหน้า POS)
const billable = (o: PosOrder) => o.status !== 'CANCELLED' && o.items.some((i) => ['IN_SERVICE', 'COMPLETED'].includes(i.queue_status))

const rows = computed<PayRow[]>(() => {
  const list: PayRow[] = []
  const seen = new Set<string>()
  for (const o of board.value?.orders ?? []) {
    const inv = invoiceByOrder.value.get(o.order_id) ?? null
    if (!billable(o) && !inv) continue
    seen.add(o.order_id)
    list.push({
      orderId: o.order_id,
      customer: o.customer_name ?? 'ลูกค้าทั่วไป',
      order: o,
      invoice: inv,
      status: inv ? inv.status : 'NOT_ISSUED',
      due: inv ? Number(inv.balance) : null,
      fromEarlierDay: false,
    })
  }
  // ค้างชำระจากวันก่อน (ไม่อยู่ในกระดานวันนี้)
  for (const inv of finance.value?.invoices ?? []) {
    if (seen.has(inv.service_order_id) || !['ISSUED', 'PARTIALLY_PAID'].includes(inv.status)) continue
    list.push({
      orderId: inv.service_order_id,
      customer: inv.customer_name ?? 'ลูกค้าทั่วไป',
      order: null,
      invoice: inv,
      status: inv.status,
      due: Number(inv.balance),
      fromEarlierDay: inv.business_date !== board.value?.business_date,
    })
  }
  return list
})

const isPending = (r: PayRow) => r.status !== 'PAID'
const filter = ref<'pending' | 'paid'>('pending')
const pendingCount = computed(() => rows.value.filter(isPending).length)
const paidCount = computed(() => rows.value.filter((r) => r.status === 'PAID').length)
const filterItems = computed(() => [
  { value: 'pending', label: `ยังไม่จ่าย (${pendingCount.value})` },
  { value: 'paid', label: `จ่ายแล้ว (${paidCount.value})` },
])
const order: Record<RowStatus, number> = { NOT_ISSUED: 0, DRAFT: 0, PARTIALLY_PAID: 1, ISSUED: 1, PAID: 2, VOID: 3 }
const visible = computed(() =>
  rows.value
    .filter((r) => (filter.value === 'paid' ? r.status === 'PAID' : isPending(r)))
    .sort((a, b) => order[a.status] - order[b.status] || Number(b.fromEarlierDay) - Number(a.fromEarlierDay)),
)

</script>

<template>
  <div class="mx-auto max-w-4xl">
    <PageHeader title="ชำระเงิน" description="ลูกค้าที่ใช้บริการแล้ว กด “รับเงิน” ที่ชื่อลูกค้า" />

    <!-- สรุปยอด: เห็นเฉพาะเจ้าของร้าน -->
    <div v-if="isOwner" class="mb-6 grid grid-cols-3 gap-2 sm:gap-4">
      <StatCard dense label="รอชำระ" :value="pendingCount" :icon="Clock" hint="ราย (รวมที่ยังไม่ออกบิล)" />
      <StatCard dense label="ยอดค้างชำระ" :icon="Wallet">
        <span class="text-pending-ink">{{ finance ? formatBaht(Number(finance.outstanding)) : '—' }}</span>
        <template #hint>เฉพาะบิลที่ออกแล้ว</template>
      </StatCard>
      <StatCard dense label="ยอดขายวันนี้" :value="finance ? formatBaht(Number(finance.today_sales)) : '—'" :icon="ReceiptText" />
    </div>

    <Alert v-if="error || financeError" variant="destructive" class="mb-4"><AlertDescription>{{ error ?? financeError }}</AlertDescription></Alert>

    <div class="mb-4"><SegmentedControl v-model="filter" :items="filterItems" label="แสดง" /></div>

    <LoadingBar v-if="loading && !board" class="mb-3" />
    <p v-else-if="!visible.length" class="m-0 rounded-xl border border-dashed border-input px-4 py-10 text-center text-[15px] text-muted-foreground">
      {{ filter === 'paid' ? 'วันนี้ยังไม่มีใครจ่ายเงิน' : 'ไม่มีลูกค้ารอจ่ายเงิน — ลูกค้าจะขึ้นที่นี่เมื่อเริ่มนวดแล้ว' }}
    </p>

    <ul v-else class="m-0 grid list-none gap-2 p-0">
      <li v-for="r in visible" :key="r.orderId">
        <NuxtLink
          :to="`/checkout/${r.orderId}`"
          class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border bg-card px-4 py-3.5 text-foreground no-underline transition-colors hover:border-input hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
        >
          <div class="min-w-0 flex-1">
            <p class="m-0 flex flex-wrap items-center gap-2 text-[15px] font-semibold text-heading">
              {{ r.customer }}
              <Badge v-if="r.status === 'PARTIALLY_PAID'" variant="pending" dot>จ่ายแล้วบางส่วน</Badge>
              <Badge v-if="r.fromEarlierDay" variant="outline">ค้างจาก <span class="num">{{ r.invoice?.business_date }}</span></Badge>
            </p>
            <template v-if="r.order">
              <p v-for="i in r.order.items.filter((x) => x.queue_status !== 'CANCELLED')" :key="i.queue_id" class="m-0 text-sm text-muted-foreground">
                <span class="num font-medium text-heading">คิว {{ formatQueueNumber(i.queue_number) }}</span>
                · {{ i.service_name }} {{ formatDuration(i.duration_minutes) }}<template v-if="i.therapist"> · {{ i.therapist.nickname }}</template>
              </p>
            </template>
          </div>

          <div class="flex items-center gap-3">
            <span v-if="r.invoice" class="num text-lg font-semibold text-heading">{{ formatBaht(Number(r.status === 'PAID' ? r.invoice.total : r.due)) }}</span>
            <span
              class="inline-flex h-10 shrink-0 items-center gap-1.5 rounded-lg px-4 text-[15px] font-medium"
              :class="r.status === 'PAID' ? 'border border-border text-heading' : 'bg-primary text-primary-foreground'"
            >
              <Banknote class="size-4" /> {{ r.status === 'PAID' ? 'ดูบิล' : 'รับเงิน' }}
            </span>
          </div>
        </NuxtLink>
      </li>
    </ul>
  </div>
</template>
