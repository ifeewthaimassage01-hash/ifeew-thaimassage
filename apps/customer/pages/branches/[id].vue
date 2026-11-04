<script setup lang="ts">
import { ArrowLeft, MapPin, Phone } from '@lucide/vue'
import { bangkokToday, isoDowLabels, type Tables } from '@ifeew/shared'
import { isoDow } from '~/composables/useOpenToday'

const route = useRoute()
const supabase = useSupabaseClient()
const branchId = computed(() => String(route.params.id))

type Hours = Pick<Tables<'branch_opening_hours'>, 'iso_dow' | 'is_closed' | 'opens_at' | 'closes_at'>
type Holiday = Pick<Tables<'branch_holidays'>, 'holiday_date' | 'name' | 'is_closed' | 'opens_at' | 'closes_at'>

const { data: detail } = await useAsyncData(`branch-${branchId.value}`, async () => {
  const [b, h, hol] = await Promise.all([
    supabase.from('branches').select('id, name, address, phone, map_url').eq('id', branchId.value).maybeSingle(),
    supabase.from('branch_opening_hours').select('iso_dow, is_closed, opens_at, closes_at').eq('branch_id', branchId.value).order('iso_dow'),
    supabase
      .from('branch_holidays')
      .select('holiday_date, name, is_closed, opens_at, closes_at')
      .eq('branch_id', branchId.value)
      .eq('is_active', true)
      .gte('holiday_date', bangkokToday())
      .order('holiday_date')
      .limit(10),
  ])
  return { branch: b.data, hours: (h.data ?? []) as Hours[], holidays: (hol.data ?? []) as Holiday[] }
})

const ids = computed(() => [branchId.value])
const { data: today } = await useOpenToday(ids)
const { data: services } = await useCatalog(branchId)

const grouped = computed(() => {
  const map = new Map<string, NonNullable<typeof services.value>>()
  for (const s of services.value ?? []) map.set(s.category_name, [...(map.get(s.category_name) ?? []), s])
  return [...map.entries()]
})

const todayDow = isoDow(bangkokToday())
const hhmm = (t: string | null) => (t ? t.slice(0, 5) : '')
const timeText = (r: { is_closed: boolean; opens_at: string | null; closes_at: string | null }) =>
  r.is_closed ? 'ปิด' : `${hhmm(r.opens_at)}–${hhmm(r.closes_at)}${(r.closes_at ?? '') < (r.opens_at ?? '') ? ' (ถึงวันถัดไป)' : ''}`
const tel = (p: string) => `tel:${p.replace(/\s|-/g, '')}`

useHead({ title: () => `${detail.value?.branch?.name ?? 'สาขา'} — Ifeew's Thaimassage` })
</script>

<template>
  <div class="grid gap-4">
    <NuxtLink to="/branches" class="inline-flex w-fit items-center gap-1.5 text-[15px] text-muted-foreground no-underline hover:text-foreground">
      <ArrowLeft class="size-4" /> สาขาทั้งหมด
    </NuxtLink>

    <template v-if="detail?.branch">
      <div class="flex flex-wrap items-end justify-between gap-4">
        <div class="min-w-0">
          <h1 class="m-0 text-[28px] font-semibold leading-tight tracking-tight">{{ detail.branch.name }}</h1>
          <p v-if="detail.branch.address" class="m-0 mt-1 text-muted-foreground">{{ detail.branch.address }}</p>
        </div>
        <div class="flex flex-wrap gap-2">
          <Button as-child><NuxtLink :to="{ path: '/book', query: { branch: detail.branch.id } }">จองสาขานี้</NuxtLink></Button>
          <Button v-if="detail.branch.phone" as-child variant="outline">
            <a :href="tel(detail.branch.phone)"><Phone /> <span class="num">{{ detail.branch.phone }}</span></a>
          </Button>
          <Button v-if="detail.branch.map_url" as-child variant="ghost">
            <a :href="detail.branch.map_url" target="_blank" rel="noopener"><MapPin /> แผนที่</a>
          </Button>
        </div>
      </div>

      <div class="grid items-start gap-6 md:grid-cols-[320px_minmax(0,1fr)]">
        <Card class="gap-4 py-5">
          <CardHeader class="px-5"><CardTitle>เวลาทำการ</CardTitle></CardHeader>
          <CardContent class="grid gap-4 px-5">
            <OpenToday :hours="today?.[detail.branch.id] ?? null" />
            <dl class="m-0 grid">
              <div
                v-for="h in detail.hours"
                :key="h.iso_dow"
                class="-mx-2 flex justify-between rounded-md px-2 py-1.5 text-[15px]"
                :class="h.iso_dow === todayDow ? 'bg-muted font-medium' : ''"
              >
                <dt>{{ isoDowLabels[h.iso_dow] }}<span v-if="h.iso_dow === todayDow" class="text-muted-foreground"> · วันนี้</span></dt>
                <dd class="num m-0" :class="h.is_closed ? 'text-muted-foreground' : ''">{{ timeText(h) }}</dd>
              </div>
            </dl>
            <template v-if="detail.holidays.length">
              <h3 class="m-0 text-base font-semibold">วันหยุดและเวลาพิเศษ</h3>
              <dl class="m-0 grid gap-1">
                <div v-for="h in detail.holidays" :key="h.holiday_date" class="flex justify-between gap-3 text-[15px]">
                  <dt>{{ new Date(`${h.holiday_date}T00:00:00+07:00`).toLocaleDateString('th-TH', { day: 'numeric', month: 'short', timeZone: 'Asia/Bangkok' }) }} · {{ h.name }}</dt>
                  <dd class="num m-0 shrink-0" :class="h.is_closed ? 'text-tint-danger-ink' : ''">{{ timeText(h) }}</dd>
                </div>
              </dl>
            </template>
          </CardContent>
        </Card>

        <section class="grid gap-4" aria-labelledby="svc-h">
          <h2 id="svc-h" class="m-0 text-xl font-semibold">บริการที่สาขานี้</h2>
          <p v-if="!services?.length" class="m-0 rounded-lg border border-dashed px-4 py-3 text-muted-foreground">ยังไม่มีบริการที่เปิดจอง</p>
          <div v-for="[category, items] in grouped" :key="category" class="grid gap-3">
            <h3 class="m-0 flex items-center gap-2 text-base font-semibold">
              <span class="size-2.5 rounded-full" :class="categoryTint(category)" aria-hidden="true" />{{ category }}
            </h3>
            <ServiceCard v-for="s in items" :key="s.branch_service_id" :item="s" />
          </div>
        </section>
      </div>
    </template>
    <Alert v-else variant="info"><AlertDescription>ไม่พบสาขานี้</AlertDescription></Alert>
  </div>
</template>
