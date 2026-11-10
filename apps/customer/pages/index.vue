<script setup lang="ts">
// หน้าแรก (ภาพอ้างอิง Warm Minimal):
//   Hero + แผงจองด่วน → บริการแนะนำ → สาขาของเรา + ทำไมต้องเลือกเรา → จองง่าย 3 ขั้นตอน + คำโปรย
// ข้อมูลจริงทั้งหมด: useBranches / useOpenToday / useCatalog / my_bookings (สมาชิก)
import { ArrowRight, CalendarCheck, CalendarDays, Check, ChevronRight, CircleCheck, Clock, MapPin, Navigation, Phone, Wallet } from '@lucide/vue'
import { bangkokDateLong, bangkokTime, type BookingView } from '@ifeew/shared'
import { hhmm } from '~/composables/useOpenToday'

useHead({ title: "Ifeew's Thaimassage — จองนวดไทยออนไลน์" })

const config = useRuntimeConfig()
const user = useSupabaseUser()
const supabase = useSupabaseClient()
const { code } = useCompany()
const { customer, ensure } = useCustomer()

const { data: branches, pending, error } = await useBranches()
const branchIds = computed(() => (branches.value ?? []).map((b) => b.id))
const { data: hours } = await useOpenToday(branchIds)
const { data: catalog } = await useCatalog()

// บริการแนะนำ: 1 การ์ดต่อบริการ (รวมทุกสาขา) ตามลำดับเมนูของร้าน
const featured = computed(() => {
  const seen = new Set<string>()
  return (catalog.value ?? []).filter((s) => (seen.has(s.service_id) ? false : (seen.add(s.service_id), true))).slice(0, 3)
})

// รูป: ตั้งค่าได้ (NUXT_PUBLIC_HERO_IMAGE / NUXT_PUBLIC_BRANCH_IMAGE) ไม่งั้นใช้รูปบริการจริงจากระบบ
const firstServiceImage = (branchId?: string) => {
  const s = (catalog.value ?? []).find((c) => c.image_path && (!branchId || c.branch_id === branchId))
  return s ? serviceImageUrl(s.image_path) : null
}
const heroImage = computed(() => (config.public.heroImage as string) || firstServiceImage())
const mainBranch = computed(() => branches.value?.[0] ?? null)
// รูปสาขา: รูปที่ร้านอัปโหลดให้สาขานั้น → ค่าตั้ง NUXT_PUBLIC_BRANCH_IMAGE → รูปบริการของสาขา
const branchImage = computed(
  () =>
    branchImageUrl(mainBranch.value?.image_path) ||
    (config.public.branchImage as string) ||
    (mainBranch.value ? firstServiceImage(mainBranch.value.id) : null) ||
    heroImage.value,
)
const todayText = (id: string) => {
  const h = hours.value?.[id]
  if (!h) return null
  return h.closed ? (h.holiday ? `วันนี้ปิด · ${h.holiday}` : 'วันนี้ปิด') : `วันนี้เปิด ${hhmm(h.opens!)} – ${hhmm(h.closes!)} น.`
}
const tel = (p: string) => `tel:${p.replace(/\s|-/g, '')}`
const mapHref = (b: { map_url: string | null; address: string | null; name: string }) =>
  b.map_url || `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(b.address || b.name)}`

// สมาชิก: นัดครั้งถัดไป + จำนวนที่รอโอนมัดจำ (โหลดฝั่ง client)
const myBookings = ref<BookingView[] | null>(null)
onMounted(async () => {
  if (!user.value) return
  await ensure().catch(() => {})
  const { data } = await supabase.rpc('my_bookings', { p_company_code: code })
  myBookings.value = (data ?? []) as unknown as BookingView[]
})
const next = computed(() =>
  (myBookings.value ?? [])
    .filter((b) => ['PENDING', 'CONFIRMED'].includes(b.status) && new Date(b.starts_at).getTime() > Date.now())
    .sort((a, b) => a.starts_at.localeCompare(b.starts_at))[0] ?? null,
)
const awaitingDeposit = computed(() => (myBookings.value ?? []).filter((b) => b.can_upload_slip).length)

const reasons = ['หมอนวดมืออาชีพ', 'บรรยากาศผ่อนคลาย', 'สะอาด ปลอดภัย', 'บริการด้วยใจ']
const steps = [
  { icon: MapPin, title: 'เลือกสาขา', sub: 'และบริการ' },
  { icon: Clock, title: 'เลือกวันและเวลา', sub: 'ที่ต้องการ' },
  { icon: CircleCheck, title: 'ยืนยันการจอง', sub: 'เสร็จสิ้น' },
]
</script>

<template>
  <div>
    <!-- Hero -->
    <section class="relative overflow-hidden pt-[76px]" aria-labelledby="hero-h">
      <!-- รูป: มือถืออยู่บน / เดสก์ท็อปเต็มด้านขวาแล้วจางเข้าหาพื้นครีม -->
      <div class="relative h-56 sm:h-72 lg:absolute lg:inset-y-0 lg:right-0 lg:h-auto lg:w-[64%]" aria-hidden="true">
        <img v-if="heroImage" :src="heroImage" alt="" class="size-full object-cover" fetchpriority="high">
        <div v-else class="size-full bg-gradient-to-br from-secondary via-muted to-background" />
        <div class="absolute inset-0 hidden bg-gradient-to-r from-background via-background/40 to-transparent lg:block" />
        <div class="absolute inset-x-0 bottom-0 h-24 bg-gradient-to-t from-background to-transparent" />
        <div class="absolute inset-x-0 top-0 h-24 bg-gradient-to-b from-background/70 to-transparent" />
      </div>

      <div class="relative mx-auto w-full max-w-[1200px] px-4 md:px-8">
        <div class="-mt-8 max-w-xl pb-8 lg:mt-0 lg:pt-10 lg:pb-[150px]">
          <span class="inline-flex items-center gap-1.5 rounded-full bg-success-soft px-3 py-1 text-[13px] text-success-ink">
            <CircleCheck class="size-4" :stroke-width="2" aria-hidden="true" /> ผ่อนคลาย ดูแลครบจบที่นี่
          </span>
          <h1 id="hero-h" class="m-0 mt-4 font-display text-[44px] leading-[1.05] font-bold tracking-tight text-heading sm:text-[56px] lg:text-[68px]">Ifeew Massage</h1>
          <p class="m-0 mt-3 text-[19px] leading-snug font-medium text-heading sm:text-[23px]">ให้ทุกช่วงเวลา… เป็นช่วงเวลาของการผ่อนคลาย</p>
          <p class="m-0 mt-3 max-w-md text-[15px] text-muted-foreground sm:text-[16px]">
            <template v-if="user && customer">สวัสดี คุณ{{ customer.first_name }} · </template>นวดไทย นวดน้ำมัน และอีกหลายบริการ ด้วยทีมงานมืออาชีพ ในบรรยากาศอบอุ่น เป็นส่วนตัว
          </p>
          <div class="mt-6 flex flex-wrap items-center gap-4">
            <Button as-child size="lg" class="h-12 rounded-full px-7 text-[16px] max-sm:w-full">
              <NuxtLink to="/book"><CalendarDays /> จองคิวเลย <ArrowRight /></NuxtLink>
            </Button>
            <NuxtLink to="/services" class="group flex items-center gap-3 text-[14px] text-heading no-underline">
              <span class="grid size-11 place-items-center rounded-full bg-card shadow-soft transition-transform group-hover:translate-x-0.5"><ChevronRight class="size-5" aria-hidden="true" /></span>
              ดูรายละเอียดบริการ
            </NuxtLink>
          </div>
        </div>
      </div>
    </section>

    <div class="relative mx-auto grid w-full max-w-[1200px] gap-10 px-4 md:px-8 lg:-mt-[110px]">
      <!-- แผงจองด่วน -->
      <HomeQuickBooking v-if="branches?.length" :branches="branches" :catalog="catalog ?? []" />

      <!-- สมาชิก: นัดถัดไป / รอโอนมัดจำ -->
      <div v-if="user && myBookings && (next || awaitingDeposit)" class="-mt-4 grid gap-3 sm:grid-cols-2">
        <NuxtLink v-if="next" :to="`/bookings/${next.booking_id}`" class="flex items-center gap-3 rounded-xl border border-border bg-card px-4 py-3 text-foreground no-underline shadow-soft hover:border-input">
          <CalendarCheck class="size-5 shrink-0 text-brand-accent" aria-hidden="true" />
          <span class="min-w-0 flex-1 text-[14px]">นัดถัดไป · <span class="num font-medium text-heading">{{ bangkokTime(next.starts_at) }} น.</span> {{ bangkokDateLong(next.starts_at) }} · {{ next.branch.name }}</span>
          <ChevronRight class="size-4 shrink-0 text-muted-soft" aria-hidden="true" />
        </NuxtLink>
        <NuxtLink v-if="awaitingDeposit" to="/bookings" class="flex items-center gap-3 rounded-xl border border-border bg-card px-4 py-3 text-foreground no-underline shadow-soft hover:border-input">
          <Wallet class="size-5 shrink-0 text-brand-accent" aria-hidden="true" />
          <span class="min-w-0 flex-1 text-[14px]">รอโอนมัดจำ <span class="num font-medium text-heading">{{ awaitingDeposit }}</span> รายการ · ส่งสลิปก่อนหมดเวลากันคิว</span>
          <ChevronRight class="size-4 shrink-0 text-muted-soft" aria-hidden="true" />
        </NuxtLink>
      </div>

      <!-- บริการแนะนำ -->
      <section class="grid gap-4" aria-labelledby="services-h">
        <div class="flex items-end justify-between gap-3">
          <div>
            <h2 id="services-h" class="m-0 text-[24px] font-semibold">บริการแนะนำ</h2>
            <p class="m-0 text-[14px] text-muted-foreground">ผ่อนคลายได้มากกว่า กับบริการยอดนิยมของเรา</p>
          </div>
          <NuxtLink to="/services" class="flex shrink-0 items-center gap-1 text-[14px] no-underline">ดูบริการทั้งหมด <ArrowRight class="size-4" aria-hidden="true" /></NuxtLink>
        </div>
        <EmptyState v-if="!featured.length" title="ยังไม่มีบริการที่เปิดจองออนไลน์" description="โทรจองที่สาขาได้ หรือแวะดูอีกครั้งเร็ว ๆ นี้">
          <Button as-child variant="outline"><NuxtLink to="/branches">ดูเบอร์โทรสาขา</NuxtLink></Button>
        </EmptyState>
        <div v-else class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          <ServiceCard v-for="s in featured" :key="s.branch_service_id" :item="s" layout="row" />
        </div>
      </section>

      <!-- สาขาของเรา + ทำไมต้องเลือกเรา: หัวข้ออยู่นอกแถว การ์ดสองใบขอบบนตรงกันและสูงเท่ากัน -->
      <section class="grid gap-4" aria-labelledby="branches-h">
        <div class="flex items-end justify-between gap-3">
          <div>
            <h2 id="branches-h" class="m-0 text-[24px] font-semibold">สาขาของเรา</h2>
            <p class="m-0 text-[14px] text-muted-foreground">เลือกสาขาที่สะดวก ใกล้คุณ</p>
          </div>
          <NuxtLink v-if="(branches?.length ?? 0) > 1" to="/branches" class="flex shrink-0 items-center gap-1 text-[14px] no-underline">ดูทุกสาขา <ArrowRight class="size-4" aria-hidden="true" /></NuxtLink>
        </div>

        <div class="grid items-stretch gap-6 lg:grid-cols-[minmax(0,2.25fr)_minmax(0,1fr)]">
          <div v-if="pending"><Skeleton class="h-56 rounded-2xl" /></div>
          <Alert v-else-if="error" variant="destructive"><AlertDescription>โหลดข้อมูลสาขาไม่สำเร็จ กรุณาลองใหม่</AlertDescription></Alert>
          <EmptyState v-else-if="!mainBranch" title="ยังไม่มีสาขาที่เปิดให้บริการ" />
          <!-- การ์ดเดียว: รูปซ้าย (มือถืออยู่บน) + ข้อมูลสาขา — รูปครอบเต็มช่องและไม่กำหนดความสูงการ์ด -->
          <article v-else class="grid overflow-hidden rounded-2xl border border-border bg-card shadow-soft md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
            <div class="relative h-[200px] overflow-hidden bg-secondary md:h-auto">
              <img v-if="branchImage" :src="branchImage" :alt="`หน้าร้าน ${mainBranch.name}`" class="absolute inset-0 size-full object-cover" loading="lazy">
            </div>
            <div class="grid content-center gap-2.5 px-6 py-6">
              <h3 class="m-0 flex items-start gap-2 text-[17px] font-semibold">
                <MapPin class="mt-1 size-5 shrink-0 text-brand-accent" :stroke-width="1.75" aria-hidden="true" />
                <NuxtLink :to="`/branches/${mainBranch.id}`" class="text-heading no-underline hover:text-primary">{{ mainBranch.name }}</NuxtLink>
              </h3>
              <p v-if="mainBranch.address" class="m-0 pl-7 text-[14px] text-muted-foreground">{{ mainBranch.address }}</p>
              <p v-if="todayText(mainBranch.id)" class="m-0 flex items-center gap-2 text-[15px] text-heading">
                <Clock class="size-5 shrink-0 text-brand-accent" :stroke-width="1.75" aria-hidden="true" /><span class="num">{{ todayText(mainBranch.id) }}</span>
              </p>
              <div class="mt-1 flex flex-wrap gap-2">
                <Button as-child class="h-10 rounded-full px-5">
                  <a :href="mapHref(mainBranch)" target="_blank" rel="noopener"><Navigation /> นำทาง</a>
                </Button>
                <Button v-if="mainBranch.phone" as-child variant="outline" class="h-10 rounded-full px-5">
                  <a :href="tel(mainBranch.phone)"><Phone /> <span class="num">{{ mainBranch.phone }}</span></a>
                </Button>
              </div>
            </div>
          </article>

          <section id="about" class="relative flex scroll-mt-24 flex-col justify-center overflow-hidden rounded-2xl border border-border bg-muted p-6" aria-labelledby="why-h">
            <h2 id="why-h" class="relative z-10 m-0 mb-4 text-[18px] font-semibold">ทำไมต้องเลือก Ifeew Massage?</h2>
            <ul class="relative z-10 m-0 grid list-none gap-3 p-0">
              <li v-for="r in reasons" :key="r" class="flex items-center gap-3 text-[15px] text-foreground">
                <span class="grid size-6 shrink-0 place-items-center rounded-full bg-success-soft text-success-ink" aria-hidden="true"><Check class="size-3.5" :stroke-width="2.5" /></span>{{ r }}
              </li>
            </ul>
            <!-- ห้องสปาตกแต่ง (ครึ่งขวา จางเข้าหาข้อความ) -->
            <img
              src="/images/spa-room.png"
              alt=""
              class="pointer-events-none absolute inset-y-0 right-0 h-full w-3/5 object-cover opacity-40 [mask-image:linear-gradient(to_left,black_35%,transparent)]"
              loading="lazy"
              aria-hidden="true"
            >
          </section>
        </div>
      </section>

      <!-- จองง่าย 3 ขั้นตอน + คำโปรย -->
      <div class="grid items-end gap-6 lg:grid-cols-[minmax(0,2.25fr)_minmax(0,1fr)]">
        <section class="grid gap-4" aria-labelledby="steps-h">
          <h2 id="steps-h" class="m-0 text-[22px] font-semibold">วิธีการจองง่าย ๆ เพียง 3 ขั้นตอน</h2>
          <ol class="m-0 grid list-none gap-3 rounded-2xl border border-border bg-card p-3 shadow-soft sm:grid-cols-3 sm:gap-0 sm:p-4">
            <li v-for="(s, i) in steps" :key="s.title" class="flex items-center gap-2.5 px-2 sm:px-3">
              <span class="num grid size-7 shrink-0 place-items-center rounded-full bg-primary/80 text-[13px] font-semibold text-white">{{ i + 1 }}</span>
              <span class="grid size-11 shrink-0 place-items-center rounded-full bg-muted text-heading" aria-hidden="true"><component :is="s.icon" class="size-6" :stroke-width="1.5" /></span>
              <span class="min-w-0 flex-1 text-[14px] leading-snug text-heading"><span class="block whitespace-nowrap">{{ s.title }}</span><span class="block text-muted-foreground">{{ s.sub }}</span></span>
              <ChevronRight v-if="i < steps.length - 1" class="hidden size-5 shrink-0 text-muted-soft sm:block" aria-hidden="true" />
            </li>
          </ol>
        </section>
        <blockquote class="relative m-0 grid min-h-[88px] place-items-center overflow-hidden rounded-2xl bg-muted px-6 py-5 text-center text-[16px] leading-relaxed text-heading">
          <img src="/images/towels.png" alt="" class="pointer-events-none absolute inset-0 size-full object-cover opacity-25" loading="lazy" aria-hidden="true">
          <span class="relative">“ดูแลตัวเอง… ให้เป็นเรื่องง่าย<br>ที่ Ifeew Massage”</span>
        </blockquote>
      </div>
    </div>
  </div>
</template>
