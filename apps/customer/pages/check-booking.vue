<script setup lang="ts">
// ตรวจสอบการจอง — ลูกค้าไม่ต้องสมัครสมาชิก
//   เข้าสู่ระบบด้วย LINE อยู่ → "การจองของฉัน" แสดงทันที (เฉพาะการจองที่ผูกกับ LINE นี้ — Edge Function line-my-bookings)
//   ไม่ได้เข้าสู่ระบบ / ต้องการค้นหาเพิ่ม → กรอกเบอร์โทร (Edge Function guest-booking-lookup จำกัดจำนวนครั้งต่อ IP และต่อเบอร์)
//   token ที่ได้เป็นแบบชั่วคราว (30 นาที) ใช้เปิด /t/<token>
import { RefreshCw, Search } from '@lucide/vue'
import { thaiPhoneSchema, type BookingView } from '@ifeew/shared'
import { toast } from 'vue-sonner'

useHead({
  title: "ตรวจสอบการจอง — I'FEEW THAIMASSAGE",
  meta: [{ name: 'robots', content: 'noindex' }],
})

const { code: companyCode } = useCompany()
const { call } = useEdgeFunction()
const line = useLiff()

// ---------------------------------------------------------------------------
// การจองของฉัน (LINE)
// ---------------------------------------------------------------------------
const mineLoading = ref(false)
const mineError = ref<string | null>(null)
async function loadMine(force = false) {
  mineLoading.value = true
  mineError.value = null
  try {
    const res = await line.myBookings(force)
    if (!res) mineError.value = 'การเข้าสู่ระบบด้วย LINE หมดอายุ กรุณาเข้าสู่ระบบอีกครั้ง'
  } catch (e) {
    mineError.value = edgeErrorText(e, 'โหลดการจองไม่สำเร็จ กรุณาลองใหม่')
  } finally {
    mineLoading.value = false
  }
}
watch(() => line.connected.value, (on) => on && loadMine(), { immediate: true })

const lineLoggingIn = ref(false)
async function lineLogin() {
  lineLoggingIn.value = true
  try {
    await line.login('/check-booking')
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'เข้าสู่ระบบด้วย LINE ไม่สำเร็จ')
  } finally {
    lineLoggingIn.value = false
  }
}

// ---------------------------------------------------------------------------
// ค้นหาด้วยเบอร์โทร
// ---------------------------------------------------------------------------
const phone = ref('')
const loading = ref(false)
const error = ref<string | null>(null)
/** เข้าสู่ระบบด้วย LINE อยู่แต่อยากค้นหาด้วยเบอร์ (เช่น การจองที่ทำก่อนเชื่อม LINE) */
const byPhone = ref(false)

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
  loading.value = true
  try {
    const res = await call<{ bookings: BookingView[] }>('guest-booking-lookup', {
      company_code: companyCode,
      phone: parsed.data,
    })
    result.value = { phone: parsed.data, bookings: res.bookings, at: Date.now() }
  } catch (e) {
    error.value = edgeErrorText(e, 'ค้นหาไม่สำเร็จ กรุณาลองใหม่')
  } finally {
    loading.value = false
  }
}

function reset() {
  result.value = null
  phone.value = ''
}

const maskedPhone = computed(() => (result.value ? `${result.value.phone.slice(0, 3)}-xxx-${result.value.phone.slice(-4)}` : ''))
/** แสดงฟอร์ม/ผลค้นหาด้วยเบอร์ */
const showPhone = computed(() => !line.connected.value || byPhone.value || !!result.value)
</script>

<template>
  <div class="mx-auto max-w-2xl">
    <PageHeader
      :title="line.connected.value ? 'การจองของฉัน' : 'ตรวจสอบการจอง'"
      :description="line.connected.value ? `การจองที่ทำตอนเข้าสู่ระบบด้วย LINE ของ ${line.user.value?.name}` : 'ดูวันนัดและสถานะการจอง ด้วย LINE หรือเบอร์โทรที่ใช้ตอนจอง'"
    />
  <div class="grid gap-6">

    <!-- ================= การจองของฉัน (LINE) ================= -->
    <section v-if="line.connected.value" aria-label="การจองของฉัน" class="grid gap-4">
      <div v-if="mineLoading && !line.mine.value" class="grid gap-2"><Skeleton v-for="i in 2" :key="i" class="h-20 rounded-xl" /></div>
      <Alert v-else-if="mineError" variant="destructive">
        <AlertDescription class="flex flex-wrap items-center justify-between gap-3">
          {{ mineError }}
          <Button size="sm" variant="outline" :disabled="lineLoggingIn" @click="lineLogin">เข้าสู่ระบบด้วย LINE</Button>
        </AlertDescription>
      </Alert>
      <template v-else-if="line.mine.value">
        <EmptyState
          v-if="!line.mine.value.bookings.length"
          title="ยังไม่มีการจองที่ผูกกับ LINE นี้"
          description="จองครั้งถัดไปตอนเข้าสู่ระบบด้วย LINE การจองจะมาอยู่ที่นี่ การจองที่ทำไว้ก่อนหน้า ค้นหาด้วยเบอร์โทรด้านล่างได้"
        >
          <Button as-child><NuxtLink to="/book">จองคิว</NuxtLink></Button>
        </EmptyState>
        <BookingList v-else :bookings="line.mine.value.bookings" />
        <div class="flex flex-wrap items-center justify-between gap-2">
          <Button variant="ghost" size="sm" :disabled="mineLoading" @click="loadMine(true)">
            <RefreshCw :class="mineLoading ? 'animate-spin' : ''" /> โหลดใหม่
          </Button>
          <Button v-if="!showPhone" variant="link" size="sm" @click="byPhone = true">ค้นหาด้วยเบอร์โทรแทน</Button>
        </div>
      </template>
    </section>

    <!-- ยังไม่ได้เข้าสู่ระบบด้วย LINE: ทางลัดที่ไม่ต้องกรอกอะไร -->
    <div
      v-else-if="line.available.value"
      class="flex flex-wrap items-center gap-3 rounded-xl border border-border bg-card p-4"
    >
      <p class="m-0 min-w-0 flex-1 basis-56 text-[15px] text-foreground">
        เข้าสู่ระบบด้วย LINE เพื่อดูการจองของคุณได้ทันที ไม่ต้องกรอกเบอร์โทร
      </p>
      <Button class="shrink-0" :disabled="lineLoggingIn || line.restoring.value" @click="lineLogin">เข้าสู่ระบบด้วย LINE</Button>
    </div>

    <!-- ================= ค้นหาด้วยเบอร์โทร ================= -->
    <template v-if="showPhone">
      <Card v-if="!result" class="gap-4 py-5">
        <CardContent class="px-5">
          <form class="grid gap-4" @submit.prevent="search">
            <div class="grid gap-1.5">
              <Label for="lookup-phone">ค้นหาด้วยเบอร์โทร</Label>
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
                  <Alert v-if="error" variant="destructive"><AlertDescription>{{ error }}</AlertDescription></Alert>
            <Button type="submit" :disabled="loading" class="w-full sm:w-auto sm:justify-self-start">
              <Search /> {{ loading ? 'กำลังค้นหา…' : 'ค้นหาการจอง' }}
            </Button>
            <p class="m-0 text-sm text-muted-foreground">แสดงการจองย้อนหลังไม่เกิน 90 วัน</p>
          </form>
        </CardContent>
      </Card>

      <section v-else class="grid gap-4" aria-label="ผลการค้นหาด้วยเบอร์โทร">
        <div class="flex flex-wrap items-center justify-between gap-3">
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
        <BookingList v-else :bookings="result.bookings" />
      </section>
    </template>
  </div>
  </div>
</template>
