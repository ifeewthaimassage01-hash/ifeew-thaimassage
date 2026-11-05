<script setup lang="ts">
// คิววันนี้ของสาขา (Realtime): เรียกคิว/เลือกหมอ, หมอรับคิว, เริ่ม-จบบริการ, ยกเลิก
// แท็บ "คิวของฉัน" สำหรับหมอที่ login ด้วย PIN บนเครื่องสาขา
// Phase 6: เปลี่ยนหมอระหว่างบริการ, ต่อเวลา, ย้อนเริ่ม/จบ (15 นาที), หมอกดคิวด้วย PIN โดยไม่ต้อง logout หน้าร้าน
import { Clock, KeyRound, RefreshCw, UserRound } from '@lucide/vue'
import {
  QUEUE_OVERDUE_MINUTES,
  QUEUE_UNDO_MINUTES,
  bangkokTime,
  formatBaht,
  newIdempotencyKey,
  formatDuration,
  formatQueueNumber,
  orderChannelLabels,
  queueStatusLabels,
  reasonSchema,
  type PosOrder,
  type PosOrderItem,
  type PosTherapist,
  type QueueStatus,
  type Database,
} from '@ifeew/shared'


const { confirm } = useDialog()
type CatalogRow = Database['public']['Views']['v_public_branch_services']['Row']

type Row = PosOrderItem & { order: PosOrder }

const supabase = useSupabaseClient()
const user = useSupabaseUser()
const { activeBranch } = useAccess()
const { board, loading, error, load } = usePosBoard()

const tab = ref<'all' | 'mine'>('all')
const message = ref<{ type: 'success' | 'error' | 'info'; text: string } | null>(null)
const busy = ref<string | null>(null)
const ok = (text: string) => (message.value = { type: 'success', text })
const fail = (e: unknown) => (message.value = { type: 'error', text: errorText(e) })

const now = ref(Date.now())
useIntervalFn(() => (now.value = Date.now()), 30_000)

const rows = computed<Row[]>(() =>
  (board.value?.orders ?? []).flatMap((o) => o.items.map((i) => ({ ...i, order: o }))),
)
const mine = computed(() =>
  rows.value.filter((r) => r.therapist?.user_id === user.value?.sub && !['COMPLETED', 'CANCELLED'].includes(r.queue_status)),
)
const columns: Array<{ key: string; title: string; statuses: QueueStatus[] }> = [
  { key: 'waiting', title: 'รอเรียก', statuses: ['WAITING'] },
  { key: 'called', title: 'เรียกแล้ว / หมอรับแล้ว', statuses: ['CALLED', 'ACCEPTED'] },
  { key: 'service', title: 'กำลังให้บริการ', statuses: ['IN_SERVICE'] },
  { key: 'done', title: 'เสร็จ / ยกเลิก', statuses: ['COMPLETED', 'CANCELLED'] },
]
const byColumn = (statuses: QueueStatus[]) =>
  rows.value
    .filter((r) => statuses.includes(r.queue_status))
    .sort((a, b) =>
      statuses.includes('COMPLETED') ? b.queue_number - a.queue_number : a.queue_number - b.queue_number,
    )

// สีของสถานะคิว (Badge variant ตาม DESIGN.md)
const statusVariant = (s: QueueStatus) =>
  (({ WAITING: 'pending', CALLED: 'default', ACCEPTED: 'default', IN_SERVICE: 'success', COMPLETED: 'neutral', CANCELLED: 'danger' }) as const)[s]

function minutesLeft(r: Row): number | null {
  if (r.queue_status !== 'IN_SERVICE' || !r.started_at) return null
  return Math.round((new Date(r.started_at).getTime() + r.duration_minutes * 60_000 - now.value) / 60_000)
}

const isOverdue = (r: Row) => (minutesLeft(r) ?? 0) < -QUEUE_OVERDUE_MINUTES
const withinUndo = (iso: string | null) => !!iso && now.value - new Date(iso).getTime() < QUEUE_UNDO_MINUTES * 60_000
const queueNo = (id: string | null) => {
  const r = rows.value.find((x) => x.queue_id === id)
  return r ? formatQueueNumber(r.queue_number) : ''
}
const extendItems = computed(() =>
  catalog.value.map((c) => ({ value: c.option_id, title: c.name + ' ' + formatDuration(c.duration_minutes) + ' · ' + formatBaht(Number(c.price)) })),
)

async function act(r: Row, fn: () => PromiseLike<{ data: unknown; error: unknown }>, done: string) {
  busy.value = r.queue_id
  try {
    await must(fn())
    ok(done)
    await load()
  } catch (e) {
    fail(e)
  } finally {
    busy.value = null
  }
}

const accept = (r: Row) =>
  act(r, () => supabase.rpc('queue_accept', { p_queue_id: r.queue_id }), `รับคิว ${formatQueueNumber(r.queue_number)} แล้ว`)
const start = (r: Row) =>
  act(r, () => supabase.rpc('queue_start', { p_queue_id: r.queue_id }), `เริ่มบริการคิว ${formatQueueNumber(r.queue_number)}`)
async function complete(r: Row) {
  if (!(await confirm({ title: `จบบริการคิว ${formatQueueNumber(r.queue_number)}?`, description: r.service_name, confirmText: 'จบบริการ' }))) return
  act(r, () => supabase.rpc('queue_complete', { p_queue_id: r.queue_id }), `จบบริการคิว ${formatQueueNumber(r.queue_number)} แล้ว`)
}

// ---------------------------------------------------------------------------
// เรียกคิว / เปลี่ยนหมอ
// ---------------------------------------------------------------------------
const callDialog = ref(false)
const callRow = ref<Row | null>(null)
const callReason = ref('')
const offShift = ref<{ therapist: PosTherapist; text: string } | null>(null)

function openCall(r: Row) {
  callRow.value = r
  callReason.value = ''
  offShift.value = null
  callDialog.value = true
}

const therapists = computed(() => board.value?.therapists ?? [])

async function pick(t: PosTherapist, confirmOffShift = false) {
  const r = callRow.value
  if (!r) return
  const changing = !!r.therapist
  if (changing && !reasonSchema.safeParse(callReason.value).success) {
    message.value = { type: 'error', text: 'กรุณาระบุเหตุผลที่เปลี่ยนหมอ' }
    return
  }
  busy.value = r.queue_id
  try {
    const { error: err } = r.queue_status === 'IN_SERVICE'
      ? await supabase.rpc('queue_handover', {
          p_queue_id: r.queue_id,
          p_employee_id: t.employee_id,
          p_reason: callReason.value.trim(),
          p_confirm_off_shift: confirmOffShift,
        })
      : await supabase.rpc('queue_call', {
          p_queue_id: r.queue_id,
          p_employee_id: t.employee_id,
          p_confirm_off_shift: confirmOffShift,
          p_reason: changing ? callReason.value.trim() : null,
        })
    if (err) {
      if ((err as { hint?: string }).hint === 'OFF_SHIFT') {
        offShift.value = { therapist: t, text: err.message }
        return
      }
      throw err
    }
    callDialog.value = false
    ok(`เรียกคิว ${formatQueueNumber(r.queue_number)} ให้${t.nickname}แล้ว`)
    await load()
  } catch (e) {
    fail(e)
  } finally {
    busy.value = null
  }
}

// ---------------------------------------------------------------------------
// ยกเลิกคิว
// ---------------------------------------------------------------------------
const cancelDialog = ref(false)
const cancelRow = ref<Row | null>(null)
const cancelReason = ref('')

function openCancel(r: Row) {
  cancelRow.value = r
  cancelReason.value = ''
  cancelDialog.value = true
}

async function submitCancel() {
  const r = cancelRow.value
  const reason = reasonSchema.safeParse(cancelReason.value)
  if (!r || !reason.success) {
    message.value = { type: 'error', text: 'กรุณาระบุเหตุผล' }
    return
  }
  await act(r, () => supabase.rpc('queue_cancel', { p_queue_id: r.queue_id, p_reason: reason.data }),
    `ยกเลิกคิว ${formatQueueNumber(r.queue_number)} แล้ว`)
  cancelDialog.value = false
}

// ---------------------------------------------------------------------------
// ย้อนเริ่ม / ย้อนจบ (ภายใน 15 นาที ต้องมีเหตุผล)
// ---------------------------------------------------------------------------
const undoDialog = ref(false)
const undoRow = ref<Row | null>(null)
const undoReason = ref('')
const undoKind = computed(() => (undoRow.value?.queue_status === 'COMPLETED' ? 'complete' : 'start'))

function openUndo(r: Row) {
  undoRow.value = r
  undoReason.value = ''
  undoDialog.value = true
}

async function submitUndo() {
  const r = undoRow.value
  const reason = reasonSchema.safeParse(undoReason.value)
  if (!r || !reason.success) {
    message.value = { type: 'error', text: 'กรุณาระบุเหตุผล' }
    return
  }
  const fn = undoKind.value === 'complete' ? 'queue_undo_complete' : 'queue_undo_start'
  await act(r, () => supabase.rpc(fn, { p_queue_id: r.queue_id, p_reason: reason.data }),
    'ย้อนคิว ' + formatQueueNumber(r.queue_number) + ' แล้ว')
  undoDialog.value = false
}

// ---------------------------------------------------------------------------
// ต่อเวลา (หมอคนเดิม เริ่มต่อทันทีเมื่อจบรายการเดิม)
// ---------------------------------------------------------------------------
const extendDialog = ref(false)
const extendRow = ref<Row | null>(null)
const extendOption = ref<string | null>(null)
const catalog = ref<CatalogRow[]>([])
let extendKey = newIdempotencyKey()

async function openExtend(r: Row) {
  extendRow.value = r
  extendOption.value = null
  extendKey = newIdempotencyKey()
  extendDialog.value = true
  const { data } = await supabase
    .from('v_public_branch_services')
    .select('*')
    .eq('branch_id', activeBranch.value!.branch_id)
    .order('category_sort_order').order('sort_order').order('duration_minutes')
  catalog.value = (data ?? []) as CatalogRow[]
}

async function submitExtend() {
  const r = extendRow.value
  const option = extendOption.value
  if (!r || !option) return
  await act(r, () => supabase.rpc('queue_extend', { p_queue_id: r.queue_id, p_option_id: option, p_idempotency_key: extendKey }),
    'ต่อเวลาคิว ' + formatQueueNumber(r.queue_number) + ' แล้ว')
  extendDialog.value = false
}

// ---------------------------------------------------------------------------
// หมอกดคิวของตัวเองด้วย PIN (ไม่ต้อง logout คนหน้าร้าน) — ใช้ได้บนเครื่องที่ผูกกับสาขาเท่านั้น
// ---------------------------------------------------------------------------
const device = useStaffDevice()
const { call: callEdge } = useEdgeFunction()
const pinDialog = ref(false)
const pinRow = ref<Row | null>(null)
const pinError = ref<string | null>(null)
const pinLoading = ref(false)
const pinPad = ref<{ reset: () => void } | null>(null)
const pinActionLabel = { ACCEPT: 'รับ', START: 'เริ่ม', COMPLETE: 'จบ' } as const
const pinAction = (r: Row): keyof typeof pinActionLabel =>
  r.queue_status === 'CALLED' ? 'ACCEPT' : r.queue_status === 'ACCEPTED' ? 'START' : 'COMPLETE'

function openPin(r: Row) {
  pinRow.value = r
  pinError.value = null
  pinDialog.value = true
}

async function submitPin(pin: string) {
  const r = pinRow.value
  if (!r?.therapist || !device.token.value) return
  pinLoading.value = true
  pinError.value = null
  try {
    await callEdge('queue-pin-action', {
      device_token: device.token.value,
      user_id: r.therapist.user_id,
      pin,
      queue_id: r.queue_id,
      action: pinAction(r),
    })
    pinDialog.value = false
    ok(r.therapist.nickname + ' ' + pinActionLabel[pinAction(r)] + 'คิว ' + formatQueueNumber(r.queue_number) + ' แล้ว')
    await load()
  } catch (e) {
    const data = (e as { data?: { error_code?: string; message?: string } }).data
    pinError.value = data?.message ?? device.errorMessage(e).message
    pinPad.value?.reset()
  } finally {
    pinLoading.value = false
  }
}

// ---------------------------------------------------------------------------
// ลงเวลาเข้า/ออกงานด้วย PIN (ใช้ตัดสินประกันมือของหมอประจำ)
// ---------------------------------------------------------------------------
type AttendanceToday = { employee_id: string; user_id: string; nickname: string; clock_in_at: string | null; clock_out_at: string | null }
const clockDialog = ref(false)
const clockList = ref<AttendanceToday[]>([])
const clockWho = ref<AttendanceToday | null>(null)
const clockError = ref<string | null>(null)
const clockLoading = ref(false)
const clockPad = ref<{ reset: () => void } | null>(null)

async function openClock() {
  clockWho.value = null
  clockError.value = null
  clockDialog.value = true
  if (!activeBranch.value) return
  const { data } = await supabase.rpc('branch_attendance_today', { p_branch_id: activeBranch.value.branch_id })
  clockList.value = (data ?? []) as unknown as AttendanceToday[]
}

async function submitClock(pin: string) {
  const who = clockWho.value
  if (!who || !device.token.value) return
  const action = who.clock_in_at ? 'CLOCK_OUT' : 'CLOCK_IN'
  clockLoading.value = true
  clockError.value = null
  try {
    await callEdge('queue-pin-action', { device_token: device.token.value, user_id: who.user_id, pin, action })
    clockDialog.value = false
    ok(`${who.nickname} ลงเวลา${action === 'CLOCK_IN' ? 'เข้า' : 'ออก'}งานแล้ว`)
  } catch (e) {
    const data = (e as { data?: { message?: string } }).data
    clockError.value = data?.message ?? device.errorMessage(e).message
    clockPad.value?.reset()
  } finally {
    clockLoading.value = false
  }
}
</script>

<template>
  <div>
    <PageHeader title="คิววันนี้" :description="`${activeBranch?.name ?? ''} · เรียกคิว มอบหมายหมอ เริ่มและจบบริการ`">
      <template #actions>
        <Button v-if="device.token.value" variant="outline" @click="openClock"><Clock /> ลงเวลา</Button>
        <Button variant="ghost" size="icon" aria-label="โหลดคิวใหม่" @click="load"><RefreshCw :class="loading ? 'animate-spin' : ''" /></Button>
      </template>
    </PageHeader>

    <SegmentedControl
      v-model="tab"
      :items="[{ value: 'all', label: 'คิวทั้งหมด' }, { value: 'mine', label: mine.length ? `คิวของฉัน (${mine.length})` : 'คิวของฉัน' }]"
      label="มุมมองคิว"
      class="mb-4"
    />

    <MessageAlert :message="message" class="mb-4" @close="message = null" />
    <Alert v-if="error" variant="destructive" class="mb-4"><AlertDescription>{{ error }}</AlertDescription></Alert>
    <LoadingBar v-if="loading" class="mb-3" />

    <!-- คิวของฉัน (หมอ) -->
    <template v-if="tab === 'mine'">
      <EmptyState v-if="!mine.length" title="ยังไม่มีคิวที่เรียกให้คุณ" description="เมื่อพนักงานเรียกคิวให้คุณ คิวจะขึ้นที่นี่" />
      <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        <Card v-for="r in mine" :key="r.queue_id" class="gap-0 py-0">
          <div class="flex items-start justify-between gap-3 p-6">
            <div>
              <p class="num m-0 text-5xl leading-none font-semibold text-heading">{{ formatQueueNumber(r.queue_number) }}</p>
              <p class="m-0 mt-3 text-xl text-heading">{{ r.service_name }} {{ formatDuration(r.duration_minutes) }}</p>
              <p class="m-0 text-muted-foreground">{{ r.order.customer_name ?? 'ลูกค้าทั่วไป' }}</p>
            </div>
            <Badge :variant="statusVariant(r.queue_status)" dot>{{ queueStatusLabels[r.queue_status] }}</Badge>
          </div>
          <p v-if="minutesLeft(r) !== null" class="m-0 px-6 pb-4 text-lg">เหลือประมาณ <span class="num font-semibold text-heading">{{ Math.max(0, minutesLeft(r)!) }}</span> นาที</p>
          <div class="border-t border-border p-4">
            <Button v-if="r.queue_status === 'CALLED'" size="lg" class="h-14 w-full text-lg" :disabled="busy === r.queue_id" @click="accept(r)">รับคิว</Button>
            <Button v-if="r.queue_status === 'ACCEPTED'" size="lg" class="h-14 w-full text-lg" :disabled="busy === r.queue_id" @click="start(r)">เริ่มบริการ</Button>
            <Button v-if="r.queue_status === 'IN_SERVICE'" size="lg" class="h-14 w-full text-lg" :disabled="busy === r.queue_id" @click="complete(r)">จบบริการ</Button>
          </div>
        </Card>
      </div>
    </template>

    <!-- คิวทั้งหมด -->
    <div v-else class="grid items-start gap-4 lg:grid-cols-2 2xl:grid-cols-[repeat(4,minmax(0,1fr))_240px]">
      <section v-for="c in columns" :key="c.key" class="grid gap-3 rounded-xl bg-secondary/35 p-3" :aria-labelledby="`col-${c.key}`">
        <h2 :id="`col-${c.key}`" class="m-0 flex items-center justify-between px-1 text-[15px] font-semibold">
          {{ c.title }} <span class="num rounded-md bg-card px-2 text-sm font-medium text-muted-foreground">{{ byColumn(c.statuses).length }}</span>
        </h2>
        <p v-if="!byColumn(c.statuses).length" class="m-0 rounded-lg border border-dashed border-input px-3 py-4 text-center text-sm text-muted-foreground">ไม่มีคิว</p>
        <article
          v-for="r in byColumn(c.statuses)"
          :key="r.queue_id"
          class="grid gap-1 rounded-lg border bg-card p-4"
          :class="[isOverdue(r) ? 'border-danger ring-1 ring-danger/40' : 'border-border', c.key === 'done' ? 'opacity-70' : '']"
        >
          <div class="flex items-start justify-between gap-2">
            <p class="num m-0 text-3xl leading-none font-semibold text-heading">{{ formatQueueNumber(r.queue_number) }}</p>
            <Badge :variant="statusVariant(r.queue_status)" dot>{{ queueStatusLabels[r.queue_status] }}</Badge>
          </div>
          <p class="m-0 mt-1 font-medium text-heading">{{ r.service_name }} {{ formatDuration(r.duration_minutes) }}</p>
          <p v-if="r.follows_queue_id" class="m-0 text-sm text-muted-foreground">ต่อเวลาจากคิว <span class="num">{{ queueNo(r.follows_queue_id) }}</span></p>
          <p v-if="isOverdue(r)" class="m-0 text-sm font-medium text-danger-ink">เลยเวลาจบ {{ -(minutesLeft(r) ?? 0) }} นาที</p>
          <p class="m-0 text-sm text-muted-foreground">
            {{ r.order.customer_name ?? 'ลูกค้าทั่วไป' }} · {{ orderChannelLabels[r.order.channel] }}
            <span v-if="r.order.booking_code"> · <span class="num">{{ r.order.booking_code }}</span></span>
          </p>
          <p class="m-0 text-sm">
            <template v-if="r.started_at">เริ่ม <span class="num">{{ bangkokTime(r.started_at) }}</span></template>
            <template v-else>นัด <span class="num">{{ bangkokTime(r.planned_starts_at) }}</span></template>
            <template v-if="minutesLeft(r) !== null"> · เหลือ <span class="num font-medium text-heading">{{ Math.max(0, minutesLeft(r)!) }}</span> นาที</template>
          </p>
          <p v-if="r.therapist" class="m-0 flex flex-wrap items-center gap-1.5 text-sm">
            <UserRound class="size-4 text-muted-soft" aria-hidden="true" /><span class="text-heading">{{ r.therapist.nickname }}</span>
            <Badge v-if="r.therapist.off_shift_confirmed" variant="outline">นอกกะ</Badge>
            <span v-if="r.handovers.length" class="text-muted-foreground">(ต่อจาก {{ r.handovers.map((h) => h.nickname).join(', ') }})</span>
          </p>
          <p v-if="r.cancel_reason && r.queue_status === 'CANCELLED'" class="m-0 text-sm text-danger-ink">{{ r.cancel_reason }}</p>

          <div v-if="c.key !== 'done'" class="mt-2 grid gap-2">
            <Button v-if="r.queue_status === 'WAITING'" size="sm" :disabled="busy === r.queue_id" @click="openCall(r)">เรียกคิว</Button>
            <Button v-if="r.queue_status === 'CALLED'" size="sm" :disabled="busy === r.queue_id" @click="accept(r)">หมอรับคิว</Button>
            <Button v-if="r.queue_status === 'ACCEPTED'" size="sm" :disabled="busy === r.queue_id" @click="start(r)">เริ่มบริการ</Button>
            <Button v-if="r.queue_status === 'IN_SERVICE'" size="sm" :disabled="busy === r.queue_id" @click="complete(r)">จบบริการ</Button>
            <div class="flex flex-wrap gap-1">
              <Button v-if="['CALLED', 'ACCEPTED'].includes(r.queue_status)" size="xs" variant="ghost" @click="openCall(r)">เปลี่ยนหมอ</Button>
              <template v-if="r.queue_status === 'IN_SERVICE'">
                <Button size="xs" variant="ghost" @click="openExtend(r)">ต่อเวลา</Button>
                <Button size="xs" variant="ghost" @click="openCall(r)">เปลี่ยนหมอ</Button>
                <Button v-if="withinUndo(r.started_at)" size="xs" variant="ghost" @click="openUndo(r)">ย้อนเริ่ม</Button>
              </template>
              <Button v-if="device.token.value && r.therapist && ['CALLED', 'ACCEPTED', 'IN_SERVICE'].includes(r.queue_status)" size="xs" variant="outline" @click="openPin(r)">
                <KeyRound /> หมอกด PIN
              </Button>
              <Button v-if="['WAITING', 'CALLED', 'ACCEPTED'].includes(r.queue_status)" size="xs" variant="ghost" class="text-danger-ink" @click="openCancel(r)">ยกเลิก</Button>
            </div>
          </div>
          <div v-else-if="r.queue_status === 'COMPLETED' && withinUndo(r.completed_at)" class="mt-1">
            <Button size="xs" variant="ghost" @click="openUndo(r)">ย้อนจบบริการ</Button>
          </div>
        </article>
      </section>

      <section class="grid gap-3 rounded-xl border border-border bg-card p-3 lg:col-span-2 2xl:col-span-1" aria-labelledby="col-therapists">
        <h2 id="col-therapists" class="m-0 flex items-center justify-between px-1 text-[15px] font-semibold">
          หมอ <span class="num rounded-md bg-muted px-2 text-sm font-medium text-muted-foreground">{{ therapists.length }}</span>
        </h2>
        <ul class="m-0 grid list-none gap-0.5 p-0 lg:grid-cols-2 2xl:grid-cols-1">
          <li v-for="t in therapists" :key="t.employee_id" class="flex items-center gap-2.5 rounded-md px-2 py-1.5">
            <span class="size-2.5 shrink-0 rounded-full" :class="t.busy_queue_number ? 'bg-brand-accent' : t.on_shift ? 'bg-success' : 'border border-muted-soft'" aria-hidden="true" />
            <span class="min-w-0">
              <span class="block truncate text-[15px] text-heading">{{ t.nickname }}</span>
              <span class="block text-[13px] text-muted-foreground">{{ t.busy_queue_number ? `คิว ${formatQueueNumber(t.busy_queue_number)}` : t.on_shift ? 'ว่าง' : 'ไม่มีกะ' }}</span>
            </span>
          </li>
          <li v-if="!therapists.length" class="px-2 py-2 text-sm text-muted-foreground">ไม่มีพนักงานในสาขานี้</li>
        </ul>
      </section>
    </div>

    <!-- เลือกหมอ -->
    <Dialog v-model:open="callDialog">
      <DialogContent class="max-h-[90dvh] grid-rows-[auto_minmax(0,1fr)_auto] sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>
            {{ callRow?.queue_status === 'IN_SERVICE' ? 'เปลี่ยนหมอระหว่างบริการ' : callRow?.therapist ? 'เปลี่ยนหมอ' : 'เรียกคิว' }}
            <span class="num">{{ callRow ? formatQueueNumber(callRow.queue_number) : '' }}</span>
          </DialogTitle>
          <DialogDescription>
            {{ callRow?.service_name }} {{ callRow ? formatDuration(callRow.duration_minutes) : '' }}
            <template v-if="callRow?.queue_status === 'IN_SERVICE'"> · ค่ามือแบ่งตามเวลาที่หมอแต่ละคนทำจริง</template>
          </DialogDescription>
        </DialogHeader>
        <div v-if="callRow" class="-mx-6 grid content-start gap-3 overflow-y-auto px-6">
          <TextareaField v-if="callRow.therapist" v-model="callReason" label="เหตุผลที่เปลี่ยนหมอ" hint="บังคับ" rows="2" />
          <Alert v-if="offShift" variant="warning">
            <AlertDescription class="grid gap-2">
              <span>{{ offShift.text }}</span>
              <span class="flex justify-end gap-2">
                <Button size="sm" variant="ghost" @click="offShift = null">ไม่ใช่</Button>
                <Button size="sm" @click="pick(offShift.therapist, true)">ยืนยันมอบหมาย</Button>
              </span>
            </AlertDescription>
          </Alert>
          <div class="grid gap-2 sm:grid-cols-2">
            <button
              v-for="t in therapists"
              :key="t.employee_id"
              type="button"
              :disabled="!!t.busy_queue_number || t.employee_id === callRow.therapist?.employee_id || busy === callRow.queue_id"
              class="flex items-center gap-3 rounded-lg border border-border bg-card px-4 py-3 text-left transition-colors hover:border-primary hover:bg-secondary/40 focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:border-border disabled:hover:bg-card"
              @click="pick(t)"
            >
              <span class="size-2.5 shrink-0 rounded-full" :class="t.busy_queue_number ? 'bg-brand-accent' : t.on_shift ? 'bg-success' : 'border border-muted-soft'" aria-hidden="true" />
              <span>
                <span class="block font-medium text-heading">{{ t.nickname }}</span>
                <span class="block text-sm text-muted-foreground">{{ t.busy_queue_number ? `มีคิว ${formatQueueNumber(t.busy_queue_number)}` : t.on_shift ? 'ว่าง · มีกะ' : 'ว่าง · ไม่มีกะ' }}</span>
              </span>
            </button>
          </div>
          <p v-if="!therapists.length" class="m-0 text-sm text-muted-foreground">ไม่มีพนักงานในสาขานี้</p>
        </div>
        <DialogFooter><Button variant="outline" @click="callDialog = false">ปิด</Button></DialogFooter>
      </DialogContent>
    </Dialog>

    <!-- ย้อนเริ่ม/จบ -->
    <Dialog v-model:open="undoDialog">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{{ undoKind === 'complete' ? 'ย้อนจบบริการ' : 'ย้อนเริ่มบริการ' }} คิว <span class="num">{{ undoRow ? formatQueueNumber(undoRow.queue_number) : '' }}</span></DialogTitle>
          <DialogDescription>
            {{ undoKind === 'complete' ? 'คิวจะกลับมาเป็นกำลังให้บริการ และจองเตียงกลับ' : 'คิวจะกลับเป็นหมอรับแล้ว (ยังไม่เริ่ม)' }} · ทำได้ภายใน {{ QUEUE_UNDO_MINUTES }} นาที
          </DialogDescription>
        </DialogHeader>
        <form class="grid gap-4" @submit.prevent="submitUndo">
          <TextareaField v-model="undoReason" label="เหตุผล" hint="บังคับ" rows="2" />
          <DialogFooter class="gap-2">
            <Button type="button" variant="outline" @click="undoDialog = false">ปิด</Button>
            <Button type="submit" :disabled="!undoRow || busy === undoRow.queue_id">ยืนยันย้อน</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>

    <!-- ต่อเวลา -->
    <Dialog v-model:open="extendDialog">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>ต่อเวลาคิว <span class="num">{{ extendRow ? formatQueueNumber(extendRow.queue_number) : '' }}</span></DialogTitle>
          <DialogDescription>{{ extendRow?.therapist?.nickname }} ให้บริการต่อทันทีเมื่อ {{ extendRow?.service_name }} จบ</DialogDescription>
        </DialogHeader>
        <form class="grid gap-4" @submit.prevent="submitExtend">
          <SelectField v-model="extendOption" label="บริการที่ต่อ" :items="extendItems" placeholder="เลือกบริการ" />
          <DialogFooter class="gap-2">
            <Button type="button" variant="outline" @click="extendDialog = false">ปิด</Button>
            <Button type="submit" :disabled="!extendOption || !extendRow || busy === extendRow.queue_id">ต่อเวลา</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>

    <!-- ลงเวลา -->
    <Dialog v-model:open="clockDialog">
      <DialogContent class="sm:max-w-md">
        <template v-if="!clockWho">
          <DialogHeader>
            <DialogTitle>ลงเวลาเข้า/ออกงาน</DialogTitle>
            <DialogDescription>เลือกชื่อของคุณ แล้วกด PIN</DialogDescription>
          </DialogHeader>
          <div class="grid gap-2">
            <button
              v-for="a in clockList"
              :key="a.employee_id"
              type="button"
              :disabled="!!a.clock_out_at"
              class="flex items-center justify-between gap-3 rounded-lg border border-border bg-card px-4 py-3 text-left transition-colors hover:bg-muted/50 focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none disabled:cursor-not-allowed disabled:opacity-50"
              @click="clockWho = a; clockError = null"
            >
              <span class="font-medium text-heading">{{ a.nickname }}</span>
              <span class="text-sm text-muted-foreground">
                {{ a.clock_out_at ? `ออกแล้ว ${bangkokTime(a.clock_out_at)}` : a.clock_in_at ? `เข้า ${bangkokTime(a.clock_in_at)} · แตะเพื่อลงเวลาออก` : 'แตะเพื่อลงเวลาเข้า' }}
              </span>
            </button>
          </div>
          <DialogFooter><Button variant="outline" @click="clockDialog = false">ปิด</Button></DialogFooter>
        </template>
        <template v-else>
          <DialogHeader class="items-center text-center">
            <DialogTitle>{{ clockWho.nickname }}</DialogTitle>
            <DialogDescription>ลงเวลา{{ clockWho.clock_in_at ? 'ออก' : 'เข้า' }}งาน · กด PIN ของคุณ</DialogDescription>
          </DialogHeader>
          <PinPad ref="clockPad" :loading="clockLoading" :error="clockError" @submit="submitClock" />
          <div class="flex justify-center"><Button variant="ghost" @click="clockWho = null">ย้อนกลับ</Button></div>
        </template>
      </DialogContent>
    </Dialog>

    <!-- หมอกด PIN -->
    <Dialog v-model:open="pinDialog">
      <DialogContent class="sm:max-w-sm">
        <DialogHeader class="items-center text-center">
          <DialogTitle>{{ pinRow?.therapist?.nickname }}</DialogTitle>
          <DialogDescription v-if="pinRow">{{ pinActionLabel[pinAction(pinRow)] }}คิว {{ formatQueueNumber(pinRow.queue_number) }} · กด PIN ของคุณ</DialogDescription>
        </DialogHeader>
        <PinPad v-if="pinRow?.therapist" ref="pinPad" :loading="pinLoading" :error="pinError" @submit="submitPin" />
        <div class="flex justify-center"><Button variant="ghost" @click="pinDialog = false">ยกเลิก</Button></div>
      </DialogContent>
    </Dialog>

    <!-- ยกเลิก -->
    <Dialog v-model:open="cancelDialog">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>ยกเลิกคิว <span class="num">{{ cancelRow ? formatQueueNumber(cancelRow.queue_number) : '' }}</span></DialogTitle>
          <DialogDescription>{{ cancelRow?.service_name }}</DialogDescription>
        </DialogHeader>
        <form class="grid gap-4" @submit.prevent="submitCancel">
          <TextareaField v-model="cancelReason" label="เหตุผล" hint="บังคับ" rows="2" />
          <DialogFooter class="gap-2">
            <Button type="button" variant="outline" @click="cancelDialog = false">ปิด</Button>
            <Button type="submit" variant="destructive" :disabled="!cancelRow || busy === cancelRow.queue_id">ยืนยันยกเลิก</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  </div>
</template>
