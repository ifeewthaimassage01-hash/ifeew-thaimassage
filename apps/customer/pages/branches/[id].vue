<script setup lang="ts">
import { MapPin, Phone } from '@lucide/vue'
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

const todayDow = isoDow(bangkokToday())
const hhmm = (t: string | null) => (t ? t.slice(0, 5) : '')
const timeText = (r: { is_closed: boolean; opens_at: string | null; closes_at: string | null }) =>
  r.is_closed ? 'ปิด' : `${hhmm(r.opens_at)}–${hhmm(r.closes_at)}${(r.closes_at ?? '') < (r.opens_at ?? '') ? ' (ถึงวันถัดไป)' : ''}`
const tel = (p: string) => `tel:${p.replace(/\s|-/g, '')}`

useHead({ title: () => `${detail.value?.branch?.name ?? 'สาขา'} — Ifeew's Thaimassage` })
</script>

<template>
  <div v-if="detail?.branch">
    <PageHeader :title="detail.branch.name" :description="detail.branch.address ?? undefined">
      <template #actions>
        <Button v-if="detail.branch.map_url" as-child variant="ghost">
          <a :href="detail.branch.map_url" target="_blank" rel="noopener"><MapPin /> แผนที่</a>
        </Button>
        <Button v-if="detail.branch.phone" as-child variant="outline">
          <a :href="tel(detail.branch.phone)"><Phone /> <span class="num">{{ detail.branch.phone }}</span></a>
        </Button>
        <Button as-child><NuxtLink :to="{ path: '/book', query: { branch: detail.branch.id } }">จองสาขานี้</NuxtLink></Button>
      </template>
    </PageHeader>

    <div class="grid items-start gap-8 lg:grid-cols-[320px_minmax(0,1fr)]">
      <Card class="gap-0 py-0">
        <div class="grid gap-3 border-b border-border p-5">
          <h2 class="m-0 text-base font-semibold">เวลาทำการ</h2>
          <OpenToday :hours="today?.[detail.branch.id] ?? null" />
        </div>
        <dl class="m-0 grid px-3 py-2">
          <div
            v-for="h in detail.hours"
            :key="h.iso_dow"
            class="flex justify-between rounded-md px-2 py-2 text-[15px]"
            :class="h.iso_dow === todayDow ? 'bg-muted font-medium text-heading' : ''"
          >
            <dt>{{ isoDowLabels[h.iso_dow] }}<span v-if="h.iso_dow === todayDow" class="font-normal"> · วันนี้</span></dt>
            <dd class="num m-0" :class="h.is_closed ? 'text-muted-foreground' : ''">{{ timeText(h) }}</dd>
          </div>
          <p v-if="!detail.hours.length" class="m-0 px-2 py-2 text-[15px] text-muted-foreground">ยังไม่ได้ระบุเวลาทำการ</p>
        </dl>
        <div v-if="detail.holidays.length" class="grid gap-2 border-t border-border p-5">
          <h3 class="m-0 text-[15px] font-semibold">วันหยุดและเวลาพิเศษ</h3>
          <dl class="m-0 grid gap-1">
            <div v-for="h in detail.holidays" :key="h.holiday_date" class="flex justify-between gap-3 text-[15px]">
              <dt>{{ new Date(`${h.holiday_date}T00:00:00+07:00`).toLocaleDateString('th-TH', { day: 'numeric', month: 'short', timeZone: 'Asia/Bangkok' }) }} · {{ h.name }}</dt>
              <dd class="num m-0 shrink-0" :class="h.is_closed ? 'text-danger-ink' : ''">{{ timeText(h) }}</dd>
            </div>
          </dl>
        </div>
      </Card>

      <section class="grid gap-4" aria-labelledby="svc-h">
        <h2 id="svc-h" class="m-0 text-lg font-semibold">บริการที่สาขานี้</h2>
        <EmptyState v-if="!services?.length" compact title="ยังไม่มีบริการที่เปิดจองออนไลน์" description="โทรสอบถามและจองที่สาขาได้" />
        <div v-else class="grid gap-4 sm:grid-cols-2">
          <ServiceCard v-for="s in services" :key="s.branch_service_id" :item="s" />
        </div>
      </section>
    </div>
  </div>
  <EmptyState v-else title="ไม่พบสาขานี้">
    <Button as-child variant="outline"><NuxtLink to="/branches">ดูสาขาทั้งหมด</NuxtLink></Button>
  </EmptyState>
</template>
