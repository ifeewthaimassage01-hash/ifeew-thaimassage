<script setup lang="ts">
// การจองของสมาชิก — คำถามของหน้า: "นัดครั้งถัดไปเมื่อไร ต้องทำอะไรไหม"
import { Plus } from '@lucide/vue'
import { bangkokDateLong, bangkokTime, bookingStatusLabels, type BookingView } from '@ifeew/shared'

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

const upcoming = computed(() => bookings.value.filter((b) => ['PENDING', 'CONFIRMED'].includes(b.status)))
const past = computed(() => bookings.value.filter((b) => !['PENDING', 'CONFIRMED'].includes(b.status)))

type BadgeVariant = 'positive' | 'warning' | 'destructive' | 'neutral' | 'default'
const variantOf = (s: string): BadgeVariant =>
  (({ CONFIRMED: 'positive', PENDING: 'warning', CANCELLED: 'destructive', NO_SHOW: 'destructive', EXPIRED: 'neutral' }) as Record<string, BadgeVariant>)[s] ?? 'default'
// ต้องทำอะไรต่อ: รอโอนมัดจำ
const todo = (b: BookingView) => (b.can_upload_slip ? 'ต้องโอนมัดจำ' : null)
</script>

<template>
  <div class="grid gap-6">
    <div class="flex flex-wrap items-end justify-between gap-3">
      <div>
        <h1 class="m-0 text-[28px] font-semibold leading-tight tracking-tight">การจองของฉัน</h1>
        <p v-if="!loading" class="m-0 mt-1 text-muted-foreground">กำลังจะถึง <span class="num">{{ upcoming.length }}</span> · ที่ผ่านมา <span class="num">{{ past.length }}</span></p>
      </div>
      <div class="flex gap-2">
        <Button as-child variant="outline"><NuxtLink to="/history">ประวัติการนวด</NuxtLink></Button>
        <Button as-child><NuxtLink to="/book"><Plus /> จองใหม่</NuxtLink></Button>
      </div>
    </div>

    <div v-if="loading" class="grid gap-3"><Skeleton v-for="n in 3" :key="n" class="h-20 rounded-xl" /></div>
    <Alert v-else-if="failed" variant="destructive"><AlertDescription>โหลดการจองไม่สำเร็จ กรุณารีเฟรชหน้านี้</AlertDescription></Alert>
    <div v-else-if="!bookings.length" class="grid justify-items-start gap-3 rounded-xl border border-dashed p-6">
      <p class="m-0">ยังไม่มีการจอง</p>
      <Button as-child><NuxtLink to="/book">จองคิวแรก</NuxtLink></Button>
    </div>

    <template v-for="[title, list] in ([['กำลังจะถึง', upcoming], ['ที่ผ่านมา', past]] as const)" :key="title">
      <section v-if="list.length" class="grid gap-3">
        <h2 class="m-0 text-xl font-semibold">{{ title }}</h2>
        <Card class="gap-0 py-1">
          <NuxtLink
            v-for="b in list"
            :key="b.booking_id"
            :to="`/bookings/${b.booking_id}`"
            class="flex items-center gap-4 border-b border-border/70 px-5 py-4 text-foreground no-underline transition-colors last:border-0 hover:bg-muted/50"
          >
            <div class="min-w-0 flex-1">
              <p class="m-0 font-medium">{{ bangkokDateLong(b.starts_at) }} · <span class="num">{{ bangkokTime(b.starts_at) }}</span> น.</p>
              <p class="m-0 truncate text-[15px] text-muted-foreground">{{ b.branch.name }} · {{ b.items.map((i) => i.service_name).join(', ') }}</p>
            </div>
            <div class="flex shrink-0 flex-col items-end gap-1">
              <Badge :variant="variantOf(b.status)">{{ bookingStatusLabels[b.status] }}</Badge>
              <span v-if="todo(b)" class="text-sm font-medium text-tint-warn-ink">{{ todo(b) }}</span>
            </div>
          </NuxtLink>
        </Card>
      </section>
    </template>
  </div>
</template>
