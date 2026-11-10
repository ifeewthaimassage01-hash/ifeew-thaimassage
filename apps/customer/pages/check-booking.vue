<script setup lang="ts">
// ตรวจสอบการจองสำหรับ Guest (ไม่ได้ login): กรอกเบอร์โทร → รายการการจอง → กดเปิด /t/<token>
// token ที่ได้เป็นแบบชั่วคราว (30 นาที) ออกโดย Edge Function guest-booking-lookup
import { ChevronRight, Search } from '@lucide/vue'
import { bangkokDateLong, bangkokTime, bookingStatusLabels, thaiPhoneSchema, type BookingView } from '@ifeew/shared'

useHead({
  title: "ตรวจสอบการจอง — Ifeew's Thaimassage",
  meta: [{ name: 'robots', content: 'noindex' }],
})

const user = useSupabaseUser()
const { code: companyCode } = useCompany()
const { call } = useEdgeFunction()

const phone = ref('')
const turnstileToken = ref('')
const turnstile = ref<{ reset: () => void } | null>(null)
const loading = ref(false)
const error = ref<string | null>(null)

// เก็บผลไว้ในหน่วยความจำ ให้กดย้อนกลับจากหน้ารายละเอียดแล้วยังเห็นรายการเดิม (ไม่เก็บลงเครื่อง)
const result = useState<{ phone: string; bookings: BookingView[]; at: number } | null>('guest-lookup', () => null)
if (result.value && Date.now() - result.value.at > 25 * 60_000) result.value = null // token ใกล้หมดอายุ

async function search() {
  error.value = null
  const parsed = thaiPhoneSchema.safeParse(phone.value)
  if (!parsed.success) {
    error.value = parsed.error.issues[0]?.message ?? 'เบอร์โทรไม่ถูกต้อง'
    return
  }
  if (!turnstileToken.value) {
    error.value = 'กรุณายืนยันว่าไม่ใช่บอท'
    return
  }
  loading.value = true
  try {
    const res = await call<{ bookings: BookingView[] }>('guest-booking-lookup', {
      company_code: companyCode,
      phone: parsed.data,
      turnstile_token: turnstileToken.value,
    })
    result.value = { phone: parsed.data, bookings: res.bookings, at: Date.now() }
  } catch (e) {
    error.value = edgeErrorText(e, 'ค้นหาไม่สำเร็จ กรุณาลองใหม่')
  } finally {
    loading.value = false
    turnstile.value?.reset()
    turnstileToken.value = ''
  }
}

function reset() {
  result.value = null
  phone.value = ''
}

const isUpcoming = (b: BookingView) => ['PENDING', 'CONFIRMED'].includes(b.status)
const upcoming = computed(() =>
  (result.value?.bookings ?? []).filter(isUpcoming).sort((a, b) => a.starts_at.localeCompare(b.starts_at)),
)
const past = computed(() =>
  (result.value?.bookings ?? []).filter((b) => !isUpcoming(b)).sort((a, b) => b.starts_at.localeCompare(a.starts_at)),
)
const services = (b: BookingView) => b.items.map((i) => i.service_name).join(', ')
const maskedPhone = computed(() => (result.value ? `${result.value.phone.slice(0, 3)}-xxx-${result.value.phone.slice(-4)}` : ''))
</script>

<template>
  <div class="mx-auto max-w-2xl">
    <PageHeader title="ตรวจสอบการจอง" description="กรอกเบอร์โทรที่ใช้ตอนจอง เพื่อดูวันนัดและสถานะการจอง" />

    <Alert v-if="user" variant="info" class="mb-6">
      <AlertDescription>คุณเข้าสู่ระบบอยู่ ดูการจองทั้งหมดได้ที่ <NuxtLink to="/bookings">การจองของฉัน</NuxtLink></AlertDescription>
    </Alert>

    <!-- ฟอร์มค้นหา -->
    <Card v-if="!result" class="gap-4 py-5">
      <CardContent class="px-5">
        <form class="grid gap-4" @submit.prevent="search">
          <div class="grid gap-1.5">
            <Label for="lookup-phone">เบอร์โทร</Label>
            <Input
              id="lookup-phone"
              v-model="phone"
              numeric="digits"
              type="tel"
              inputmode="tel"
              autocomplete="tel"
              placeholder="0812345678"
              required
              class="num"
            />
          </div>
          <ClientOnly><TurnstileWidget ref="turnstile" @token="(t: string) => (turnstileToken = t)" /></ClientOnly>
          <Alert v-if="error" variant="destructive"><AlertDescription>{{ error }}</AlertDescription></Alert>
          <Button type="submit" :disabled="loading" class="w-full sm:w-auto sm:justify-self-start">
            <Search /> {{ loading ? 'กำลังค้นหา…' : 'ค้นหาการจอง' }}
          </Button>
          <p class="m-0 text-sm text-muted-foreground">
            แสดงการจองย้อนหลังไม่เกิน 90 วัน · ถ้าเป็นสมาชิก <NuxtLink :to="{ path: '/login', query: { redirect: '/bookings' } }">เข้าสู่ระบบ</NuxtLink> เพื่อดูการจองของคุณ
          </p>
        </form>
      </CardContent>
    </Card>

    <!-- ผลการค้นหา -->
    <template v-else>
      <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
        <p class="m-0 text-[15px] text-muted-foreground">
          การจองของเบอร์ <span class="num font-medium text-heading">{{ maskedPhone }}</span>
        </p>
        <Button variant="outline" size="sm" @click="reset">ค้นหาเบอร์อื่น</Button>
      </div>

      <EmptyState
        v-if="!result.bookings.length"
        title="ไม่พบการจองของเบอร์นี้"
        description="ตรวจสอบเบอร์โทรอีกครั้ง หรือติดต่อสาขาที่จองไว้"
      >
        <Button as-child><NuxtLink to="/book">จองคิว</NuxtLink></Button>
      </EmptyState>

      <div v-else class="grid gap-6">
        <section v-for="sec in ([['กำลังจะถึง', upcoming], ['ที่ผ่านมา', past]] as const)" v-show="sec[1].length" :key="sec[0]">
          <h2 class="mb-2 text-[15px] font-medium text-muted-foreground">
            {{ sec[0] }} <span class="num">{{ sec[1].length }}</span>
          </h2>
          <div class="grid overflow-hidden rounded-xl border border-border bg-card">
            <NuxtLink
              v-for="b in sec[1]"
              :key="b.booking_id"
              :to="`/t/${b.tracking_token}`"
              class="flex items-center gap-3 border-b border-border px-4 py-3.5 text-foreground no-underline transition-colors last:border-0 hover:bg-muted active:bg-muted"
            >
              <div class="min-w-0 flex-1">
                <p class="m-0 font-medium text-heading">{{ bangkokDateLong(b.starts_at) }}</p>
                <p class="m-0 truncate text-sm text-muted-foreground">
                  <span class="num">{{ bangkokTime(b.starts_at) }}–{{ bangkokTime(b.ends_at) }}</span> น. · {{ b.branch.name }} · {{ services(b) }}
                </p>
                <span v-if="b.can_upload_slip" class="text-[13px] font-medium text-pending-ink">ต้องโอนมัดจำ</span>
              </div>
              <Badge :variant="bookingStatusVariant(b.status)" dot>{{ bookingStatusLabels[b.status] }}</Badge>
              <ChevronRight class="size-4 shrink-0 text-muted-soft" aria-hidden="true" />
            </NuxtLink>
          </div>
        </section>
      </div>
    </template>
  </div>
</template>
