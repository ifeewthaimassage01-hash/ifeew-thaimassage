<script setup lang="ts">
// การจองของฉัน: การ์ดสรุป → แท็บ กำลังจะถึง/ที่ผ่านมา → ตาราง (เดสก์ท็อป) / รายการ (มือถือ)
import { CalendarCheck, CalendarClock, ChevronRight, Plus, Wallet } from '@lucide/vue'
import { bangkokDateLong, bangkokTime, bookingStatusLabels, formatBaht, type BookingView } from '@ifeew/shared'

definePageMeta({ middleware: 'auth' })
useHead({ title: "การจองของฉัน — Ifeew's Thaimassage" })

const supabase = useSupabaseClient()
const { code } = useCompany()
const bookings = ref<BookingView[]>([])
const loading = ref(true)
const failed = ref(false)

onMounted(async () => {
  const { data, error } = await supabase.rpc('my_bookings', { p_company_code: code })
  failed.value = !!error
  bookings.value = (data ?? []) as unknown as BookingView[]
  loading.value = false
})

const isUpcoming = (b: BookingView) => ['PENDING', 'CONFIRMED'].includes(b.status)
const upcoming = computed(() => bookings.value.filter(isUpcoming).sort((a, b) => a.starts_at.localeCompare(b.starts_at)))
const past = computed(() => bookings.value.filter((b) => !isUpcoming(b)).sort((a, b) => b.starts_at.localeCompare(a.starts_at)))
const awaiting = computed(() => bookings.value.filter((b) => b.can_upload_slip).length)

const tab = ref<'upcoming' | 'past'>('upcoming')
const list = computed(() => (tab.value === 'upcoming' ? upcoming.value : past.value))
const services = (b: BookingView) => b.items.map((i) => i.service_name).join(', ')
</script>

<template>
  <div>
    <PageHeader title="การจองของฉัน" description="ดูสถานะ ส่งสลิปมัดจำ หรือยกเลิกก่อนเวลานัด">
      <template #actions>
        <Button as-child><NuxtLink to="/book"><Plus /> จองใหม่</NuxtLink></Button>
      </template>
    </PageHeader>

    <div class="mb-8 grid gap-4 sm:grid-cols-3">
      <StatCard label="กำลังจะถึง" :icon="CalendarClock" :value="loading ? null : upcoming.length" hint="นัดที่รอและยืนยันแล้ว" />
      <StatCard label="รอโอนมัดจำ" :icon="Wallet" :value="loading ? null : awaiting" :hint="awaiting ? 'ส่งสลิปก่อนหมดเวลากันคิว' : 'ไม่มีรายการค้าง'" />
      <StatCard label="ที่ผ่านมา" :icon="CalendarCheck" :value="loading ? null : past.length" hint="เสร็จ ยกเลิก หรือหมดเวลา" />
    </div>

    <div class="mb-4 inline-flex rounded-lg border border-border bg-card p-1" role="tablist" aria-label="ช่วงเวลา">
      <button
        v-for="t in ([['upcoming', 'กำลังจะถึง', upcoming.length], ['past', 'ที่ผ่านมา', past.length]] as const)"
        :key="t[0]"
        type="button"
        role="tab"
        :aria-selected="tab === t[0]"
        class="h-9 rounded-md px-4 text-[15px] transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
        :class="tab === t[0] ? 'bg-secondary font-medium text-heading' : 'text-muted-foreground hover:text-heading'"
        @click="tab = t[0]"
      >{{ t[1] }} <span class="num ml-1 text-muted-foreground">{{ t[2] }}</span></button>
    </div>

    <div v-if="loading" class="grid gap-2"><Skeleton v-for="n in 4" :key="n" class="h-14 rounded-lg" /></div>
    <Alert v-else-if="failed" variant="destructive"><AlertDescription>โหลดการจองไม่สำเร็จ กรุณารีเฟรชหน้านี้</AlertDescription></Alert>
    <EmptyState
      v-else-if="!list.length"
      :title="tab === 'upcoming' ? 'ยังไม่มีนัดที่กำลังจะถึง' : 'ยังไม่มีการจองที่ผ่านมา'"
      :description="tab === 'upcoming' ? 'เลือกสาขาและเวลาที่สะดวก จองได้ภายในไม่กี่นาที' : undefined"
    >
      <Button v-if="tab === 'upcoming'" as-child><NuxtLink to="/book">จองคิว</NuxtLink></Button>
    </EmptyState>

    <template v-else>
      <!-- เดสก์ท็อป: ตาราง -->
      <div class="hidden overflow-hidden rounded-xl border border-border bg-card md:block">
        <Table>
          <TableHeader>
            <TableRow class="hover:bg-transparent">
              <TableHead>วันและเวลา</TableHead>
              <TableHead>สาขา</TableHead>
              <TableHead>บริการ</TableHead>
              <TableHead class="text-right">ค่าบริการ</TableHead>
              <TableHead>สถานะ</TableHead>
              <TableHead class="w-10"><span class="sr-only">เปิด</span></TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow v-for="b in list" :key="b.booking_id" class="cursor-pointer" @click="navigateTo(`/bookings/${b.booking_id}`)">
              <TableCell>
                <NuxtLink :to="`/bookings/${b.booking_id}`" class="font-medium text-heading no-underline" @click.stop>{{ bangkokDateLong(b.starts_at) }}</NuxtLink>
                <span class="num block text-sm text-muted-foreground">{{ bangkokTime(b.starts_at) }}–{{ bangkokTime(b.ends_at) }} น.</span>
              </TableCell>
              <TableCell>{{ b.branch.name }}</TableCell>
              <TableCell class="max-w-64 truncate">{{ services(b) }}</TableCell>
              <TableCell class="num text-right text-heading">{{ formatBaht(Number(b.total_amount)) }}</TableCell>
              <TableCell>
                <div class="flex flex-col items-start gap-1">
                  <Badge :variant="bookingStatusVariant(b.status)" dot>{{ bookingStatusLabels[b.status] }}</Badge>
                  <span v-if="b.can_upload_slip" class="text-[13px] font-medium text-pending-ink">ต้องโอนมัดจำ</span>
                </div>
              </TableCell>
              <TableCell><ChevronRight class="size-4 text-muted-soft" aria-hidden="true" /></TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </div>

      <!-- มือถือ: รายการ -->
      <div class="grid overflow-hidden rounded-xl border border-border bg-card md:hidden">
        <NuxtLink
          v-for="b in list"
          :key="b.booking_id"
          :to="`/bookings/${b.booking_id}`"
          class="flex items-center gap-3 border-b border-border px-4 py-3.5 text-foreground no-underline last:border-0 active:bg-muted"
        >
          <div class="min-w-0 flex-1">
            <p class="m-0 font-medium text-heading">{{ bangkokDateLong(b.starts_at) }}</p>
            <p class="m-0 truncate text-sm text-muted-foreground"><span class="num">{{ bangkokTime(b.starts_at) }}</span> น. · {{ b.branch.name }} · {{ services(b) }}</p>
            <span v-if="b.can_upload_slip" class="text-[13px] font-medium text-pending-ink">ต้องโอนมัดจำ</span>
          </div>
          <Badge :variant="bookingStatusVariant(b.status)" dot>{{ bookingStatusLabels[b.status] }}</Badge>
        </NuxtLink>
      </div>
    </template>
  </div>
</template>
