<script setup lang="ts">
// ชำระเงิน: รวมลูกค้าที่ต้องเก็บเงินของสาขาไว้ที่เดียว (วันนี้ + ค้างชำระจากวันก่อน)
// กดเพื่อไปหน้า /checkout/[orderId] (ออก Invoice / ส่วนลด / รับเงิน) — Realtime ผ่าน usePosBoard
import { Banknote, Clock, ReceiptText, RefreshCw, Wallet } from '@lucide/vue'
import {
  formatBaht,
  formatDuration,
  formatQueueNumber,
  invoiceStatusLabels,
  queueStatusLabels,
  type FinanceBoard,
  type InvoiceStatus,
  type PosOrder,
} from '@ifeew/shared'

const supabase = useSupabaseClient()
const { activeBranch } = useAccess()
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
const filter = ref<'pending' | 'paid' | 'all'>('pending')
const pendingCount = computed(() => rows.value.filter(isPending).length)
const paidCount = computed(() => rows.value.filter((r) => r.status === 'PAID').length)
const filterItems = computed(() => [
  { value: 'pending', label: `รอชำระ (${pendingCount.value})` },
  { value: 'paid', label: `ชำระแล้ว (${paidCount.value})` },
  { value: 'all', label: 'ทั้งหมด' },
])
const order: Record<RowStatus, number> = { NOT_ISSUED: 0, DRAFT: 0, PARTIALLY_PAID: 1, ISSUED: 1, PAID: 2, VOID: 3 }
const visible = computed(() =>
  rows.value
    .filter((r) => (filter.value === 'all' ? true : filter.value === 'paid' ? r.status === 'PAID' : isPending(r)))
    .sort((a, b) => order[a.status] - order[b.status] || Number(b.fromEarlierDay) - Number(a.fromEarlierDay)),
)

const statusLabel = (s: RowStatus) => (s === 'NOT_ISSUED' ? 'ยังไม่ออกบิล' : invoiceStatusLabels[s])
const statusVariant = (s: RowStatus) => (s === 'PAID' ? 'success' : s === 'NOT_ISSUED' || s === 'DRAFT' ? 'neutral' : 'pending')

async function refresh() {
  await Promise.all([load(), loadFinance()])
}
</script>

<template>
  <div class="max-w-5xl">
    <PageHeader title="ชำระเงิน" :description="`${activeBranch?.name ?? ''} · ลูกค้าที่ต้องเก็บเงิน กดที่รายการเพื่อออกบิลและรับเงิน`">
      <template #actions>
        <Button variant="outline" size="sm" :disabled="loading" @click="refresh"><RefreshCw :class="loading ? 'animate-spin' : ''" /> โหลดใหม่</Button>
      </template>
    </PageHeader>

    <div class="mb-6 grid gap-4 sm:grid-cols-3">
      <StatCard label="รอชำระ" :value="pendingCount" :icon="Clock" hint="ราย (รวมที่ยังไม่ออกบิล)" />
      <StatCard label="ยอดค้างชำระ" :icon="Wallet">
        <span class="text-pending-ink">{{ finance ? formatBaht(Number(finance.outstanding)) : '—' }}</span>
        <template #hint>เฉพาะบิลที่ออกแล้ว</template>
      </StatCard>
      <StatCard label="ยอดขายวันนี้" :value="finance ? formatBaht(Number(finance.today_sales)) : '—'" :icon="ReceiptText" />
    </div>

    <Alert v-if="error || financeError" variant="destructive" class="mb-4"><AlertDescription>{{ error ?? financeError }}</AlertDescription></Alert>

    <div class="mb-4"><SegmentedControl v-model="filter" :items="filterItems" label="แสดง" /></div>

    <LoadingBar v-if="loading && !board" class="mb-3" />
    <EmptyState
      v-else-if="!visible.length"
      :title="filter === 'paid' ? 'ยังไม่มีรายการที่ชำระแล้ววันนี้' : 'ไม่มีลูกค้ารอชำระ'"
      description="ลูกค้าจะขึ้นที่นี่เมื่อเริ่มบริการแล้ว"
    />

    <Card v-else class="gap-0 py-0">
      <ul class="m-0 grid list-none p-0">
        <li v-for="r in visible" :key="r.orderId" class="border-b border-border last:border-0">
          <NuxtLink
            :to="`/checkout/${r.orderId}`"
            class="flex flex-wrap items-center justify-between gap-4 px-5 py-4 text-foreground no-underline transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none"
          >
            <div class="min-w-0 flex-1">
              <p class="m-0 flex flex-wrap items-center gap-2 font-medium text-heading">
                {{ r.customer }}
                <Badge :variant="statusVariant(r.status)">{{ statusLabel(r.status) }}</Badge>
                <Badge v-if="r.fromEarlierDay" variant="outline">ค้างจาก <span class="num">{{ r.invoice?.business_date }}</span></Badge>
              </p>
              <template v-if="r.order">
                <p v-for="i in r.order.items.filter((x) => x.queue_status !== 'CANCELLED')" :key="i.queue_id" class="m-0 mt-0.5 text-sm text-muted-foreground">
                  คิว <span class="num">{{ formatQueueNumber(i.queue_number) }}</span> · {{ i.service_name }} {{ formatDuration(i.duration_minutes) }}
                  · {{ queueStatusLabels[i.queue_status] }}<span v-if="i.therapist"> · {{ i.therapist.nickname }}</span>
                </p>
              </template>
              <p v-if="r.invoice?.invoice_number" class="num m-0 mt-0.5 text-sm text-muted-foreground">{{ r.invoice.invoice_number }}</p>
            </div>

            <div class="flex items-center gap-4">
              <div v-if="r.invoice" class="text-right">
                <p class="num m-0 text-lg font-semibold text-heading">{{ formatBaht(Number(r.status === 'PAID' ? r.invoice.total : r.due)) }}</p>
                <p class="m-0 text-[13px] text-muted-foreground">
                  <template v-if="r.status === 'PAID'">ชำระครบ</template>
                  <template v-else-if="r.status === 'PARTIALLY_PAID'">คงเหลือ · จ่ายแล้ว <span class="num">{{ formatBaht(Number(r.invoice.paid_amount)) }}</span></template>
                  <template v-else>ยอดที่ต้องชำระ</template>
                </p>
              </div>
              <span
                class="inline-flex h-9 shrink-0 items-center gap-1.5 rounded-lg px-3 text-sm font-medium"
                :class="r.status === 'PAID' ? 'border border-border text-heading' : 'bg-primary text-primary-foreground'"
              >
                <Banknote class="size-4" /> {{ r.status === 'PAID' ? 'ดูการชำระ' : 'ชำระเงิน' }}
              </span>
            </div>
          </NuxtLink>
        </li>
      </ul>
    </Card>
  </div>
</template>
