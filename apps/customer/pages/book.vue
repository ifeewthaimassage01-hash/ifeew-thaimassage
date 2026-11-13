<script setup lang="ts">
// จองบริการ: สาขา -> บริการ/ระยะเวลา (สูงสุด 4 คน) -> วัน -> เวลาว่าง -> ข้อมูลผู้จอง -> ยืนยัน (มัดจำ)
// คำถามของหน้า: "ว่างกี่โมง รวมเท่าไร" — สรุปการจองอยู่ข้างขวา (มือถืออยู่ก่อนปุ่มจอง)
import { Check, UserPlus, X } from '@lucide/vue'
import {
  addDays,
  bangkokToday,
  formatBaht,
  formatDuration,
  newIdempotencyKey,
  personNameSchema,
  thaiPhoneSchema,
  type AvailableSlot,
  type BookingView,
} from '@ifeew/shared'

useHead({ title: "จองบริการ — Ifeew's Thaimassage" })

const MAX_PEOPLE = 4
const route = useRoute()
const supabase = useSupabaseClient()
const { code: companyCode } = useCompany()
const { call } = useEdgeFunction()
const { data: branches } = await useBranches()
const { data: policies } = await usePolicies()

const branchId = ref<string | null>((route.query.branch as string) || null)
const { data: catalog } = await useCatalog(branchId)

interface Person { branch_service_id: string | null; option_id: string | null }
// ค่าที่ส่งมาจากแผงจองด่วนหน้าแรก: ?branch=&service=&option=&date=YYYY-MM-DD&time=<starts_at ISO>
const qs = (k: string) => (typeof route.query[k] === 'string' && route.query[k] ? (route.query[k] as string) : null)
const people = ref<Person[]>([{ branch_service_id: qs('service'), option_id: qs('option') }])
const today = bangkokToday()
const qDate = qs('date')
const date = ref(qDate && /^\d{4}-\d{2}-\d{2}$/.test(qDate) && qDate >= today ? qDate : addDays(today, 1))
let wantedSlot = qs('time')
const slots = ref<AvailableSlot[]>([])
const loadingSlots = ref(false)
const slotError = ref<string | null>(null)
const slot = ref<AvailableSlot | null>(null)
const note = ref('')

const guest = reactive({ firstName: '', lastName: '', phone: '', email: '' })
const privacy = ref(false)
const marketing = ref(false)
const turnstileToken = ref('')
const turnstile = ref<{ reset: () => void } | null>(null)
const submitting = ref(false)
const error = ref<string | null>(null)
let idempotencyKey = newIdempotencyKey()


watch(branchId, (_, old) => {
  if (old !== undefined && old !== null) people.value = [{ branch_service_id: null, option_id: null }]
})

const branch = computed(() => branches.value?.find((b) => b.id === branchId.value) ?? null)
const serviceOf = (p: Person) => catalog.value?.find((c) => c.branch_service_id === p.branch_service_id) ?? null
const optionsFor = (p: Person) => serviceOf(p)?.options ?? []
const optionOf = (p: Person) => optionsFor(p).find((o) => o.option_id === p.option_id) ?? null
const optionIds = computed(() => people.value.map((p) => p.option_id).filter((x): x is string => !!x))
const ready = computed(() => !!branchId.value && optionIds.value.length === people.value.length && people.value.length > 0)

const total = computed(() => people.value.reduce((sum, p) => sum + (optionOf(p)?.price ?? 0), 0))

function pickService(p: Person, id: string | null) {
  p.branch_service_id = id
  const opts = optionsFor(p)
  p.option_id = opts.length === 1 ? opts[0]!.option_id : null
}

// เวลาว่างแบ่งเป็นช่วงเช้า / บ่าย / เย็น ให้ไล่หาได้เร็วบนมือถือ
const slotGroups = computed(() => {
  const groups: Array<{ label: string; items: AvailableSlot[] }> = [
    { label: 'ช่วงเช้า', items: [] },
    { label: 'ช่วงบ่าย', items: [] },
    { label: 'ช่วงเย็น', items: [] },
  ]
  for (const s of slots.value) {
    const h = Number(s.time.slice(0, 2))
    groups[h < 12 ? 0 : h < 17 ? 1 : 2]!.items.push(s)
  }
  return groups.filter((g) => g.items.length)
})

const dateLabel = computed(() =>
  date.value
    ? new Date(`${date.value}T00:00:00+07:00`).toLocaleDateString('th-TH', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'Asia/Bangkok' })
    : '',
)

// โหลดเวลาว่างเมื่อข้อมูลครบ
watch(
  [branchId, date, () => optionIds.value.join(',')],
  async () => {
    slot.value = null
    slots.value = []
    slotError.value = null
    idempotencyKey = newIdempotencyKey()
    if (!ready.value || !date.value) return
    loadingSlots.value = true
    const { data, error: err } = await supabase.rpc('get_available_slots', {
      p_branch_id: branchId.value!, p_date: date.value, p_option_ids: optionIds.value,
    })
    loadingSlots.value = false
    if (err) {
      slotError.value = err.message
      return
    }
    slots.value = (data ?? []) as unknown as AvailableSlot[]
    // เลือกเวลาที่ลูกค้าเลือกไว้จากหน้าแรกให้ (ถ้ายังว่างอยู่) — ใช้ครั้งเดียว
    if (wantedSlot) {
      slot.value = slots.value.find((s) => s.starts_at === wantedSlot) ?? null
      wantedSlot = null
    }
  },
  { immediate: true },
)

async function submit() {
  error.value = null
  if (!ready.value || !slot.value) {
    error.value = 'กรุณาเลือกบริการและเวลาให้ครบ'
    return
  }
  submitting.value = true
  try {
    const first = personNameSchema.safeParse(guest.firstName)
    const phone = thaiPhoneSchema.safeParse(guest.phone)
    if (!first.success || !phone.success) throw new Error('กรุณากรอกชื่อและเบอร์โทรให้ถูกต้อง')
    if (!privacy.value || !policies.value?.PRIVACY_NOTICE) throw new Error('กรุณารับทราบนโยบายความเป็นส่วนตัว')
    if (!turnstileToken.value) throw new Error('กรุณายืนยันว่าไม่ใช่บอท')

    const view = await call<BookingView>('guest-booking', {
      company_code: companyCode,
      branch_id: branchId.value,
      starts_at: slot.value.starts_at,
      option_ids: optionIds.value,
      first_name: first.data,
      last_name: guest.lastName.trim(),
      phone: phone.data,
      email: guest.email.trim() || null,
      note: note.value.trim() || null,
      privacy_version_id: policies.value.PRIVACY_NOTICE.id,
      turnstile_token: turnstileToken.value,
      idempotency_key: idempotencyKey,
    })
    // เก็บลิงก์ไว้ในเครื่องนี้ ให้ Guest กลับมาดูได้
    const saved = JSON.parse(localStorage.getItem('ifeew.guest_bookings') ?? '[]') as string[]
    localStorage.setItem('ifeew.guest_bookings', JSON.stringify([view.tracking_token, ...saved].slice(0, 10)))
    await navigateTo(`/t/${view.tracking_token}`)
  } catch (e) {
    error.value = e instanceof Error && !(e as { data?: unknown }).data ? e.message : edgeErrorText(e)
    turnstile.value?.reset()
    turnstileToken.value = ''
  } finally {
    submitting.value = false
  }
}

const chip = (on: boolean) =>
  on
    ? 'border-primary bg-primary text-primary-foreground'
    : 'border-border bg-card text-heading hover:border-input hover:bg-muted'

// แถบวันที่ 14 วัน (พรุ่งนี้เป็นค่าเริ่มต้น) — ดูตารางว่างได้ทีละวันโดยไม่ต้องเปิดปฏิทิน
const days = computed(() =>
  Array.from({ length: 14 }, (_, i) => {
    const iso = addDays(today, i)
    const d = new Date(`${iso}T00:00:00+07:00`)
    const fmt = (o: Intl.DateTimeFormatOptions) => d.toLocaleDateString('th-TH', { ...o, timeZone: 'Asia/Bangkok' })
    return { iso, weekday: i === 0 ? 'วันนี้' : i === 1 ? 'พรุ่งนี้' : fmt({ weekday: 'short' }), day: fmt({ day: 'numeric' }), month: fmt({ month: 'short' }) }
  }),
)

// ความคืบหน้า: แสดงว่าขั้นไหนเสร็จแล้ว
const steps = computed(() => [
  { label: 'สาขา', done: !!branchId.value },
  { label: 'บริการ', done: ready.value },
  { label: 'วันและเวลา', done: !!slot.value },
  { label: 'ข้อมูลผู้จอง', done: false },
])
const currentStep = computed(() => steps.value.findIndex((s) => !s.done))
</script>

<template>
  <div>
    <PageHeader title="จองคิวนวด" :description="`เลือกได้สูงสุด ${MAX_PEOPLE} คนต่อการจอง · ชำระค่าบริการที่ร้าน มัดจำผ่าน PromptPay`" />

    <!-- ความคืบหน้า -->
    <ol class="m-0 mb-6 grid list-none grid-cols-4 gap-2 p-0" aria-label="ขั้นตอนการจอง">
      <li v-for="(s, i) in steps" :key="s.label" class="grid gap-2" :aria-current="i === currentStep ? 'step' : undefined">
        <span class="h-1 rounded-full" :class="s.done ? 'bg-primary' : i === currentStep ? 'bg-brand-accent' : 'bg-secondary'" />
        <span class="flex items-center gap-1 text-sm" :class="s.done || i === currentStep ? 'font-medium text-heading' : 'text-muted-foreground'">
          <Check v-if="s.done" class="size-3.5 text-primary" aria-hidden="true" />{{ s.label }}
        </span>
      </li>
    </ol>

    <div class="grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_340px]">
      <div class="grid gap-4">
        <!-- สาขา -->
        <Card class="gap-4 py-5">
          <CardHeader class="px-5"><CardTitle as="h2" class="text-base">สาขา</CardTitle></CardHeader>
          <CardContent class="px-5">
            <Label for="branch" class="sr-only">สาขา</Label>
            <Select v-model="branchId">
              <SelectTrigger id="branch" class="w-full sm:w-80"><SelectValue placeholder="เลือกสาขา" /></SelectTrigger>
              <SelectContent>
                <SelectItem v-for="b in branches ?? []" :key="b.id" :value="b.id">{{ b.name }}</SelectItem>
              </SelectContent>
            </Select>
          </CardContent>
        </Card>

        <!-- บริการ -->
        <Card v-if="branchId" class="gap-4 py-5">
          <CardHeader class="px-5"><CardTitle as="h2" class="text-base">บริการ</CardTitle></CardHeader>
          <CardContent class="grid gap-3 px-5">
            <EmptyState v-if="!catalog?.length" compact title="สาขานี้ยังไม่เปิดจองบริการออนไลน์" description="โทรจองที่สาขาได้ หรือเลือกสาขาอื่น" />
            <template v-else>
              <fieldset v-for="(p, idx) in people" :key="idx" class="m-0 grid gap-3 rounded-lg border border-border bg-muted p-4">
                <div class="flex items-center justify-between">
                  <legend class="float-left text-[15px] font-medium text-heading">คนที่ {{ idx + 1 }}</legend>
                  <Button v-if="people.length > 1" variant="ghost" size="icon-sm" :aria-label="`ลบคนที่ ${idx + 1}`" @click="people.splice(idx, 1)"><X /></Button>
                </div>
                <Select :model-value="p.branch_service_id ?? undefined" @update:model-value="(v) => pickService(p, (v as string) ?? null)">
                  <SelectTrigger class="w-full" :aria-label="`บริการของคนที่ ${idx + 1}`"><SelectValue placeholder="เลือกบริการ" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem v-for="c in catalog" :key="c.branch_service_id" :value="c.branch_service_id">{{ c.name }}</SelectItem>
                  </SelectContent>
                </Select>
                <div v-if="p.branch_service_id" class="flex flex-wrap gap-2" role="radiogroup" :aria-label="`ระยะเวลาของคนที่ ${idx + 1}`">
                  <button
                    v-for="o in optionsFor(p)"
                    :key="o.option_id"
                    type="button"
                    role="radio"
                    :aria-checked="p.option_id === o.option_id"
                    class="inline-flex h-11 items-center gap-2 rounded-lg border px-4 text-[15px] transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none md:h-10"
                    :class="chip(p.option_id === o.option_id)"
                    @click="p.option_id = o.option_id"
                  >
                    {{ formatDuration(o.duration_minutes) }}<span class="num font-semibold">{{ formatBaht(o.price) }}</span>
                  </button>
                </div>
              </fieldset>
              <Button v-if="people.length < MAX_PEOPLE" variant="outline" class="w-fit" @click="people.push({ branch_service_id: null, option_id: null })">
                <UserPlus /> เพิ่มคน
              </Button>
            </template>
          </CardContent>
        </Card>

        <!-- วันและเวลา -->
        <Card v-if="ready" class="gap-4 py-5">
          <CardHeader class="px-5"><CardTitle as="h2" class="text-base">วันและเวลา</CardTitle></CardHeader>
          <CardContent class="grid gap-5 px-5">
            <div class="-mx-5 overflow-x-auto px-5 pb-1" role="radiogroup" aria-label="วันที่">
              <div class="flex w-max gap-2">
                <button
                  v-for="d in days"
                  :key="d.iso"
                  type="button"
                  role="radio"
                  :aria-checked="date === d.iso"
                  :aria-label="`${d.weekday} ${d.day} ${d.month}`"
                  class="grid w-16 justify-items-center gap-0.5 rounded-lg border py-2 transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
                  :class="chip(date === d.iso)"
                  @click="date = d.iso"
                >
                  <span class="text-[13px]" :class="date === d.iso ? 'text-primary-foreground/85' : 'text-muted-foreground'">{{ d.weekday }}</span>
                  <span class="num text-lg leading-tight font-semibold">{{ d.day }}</span>
                  <span class="text-[13px]" :class="date === d.iso ? 'text-primary-foreground/85' : 'text-muted-foreground'">{{ d.month }}</span>
                </button>
              </div>
            </div>

            <div v-if="loadingSlots" class="grid grid-cols-3 gap-2 sm:grid-cols-5 xl:grid-cols-6">
              <Skeleton v-for="n in 10" :key="n" class="h-11 rounded-lg md:h-10" />
            </div>
            <Alert v-else-if="slotError" variant="destructive"><AlertDescription>โหลดเวลาว่างไม่สำเร็จ: {{ slotError }}</AlertDescription></Alert>
            <EmptyState v-else-if="!slots.length" compact :title="`${dateLabel} ไม่มีเวลาว่าง`" description="ร้านปิดหรือคิวเต็ม ลองเลือกวันอื่น" />
            <div v-else class="grid gap-4" role="radiogroup" aria-label="เวลาเริ่ม">
              <p class="m-0 text-[15px] text-muted-foreground">{{ dateLabel }} · ว่าง <span class="num font-medium text-heading">{{ slots.length }}</span> ช่วงเวลา</p>
              <div v-for="g in slotGroups" :key="g.label" class="grid gap-2">
                <h3 class="m-0 text-sm font-medium text-muted-foreground">{{ g.label }}</h3>
                <div class="grid grid-cols-3 gap-2 sm:grid-cols-5 xl:grid-cols-6">
                  <button
                    v-for="s in g.items"
                    :key="s.starts_at"
                    type="button"
                    role="radio"
                    :aria-checked="slot?.starts_at === s.starts_at"
                    class="num h-11 rounded-lg border text-[15px] font-medium transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none md:h-10"
                    :class="chip(slot?.starts_at === s.starts_at)"
                    @click="slot = s"
                  >{{ s.time }}</button>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        <!-- ข้อมูลผู้จอง -->
        <Card v-if="slot" class="gap-4 py-5">
          <CardHeader class="px-5"><CardTitle as="h2" class="text-base">ข้อมูลผู้จอง</CardTitle></CardHeader>
          <CardContent class="grid gap-4 px-5">
            <p class="m-0 text-[15px] text-muted-foreground">จองได้ทันที ไม่ต้องสมัครสมาชิก · ใช้เบอร์โทรนี้ตรวจสอบการจองภายหลัง</p>
            <div class="grid grid-cols-2 gap-3">
              <div class="grid content-start gap-1.5"><Label for="g-first">ชื่อ</Label><Input id="g-first" v-model="guest.firstName" autocomplete="given-name" required /></div>
              <div class="grid content-start gap-1.5"><Label for="g-last">นามสกุล <span class="font-normal text-muted-foreground">(ไม่บังคับ)</span></Label><Input id="g-last" v-model="guest.lastName" autocomplete="family-name" /></div>
            </div>
            <div class="grid gap-3 sm:grid-cols-2">
              <div class="grid content-start gap-1.5"><Label for="g-phone">เบอร์โทร</Label><Input id="g-phone" v-model="guest.phone" numeric="digits" type="tel" inputmode="tel" autocomplete="tel" required class="num" /></div>
              <div class="grid content-start gap-1.5"><Label for="g-email">อีเมล <span class="font-normal text-muted-foreground">(ไม่บังคับ)</span></Label><Input id="g-email" v-model="guest.email" type="email" autocomplete="email" /></div>
            </div>
            <ConsentFields v-model:privacy="privacy" v-model:marketing="marketing" :policies="policies ?? null" />
            <ClientOnly><TurnstileWidget ref="turnstile" @token="(t: string) => (turnstileToken = t)" /></ClientOnly>
            <div class="grid gap-1.5">
              <Label for="note">หมายเหตุถึงร้าน <span class="font-normal text-muted-foreground">(ไม่บังคับ)</span></Label>
              <Textarea id="note" v-model="note" rows="2" maxlength="500" placeholder="เช่น ขอหมอผู้หญิง หรือเจ็บไหล่ขวา" />
            </div>
          </CardContent>
        </Card>
      </div>

      <!-- สรุปการจอง -->
      <Card class="gap-0 py-0 lg:sticky lg:top-24" aria-labelledby="summary-h">
        <div class="border-b border-border p-5"><h2 id="summary-h" class="m-0 text-base font-semibold">สรุปการจอง</h2></div>
        <div class="grid gap-4 p-5">
          <dl class="m-0 grid gap-2 text-[15px]">
            <div class="flex justify-between gap-3"><dt class="text-muted-foreground">สาขา</dt><dd class="m-0 text-right text-heading">{{ branch?.name ?? '—' }}</dd></div>
            <div class="flex justify-between gap-3">
              <dt class="text-muted-foreground">เวลา</dt>
              <dd class="m-0 text-right text-heading">{{ slot ? `${dateLabel} ${slot.time} น.` : '—' }}</dd>
            </div>
          </dl>
          <ul class="m-0 grid list-none gap-1.5 border-t border-border p-0 pt-4 text-[15px]">
            <li v-for="(p, idx) in people" :key="idx" class="flex justify-between gap-3">
              <span class="min-w-0">
                คนที่ {{ idx + 1 }} · {{ serviceOf(p)?.name ?? 'ยังไม่เลือก' }}
                <span v-if="optionOf(p)" class="text-muted-foreground"> {{ formatDuration(optionOf(p)!.duration_minutes) }}</span>
              </span>
              <span class="num shrink-0 text-heading">{{ optionOf(p) ? formatBaht(optionOf(p)!.price) : '—' }}</span>
            </li>
          </ul>
          <div class="flex items-baseline justify-between border-t border-border pt-4">
            <span class="font-medium text-heading">รวมค่าบริการ</span>
            <span class="num text-2xl font-semibold text-heading">{{ formatBaht(total) }}</span>
          </div>
        </div>
        <div class="grid gap-3 border-t border-border bg-muted p-5">
          <p class="m-0 text-sm text-muted-foreground">ชำระที่ร้านหลังใช้บริการ หลังกดจองต้องโอนมัดจำผ่าน PromptPay และส่งสลิปภายในเวลาที่กำหนด</p>
          <Alert v-if="error" variant="destructive"><AlertDescription>{{ error }}</AlertDescription></Alert>
          <Button size="lg" class="w-full" :disabled="!slot || submitting" @click="submit">
            {{ submitting ? 'กำลังจอง…' : 'จองและชำระมัดจำ' }}
          </Button>
          <p v-if="!slot" class="m-0 text-center text-sm text-muted-foreground">เลือกบริการและเวลาก่อน</p>
        </div>
      </Card>
    </div>
  </div>
</template>
