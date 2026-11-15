// การ์ด LINE (Flex Message) โทน Warm Cream ของร้าน — DESIGN.md
//   confirm  = ยืนยันการจอง (ถึงลูกค้า)
//   reminder = เตือนก่อนถึงนัด (ถึงลูกค้า)
//   staff    = แจ้งเตือนกลุ่มพนักงาน (จองใหม่ / สลิป / ยกเลิก / หน้าร้าน / บริการเสร็จ)
// ข้อมูลมาจาก SQL (private.line_booking_data / push_claim.line_flex) · altText = ข้อความธรรมดาเดิม

const TEAK = '#93704F' // ปุ่มหลัก/หัวการ์ด
const COFFEE = '#514337' // หัวข้อ/ตัวเลข
const INK = '#66594D' // ตัวหนังสือ
const DRIFT = '#7A6E61' // ตัวหนังสือรอง
const LINEN = '#FFFCF8'
const BORDER = '#EDE4DA'
const ON_TEAK = '#F6EEE5'
const TONES = {
  teak: { bg: TEAK, fg: '#FFFFFF', sub: ON_TEAK },
  pending: { bg: '#F2E6D6', fg: '#72543E', sub: '#72543E' },
  success: { bg: '#E6EEE6', fg: '#557560', sub: '#557560' },
  danger: { bg: '#F6E5E1', fg: '#9E5149', sub: '#9E5149' },
  beige: { bg: '#EDE0D2', fg: COFFEE, sub: INK },
} as const

export interface FlexBooking {
  customer_name: string
  branch_name: string
  branch_phone: string | null
  map_url: string | null
  booking_code: string | null
  date_label: string
  time_label: string
  short_label: string
  people: number
  total: number
  deposit_required: number
  deposit_status: string
  hold_until: string | null
  items: Array<{ name: string; minutes: number }>
}

/** สรุปประจำวันถึงเจ้าของร้าน (private.line_daily_summary_data — migration 077) */
export interface FlexSummaryFigures {
  revenue: number
  expenses: number
  therapist_pay: number
  net: number
  customers: number
  from_booking: number
  cancelled: number
  no_show: number
}
export interface FlexSummary {
  date: string
  date_label: string
  company_name?: string
  total: FlexSummaryFigures
  branches: Array<FlexSummaryFigures & { name: string }>
  pending_slips: number
  unpaid_bills: number
  unpaid_amount: number
  tomorrow_bookings: number
}

export type FlexData =
  | { kind: 'confirm' | 'reminder'; booking: FlexBooking | null; link: string | null }
  | { kind: 'summary'; summary: FlexSummary; link: string | null }
  | {
      kind: 'staff'
      event: string
      title: string
      body: string
      link: string | null
      booking: FlexBooking | null
      slip_amount: number | null
      /** DEPOSIT_REVIEWED: "ตรวจโดย …" / "ตรวจอัตโนมัติ" และผลตรวจ */
      review?: string | null
      review_ok?: boolean | null
      /** สลิปที่ผ่านแล้ว: signed URL ของรูป (JPG/PNG แสดงในการ์ด · แบบอื่นเป็นปุ่ม "ดูรูปสลิป") — push-dispatch ใส่ให้ */
      slip_url?: string | null
    }

type Json = Record<string, unknown>

const baht = (n: number | string | null | undefined) => `฿${Math.round(Number(n ?? 0)).toLocaleString('en-US')}`
const duration = (m: number) =>
  m % 60 === 0 ? `${m / 60} ชม.` : m > 60 ? `${Math.floor(m / 60)} ชม. ${m % 60} นาที` : `${m} นาที`
const text = (t: string, o: Json = {}): Json => ({ type: 'text', text: t || ' ', wrap: true, color: INK, size: 'sm', ...o })
const row = (label: string, value: string, o: Json = {}): Json => ({
  type: 'box',
  layout: 'horizontal',
  spacing: 'md',
  contents: [text(label, { color: DRIFT, flex: 3 }), text(value, { align: 'end', flex: 2, color: COFFEE, ...o })],
})
const sep = (): Json => ({ type: 'separator', color: BORDER, margin: 'md' })
const isUri = (u: string | null | undefined): u is string => !!u && /^(https:\/\/|tel:)/.test(u) && u.length <= 1000
const tel = (p: string | null) => (p ? `tel:${p.replace(/[^0-9+]/g, '')}` : null)
const button = (label: string, uri: string, primary = false): Json => ({
  type: 'button',
  height: 'sm',
  style: primary ? 'primary' : 'secondary',
  ...(primary ? { color: TEAK } : {}),
  action: { type: 'uri', label: label.slice(0, 20), uri },
})

function header(title: string, sub: string | null, tone: keyof typeof TONES): Json {
  const t = TONES[tone]
  return {
    type: 'box',
    layout: 'vertical',
    backgroundColor: t.bg,
    paddingAll: '16px',
    spacing: 'xs',
    contents: [text(title, { color: t.fg, weight: 'bold', size: 'lg' }), ...(sub ? [text(sub, { color: t.sub, size: 'xs' })] : [])],
  }
}

function itemRows(b: FlexBooking): Json[] {
  return b.items.map((i, idx) => row(b.items.length > 1 ? `คนที่ ${idx + 1} ${i.name}` : i.name, duration(i.minutes), { color: INK }))
}

function depositBox(b: FlexBooking): Json | null {
  const box = (tone: keyof typeof TONES, title: string, note?: string): Json => ({
    type: 'box',
    layout: 'vertical',
    backgroundColor: TONES[tone].bg,
    cornerRadius: '10px',
    paddingAll: '12px',
    margin: 'md',
    spacing: 'xs',
    contents: [text(title, { color: TONES[tone].fg, weight: 'bold' }), ...(note ? [text(note, { color: TONES[tone].fg, size: 'xs' })] : [])],
  })
  switch (b.deposit_status) {
    case 'AWAITING_PAYMENT':
      return box(
        'pending',
        `ชำระมัดจำ ${baht(b.deposit_required)}${b.hold_until ? ` ภายใน ${b.hold_until} น.` : ''}`,
        'ไม่เช่นนั้นการจองจะถูกยกเลิกอัตโนมัติ',
      )
    case 'PENDING_REVIEW':
      return box('pending', 'ได้รับสลิปมัดจำแล้ว', 'รอร้านตรวจสอบ จะแจ้งยืนยันโดยเร็วที่สุด')
    case 'PAID':
      return box('success', `ชำระมัดจำ ${baht(b.deposit_required)} แล้ว`)
    default:
      return null
  }
}

function contactButtons(b: FlexBooking): Json[] {
  const out: Json[] = []
  if (isUri(b.map_url)) out.push(button('แผนที่', b.map_url))
  const t = tel(b.branch_phone)
  if (isUri(t)) out.push(button('โทรหาร้าน', t))
  return out.length ? [{ type: 'box', layout: 'horizontal', spacing: 'sm', contents: out }] : []
}

function customerBubble(kind: 'confirm' | 'reminder', b: FlexBooking, link: string | null): Json {
  const deposit = kind === 'confirm' ? depositBox(b) : null
  const body: Json[] = [
    text(b.date_label, { color: DRIFT }),
    text(b.time_label, { size: 'xxl', weight: 'bold', color: COFFEE }),
    text(kind === 'confirm' ? `คุณ${b.customer_name} ขอบคุณที่จองกับเรา` : `คุณ${b.customer_name} มีนัดนวดกับเรา`, { margin: 'sm' }),
    sep(),
    { type: 'box', layout: 'vertical', spacing: 'sm', margin: 'md', contents: itemRows(b) },
    sep(),
    row(`รวม ${b.people} คน`, baht(b.total), { weight: 'bold', size: 'md' }),
    ...(b.booking_code ? [row('รหัสการจอง', b.booking_code, { size: 'xs', color: DRIFT })] : []),
    ...(deposit ? [deposit] : []),
    ...(kind === 'reminder' ? [text('กรุณามาก่อนเวลาประมาณ 10 นาที ถ้ามาไม่ได้รบกวนแจ้งร้านล่วงหน้า', { color: DRIFT, size: 'xs', margin: 'md' })] : []),
  ]
  const primaryLabel =
    kind === 'reminder' ? 'ตรวจสอบการจอง' : b.deposit_status === 'AWAITING_PAYMENT' ? 'ชำระมัดจำ / ดูสถานะ' : 'ดูสถานะการจอง'
  const footer: Json[] = [...(isUri(link) ? [button(primaryLabel, link, true)] : []), ...contactButtons(b)]
  return {
    type: 'bubble',
    header: header(kind === 'confirm' ? 'ได้รับการจองแล้ว' : 'แจ้งเตือนนัดหมาย', b.branch_name, 'teak'),
    body: { type: 'box', layout: 'vertical', spacing: 'sm', paddingAll: '16px', backgroundColor: LINEN, contents: body },
    ...(footer.length ? { footer: { type: 'box', layout: 'vertical', spacing: 'sm', paddingAll: '12px', contents: footer } } : {}),
    styles: { footer: { separator: true, separatorColor: BORDER } },
  }
}

const STAFF_TONE: Record<string, keyof typeof TONES> = {
  NEW_BOOKING: 'teak',
  DEPOSIT_SLIP: 'pending',
  BOOKING_CANCELLED: 'danger',
  WALK_IN: 'beige',
  SERVICE_DONE: 'success',
}

function staffBubble(d: Extract<FlexData, { kind: 'staff' }>): Json {
  const [title, branch] = d.title.split(' · ')
  const b = d.booking
  const body: Json[] = b
    ? [
        text(`คุณ${b.customer_name}`, { size: 'md', weight: 'bold', color: COFFEE }),
        text(`${b.date_label} ${b.time_label}`, { color: DRIFT }),
        sep(),
        { type: 'box', layout: 'vertical', spacing: 'sm', margin: 'md', contents: itemRows(b) },
        sep(),
        row(`รวม ${b.people} คน`, baht(b.total), { weight: 'bold' }),
        ...(d.event === 'DEPOSIT_REVIEWED'
          ? [row(d.review_ok ? 'มัดจำ' : 'ยอดในสลิป', baht(d.slip_amount), { color: d.review_ok ? TONES.success.fg : TONES.danger.fg, weight: 'bold' }), ...(d.review ? [text(d.review, { color: DRIFT, size: 'xs' })] : [])]
          : []),
        ...(d.event === 'DEPOSIT_SLIP' ? [row('โอนมัดจำ', `${baht(d.slip_amount)} รอตรวจ`, { color: TONES.pending.fg, weight: 'bold' })] : []),
        ...(d.event === 'NEW_BOOKING' && Number(b.deposit_required) > 0 ? [row('มัดจำ', baht(b.deposit_required))] : []),
      ]
    : [text(d.body, { color: INK })]
  // รูปสลิป: LINE แสดงในการ์ดได้เฉพาะ JPG/PNG (ไม่เกิน 10 MB) · แตะรูปเพื่อเปิดเต็มจอ
  const slip = d.slip_url && d.slip_url.length <= 1000 && d.slip_url.startsWith('https://') ? d.slip_url : null
  const slipInCard = !!slip && /\.(jpe?g|png)(\?|$)/i.test(slip)
  if (slip && slipInCard) {
    body.push({
      type: 'image',
      url: slip,
      size: 'full',
      aspectMode: 'fit',
      aspectRatio: '3:4',
      backgroundColor: '#FFFFFF',
      margin: 'md',
      action: { type: 'uri', label: 'ดูรูปสลิป', uri: slip },
    })
  }
  const footer: Json[] = [
    ...(isUri(d.link) ? [button('เปิดในระบบ', d.link, true)] : []),
    ...(slip && !slipInCard ? [button('ดูรูปสลิป', slip)] : []),
  ]
  return {
    type: 'bubble',
    size: 'kilo',
    header: header(title ?? d.title, branch ?? null, d.event === 'DEPOSIT_REVIEWED' ? (d.review_ok ? 'success' : 'danger') : STAFF_TONE[d.event] ?? 'beige'),
    body: { type: 'box', layout: 'vertical', spacing: 'sm', paddingAll: '14px', backgroundColor: LINEN, contents: body },
    ...(footer.length ? { footer: { type: 'box', layout: 'vertical', spacing: 'sm', paddingAll: '10px', contents: footer } } : {}),
  }
}

// ---------------------------------------------------------------------------
// สรุปประจำวัน (ถึงเจ้าของร้าน): ยอดสุทธิตัวใหญ่ → รายได้/รายจ่าย/ค่าแรงหมอ → ลูกค้า → เรื่องที่ต้องดู → แยกสาขา
// ---------------------------------------------------------------------------
const signedBaht = (n: number) => (Number(n) < 0 ? `−${baht(Math.abs(Number(n)))}` : baht(n))
const thaiDate = (iso: string) => {
  const d = new Date(`${iso}T00:00:00+07:00`)
  return d.toLocaleDateString('th-TH', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'Asia/Bangkok' })
}

function summaryBubble(s: FlexSummary, link: string | null): Json {
  const t = s.total
  const n = (v: unknown) => Number(v) || 0
  const netNeg = n(t.net) < 0
  const attention: Json[] = []
  if (n(s.pending_slips)) attention.push(row('สลิปรอตรวจ', `${n(s.pending_slips)} รายการ`, { color: TONES.pending.fg, weight: 'bold' }))
  if (n(s.unpaid_bills)) attention.push(row('บิลค้างชำระ', `${n(s.unpaid_bills)} บิล ${baht(s.unpaid_amount)}`, { color: TONES.pending.fg, weight: 'bold' }))

  const body: Json[] = [
    text('ยอดสุทธิ', { color: DRIFT }),
    text(signedBaht(t.net), { size: 'xxl', weight: 'bold', color: netNeg ? TONES.danger.fg : TONES.success.fg }),
    sep(),
    {
      type: 'box', layout: 'vertical', spacing: 'sm', margin: 'md',
      contents: [
        row('รายได้', baht(t.revenue), { color: COFFEE }),
        row('รายจ่าย', baht(t.expenses), { color: COFFEE }),
        row('ค่าแรงหมอ', baht(t.therapist_pay), { color: COFFEE }),
      ],
    },
    sep(),
    {
      type: 'box', layout: 'vertical', spacing: 'sm', margin: 'md',
      contents: [
        row('ลูกค้าที่ใช้บริการ', `${n(t.customers)} คน`, { color: COFFEE, weight: 'bold' }),
        ...(n(t.from_booking) ? [row('มาจากการจอง', `${n(t.from_booking)} คน`)] : []),
        ...(n(t.cancelled) ? [row('ยกเลิกการจอง', `${n(t.cancelled)}`)] : []),
        ...(n(t.no_show) ? [row('ไม่มาตามนัด', `${n(t.no_show)}`, { color: TONES.danger.fg })] : []),
        row('นัดพรุ่งนี้', `${n(s.tomorrow_bookings)} การจอง`),
      ],
    },
  ]
  if (attention.length) {
    body.push({
      type: 'box', layout: 'vertical', spacing: 'xs', margin: 'md', paddingAll: '12px', cornerRadius: '10px',
      backgroundColor: TONES.pending.bg,
      contents: [text('ต้องดู', { color: TONES.pending.fg, weight: 'bold', size: 'xs' }), ...attention],
    })
  }
  if (s.branches?.length) {
    body.push(sep(), text('แยกสาขา', { color: DRIFT, size: 'xs', margin: 'md' }))
    for (const b of s.branches) {
      body.push(row(`${b.name} (${n(b.customers)} คน)`, signedBaht(b.net), { color: n(b.net) < 0 ? TONES.danger.fg : COFFEE, weight: 'bold' }))
    }
  }
  return {
    type: 'bubble',
    size: 'kilo',
    header: header(`สรุป${thaiDate(s.date)}`, s.company_name ?? null, 'teak'),
    body: { type: 'box', layout: 'vertical', spacing: 'sm', paddingAll: '16px', backgroundColor: LINEN, contents: body },
    ...(isUri(link) ? { footer: { type: 'box', layout: 'vertical', paddingAll: '10px', contents: [button('เปิดแดชบอร์ด', link, true)] } } : {}),
  }
}

/** การ์ดสรุปสำหรับตอบกลับในแชท (พิมพ์ "สรุป") */
export function summaryMessage(s: FlexSummary, link: string | null): Json {
  return buildLineMessage(`สรุป${s.date_label} ยอดสุทธิ ${signedBaht(s.total.net)} ลูกค้า ${s.total.customers} คน`, { kind: 'summary', summary: s, link })
}

/** การ์ดประกาศสั้น (ข้อความตอบกลับของบอท / ทดสอบ) */
export function noticeMessage(
  altText: string,
  o: { title: string; sub?: string; lines: string[]; tone?: keyof typeof TONES; button?: { label: string; uri: string } },
): Json {
  return {
    type: 'flex',
    altText: altText.replace(/\s+/g, ' ').slice(0, 400),
    contents: {
      type: 'bubble',
      size: 'kilo',
      header: header(o.title, o.sub ?? null, o.tone ?? 'teak'),
      body: {
        type: 'box',
        layout: 'vertical',
        spacing: 'sm',
        paddingAll: '14px',
        backgroundColor: LINEN,
        contents: o.lines.map((l) => text(l)),
      },
      ...(o.button && isUri(o.button.uri)
        ? { footer: { type: 'box', layout: 'vertical', paddingAll: '10px', contents: [button(o.button.label, o.button.uri, true)] } }
        : {}),
    },
  }
}

/** การ์ดตัวอย่างที่กลุ่มพนักงานจะได้รับ (ปุ่ม "ส่งทดสอบ") */
export function sampleStaffMessage(branchName: string | null, staffUrl: string | null): Json {
  const today = new Date(Date.now() + 7 * 3600_000)
  const dd = `${String(today.getUTCDate()).padStart(2, '0')}/${String(today.getUTCMonth() + 1).padStart(2, '0')}`
  return buildLineMessage(`🔔 ทดสอบการแจ้งเตือน · ถ้าเห็นข้อความนี้ กลุ่มนี้พร้อมรับแจ้งเตือนแล้ว`, {
    kind: 'staff',
    event: 'NEW_BOOKING',
    title: `ทดสอบการแจ้งเตือน${branchName ? ` · ${branchName}` : ''}`,
    body: '',
    link: staffUrl ? `${staffUrl.replace(/\/+$/, '')}/bookings` : null,
    slip_amount: null,
    booking: {
      customer_name: 'ตัวอย่าง',
      branch_name: branchName ?? '',
      branch_phone: null,
      map_url: null,
      booking_code: null,
      date_label: 'วันนี้',
      time_label: '14:00–15:00 น.',
      short_label: `${dd} 14:00 น.`,
      people: 1,
      total: 400,
      deposit_required: 0,
      deposit_status: 'NOT_REQUIRED',
      hold_until: null,
      items: [{ name: 'นวดไทย', minutes: 60 }],
    },
  })
}

/** สร้างข้อความ LINE: การ์ดถ้าข้อมูลพอ ไม่งั้นข้อความธรรมดา */
export function buildLineMessage(altText: string, flex: FlexData | null | undefined): Json {
  const plain = { type: 'text', text: altText.slice(0, 5000) }
  if (!flex) return plain
  try {
    let contents: Json | null = null
    if (flex.kind === 'staff') contents = staffBubble(flex)
    else if (flex.kind === 'summary') contents = summaryBubble(flex.summary, flex.link)
    else if (flex.booking) contents = customerBubble(flex.kind, flex.booking, flex.link)
    if (!contents) return plain
    return { type: 'flex', altText: altText.replace(/\s+/g, ' ').slice(0, 400), contents }
  } catch (e) {
    console.error('buildLineMessage', e)
    return plain
  }
}
