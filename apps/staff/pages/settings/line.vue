<script setup lang="ts">
// OWNER: ตั้งค่า LINE OA ทั้งหมดจากหน้านี้
// บนสุด: บัญชี LINE ที่เชื่อม + โควตาข้อความเดือนนี้
// ขั้นตอนตั้งค่า (ทำตามลำดับ · ขั้นที่เสร็จแล้วยุบเหลือบรรทัดเดียว · ขั้นถัดไปเปิดรอ)
//   1) เชื่อมบัญชี (token/secret เก็บเข้ารหัสใน Vault — อ่านกลับไม่ได้)
//   2) ให้ LINE ส่งข้อความมาที่ระบบ (ตั้ง Webhook อัตโนมัติ)
//   3) เชื่อมกลุ่มพนักงาน
//   4) จองผ่าน LINE (LIFF) — ไม่บังคับ
// ล่างสุด: เลือกสิ่งที่จะส่ง + ตัวอย่างข้อความจริงที่กลุ่ม/ลูกค้าจะเห็น
import { Check, ChevronDown, Copy, Lock, RefreshCw, Send } from '@lucide/vue'
import { toast } from 'vue-sonner'

definePageMeta({ ownerOnly: true })

interface LineSettings {
  has_access_token: boolean
  access_token_hint: string | null
  has_channel_secret: boolean
  login_channel_id: string | null
  liff_id: string | null
  add_friend_url: string | null
  bot_name: string | null
  bot_basic_id: string | null
  customer_url: string | null
  staff_url: string | null
  confirm_enabled: boolean
  reminder_enabled: boolean
  reminder_minutes: number
  group_events: string[]
  webhook_url: string
}
interface CheckResult {
  configured: boolean
  token_valid?: boolean
  bot?: { name: string; basic_id: string; picture_url: string | null }
  webhook?: { endpoint: string; active: boolean; matches: boolean } | null
  quota?: { limit: number | null; used: number | null }
  has_channel_secret?: boolean
}
interface LineGroup {
  group_id: string
  group_name: string | null
  branch_id: string | null
  branch_name: string | null
  linked_at: string
}

const EVENTS = [
  { key: 'NEW_BOOKING', label: 'มีการจองใหม่', hint: 'ลูกค้าจองผ่านเว็บหรือ LINE' },
  { key: 'DEPOSIT_SLIP', label: 'ลูกค้าส่งสลิปมัดจำ', hint: 'รอพนักงานตรวจสลิป' },
  { key: 'BOOKING_CANCELLED', label: 'ลูกค้ายกเลิกการจอง', hint: 'ยกเลิกเองจากลิงก์ติดตาม' },
  { key: 'WALK_IN', label: 'รับลูกค้าหน้าร้าน', hint: 'เกิดบ่อย ใช้โควตามาก' },
  { key: 'SERVICE_DONE', label: 'บริการเสร็จ', hint: 'เกิดบ่อย ใช้โควตามาก' },
] as const
type EventKey = (typeof EVENTS)[number]['key']
const REMINDER_ITEMS = [
  { value: 30, title: '30 นาที' },
  { value: 60, title: '1 ชั่วโมง' },
  { value: 120, title: '2 ชั่วโมง' },
  { value: 180, title: '3 ชั่วโมง' },
  { value: 360, title: '6 ชั่วโมง' },
  { value: 1440, title: '1 วัน' },
]

const supabase = useSupabaseClient()
const { call } = useEdgeFunction()
const { company, branches } = useAccess()
const { confirm } = useDialog()
const companyId = computed(() => company.value?.company_id ?? '')

const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)
const settings = ref<LineSettings | null>(null)
const cfg = ref({
  login_channel_id: '',
  liff_id: '',
  add_friend_url: '',
  customer_url: '',
  staff_url: '',
  confirm_enabled: true,
  reminder_enabled: true,
  reminder_minutes: 120,
  events: {} as Record<string, boolean>,
})
const saving = ref(false)
// มีการแก้ที่ยังไม่บันทึก → แถบบันทึกลอยด้านล่าง (มือถืออยู่เหนือเมนูล่าง)
const snapshot = ref('')
const dirty = computed(() => !!settings.value && JSON.stringify(cfg.value) !== snapshot.value)
function resetCfg() {
  Object.assign(cfg.value, JSON.parse(snapshot.value))
}

// ---------------------------------------------------------------- โหลด / บันทึก
async function loadSettings() {
  if (!companyId.value) return
  const { data, error } = await supabase.rpc('line_settings_get', { p_company_id: companyId.value })
  if (error) {
    message.value = { type: 'error', text: 'โหลดการตั้งค่า LINE ไม่สำเร็จ ลองรีเฟรชหน้า' }
    return
  }
  const s = data as unknown as LineSettings
  settings.value = s
  Object.assign(cfg.value, {
    login_channel_id: s.login_channel_id ?? '',
    liff_id: s.liff_id ?? '',
    add_friend_url: s.add_friend_url ?? '',
    customer_url: s.customer_url ?? '',
    staff_url: s.staff_url ?? (import.meta.client ? location.origin : ''),
    confirm_enabled: s.confirm_enabled,
    reminder_enabled: s.reminder_enabled,
    reminder_minutes: s.reminder_minutes,
    events: Object.fromEntries(EVENTS.map((e) => [e.key, s.group_events.includes(e.key)])),
  })
  snapshot.value = JSON.stringify(cfg.value)
}

async function save(successText = 'บันทึกแล้ว') {
  if (!companyId.value) return false
  saving.value = true
  const { error } = await supabase.rpc('line_settings_save', {
    p_company_id: companyId.value,
    p: {
      login_channel_id: cfg.value.login_channel_id,
      liff_id: cfg.value.liff_id,
      add_friend_url: cfg.value.add_friend_url,
      customer_url: cfg.value.customer_url,
      staff_url: cfg.value.staff_url,
      confirm_enabled: cfg.value.confirm_enabled,
      reminder_enabled: cfg.value.reminder_enabled,
      reminder_minutes: Number(cfg.value.reminder_minutes),
      group_events: EVENTS.filter((e) => cfg.value.events[e.key]).map((e) => e.key),
    },
  })
  saving.value = false
  if (error) {
    message.value = { type: 'error', text: error.message || 'บันทึกไม่สำเร็จ' }
    return false
  }
  toast.success(successText)
  await loadSettings()
  return true
}

// ---------------------------------------------------------------- ขั้นที่ 1–2: บัญชี + Webhook
const cred = reactive({ token: '', secret: '' })
const savingCred = ref(false)
const check = ref<CheckResult | null>(null)
const checking = ref(false)
const settingWebhook = ref(false)
const editingCred = ref(false)

async function runCheck() {
  if (!companyId.value || !settings.value?.has_access_token) {
    check.value = null
    return
  }
  checking.value = true
  try {
    check.value = await call<CheckResult>('line-admin', { company_id: companyId.value, action: 'check' })
    if (check.value.token_valid) await loadSettings() // ชื่อบอท / ลิงก์เพิ่มเพื่อนที่ระบบเติมให้
  } catch (e) {
    message.value = { type: 'error', text: edgeErrorText(e, 'ตรวจการเชื่อมต่อ LINE ไม่สำเร็จ') }
  } finally {
    checking.value = false
  }
}

async function saveCredentials() {
  if (!companyId.value || (!cred.token.trim() && !cred.secret.trim())) return
  savingCred.value = true
  const { error } = await supabase.rpc('line_set_credentials', {
    p_company_id: companyId.value,
    p_access_token: cred.token.trim() || null,
    p_channel_secret: cred.secret.trim() || null,
  })
  savingCred.value = false
  if (error) {
    message.value = { type: 'error', text: error.message || 'บันทึกไม่สำเร็จ' }
    return
  }
  cred.token = ''
  cred.secret = ''
  editingCred.value = false
  await loadSettings()
  await runCheck()
  if (check.value?.token_valid) toast.success(`เชื่อมกับ ${check.value.bot?.name ?? 'LINE OA'} แล้ว`)
  else if (check.value?.configured) message.value = { type: 'error', text: 'LINE ไม่รับ Channel access token นี้ ตรวจว่าคัดลอกครบและเป็นแบบ long-lived' }
  openStep.value = undefined
}

async function disconnect() {
  if (!companyId.value) return
  const ok = await confirm({
    title: 'ยกเลิกการเชื่อมบัญชี LINE OA?',
    description: 'ระบบจะลบ Channel access token และ Channel secret และหยุดส่งข้อความทาง LINE ทั้งหมด กลุ่มที่เชื่อมไว้ยังอยู่',
    confirmText: 'ยกเลิกการเชื่อม',
    destructive: true,
  })
  if (!ok) return
  const { error } = await supabase.rpc('line_set_credentials', { p_company_id: companyId.value, p_access_token: '', p_channel_secret: '' })
  if (error) {
    message.value = { type: 'error', text: 'ยกเลิกไม่สำเร็จ' }
    return
  }
  check.value = null
  toast.success('ยกเลิกการเชื่อมบัญชีแล้ว')
  await loadSettings()
  openStep.value = undefined
}

async function setupWebhook() {
  settingWebhook.value = true
  message.value = null
  try {
    const r = await call<{ ok: boolean; step: string; status?: number; active?: boolean | null; test?: { reason?: string; statusCode?: number } }>(
      'line-admin',
      { company_id: companyId.value, action: 'setup_webhook' },
    )
    if (r.ok && r.active !== false) toast.success('LINE ส่งข้อความมาที่ระบบได้แล้ว')
    else if (r.ok) message.value = { type: 'error', text: 'อีกขั้นเดียว: เปิด “Use webhook” ใน LINE Developers Console แท็บ Messaging API แล้วกดตรวจสถานะ' }
    else if (r.step === 'set') message.value = { type: 'error', text: `ตั้งค่าไม่สำเร็จ (LINE ตอบ ${r.status}) ตรวจ Channel access token ในขั้นที่ 1` }
    else
      message.value = {
        type: 'error',
        text: r.test?.statusCode === 401 ? 'Channel secret ไม่ถูกต้อง แก้ในขั้นที่ 1 แล้วลองอีกครั้ง' : `LINE ทดสอบไม่ผ่าน: ${r.test?.reason ?? 'ไม่ทราบสาเหตุ'}`,
      }
    await runCheck()
    openStep.value = undefined
  } catch (e) {
    message.value = { type: 'error', text: edgeErrorText(e, 'ตั้งค่าไม่สำเร็จ') }
  } finally {
    settingWebhook.value = false
  }
}

// ---------------------------------------------------------------- ขั้นที่ 3: กลุ่ม LINE
const groups = ref<LineGroup[]>([])
const groupsLoaded = ref(false)
const ALL = '__all__'
const branchChoice = ref<string>(ALL)
const branchItems = computed(() => [{ branch_id: ALL, name: 'ทุกสาขา' }, ...branches.value])
const code = ref<{ code: string; expires_at: string } | null>(null)
const creating = ref(false)
const testing = ref<string | null>(null)
const command = computed(() => (code.value ? `เชื่อมร้าน ${code.value.code}` : ''))

async function loadGroups() {
  if (!companyId.value) return
  const { data, error } = await supabase.rpc('line_groups_list', { p_company_id: companyId.value })
  groupsLoaded.value = true
  if (error) return
  const before = groups.value.length
  groups.value = (data ?? []) as unknown as LineGroup[]
  if (code.value && groups.value.length > before) {
    code.value = null
    toast.success('เชื่อมกลุ่มแล้ว')
  }
}

async function createCode() {
  if (!companyId.value) return
  creating.value = true
  const { data, error } = await supabase.rpc('line_create_link_code', {
    p_company_id: companyId.value,
    p_branch_id: branchChoice.value === ALL ? null : branchChoice.value,
  })
  creating.value = false
  if (error) {
    message.value = { type: 'error', text: error.message || 'สร้างรหัสไม่สำเร็จ' }
    return
  }
  code.value = data as unknown as { code: string; expires_at: string }
}

async function testGroup(g: LineGroup) {
  testing.value = g.group_id
  try {
    const r = await call<{ ok: boolean; status: number }>('line-admin', { company_id: companyId.value, action: 'test_group', group_id: g.group_id })
    if (r.ok) toast.success(`ส่งข้อความทดสอบเข้า “${g.group_name ?? 'กลุ่ม'}” แล้ว`)
    else toast.error(r.status === 429 ? 'ส่งไม่ได้: โควตาข้อความเดือนนี้หมดแล้ว' : `ส่งไม่สำเร็จ (LINE ตอบ ${r.status})`)
  } catch (e) {
    toast.error(edgeErrorText(e, 'ส่งไม่สำเร็จ'))
  } finally {
    testing.value = null
  }
}

async function unlink(g: LineGroup) {
  const ok = await confirm({
    title: `หยุดส่งเข้ากลุ่ม “${g.group_name ?? 'กลุ่ม LINE'}”?`,
    description: 'บอทยังอยู่ในกลุ่ม ถ้าไม่ใช้แล้วนำออกเองใน LINE ได้',
    confirmText: 'หยุดส่ง',
    destructive: true,
  })
  if (!ok) return
  const { error } = await supabase.rpc('line_unlink_group', { p_company_id: companyId.value, p_group_id: g.group_id })
  if (error) {
    message.value = { type: 'error', text: 'หยุดส่งไม่สำเร็จ' }
    return
  }
  toast.success('หยุดส่งเข้ากลุ่มนี้แล้ว')
  await loadGroups()
}

// ระหว่างรอให้พิมพ์รหัสในกลุ่ม → เช็กทุก 5 วินาทีว่าเชื่อมสำเร็จหรือยัง
const { pause, resume } = useIntervalFn(loadGroups, 5000, { immediate: false })
watch(code, (c) => (c ? resume() : pause()))

// ---------------------------------------------------------------- ขั้นตอน
const account = computed(() =>
  check.value?.token_valid && check.value.bot
    ? check.value.bot
    : settings.value?.bot_name
      ? { name: settings.value.bot_name, basic_id: settings.value.bot_basic_id ?? '', picture_url: null }
      : null,
)
const baseCustomerUrl = computed(() => cfg.value.customer_url.trim().replace(/\/+$/, ''))
const liffEndpoint = computed(() => baseCustomerUrl.value)
const liffLink = computed(() => (cfg.value.liff_id.trim() ? `https://liff.line.me/${cfg.value.liff_id.trim()}/book` : ''))

type StepState = 'done' | 'todo' | 'locked'
const steps = computed(() => {
  const s = settings.value
  const accountDone = !!s?.has_access_token && !!s?.has_channel_secret && check.value?.token_valid !== false && (!!check.value?.token_valid || !!s?.bot_name)
  const webhookDone = !!check.value?.webhook?.matches && !!check.value.webhook.active
  const groupsDone = groups.value.length > 0
  const liffDone = !!s?.has_access_token && !!s?.login_channel_id && !!s?.liff_id
  const st = (done: boolean, ready: boolean): StepState => (done ? 'done' : ready ? 'todo' : 'locked')
  return [
    {
      title: 'เชื่อมบัญชี LINE OA',
      state: st(accountDone, true),
      summary: account.value ? `${account.value.name} ${account.value.basic_id}` : 'ยังไม่ได้เชื่อม',
    },
    {
      title: 'ให้ LINE ส่งข้อความมาที่ระบบ',
      state: st(webhookDone, accountDone),
      summary: webhookDone ? 'พร้อมแล้ว' : check.value?.webhook?.matches ? 'ยังไม่ได้เปิด Use webhook' : 'ต้องใช้ตอนเชื่อมกลุ่มพนักงาน',
    },
    {
      title: 'เชื่อมกลุ่ม LINE ของพนักงาน',
      state: st(groupsDone, webhookDone),
      summary: groupsDone ? `${groups.value.length} กลุ่ม` : 'ยังไม่มีกลุ่ม',
    },
    {
      title: 'ให้ลูกค้าจองผ่าน LINE',
      state: st(liffDone, accountDone),
      summary: liffDone ? 'จองใน LINE หรือกดเชื่อม LINE ในหน้าสถานะการจอง' : 'ไม่บังคับ',
    },
  ]
})
// undefined = เปิดขั้นแรกที่ยังไม่เสร็จให้อัตโนมัติ · null = ปิดทั้งหมด
const openStep = ref<number | null | undefined>(undefined)
const activeStep = computed(() => (openStep.value === undefined ? steps.value.findIndex((s) => s.state === 'todo') : openStep.value))
function toggleStep(i: number) {
  if (steps.value[i]!.state === 'locked') return
  openStep.value = activeStep.value === i ? null : i
}

// ---------------------------------------------------------------- ตัวอย่างข้อความ
type PreviewKind = 'group' | 'confirm' | 'reminder'
const preview = ref<PreviewKind>('group')
const previewItems = [
  { value: 'group', label: 'ถึงกลุ่ม' },
  { value: 'confirm', label: 'ยืนยันจอง' },
  { value: 'reminder', label: 'เตือนนัด' },
]
const TH_DAYS = ['อาทิตย์', 'จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์']
const TH_MONTHS = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.']
const sampleDate = new Date(Date.now() + 86_400_000)
const sampleDay = `วัน${TH_DAYS[sampleDate.getDay()]}ที่ ${sampleDate.getDate()} ${TH_MONTHS[sampleDate.getMonth()]} เวลา 14:00 น.`
const sampleShort = `${String(sampleDate.getDate()).padStart(2, '0')}/${String(sampleDate.getMonth() + 1).padStart(2, '0')} 14:00`
const sampleBranch = computed(() => branches.value[0]?.name ?? 'สาขาหลัก')
const firstEvent = computed<EventKey | null>(() => EVENTS.find((e) => cfg.value.events[e.key])?.key ?? null)
const reminderLabel = computed(() => REMINDER_ITEMS.find((r) => r.value === Number(cfg.value.reminder_minutes))?.title ?? '')

const previewText = computed<string | null>(() => {
  const staff = cfg.value.staff_url.trim().replace(/\/+$/, '')
  const site = baseCustomerUrl.value
  if (preview.value === 'group') {
    const e = firstEvent.value
    if (!e) return null
    const lines: Record<EventKey, [string, string, string]> = {
      NEW_BOOKING: ['การจองใหม่', `คุณสมใจ · ${sampleShort} น. · 2 คน · ฿900`, '/bookings'],
      DEPOSIT_SLIP: ['ลูกค้าส่งสลิปมัดจำ', `คุณสมใจ โอน ฿200 · นัด ${sampleShort} น. · รอตรวจสลิป`, '/bookings'],
      BOOKING_CANCELLED: ['ลูกค้ายกเลิกการจอง', `คุณสมใจ · นัด ${sampleShort} น.`, '/bookings'],
      WALK_IN: ['รับลูกค้าหน้าร้าน', '1 คน · นวดไทย 60 นาที', '/queue'],
      SERVICE_DONE: ['บริการเสร็จแล้ว', 'คิว 012 · นวดไทย 60 นาที · หมอแนน · รอชำระเงิน', '/payments'],
    }
    const [title, body, path] = lines[e]
    return `🔔 ${title} · ${sampleBranch.value}\n${body}${staff ? `\n${staff}${path}` : ''}`
  }
  if (preview.value === 'confirm') {
    if (!cfg.value.confirm_enabled) return null
    return `✅ ได้รับการจองแล้ว\nคุณสมใจ ขอบคุณที่จองกับเรา\n\n📍 ${sampleBranch.value}\n🗓 ${sampleDay}\n• นวดไทย 60 นาที\n• นวดเท้า 60 นาที\n\nรวม 2 คน · ฿900${
      site ? `\n\nดูสถานะ · ชำระมัดจำ · ยกเลิก\n${site}/t/…` : ''
    }`
  }
  if (!cfg.value.reminder_enabled) return null
  return `⏰ แจ้งเตือนนัดหมาย\nคุณสมใจ มีนัดนวดกับเราเร็ว ๆ นี้\n\n📍 ${sampleBranch.value}\n🗓 ${sampleDay}\n• นวดไทย 60 นาที\n\nกรุณามาก่อนเวลาประมาณ 10 นาที ถ้ามาไม่ได้รบกวนแจ้งร้านล่วงหน้า${
    site ? `\n\nตรวจสอบการจอง ${site}/check-booking` : ''
  }`
})
const previewEmpty = computed(() =>
  preview.value === 'group'
    ? 'ยังไม่ได้เลือกเหตุการณ์ กลุ่มพนักงานจะไม่ได้รับข้อความ'
    : preview.value === 'confirm'
      ? 'ปิดข้อความยืนยันการจองอยู่'
      : 'ปิดการเตือนนัดอยู่',
)
const previewWhen = computed(() =>
  preview.value === 'group'
    ? `ตัวอย่างเมื่อ${EVENTS.find((e) => e.key === firstEvent.value)?.label ?? ''}`
    : preview.value === 'confirm'
      ? 'ส่งทันทีหลังลูกค้าจองผ่าน LINE'
      : `ส่งก่อนถึงนัด ${reminderLabel.value}`,
)
// แยกบรรทัดที่เป็นลิงก์ ให้แสดงเหมือนลิงก์ใน LINE
const previewLines = computed(() => (previewText.value ?? '').split('\n').map((l) => ({ text: l, link: /https?:\/\//.test(l) })))

// ---------------------------------------------------------------- ตัวช่วย
const fmt = (v: string) => new Date(v).toLocaleString('th-TH', { timeZone: 'Asia/Bangkok', dateStyle: 'medium', timeStyle: 'short' })
const quotaPct = computed(() => {
  const q = check.value?.quota
  return q?.limit && q.used !== null ? Math.min(100, Math.round((q.used / q.limit) * 100)) : null
})

async function copy(text: string) {
  try {
    await navigator.clipboard.writeText(text)
    toast.success('คัดลอกแล้ว')
  } catch {
    toast.error('คัดลอกไม่สำเร็จ')
  }
}

async function loadAll() {
  if (!companyId.value) return
  await Promise.all([loadSettings(), loadGroups()])
  await runCheck()
}
onMounted(loadAll)
watch(companyId, loadAll)
</script>

<template>
  <div class="max-w-5xl">
    <PageHeader title="LINE OA" description="แจ้งเตือนพนักงานในกลุ่ม LINE และส่งยืนยันการจองกับเตือนนัดให้ลูกค้า">
      <template #actions>
        <Button variant="outline" :disabled="checking || !settings?.has_access_token" @click="runCheck">
          <RefreshCw :class="checking ? 'animate-spin' : ''" /> ตรวจสถานะ
        </Button>
      </template>
    </PageHeader>
    <MessageAlert :message="message" class="mb-6" @close="message = null" />

    <div v-if="settings && groupsLoaded" class="grid gap-10">
      <!-- บัญชีที่เชื่อม -->
      <div v-if="account" class="flex flex-wrap items-center gap-x-6 gap-y-4 rounded-[18px] border border-border bg-card px-4 py-4 sm:px-5">
        <div class="flex min-w-0 items-center gap-3">
          <img v-if="account.picture_url" :src="account.picture_url" alt="" class="size-12 shrink-0 rounded-full border border-border" />
          <span v-else class="grid size-12 shrink-0 place-items-center rounded-full bg-secondary text-lg font-semibold text-heading" aria-hidden="true">{{ account.name.slice(0, 1) }}</span>
          <div class="grid min-w-0">
            <span class="truncate text-lg font-semibold text-heading">{{ account.name }}</span>
            <span class="num text-sm text-muted-foreground">{{ account.basic_id }}</span>
          </div>
        </div>
        <div v-if="check?.quota && check.quota.used !== null" class="grid w-full gap-1.5 sm:ml-auto sm:w-72">
          <div class="flex items-baseline justify-between gap-3 text-sm">
            <span class="text-muted-foreground">ส่งเดือนนี้</span>
            <span class="num text-heading">
              <span class="font-semibold">{{ check.quota.used.toLocaleString() }}</span>
              <template v-if="check.quota.limit !== null"> / {{ check.quota.limit.toLocaleString() }} ข้อความ</template>
              <template v-else> ข้อความ</template>
            </span>
          </div>
          <div v-if="quotaPct !== null" class="h-1.5 overflow-hidden rounded-full bg-muted" role="progressbar" :aria-valuenow="quotaPct" aria-valuemin="0" aria-valuemax="100" aria-label="โควตาข้อความเดือนนี้">
            <div class="h-full rounded-full" :class="quotaPct >= 90 ? 'bg-danger' : quotaPct >= 70 ? 'bg-brand-accent' : 'bg-success'" :style="{ width: `${quotaPct}%` }" />
          </div>
        </div>
      </div>

      <!-- ขั้นตอนตั้งค่า -->
      <section aria-labelledby="s-setup">
        <h2 id="s-setup" class="m-0 mb-4 text-xl font-semibold text-heading">ตั้งค่าให้พร้อมใช้</h2>
        <ol class="m-0 grid list-none rounded-[18px] border border-border bg-card p-0">
          <li v-for="(s, i) in steps" :key="s.title" class="relative border-border px-4 py-4 sm:px-5 [&:not(:last-child)]:border-b">
            <button
              type="button"
              class="flex w-full items-center gap-4 rounded-lg text-left focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none disabled:cursor-not-allowed"
              :aria-expanded="activeStep === i"
              :aria-controls="`step-${i}`"
              :disabled="s.state === 'locked'"
              @click="toggleStep(i)"
            >
              <span
                class="grid size-8 shrink-0 place-items-center rounded-full text-sm font-semibold"
                :class="s.state === 'done' ? 'bg-success-soft text-success-ink' : s.state === 'todo' ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground'"
              >
                <Check v-if="s.state === 'done'" class="size-4" aria-label="เสร็จแล้ว" />
                <Lock v-else-if="s.state === 'locked'" class="size-3.5" aria-label="ทำขั้นก่อนหน้าก่อน" />
                <span v-else class="num">{{ i + 1 }}</span>
              </span>
              <span class="grid min-w-0 flex-1 gap-0.5 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-baseline sm:gap-4">
                <span class="text-title font-semibold" :class="s.state === 'locked' ? 'text-muted-foreground' : 'text-heading'">{{ s.title }}</span>
                <span class="truncate text-sm" :class="s.state === 'done' ? 'text-success-ink' : 'text-muted-foreground'">{{ s.summary }}</span>
              </span>
              <ChevronDown v-if="s.state !== 'locked'" class="size-4 shrink-0 text-muted-foreground transition-transform motion-reduce:transition-none" :class="activeStep === i ? 'rotate-180' : ''" aria-hidden="true" />
            </button>

            <div v-if="activeStep === i" :id="`step-${i}`" class="mt-4 grid gap-4 sm:pl-12">
              <!-- 1. บัญชี -->
              <template v-if="i === 0">
                <p class="m-0 max-w-[68ch] text-[15px] text-muted-foreground">
                  ที่ developers.line.biz เลือก channel ของ LINE OA ร้าน คัดลอก Channel secret จากแท็บ Basic settings
                  และกด Issue ที่ Channel access token (long-lived) ในแท็บ Messaging API
                </p>
                <form v-if="!settings.has_access_token || editingCred" class="grid max-w-xl gap-3" @submit.prevent="saveCredentials">
                  <TextField
                    v-model="cred.token"
                    label="Channel access token"
                    type="password"
                    autocomplete="off"
                    :placeholder="settings.has_access_token ? `ตอนนี้ลงท้าย …${settings.access_token_hint} เว้นว่างถ้าไม่เปลี่ยน` : 'วาง token'"
                  />
                  <TextField
                    v-model="cred.secret"
                    label="Channel secret"
                    type="password"
                    autocomplete="off"
                    :placeholder="settings.has_channel_secret ? 'ตั้งไว้แล้ว เว้นว่างถ้าไม่เปลี่ยน' : 'ตัวอักษร 32 ตัว'"
                  />
                  <p class="m-0 text-sm text-muted-foreground">ระบบเก็บสองค่านี้แบบเข้ารหัส และจะไม่แสดงกลับในหน้านี้</p>
                  <div class="flex flex-wrap gap-2">
                    <Button type="submit" :disabled="savingCred || (!cred.token.trim() && !cred.secret.trim())">{{ savingCred ? 'กำลังเชื่อม…' : 'เชื่อมบัญชี' }}</Button>
                    <Button v-if="editingCred" type="button" variant="ghost" @click="editingCred = false">ยกเลิก</Button>
                  </div>
                </form>
                <div v-else class="flex flex-wrap gap-2">
                  <Button variant="outline" @click="editingCred = true">เปลี่ยน token หรือ secret</Button>
                  <Button variant="ghost" class="text-danger-ink" @click="disconnect">ยกเลิกการเชื่อม</Button>
                </div>
              </template>

              <!-- 2. Webhook -->
              <template v-else-if="i === 1">
                <p class="m-0 max-w-[68ch] text-[15px] text-muted-foreground">
                  ระบบจะตั้งค่าที่ LINE ให้ แล้วให้ LINE ลองส่งข้อความทดสอบมา ถ้าผ่านแปลว่าบอทอ่านคำสั่งในกลุ่มได้
                </p>
                <p v-if="check?.webhook?.matches && !check.webhook.active" class="m-0 max-w-[68ch] rounded-lg bg-pending-soft px-3 py-2 text-[15px] text-pending-ink">
                  ตั้งค่าแล้ว เหลือเปิดสวิตช์ “Use webhook” ใน LINE Developers Console แท็บ Messaging API แล้วกดตรวจสถานะ
                </p>
                <div class="flex flex-wrap gap-2">
                  <Button :disabled="settingWebhook" @click="setupWebhook">{{ settingWebhook ? 'กำลังตั้งค่า…' : 'ตั้งค่าและทดสอบ' }}</Button>
                </div>
                <details class="max-w-xl text-sm text-muted-foreground">
                  <summary class="cursor-pointer select-none text-heading">ตั้งเองใน LINE Developers Console</summary>
                  <div class="mt-2 grid gap-1.5">
                    <span>วาง URL นี้ในช่อง Webhook URL แท็บ Messaging API</span>
                    <div class="flex items-center gap-2">
                      <code class="min-w-0 flex-1 truncate rounded-md bg-muted px-3 py-2">{{ settings.webhook_url }}</code>
                      <Button variant="outline" size="sm" @click="copy(settings.webhook_url)"><Copy /><span class="max-sm:sr-only">คัดลอก</span></Button>
                    </div>
                  </div>
                </details>
              </template>

              <!-- 3. กลุ่ม -->
              <template v-else-if="i === 2">
                <div class="grid gap-5 lg:grid-cols-[minmax(0,5fr)_minmax(0,6fr)]">
                  <div class="grid content-start gap-3">
                    <ol class="m-0 grid gap-1 pl-5 text-[15px] text-heading">
                      <li>เลือกสาขาแล้วสร้างรหัส</li>
                      <li>เชิญ LINE OA ร้านเข้ากลุ่มพนักงาน</li>
                      <li>พิมพ์คำสั่งที่ได้ในกลุ่ม</li>
                    </ol>
                    <form class="grid items-end gap-3 sm:grid-cols-[1fr_auto]" @submit.prevent="createCode">
                      <SelectField v-model="branchChoice" :items="branchItems" item-title="name" item-value="branch_id" label="ส่งเรื่องของ" />
                      <Button type="submit" :variant="code ? 'outline' : 'default'" :disabled="creating">{{ code ? 'สร้างใหม่' : 'สร้างรหัส' }}</Button>
                    </form>
                    <div v-if="code" class="grid gap-2 rounded-[14px] bg-secondary p-4">
                      <span class="text-sm text-muted-foreground">พิมพ์ในกลุ่ม ใช้ได้ครั้งเดียวถึง {{ fmt(code.expires_at) }}</span>
                      <div class="flex flex-wrap items-center gap-2">
                        <span class="num min-w-0 flex-1 text-xl font-semibold tracking-wide text-heading sm:text-2xl">{{ command }}</span>
                        <Button variant="outline" size="sm" class="bg-card" @click="copy(command)"><Copy /><span class="max-sm:sr-only">คัดลอก</span></Button>
                      </div>
                      <span class="flex items-center gap-1.5 text-sm text-muted-foreground"><RefreshCw class="size-3.5 animate-spin motion-reduce:animate-none" /> รอให้พิมพ์ในกลุ่ม</span>
                    </div>
                    <p class="m-0 text-sm text-muted-foreground">เชิญบอทไม่ได้? เปิด “อนุญาตให้เข้าร่วมแชทกลุ่ม” ใน LINE OA Manager ที่การตั้งค่าบัญชี</p>
                  </div>

                  <div class="grid content-start gap-2">
                    <span class="text-sm font-medium text-heading">กลุ่มที่รับข้อความ</span>
                    <ul v-if="groups.length" class="m-0 grid list-none divide-y divide-border rounded-[14px] border border-border p-0">
                      <li v-for="g in groups" :key="g.group_id" class="flex flex-wrap items-center gap-x-3 gap-y-1 px-4 py-3">
                        <div class="grid min-w-0 flex-1">
                          <span class="truncate font-medium text-heading">{{ g.group_name || 'กลุ่ม LINE' }}</span>
                          <span class="text-sm text-muted-foreground">{{ g.branch_name ? `สาขา${g.branch_name}` : 'ทุกสาขา' }}</span>
                        </div>
                        <div class="-ml-2 flex gap-1 sm:ml-0">
                          <Button variant="ghost" size="sm" :disabled="testing === g.group_id" @click="testGroup(g)"><Send /> ส่งทดสอบ</Button>
                          <Button variant="ghost" size="sm" class="text-danger-ink" @click="unlink(g)">หยุดส่ง</Button>
                        </div>
                      </li>
                    </ul>
                    <p v-else class="m-0 rounded-[14px] border border-dashed border-border px-4 py-6 text-center text-[15px] text-muted-foreground">
                      สร้างรหัสทางซ้าย แล้วกลุ่มจะขึ้นที่นี่ทันทีที่เชื่อมสำเร็จ
                    </p>
                  </div>
                </div>
              </template>

              <!-- 4. LIFF -->
              <form v-else class="grid gap-4" @submit.prevent="save()">
                <p class="m-0 max-w-[68ch] text-[15px] text-muted-foreground">
                  ที่ developers.line.biz สร้าง LINE Login channel ใน provider เดียวกัน ตั้ง Linked OA เป็นบัญชีร้าน
                  แล้วเพิ่ม LIFF แบบ Full เลือก scope openid และ profile เปิด Add friend option แล้วกด Publish
                </p>
                <div class="grid max-w-2xl gap-4 sm:grid-cols-2">
                  <TextField v-model="cfg.login_channel_id" label="LINE Login Channel ID" numeric="digits" inputmode="numeric" placeholder="2001234567" />
                  <TextField v-model="cfg.liff_id" label="LIFF ID" placeholder="2001234567-AbCdEfGh" />
                  <TextField v-model="cfg.customer_url" label="เว็บจองของร้าน" placeholder="https://…" hint="ใช้ทำลิงก์ในข้อความถึงลูกค้า" />
                  <TextField v-model="cfg.add_friend_url" label="ลิงก์เพิ่มเพื่อน" placeholder="https://lin.ee/…" hint="เว้นว่างได้ ระบบเติมให้" />
                </div>
                <dl v-if="liffEndpoint || liffLink" class="m-0 grid max-w-2xl gap-3">
                  <div v-if="liffEndpoint" class="grid gap-1.5">
                    <dt class="text-sm text-muted-foreground">Endpoint URL ตอนสร้าง LIFF</dt>
                    <dd class="m-0 flex items-center gap-2">
                      <code class="min-w-0 flex-1 truncate rounded-md bg-muted px-3 py-2 text-sm">{{ liffEndpoint }}</code>
                      <Button type="button" variant="outline" size="sm" @click="copy(liffEndpoint)"><Copy /><span class="max-sm:sr-only">คัดลอก</span></Button>
                    </dd>
                  </div>
                  <div v-if="liffLink" class="grid gap-1.5">
                    <dt class="text-sm text-muted-foreground">ลิงก์ปุ่ม “จองคิว” ใน Rich Menu</dt>
                    <dd class="m-0 flex items-center gap-2">
                      <code class="min-w-0 flex-1 truncate rounded-md bg-muted px-3 py-2 text-sm">{{ liffLink }}</code>
                      <Button type="button" variant="outline" size="sm" @click="copy(liffLink)"><Copy /><span class="max-sm:sr-only">คัดลอก</span></Button>
                    </dd>
                  </div>
                </dl>
              </form>
            </div>
          </li>
        </ol>
      </section>

      <!-- สิ่งที่ส่ง + ตัวอย่าง -->
      <section aria-labelledby="s-send">
        <h2 id="s-send" class="m-0 mb-4 text-xl font-semibold text-heading">ข้อความที่ส่งทาง LINE</h2>
        <form class="grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_360px]" @submit.prevent="save()">
          <div class="grid gap-6 rounded-[18px] border border-border bg-card p-4 sm:p-5">
            <fieldset class="m-0 grid gap-3 border-0 p-0" @focusin="preview = 'group'">
              <legend class="mb-1 p-0 font-semibold text-heading">ถึงกลุ่มพนักงาน</legend>
              <p class="m-0 -mt-1 text-sm text-muted-foreground">นับโควตาตามจำนวนคนในกลุ่ม ส่งเข้ากลุ่ม 5 คนนับเป็น 5 ข้อความ</p>
              <div class="grid gap-x-6 gap-y-3 sm:grid-cols-2">
                <CheckboxField v-for="e in EVENTS" :key="e.key" v-model="cfg.events[e.key]">
                  <span class="text-heading">{{ e.label }}</span>
                  <span class="block text-sm text-muted-foreground">{{ e.hint }}</span>
                </CheckboxField>
              </div>
            </fieldset>

            <fieldset class="m-0 grid gap-4 border-0 border-t border-border p-0 pt-6" @focusin="preview === 'group' && (preview = 'confirm')">
              <legend class="sr-only">ถึงลูกค้า</legend>
              <p class="m-0 font-semibold text-heading">ถึงลูกค้าที่จองผ่าน LINE</p>
              <SwitchField v-model="cfg.confirm_enabled" label="ยืนยันการจอง" hint="พร้อมลิงก์ดูสถานะ ชำระมัดจำ และยกเลิก" @click="preview = 'confirm'" />
              <SwitchField v-model="cfg.reminder_enabled" label="เตือนก่อนถึงนัด" hint="ไม่เตือนการจองที่ยังไม่ชำระมัดจำ" @click="preview = 'reminder'" />
              <SelectField v-if="cfg.reminder_enabled" v-model="cfg.reminder_minutes" :items="REMINDER_ITEMS" item-title="title" item-value="value" label="เตือนล่วงหน้า" class="sm:max-w-xs" />
            </fieldset>

            <details class="border-t border-border pt-4 text-sm">
              <summary class="cursor-pointer select-none text-heading">ลิงก์ในข้อความ</summary>
              <div class="mt-3 grid gap-4 sm:grid-cols-2">
                <TextField v-model="cfg.staff_url" label="แอปพนักงาน" hint="แนบในข้อความถึงกลุ่ม" />
                <TextField v-model="cfg.customer_url" label="เว็บจองของร้าน" hint="แนบในข้อความถึงลูกค้า" />
              </div>
            </details>
          </div>

          <!-- ตัวอย่างข้อความ: หน้าตาเหมือนแชท LINE -->
          <aside class="grid gap-3 lg:sticky lg:top-24" aria-label="ตัวอย่างข้อความ">
            <SegmentedControl v-model="preview" :items="previewItems" label="ดูตัวอย่าง" class="w-full flex-nowrap [&>button]:flex-1 [&>button]:px-2" />
            <div class="grid min-h-64 content-start gap-2 rounded-[18px] bg-secondary p-3 sm:p-4 lg:min-h-80">
              <span class="justify-self-center rounded-full bg-card/70 px-3 py-0.5 text-xs text-muted-foreground">{{ previewWhen }}</span>
              <div v-if="previewText" class="mt-2 flex items-start gap-2.5">
                <img v-if="account?.picture_url" :src="account.picture_url" alt="" class="size-9 shrink-0 rounded-full" />
                <span v-else class="grid size-9 shrink-0 place-items-center rounded-full bg-card text-sm font-semibold text-heading" aria-hidden="true">{{ (account?.name ?? 'L').slice(0, 1) }}</span>
                <div class="grid min-w-0 gap-1">
                  <span class="text-xs text-muted-foreground">{{ account?.name ?? 'LINE OA ของร้าน' }}</span>
                  <p class="m-0 rounded-[18px] rounded-tl-md bg-card px-3.5 py-2.5 text-sm leading-relaxed text-foreground shadow-[0_1px_2px_rgba(81,67,55,.06)]">
                    <template v-for="(l, k) in previewLines" :key="k">
                      <span v-if="l.link" class="break-all text-primary underline underline-offset-2">{{ l.text }}</span>
                      <template v-else>{{ l.text }}</template>
                      <br v-if="k < previewLines.length - 1" />
                    </template>
                  </p>
                </div>
              </div>
              <p v-else class="m-0 mt-10 text-center text-[15px] text-muted-foreground">{{ previewEmpty }}</p>
            </div>
            <p class="m-0 text-sm text-muted-foreground">ข้อมูลในตัวอย่างเป็นข้อมูลสมมติ ข้อความจริงใช้ชื่อ เวลา และบริการของการจองนั้น</p>
          </aside>
        </form>
      </section>

      <Transition
        enter-active-class="transition duration-200 ease-out motion-reduce:transition-none"
        enter-from-class="translate-y-3 opacity-0"
        leave-active-class="transition duration-150 ease-in motion-reduce:transition-none"
        leave-to-class="translate-y-3 opacity-0"
      >
        <div
          v-if="dirty"
          class="sticky bottom-[calc(80px+env(safe-area-inset-bottom))] z-30 -mt-4 flex flex-wrap items-center gap-x-3 gap-y-2 rounded-[18px] border border-border bg-card px-4 py-3 shadow-[0_12px_32px_rgba(81,67,55,.10)] md:bottom-6"
          role="status"
        >
          <span class="min-w-0 flex-1 text-[15px] text-heading">ยังไม่ได้บันทึกการเปลี่ยนแปลง</span>
          <div class="flex gap-2">
            <Button variant="ghost" :disabled="saving" @click="resetCfg">ยกเลิก</Button>
            <Button :disabled="saving" @click="save()">{{ saving ? 'กำลังบันทึก…' : 'บันทึก' }}</Button>
          </div>
        </div>
      </Transition>
    </div>
    <div v-else class="grid gap-6"><Skeleton class="h-20 rounded-[18px]" /><Skeleton class="h-72 rounded-[18px]" /><Skeleton class="h-96 rounded-[18px]" /></div>
  </div>
</template>
