<script setup lang="ts">
// คิววันนี้ของสาขา (Realtime): เรียกคิว/เลือกหมอ, หมอรับคิว, เริ่ม-จบบริการ, ยกเลิก
// แท็บ "คิวของฉัน" สำหรับหมอที่ login ด้วย PIN บนเครื่องสาขา
// Phase 6: เปลี่ยนหมอระหว่างบริการ, ต่อเวลา, ย้อนเริ่ม/จบ (15 นาที), หมอกดคิวด้วย PIN โดยไม่ต้อง logout หน้าร้าน
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

const statusColor = (s: QueueStatus) =>
  ({ WAITING: 'warning', CALLED: 'info', ACCEPTED: 'primary', IN_SERVICE: 'success', COMPLETED: 'grey', CANCELLED: 'error' })[s]

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
function complete(r: Row) {
  if (!window.confirm(`จบบริการคิว ${formatQueueNumber(r.queue_number)} (${r.service_name})?`)) return
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
    <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
      <h1 class="m-0 text-2xl font-semibold text-cocoa">คิววันนี้ · {{ activeBranch?.name }}</h1>
      <div class="flex items-center gap-2">
        <v-btn-toggle v-model="tab" mandatory color="primary" density="comfortable">
          <v-btn value="all">คิวทั้งหมด</v-btn>
          <v-btn value="mine">คิวของฉัน <v-badge v-if="mine.length" :content="mine.length" color="error" inline /></v-btn>
        </v-btn-toggle>
        <v-btn v-if="device.token.value" variant="tonal" prepend-icon="mdi-clock-check-outline" @click="openClock">ลงเวลา</v-btn>
        <v-btn icon="mdi-refresh" variant="text" aria-label="โหลดใหม่" @click="load" />
      </div>
    </div>

    <v-alert v-if="message" :type="message.type" variant="tonal" class="mb-4" closable :text="message.text" @click:close="message = null" />
    <v-alert v-if="error" type="error" variant="tonal" class="mb-4" :text="error" />
    <v-progress-linear v-if="loading" indeterminate color="primary" />

    <!-- คิวของฉัน (หมอ) -->
    <template v-if="tab === 'mine'">
      <p v-if="!mine.length" class="text-light-brown">ยังไม่มีคิวที่เรียกให้คุณ</p>
      <div class="grid gap-4 md:grid-cols-2">
        <v-card v-for="r in mine" :key="r.queue_id" class="p-6">
          <div class="flex items-start justify-between gap-3">
            <div>
              <p class="m-0 text-5xl font-semibold text-cocoa">{{ formatQueueNumber(r.queue_number) }}</p>
              <p class="m-0 mt-2 text-xl">{{ r.service_name }} {{ formatDuration(r.duration_minutes) }}</p>
              <p class="m-0 text-light-brown">{{ r.order.customer_name ?? 'ลูกค้าทั่วไป' }}</p>
            </div>
            <v-chip :color="statusColor(r.queue_status)" variant="tonal">{{ queueStatusLabels[r.queue_status] }}</v-chip>
          </div>
          <p v-if="minutesLeft(r) !== null" class="m-0 mt-3 text-lg">
            เหลือประมาณ {{ Math.max(0, minutesLeft(r)!) }} นาที
          </p>
          <div class="mt-4 grid gap-2">
            <v-btn v-if="r.queue_status === 'CALLED'" color="primary" size="x-large" :loading="busy === r.queue_id" @click="accept(r)">รับคิว</v-btn>
            <v-btn v-if="r.queue_status === 'ACCEPTED'" color="primary" size="x-large" :loading="busy === r.queue_id" @click="start(r)">เริ่มบริการ</v-btn>
            <v-btn v-if="r.queue_status === 'IN_SERVICE'" color="success" size="x-large" :loading="busy === r.queue_id" @click="complete(r)">จบบริการ</v-btn>
          </div>
        </v-card>
      </div>
    </template>

    <!-- คิวทั้งหมด -->
    <div v-else class="grid gap-4 lg:grid-cols-[1fr_1fr_1fr_1fr_240px]">
      <section v-for="c in columns" :key="c.key">
        <p class="m-0 mb-2 font-medium">{{ c.title }} ({{ byColumn(c.statuses).length }})</p>
        <div class="grid gap-3">
          <v-card v-for="r in byColumn(c.statuses)" :key="r.queue_id" class="p-4"
            :class="{ 'opacity-60': c.key === 'done', 'border-2 border-red-400': isOverdue(r) }">
            <div class="flex items-start justify-between gap-2">
              <p class="m-0 text-3xl font-semibold text-cocoa">{{ formatQueueNumber(r.queue_number) }}</p>
              <v-chip :color="statusColor(r.queue_status)" variant="tonal" size="small">{{ queueStatusLabels[r.queue_status] }}</v-chip>
            </div>
            <p class="m-0 mt-1 font-medium">{{ r.service_name }} {{ formatDuration(r.duration_minutes) }}</p>
            <p v-if="r.follows_queue_id" class="m-0 text-xs text-light-brown">ต่อเวลาจากคิว {{ queueNo(r.follows_queue_id) }}</p>
            <p v-if="isOverdue(r)" class="m-0 text-sm font-medium text-red-700">เลยเวลาจบ {{ -(minutesLeft(r) ?? 0) }} นาที</p>
            <p class="m-0 text-sm text-light-brown">
              {{ r.order.customer_name ?? 'ลูกค้าทั่วไป' }} · {{ orderChannelLabels[r.order.channel] }}
              <span v-if="r.order.booking_code"> · {{ r.order.booking_code }}</span>
            </p>
            <p class="m-0 text-sm">
              <template v-if="r.started_at">เริ่ม {{ bangkokTime(r.started_at) }}</template>
              <template v-else>นัด {{ bangkokTime(r.planned_starts_at) }}</template>
              <template v-if="minutesLeft(r) !== null"> · เหลือ {{ Math.max(0, minutesLeft(r)!) }} นาที</template>
            </p>
            <p v-if="r.therapist" class="m-0 mt-1 text-sm">
              <v-icon icon="mdi-account-outline" size="16" /> {{ r.therapist.nickname }}
              <v-chip v-if="r.therapist.off_shift_confirmed" size="x-small" variant="outlined">นอกกะ</v-chip>
              <span v-if="r.handovers.length" class="text-xs text-light-brown">
                (ต่อจาก {{ r.handovers.map((h) => h.nickname).join(', ') }})
              </span>
            </p>
            <p v-if="r.cancel_reason && r.queue_status === 'CANCELLED'" class="m-0 text-sm text-red-700">{{ r.cancel_reason }}</p>

            <div v-if="c.key !== 'done'" class="mt-2 flex flex-wrap gap-1">
              <v-btn v-if="r.queue_status === 'WAITING'" size="small" color="primary" :loading="busy === r.queue_id" @click="openCall(r)">เรียกคิว</v-btn>
              <v-btn v-if="r.queue_status === 'CALLED'" size="small" color="primary" :loading="busy === r.queue_id" @click="accept(r)">หมอรับคิว</v-btn>
              <v-btn v-if="r.queue_status === 'ACCEPTED'" size="small" color="primary" :loading="busy === r.queue_id" @click="start(r)">เริ่มบริการ</v-btn>
              <v-btn v-if="r.queue_status === 'IN_SERVICE'" size="small" color="success" :loading="busy === r.queue_id" @click="complete(r)">จบบริการ</v-btn>
              <v-btn v-if="['CALLED', 'ACCEPTED'].includes(r.queue_status)" size="small" variant="text" @click="openCall(r)">เปลี่ยนหมอ</v-btn>
              <v-btn v-if="['WAITING', 'CALLED', 'ACCEPTED'].includes(r.queue_status)" size="small" variant="text" color="error" @click="openCancel(r)">ยกเลิก</v-btn>
              <template v-if="r.queue_status === 'IN_SERVICE'">
                <v-btn size="small" variant="text" @click="openExtend(r)">ต่อเวลา</v-btn>
                <v-btn size="small" variant="text" @click="openCall(r)">เปลี่ยนหมอ</v-btn>
                <v-btn v-if="withinUndo(r.started_at)" size="small" variant="text" @click="openUndo(r)">ย้อนเริ่ม</v-btn>
              </template>
              <v-btn v-if="device.token.value && r.therapist && ['CALLED', 'ACCEPTED', 'IN_SERVICE'].includes(r.queue_status)"
                size="small" variant="tonal" prepend-icon="mdi-dialpad" @click="openPin(r)">หมอกด PIN</v-btn>
            </div>
            <div v-else-if="r.queue_status === 'COMPLETED' && withinUndo(r.completed_at)" class="mt-2">
              <v-btn size="small" variant="text" @click="openUndo(r)">ย้อนจบบริการ</v-btn>
            </div>
          </v-card>
        </div>
      </section>

      <section>
        <p class="m-0 mb-2 font-medium">หมอ ({{ therapists.length }})</p>
        <v-card class="p-2">
          <v-list density="compact">
            <v-list-item v-for="t in therapists" :key="t.employee_id" :title="t.nickname"
              :subtitle="t.busy_queue_number ? `คิว ${formatQueueNumber(t.busy_queue_number)}` : t.on_shift ? 'ว่าง' : 'ไม่มีกะ'">
              <template #prepend>
                <v-icon :icon="t.busy_queue_number ? 'mdi-circle' : 'mdi-circle-outline'"
                  :color="t.busy_queue_number ? 'warning' : t.on_shift ? 'success' : 'grey'" size="12" class="mr-2" />
              </template>
            </v-list-item>
          </v-list>
        </v-card>
      </section>
    </div>

    <!-- เลือกหมอ -->
    <v-dialog v-model="callDialog" max-width="520">
      <v-card v-if="callRow" class="p-6">
        <p class="m-0 mb-1 text-lg font-medium">
          {{ callRow.queue_status === 'IN_SERVICE' ? 'เปลี่ยนหมอระหว่างบริการ' : callRow.therapist ? 'เปลี่ยนหมอ' : 'เรียกคิว' }}
          {{ formatQueueNumber(callRow.queue_number) }}
        </p>
        <p class="m-0 mb-3 text-sm text-light-brown">{{ callRow.service_name }} {{ formatDuration(callRow.duration_minutes) }}</p>
        <v-textarea v-if="callRow.therapist" v-model="callReason" label="เหตุผลที่เปลี่ยนหมอ (บังคับ)" rows="2" variant="outlined" />
        <p v-if="callRow.queue_status === 'IN_SERVICE'" class="m-0 mb-3 text-xs text-light-brown">
          ค่ามือแบ่งตามเวลาที่หมอแต่ละคนทำจริง
        </p>

        <v-alert v-if="offShift" type="warning" variant="tonal" class="mb-3">
          {{ offShift.text }}
          <div class="mt-2 flex justify-end gap-2">
            <v-btn size="small" variant="text" @click="offShift = null">ไม่ใช่</v-btn>
            <v-btn size="small" color="warning" @click="pick(offShift.therapist, true)">ยืนยันมอบหมาย</v-btn>
          </div>
        </v-alert>

        <div class="grid gap-2">
          <v-btn
            v-for="t in therapists"
            :key="t.employee_id"
            :disabled="!!t.busy_queue_number || t.employee_id === callRow.therapist?.employee_id"
            :loading="busy === callRow.queue_id"
            variant="outlined"
            class="justify-start"
            @click="pick(t)"
          >
            {{ t.nickname }}
            <span class="ml-2 text-xs text-light-brown">
              {{ t.busy_queue_number ? `มีคิว ${formatQueueNumber(t.busy_queue_number)}` : t.on_shift ? 'ว่าง · มีกะ' : 'ว่าง · ไม่มีกะ' }}
            </span>
          </v-btn>
        </div>
        <p v-if="!therapists.length" class="m-0 text-sm text-light-brown">ไม่มีพนักงานในสาขานี้</p>
        <div class="mt-4 flex justify-end"><v-btn variant="text" @click="callDialog = false">ปิด</v-btn></div>
      </v-card>
    </v-dialog>

    <!-- ย้อนเริ่ม/จบ -->
    <v-dialog v-model="undoDialog" max-width="460">
      <v-card v-if="undoRow" class="p-6">
        <p class="m-0 mb-1 text-lg font-medium">
          {{ undoKind === 'complete' ? 'ย้อนจบบริการ' : 'ย้อนเริ่มบริการ' }} คิว {{ formatQueueNumber(undoRow.queue_number) }}
        </p>
        <p class="m-0 mb-3 text-sm text-light-brown">
          {{ undoKind === 'complete' ? 'คิวจะกลับมาเป็นกำลังให้บริการ และจองเตียงกลับ' : 'คิวจะกลับเป็นหมอรับแล้ว (ยังไม่เริ่ม)' }}
          · ทำได้ภายใน {{ QUEUE_UNDO_MINUTES }} นาที
        </p>
        <v-textarea v-model="undoReason" label="เหตุผล (บังคับ)" rows="2" variant="outlined" />
        <div class="flex justify-end gap-2">
          <v-btn variant="text" @click="undoDialog = false">ปิด</v-btn>
          <v-btn color="primary" :loading="busy === undoRow.queue_id" @click="submitUndo">ยืนยันย้อน</v-btn>
        </div>
      </v-card>
    </v-dialog>

    <!-- ต่อเวลา -->
    <v-dialog v-model="extendDialog" max-width="480">
      <v-card v-if="extendRow" class="p-6">
        <p class="m-0 mb-1 text-lg font-medium">ต่อเวลาคิว {{ formatQueueNumber(extendRow.queue_number) }}</p>
        <p class="m-0 mb-3 text-sm text-light-brown">
          {{ extendRow.therapist?.nickname }} ให้บริการต่อทันทีเมื่อ {{ extendRow.service_name }} จบ
        </p>
        <v-select v-model="extendOption" label="บริการที่ต่อ" :items="extendItems" />
        <div class="flex justify-end gap-2">
          <v-btn variant="text" @click="extendDialog = false">ปิด</v-btn>
          <v-btn color="primary" :disabled="!extendOption" :loading="busy === extendRow.queue_id" @click="submitExtend">ต่อเวลา</v-btn>
        </div>
      </v-card>
    </v-dialog>

    <!-- ลงเวลา -->
    <v-dialog v-model="clockDialog" max-width="420">
      <v-card class="p-6">
        <template v-if="!clockWho">
          <p class="m-0 mb-3 text-lg font-medium">ลงเวลาเข้า/ออกงาน</p>
          <div class="grid gap-2">
            <v-btn v-for="a in clockList" :key="a.employee_id" variant="outlined" class="justify-start" :disabled="!!a.clock_out_at"
              @click="clockWho = a; clockError = null">
              {{ a.nickname }}
              <span class="ml-2 text-xs text-light-brown">
                {{ a.clock_out_at ? `ออกแล้ว ${bangkokTime(a.clock_out_at)}` : a.clock_in_at ? `เข้า ${bangkokTime(a.clock_in_at)} · กดเพื่อลงเวลาออก` : 'กดเพื่อลงเวลาเข้า' }}
              </span>
            </v-btn>
          </div>
          <div class="mt-4 flex justify-end"><v-btn variant="text" @click="clockDialog = false">ปิด</v-btn></div>
        </template>
        <template v-else>
          <p class="m-0 text-center text-lg font-medium">{{ clockWho.nickname }}</p>
          <p class="m-0 mb-4 text-center text-sm text-light-brown">ลงเวลา{{ clockWho.clock_in_at ? 'ออก' : 'เข้า' }}งาน · กด PIN ของคุณ</p>
          <PinPad ref="clockPad" :loading="clockLoading" :error="clockError" @submit="submitClock" />
          <div class="mt-4 flex justify-center"><v-btn variant="text" @click="clockWho = null">ย้อนกลับ</v-btn></div>
        </template>
      </v-card>
    </v-dialog>

    <!-- หมอกด PIN -->
    <v-dialog v-model="pinDialog" max-width="400">
      <v-card v-if="pinRow?.therapist" class="p-6">
        <p class="m-0 text-center text-lg font-medium">{{ pinRow.therapist.nickname }}</p>
        <p class="m-0 mb-4 text-center text-sm text-light-brown">
          {{ pinActionLabel[pinAction(pinRow)] }}คิว {{ formatQueueNumber(pinRow.queue_number) }} · กด PIN ของคุณ
        </p>
        <PinPad ref="pinPad" :loading="pinLoading" :error="pinError" @submit="submitPin" />
        <div class="mt-4 flex justify-center"><v-btn variant="text" @click="pinDialog = false">ยกเลิก</v-btn></div>
      </v-card>
    </v-dialog>

    <!-- ยกเลิก -->
    <v-dialog v-model="cancelDialog" max-width="460">
      <v-card v-if="cancelRow" class="p-6">
        <p class="m-0 mb-3 text-lg font-medium">ยกเลิกคิว {{ formatQueueNumber(cancelRow.queue_number) }} · {{ cancelRow.service_name }}</p>
        <v-textarea v-model="cancelReason" label="เหตุผล (บังคับ)" rows="2" variant="outlined" />
        <div class="flex justify-end gap-2">
          <v-btn variant="text" @click="cancelDialog = false">ปิด</v-btn>
          <v-btn color="error" :loading="busy === cancelRow.queue_id" @click="submitCancel">ยืนยันยกเลิก</v-btn>
        </div>
      </v-card>
    </v-dialog>
  </div>
</template>
