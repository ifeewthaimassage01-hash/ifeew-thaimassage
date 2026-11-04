<script setup lang="ts">
// จองบริการ: สาขา -> บริการ/ระยะเวลา (สูงสุด 4 คน) -> วัน -> เวลาว่าง -> ข้อมูลผู้จอง -> ยืนยัน (มัดจำ)
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
const user = useSupabaseUser()
const { code: companyCode } = useCompany()
const { customer, ensure } = useCustomer()
const { call } = useEdgeFunction()
const { data: branches } = await useBranches()
const { data: policies } = await usePolicies()

const branchId = ref<string | null>((route.query.branch as string) || null)
const { data: catalog } = await useCatalog(branchId)

interface Person { branch_service_id: string | null; option_id: string | null }
const people = ref<Person[]>([{ branch_service_id: (route.query.service as string) || null, option_id: null }])
const date = ref(addDays(bangkokToday(), 1))
const slots = ref<AvailableSlot[]>([])
const loadingSlots = ref(false)
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

onMounted(() => ensure().catch(() => {}))
const isMember = computed(() => !!user.value && !!customer.value)

watch(branchId, (_, old) => {
  if (old !== undefined && old !== null) people.value = [{ branch_service_id: null, option_id: null }]
})

const serviceItems = computed(() => (catalog.value ?? []).map((c) => ({ value: c.branch_service_id, title: c.name, item: c })))
const optionsFor = (p: Person) => catalog.value?.find((c) => c.branch_service_id === p.branch_service_id)?.options ?? []
const optionIds = computed(() => people.value.map((p) => p.option_id).filter((x): x is string => !!x))
const ready = computed(() => !!branchId.value && optionIds.value.length === people.value.length && people.value.length > 0)

const total = computed(() =>
  people.value.reduce((sum, p) => sum + (optionsFor(p).find((o) => o.option_id === p.option_id)?.price ?? 0), 0),
)

function pickService(p: Person, id: string | null) {
  p.branch_service_id = id
  const opts = optionsFor(p)
  p.option_id = opts.length === 1 ? opts[0]!.option_id : null
}

// โหลดเวลาว่างเมื่อข้อมูลครบ
watch(
  [branchId, date, () => optionIds.value.join(',')],
  async () => {
    slot.value = null
    slots.value = []
    idempotencyKey = newIdempotencyKey()
    if (!ready.value || !date.value) return
    loadingSlots.value = true
    const { data, error: err } = await supabase.rpc('get_available_slots', {
      p_branch_id: branchId.value!, p_date: date.value, p_option_ids: optionIds.value,
    })
    loadingSlots.value = false
    if (err) {
      error.value = err.message
      return
    }
    slots.value = (data ?? []) as unknown as AvailableSlot[]
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
    if (isMember.value) {
      const { data, error: err } = await supabase.rpc('create_member_booking', {
        p_company_code: companyCode,
        p_branch_id: branchId.value!,
        p_starts_at: slot.value.starts_at,
        p_option_ids: optionIds.value,
        p_note: note.value.trim() || null,
        p_idempotency_key: idempotencyKey,
      })
      if (err) throw new Error(err.message)
      await navigateTo(`/bookings/${(data as unknown as BookingView).booking_id}`)
      return
    }

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
</script>

<template>
  <div class="grid gap-4">
    <h1 class="m-0 text-2xl font-semibold text-cocoa">จองบริการ</h1>

    <!-- 1 สาขา -->
    <v-card class="p-5">
      <p class="m-0 mb-3 font-medium">1. เลือกสาขา</p>
      <v-select v-model="branchId" :items="branches ?? []" item-title="name" item-value="id" label="สาขา" hide-details />
    </v-card>

    <!-- 2 บริการ -->
    <v-card v-if="branchId" class="p-5">
      <p class="m-0 mb-3 font-medium">2. เลือกบริการ</p>
      <div v-for="(p, idx) in people" :key="idx" class="mb-4 rounded-2xl border border-beige p-4">
        <div class="mb-2 flex items-center justify-between">
          <span class="text-sm font-medium">คนที่ {{ idx + 1 }}</span>
          <v-btn v-if="people.length > 1" icon="mdi-close" size="small" variant="text" aria-label="ลบ" @click="people.splice(idx, 1)" />
        </div>
        <v-select
          :model-value="p.branch_service_id"
          :items="serviceItems"
          label="บริการ"
          hide-details
          class="mb-3"
          @update:model-value="(v: string | null) => pickService(p, v)"
        />
        <div v-if="p.branch_service_id" class="flex flex-wrap gap-2">
          <v-chip
            v-for="o in optionsFor(p)"
            :key="o.option_id"
            :color="p.option_id === o.option_id ? 'primary' : undefined"
            :variant="p.option_id === o.option_id ? 'flat' : 'outlined'"
            class="touch-target"
            @click="p.option_id = o.option_id"
          >
            {{ formatDuration(o.duration_minutes) }} · {{ formatBaht(o.price) }}
          </v-chip>
        </div>
      </div>
      <v-btn v-if="people.length < MAX_PEOPLE" variant="text" prepend-icon="mdi-account-plus-outline"
        @click="people.push({ branch_service_id: null, option_id: null })">เพิ่มคน</v-btn>
    </v-card>

    <!-- 3 วันเวลา -->
    <v-card v-if="ready" class="p-5">
      <p class="m-0 mb-3 font-medium">3. เลือกวันและเวลา</p>
      <v-text-field v-model="date" type="date" label="วันที่" :min="bangkokToday()" :max="addDays(bangkokToday(), 30)" />
      <v-progress-linear v-if="loadingSlots" indeterminate color="primary" />
      <p v-else-if="!slots.length" class="m-0 text-sm text-light-brown">ไม่มีเวลาว่างในวันนี้ (ร้านปิดหรือเต็ม) กรุณาเลือกวันอื่น</p>
      <div class="grid grid-cols-4 gap-2 sm:grid-cols-6">
        <v-btn
          v-for="s in slots"
          :key="s.starts_at"
          :color="slot?.starts_at === s.starts_at ? 'primary' : undefined"
          :variant="slot?.starts_at === s.starts_at ? 'flat' : 'outlined'"
          @click="slot = s"
        >{{ s.time }}</v-btn>
      </div>
    </v-card>

    <!-- 4 ข้อมูลผู้จอง -->
    <v-card v-if="slot" class="p-5">
      <p class="m-0 mb-3 font-medium">4. ข้อมูลผู้จอง</p>
      <template v-if="isMember">
        <p class="m-0 mb-3">{{ customer?.first_name }} {{ customer?.last_name }} · {{ customer?.phone }}</p>
      </template>
      <template v-else>
        <p class="m-0 mb-3 text-sm text-light-brown">
          จองแบบไม่สมัครสมาชิก หรือ <NuxtLink :to="{ path: '/login', query: { redirect: route.fullPath } }" class="text-light-brown">เข้าสู่ระบบ</NuxtLink>
        </p>
        <div class="grid grid-cols-2 gap-x-3">
          <v-text-field v-model="guest.firstName" label="ชื่อ *" autocomplete="given-name" />
          <v-text-field v-model="guest.lastName" label="นามสกุล" autocomplete="family-name" />
        </div>
        <v-text-field v-model="guest.phone" label="เบอร์โทร *" type="tel" inputmode="tel" autocomplete="tel" />
        <v-text-field v-model="guest.email" label="อีเมล (ไม่บังคับ)" type="email" autocomplete="email" />
        <ConsentFields v-model:privacy="privacy" v-model:marketing="marketing" :policies="policies ?? null" />
        <ClientOnly><TurnstileWidget ref="turnstile" @token="(t: string) => (turnstileToken = t)" /></ClientOnly>
      </template>
      <v-textarea v-model="note" label="หมายเหตุถึงร้าน (ไม่บังคับ)" rows="2" variant="outlined" maxlength="500" />

      <div class="mb-4 rounded-xl bg-cream p-4 text-sm">
        <div class="flex justify-between"><span>ค่าบริการ (ชำระที่ร้าน)</span><span>{{ formatBaht(total) }}</span></div>
        <p class="m-0 mt-1 text-light-brown">ต้องชำระมัดจำผ่าน PromptPay หลังกดจอง และส่งสลิปภายในเวลาที่กำหนด</p>
      </div>
      <v-alert v-if="error" type="error" variant="tonal" class="mb-4" :text="error" />
      <v-btn color="primary" block size="x-large" :loading="submitting" @click="submit">จองและชำระมัดจำ</v-btn>
    </v-card>
  </div>
</template>
