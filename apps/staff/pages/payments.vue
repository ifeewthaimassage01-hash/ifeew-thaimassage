<script setup lang="ts">
// ชำระเงิน: รวมลูกค้าที่ต้องเก็บเงินของสาขาไว้ที่เดียว (วันนี้ + ค้างชำระจากวันก่อน)
// กดเพื่อไปหน้า /checkout/[orderId] (ออก Invoice / ส่วนลด / รับเงิน) — Realtime ผ่าน usePosBoard
import { Banknote, ChevronRight, CircleCheck, Clock, ReceiptText, Wallet } from '@lucide/vue'
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
const pendingCount = computed(() => rows.value.filter(isPending).length)
// ยังไม่จ่าย: ค้างจากวันก่อนขึ้นก่อน แล้วตามลำดับลูกค้า · จ่ายแล้ว: ล่าสุดก่อน
const pendingRows = computed(() =>
  rows.value.filter(isPending).sort((a, b) => Number(b.fromEarlierDay) - Number(a.fromEarlierDay)),
)
const paidRows = computed(() => rows.value.filter((r) => r.status === 'PAID').reverse())

type Item = PosOrder['items'][number]
const liveItems = (r: PayRow) => (r.order?.items ?? []).filter((i) => i.queue_status !== 'CANCELLED')
// ยอด: มีบิล = ยอดค้าง · ยังไม่ออกบิล = ราคารวมของคิว
const dueOf = (r: PayRow) => (r.due ?? liveItems(r).reduce((s, i) => s + Number(i.unit_price), 0))
const itemChip = (i: Item) =>
  i.queue_status === 'IN_SERVICE'
    ? { label: 'กำลังนวด', cls: 'bg-success-soft text-success-ink' }
    : i.queue_status === 'COMPLETED'
      ? { label: 'เสร็จแล้ว', cls: 'bg-secondary text-heading' }
      : { label: 'รอคิว', cls: 'bg-pending-soft text-pending-ink' }

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

    <LoadingBar v-if="loading && !board" class="mb-3" />
    <div v-else class="grid gap-3">
      <h2 class="m-0 text-base font-semibold">ยังไม่จ่าย <span class="num font-normal text-muted-foreground">{{ pendingRows.length }} กลุ่ม</span></h2>
      <p v-if="!pendingRows.length" class="m-0 rounded-xl border border-dashed border-input px-4 py-8 text-center text-[15px] text-muted-foreground">
        ไม่มีลูกค้ารอจ่ายเงิน — ลูกค้าจะขึ้นที่นี่เมื่อเริ่มนวดแล้ว
      </p>

      <!-- ยังไม่จ่าย: การ์ดเต็ม (หัว = ชื่อ+ยอด · กลาง = ตารางคิว · ล่าง = ปุ่มรับเงินตำแหน่งเดิมเสมอ) -->
      <article v-for="r in pendingRows" :key="r.orderId" class="overflow-hidden rounded-xl border border-border bg-card shadow-soft">
        <header class="flex items-baseline justify-between gap-3 px-4 pt-3.5 pb-2">
          <p class="m-0 min-w-0 truncate text-[15px] font-semibold text-heading">
            {{ r.customer }}
            <span v-if="liveItems(r).length" class="font-normal text-muted-foreground">· {{ liveItems(r).length }} คน</span>
          </p>
          <p class="num m-0 shrink-0 text-[15px] font-semibold text-heading">{{ formatBaht(dueOf(r)) }}</p>
        </header>
        <p v-if="r.fromEarlierDay || r.status === 'PARTIALLY_PAID'" class="m-0 flex flex-wrap gap-1.5 px-4 pb-2">
          <Badge v-if="r.fromEarlierDay" variant="outline">ค้างจาก <span class="num">{{ r.invoice?.business_date }}</span></Badge>
          <Badge v-if="r.status === 'PARTIALLY_PAID'" variant="pending" dot>
            จ่ายแล้วบางส่วน <span class="num">{{ formatBaht(Number(r.invoice?.paid_amount ?? 0)) }}</span>
          </Badge>
        </p>
        <ul v-if="liveItems(r).length" class="m-0 grid list-none px-4 pb-2">
          <li v-for="i in liveItems(r)" :key="i.queue_id" class="grid grid-cols-[3.25rem_minmax(0,1fr)_auto] items-center gap-2 border-t border-border/60 py-2 text-sm">
            <span class="num font-semibold text-heading">{{ formatQueueNumber(i.queue_number) }}</span>
            <span class="min-w-0 truncate text-foreground">
              {{ i.service_name }} {{ formatDuration(i.duration_minutes) }}<span v-if="i.therapist" class="text-muted-foreground"> · {{ i.therapist.nickname }}</span>
            </span>
            <span class="rounded-full px-2 py-0.5 text-[12px] font-medium" :class="itemChip(i).cls">{{ itemChip(i).label }}</span>
          </li>
        </ul>
        <footer class="flex items-center justify-end border-t border-border bg-muted/40 px-3 py-2">
          <Button as-child size="sm">
            <NuxtLink :to="`/checkout/${r.orderId}`"><Banknote /> รับเงิน</NuxtLink>
          </Button>
        </footer>
      </article>

      <!-- จ่ายแล้ว: แถวสั้น -->
      <div v-if="paidRows.length" class="mt-2 overflow-hidden rounded-xl border border-border bg-card">
        <p class="m-0 border-b border-border bg-muted/40 px-4 py-2 text-sm font-medium text-muted-foreground">จ่ายแล้ววันนี้ · <span class="num">{{ paidRows.length }}</span> กลุ่ม</p>
        <NuxtLink
          v-for="r in paidRows"
          :key="r.orderId"
          :to="`/checkout/${r.orderId}`"
          class="flex items-center gap-3 border-b border-border px-4 py-2.5 text-sm text-foreground no-underline last:border-0 hover:bg-muted"
        >
          <CircleCheck class="size-4 shrink-0 text-success-ink" />
          <span class="min-w-0 flex-1 truncate">
            <span class="font-medium text-heading">{{ r.customer }}</span>
            <span v-if="liveItems(r).length" class="num text-muted-foreground"> · คิว {{ liveItems(r).map((i) => formatQueueNumber(i.queue_number)).join(', ') }}</span>
          </span>
          <span class="num shrink-0 font-medium text-heading">{{ formatBaht(Number(r.invoice?.total ?? 0)) }}</span>
          <ChevronRight class="size-4 shrink-0 text-muted-soft" />
        </NuxtLink>
      </div>
    </div>
  </div>
</template>
