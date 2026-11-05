<script setup lang="ts">
import { CalendarClock, HandHeart, MapPin, Sparkles, Wallet } from '@lucide/vue'
import { bangkokDateLong, bangkokTime, formatBaht, type BookingView } from '@ifeew/shared'

// หน้าแรก: การ์ดสรุป (นัดถัดไป / สาขาเปิดวันนี้ / ราคาเริ่มต้น) → สาขา → บริการแนะนำ
useHead({ title: "Ifeew's Thaimassage — จองนวดไทยออนไลน์" })

const user = useSupabaseUser()
const supabase = useSupabaseClient()
const { code } = useCompany()
const { customer, ensure } = useCustomer()

const { data: branches, pending, error } = await useBranches()
const branchIds = computed(() => (branches.value ?? []).map((b) => b.id))
const { data: hours } = await useOpenToday(branchIds)
const { data: catalog } = await useCatalog()

const openToday = computed(() => Object.values(hours.value ?? {}).filter((h) => !h.closed).length)
const minPrice = computed(() => {
  const prices = (catalog.value ?? []).flatMap((s) => s.options.map((o) => o.price))
  return prices.length ? Math.min(...prices) : null
})

// บริการแนะนำ: 1 การ์ดต่อบริการ (รวมทุกสาขา) ตามลำดับเมนูของร้าน
const featured = computed(() => {
  const seen = new Set<string>()
  return (catalog.value ?? []).filter((s) => (seen.has(s.service_id) ? false : (seen.add(s.service_id), true))).slice(0, 6)
})

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

const greeting = computed(() => (user.value && customer.value ? `สวัสดี คุณ${customer.value.first_name}` : 'นวดไทย จองออนไลน์ได้ทุกสาขา'))
</script>

<template>
  <div class="grid gap-10">
    <div>
      <PageHeader :title="greeting" description="เลือกสาขา บริการ และเวลาที่ว่าง แล้วโอนมัดจำผ่าน PromptPay ก็ได้คิวทันที">
        <template #actions>
          <Button as-child variant="outline"><NuxtLink to="/services">ดูบริการทั้งหมด</NuxtLink></Button>
          <Button as-child><NuxtLink to="/book">จองคิว</NuxtLink></Button>
        </template>
      </PageHeader>

      <!-- การ์ดสรุป -->
      <div class="grid gap-4 sm:grid-cols-2" :class="user ? 'lg:grid-cols-4' : 'lg:grid-cols-3'">
        <StatCard v-if="user" label="นัดครั้งถัดไป" :icon="CalendarClock" :to="next ? `/bookings/${next.booking_id}` : '/book'">
          <template v-if="next"><span class="num">{{ bangkokTime(next.starts_at) }}</span> น.</template>
          <template v-else-if="myBookings">ยังไม่มีนัด</template>
          <Skeleton v-else class="h-8 w-24" />
          <template #hint>{{ next ? `${bangkokDateLong(next.starts_at)} · ${next.branch.name}` : 'จองคิวได้เลยวันนี้' }}</template>
        </StatCard>
        <StatCard v-if="user" label="รอโอนมัดจำ" :icon="Wallet" :value="myBookings ? awaitingDeposit : null" :to="awaitingDeposit ? '/bookings' : undefined"
          :hint="awaitingDeposit ? 'ส่งสลิปก่อนหมดเวลากันคิว' : 'ไม่มีรายการค้าง'" />
        <StatCard label="สาขาเปิดวันนี้" :icon="MapPin" to="/branches">
          <span class="num">{{ openToday }}</span><span class="text-base font-normal text-muted-foreground"> / <span class="num">{{ branches?.length ?? 0 }}</span> สาขา</span>
          <template #hint>ดูเวลาเปิด-ปิดของแต่ละสาขา</template>
        </StatCard>
        <StatCard v-if="!user" label="บริการที่เปิดจอง" :icon="Sparkles" to="/services">
          <span class="num">{{ featured.length }}</span><span class="text-base font-normal text-muted-foreground"> บริการ</span>
          <template #hint>{{ featured.length ? 'ดูระยะเวลาและราคาได้ก่อนจอง' : 'ยังไม่เปิดจองออนไลน์ โทรจองที่สาขาได้' }}</template>
        </StatCard>
        <StatCard label="ราคาเริ่มต้น" :icon="HandHeart" :value="minPrice !== null ? formatBaht(minPrice) : '—'" to="/services"
          :hint="minPrice !== null ? 'ชำระที่ร้านหลังใช้บริการ' : 'ยังไม่มีบริการที่เปิดจองออนไลน์'" />
      </div>
    </div>

    <!-- สาขา -->
    <section class="grid gap-4" aria-labelledby="branches-h">
      <div class="flex items-baseline justify-between gap-3">
        <h2 id="branches-h" class="m-0 text-lg font-semibold">สาขาของเรา</h2>
        <NuxtLink to="/branches" class="text-[15px]">ดูทั้งหมด</NuxtLink>
      </div>
      <div v-if="pending" class="grid gap-4 md:grid-cols-2"><Skeleton v-for="n in 2" :key="n" class="h-40 rounded-xl" /></div>
      <Alert v-else-if="error" variant="destructive"><AlertDescription>โหลดข้อมูลสาขาไม่สำเร็จ กรุณาลองใหม่</AlertDescription></Alert>
      <EmptyState v-else-if="!branches?.length" title="ยังไม่มีสาขาที่เปิดให้บริการ" />
      <div v-else class="grid items-start gap-4 md:grid-cols-2">
        <BranchCard v-for="b in branches" :key="b.id" :branch="b" :hours="hours?.[b.id] ?? null" />
      </div>
    </section>

    <!-- บริการแนะนำ -->
    <section class="grid gap-4" aria-labelledby="services-h">
      <div class="flex items-baseline justify-between gap-3">
        <h2 id="services-h" class="m-0 text-lg font-semibold">บริการแนะนำ</h2>
        <NuxtLink to="/services" class="text-[15px]">ดูทั้งหมด</NuxtLink>
      </div>
      <EmptyState v-if="!featured.length" title="ยังไม่มีบริการที่เปิดจองออนไลน์" description="โทรจองที่สาขาได้ หรือแวะดูอีกครั้งเร็ว ๆ นี้">
        <Button as-child variant="outline"><NuxtLink to="/branches">ดูเบอร์โทรสาขา</NuxtLink></Button>
      </EmptyState>
      <div v-else class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <ServiceCard v-for="s in featured" :key="s.branch_service_id" :item="s" />
      </div>
    </section>
  </div>
</template>
