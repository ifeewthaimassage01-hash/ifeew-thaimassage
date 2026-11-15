<script setup lang="ts">
// ตัวอย่างการ์ด LINE (Flex Message) ในหน้า /settings/line — โครงและสีเดียวกับ supabase/functions/_shared/lineFlex.ts
// ใช้ข้อมูลสมมติ: คุณสมใจ 2 คน นัดพรุ่งนี้ 14:00
const props = defineProps<{
  kind: 'group' | 'confirm' | 'reminder' | 'owner'
  event?: 'NEW_BOOKING' | 'DEPOSIT_SLIP' | 'DEPOSIT_REVIEWED' | 'BOOKING_CANCELLED' | 'WALK_IN' | 'SERVICE_DONE' | null
  branch: string
  staffUrl?: string
  siteUrl?: string
  /** ชื่อร้าน (หัวการ์ดสรุปถึงเจ้าของ) */
  company?: string
  /** สรุปของวันนี้ (ตั้งเวลาส่งตั้งแต่เที่ยงวัน) · ไม่ตั้ง = ของเมื่อวาน */
  summaryToday?: boolean
}>()

// สรุปประจำวันถึงเจ้าของ (โครงเดียวกับ summaryBubble ใน lineFlex.ts) — ข้อมูลสมมติ
const summaryDay = computed(() =>
  new Date(Date.now() - (props.summaryToday ? 0 : 86_400_000))
    .toLocaleDateString('th-TH', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'Asia/Bangkok' }),
)
const summaryRows = [
  { label: 'รายได้', value: '฿5,400' },
  { label: 'รายจ่าย', value: '฿350' },
  { label: 'ค่าแรงหมอ', value: '฿1,800' },
]

const TH_DAYS = ['อาทิตย์', 'จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์']
const TH_MONTHS = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.']
const d = new Date(Date.now() + 86_400_000)
const dateLabel = `วัน${TH_DAYS[d.getDay()]}ที่ ${d.getDate()} ${TH_MONTHS[d.getMonth()]}`
const timeLabel = '14:00–15:30 น.'
const items = [
  { name: 'นวดไทย', dur: '1 ชม.' },
  { name: 'นวดเท้า', dur: '1 ชม. 30 นาที' },
]

type Tone = 'teak' | 'pending' | 'danger' | 'beige' | 'success'
const TONE_CLASS: Record<Tone, string> = {
  teak: 'bg-primary text-primary-foreground',
  pending: 'bg-pending-soft text-pending-ink',
  danger: 'bg-danger-soft text-danger-ink',
  beige: 'bg-secondary text-heading',
  success: 'bg-success-soft text-success-ink',
}
const STAFF: Record<string, { title: string; tone: Tone; booking: boolean; body?: string }> = {
  NEW_BOOKING: { title: 'การจองใหม่', tone: 'teak', booking: true },
  DEPOSIT_SLIP: { title: 'จองใหม่ · สลิปรอตรวจ', tone: 'pending', booking: true },
  DEPOSIT_REVIEWED: { title: 'สลิปผ่าน · ยืนยันการจองแล้ว', tone: 'success', booking: true },
  BOOKING_CANCELLED: { title: 'ลูกค้ายกเลิกการจอง', tone: 'danger', booking: true },
  WALK_IN: { title: 'รับลูกค้าหน้าร้าน', tone: 'beige', booking: false, body: '1 คน · นวดไทย 60 นาที' },
  SERVICE_DONE: { title: 'บริการเสร็จแล้ว', tone: 'success', booking: false, body: 'คิว 012 · นวดไทย 60 นาที · หมอแนน · รอชำระเงิน' },
}

const head = computed(() => {
  if (props.kind === 'owner') return { title: `สรุป${summaryDay.value}`, tone: 'teak' as Tone }
  if (props.kind === 'confirm') return { title: 'ได้รับการจองแล้ว', tone: 'teak' as Tone }
  if (props.kind === 'reminder') return { title: 'แจ้งเตือนนัดหมาย', tone: 'teak' as Tone }
  const s = STAFF[props.event ?? 'NEW_BOOKING']!
  return { title: s.title, tone: s.tone }
})
const staff = computed(() => STAFF[props.event ?? 'NEW_BOOKING']!)
const compact = computed(() => props.kind === 'group')
</script>

<template>
  <div
    class="overflow-hidden rounded-2xl bg-card shadow-[0_1px_3px_rgba(81,67,55,.10)]"
    :class="compact ? 'w-full max-w-[260px]' : 'w-full max-w-[300px]'"
    role="img"
    :aria-label="`ตัวอย่างการ์ด LINE: ${head.title}`"
  >
    <!-- หัวการ์ด: สีบอกประเภท -->
    <div class="grid gap-0.5 px-4 py-3" :class="TONE_CLASS[head.tone]">
      <span class="text-base leading-snug font-bold">{{ head.title }}</span>
      <span class="text-xs opacity-90">{{ kind === 'owner' ? (company ?? branch) : branch }}</span>
    </div>

    <!-- เนื้อหา: สรุปประจำวันถึงเจ้าของ -->
    <div v-if="kind === 'owner'" class="grid gap-1.5 px-4 py-3 text-sm text-foreground">
      <span class="text-muted-foreground">ยอดสุทธิ</span>
      <span class="num text-2xl leading-tight font-bold text-success-ink">฿3,250</span>
      <span class="my-1 h-px bg-border" aria-hidden="true" />
      <div v-for="r in summaryRows" :key="r.label" class="flex justify-between gap-3">
        <span class="text-muted-foreground">{{ r.label }}</span><span class="num text-heading">{{ r.value }}</span>
      </div>
      <span class="my-1 h-px bg-border" aria-hidden="true" />
      <div class="flex justify-between gap-3 font-bold text-heading"><span>ลูกค้าที่ใช้บริการ</span><span class="num">9 คน</span></div>
      <div class="flex justify-between gap-3"><span class="text-muted-foreground">มาจากการจอง</span><span class="num text-heading">4 คน</span></div>
      <div class="flex justify-between gap-3"><span class="text-muted-foreground">นัดพรุ่งนี้</span><span class="num text-heading">6 การจอง</span></div>
      <div class="mt-1 grid gap-0.5 rounded-[10px] bg-pending-soft px-3 py-2.5 text-pending-ink">
        <span class="text-xs font-bold">ต้องดู</span>
        <div class="flex justify-between gap-3 font-bold"><span>สลิปรอตรวจ</span><span class="num">1 รายการ</span></div>
      </div>
    </div>

    <!-- เนื้อหา -->
    <div v-else class="grid gap-1.5 px-4 py-3 text-sm text-foreground">
      <template v-if="kind !== 'group' || staff.booking">
        <template v-if="kind === 'group'">
          <span class="text-[15px] font-bold text-heading">คุณสมใจ</span>
          <span class="text-muted-foreground">{{ dateLabel }} {{ timeLabel }}</span>
        </template>
        <template v-else>
          <span class="text-muted-foreground">{{ dateLabel }}</span>
          <span class="num text-2xl leading-tight font-bold text-heading">{{ timeLabel }}</span>
          <span>{{ kind === 'confirm' ? 'คุณสมใจ ขอบคุณที่จองกับเรา' : 'คุณสมใจ มีนัดนวดกับเรา' }}</span>
        </template>

        <span class="my-1 h-px bg-border" aria-hidden="true" />
        <div v-for="(it, i) in items" :key="it.name" class="flex justify-between gap-3">
          <span>คนที่ {{ i + 1 }} {{ it.name }}</span><span class="shrink-0">{{ it.dur }}</span>
        </div>
        <span class="my-1 h-px bg-border" aria-hidden="true" />
        <div class="flex justify-between gap-3 font-bold text-heading"><span class="font-normal text-muted-foreground">รวม 2 คน</span><span class="num">฿900</span></div>

        <div v-if="kind === 'group' && event === 'DEPOSIT_SLIP'" class="flex justify-between gap-3 font-bold text-pending-ink">
          <span class="font-normal text-muted-foreground">โอนมัดจำ</span><span class="num">฿200 รอตรวจ</span>
        </div>
        <template v-if="kind === 'group' && event === 'DEPOSIT_REVIEWED'">
          <div class="flex justify-between gap-3 font-bold text-success-ink"><span class="font-normal text-muted-foreground">มัดจำ</span><span class="num">฿200</span></div>
          <span class="text-xs text-muted-foreground">ตรวจโดย แตน</span>
          <div class="mt-1 grid aspect-[3/4] place-items-center rounded-md border border-dashed border-border bg-white text-xs text-muted-foreground">
            รูปสลิป (แตะเพื่อดูเต็มจอ)
          </div>
        </template>
        <template v-if="kind === 'confirm'">
          <div class="flex justify-between gap-3 text-xs text-muted-foreground"><span>รหัสการจอง</span><span class="num">BKG-IFEEW-0001</span></div>
          <div class="mt-1 grid gap-0.5 rounded-[10px] bg-pending-soft px-3 py-2.5 text-pending-ink">
            <span class="font-bold">ชำระมัดจำ ฿200 ภายใน 13:15 น.</span>
            <span class="text-xs">ไม่เช่นนั้นการจองจะถูกยกเลิกอัตโนมัติ</span>
          </div>
        </template>
        <span v-if="kind === 'reminder'" class="mt-1 text-xs text-muted-foreground">กรุณามาก่อนเวลาประมาณ 10 นาที ถ้ามาไม่ได้รบกวนแจ้งร้านล่วงหน้า</span>
      </template>
      <span v-else>{{ staff.body }}</span>
    </div>

    <!-- ปุ่ม -->
    <div class="grid gap-1.5 border-t border-border px-3 py-2.5">
      <template v-if="kind === 'owner'">
        <span v-if="staffUrl" class="grid h-8 place-items-center rounded-md bg-primary text-sm font-medium text-primary-foreground">เปิดแดชบอร์ด</span>
        <span v-else class="py-1 text-center text-xs text-muted-foreground">ตั้ง URL แอปพนักงานเพื่อมีปุ่ม “เปิดแดชบอร์ด”</span>
      </template>
      <template v-else-if="kind === 'group'">
        <span v-if="staffUrl" class="grid h-8 place-items-center rounded-md bg-primary text-sm font-medium text-primary-foreground">เปิดในระบบ</span>
        <span v-else class="py-1 text-center text-xs text-muted-foreground">ตั้ง URL แอปพนักงานเพื่อมีปุ่ม “เปิดในระบบ”</span>
      </template>
      <template v-else>
        <span v-if="siteUrl" class="grid h-8 place-items-center rounded-md bg-primary text-sm font-medium text-primary-foreground">
          {{ kind === 'confirm' ? 'ชำระมัดจำ / ดูสถานะ' : 'ตรวจสอบการจอง' }}
        </span>
        <div class="grid grid-cols-2 gap-1.5">
          <span class="grid h-8 place-items-center rounded-md bg-muted text-sm font-medium text-heading">แผนที่</span>
          <span class="grid h-8 place-items-center rounded-md bg-muted text-sm font-medium text-heading">โทรหาร้าน</span>
        </div>
      </template>
    </div>
  </div>
</template>
