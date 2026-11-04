<script setup lang="ts">
import { bangkokToday, isoDowLabels, type Tables } from '@ifeew/shared'

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

const { data: services } = await useCatalog(branchId)

const grouped = computed(() => {
  const map = new Map<string, NonNullable<typeof services.value>>()
  for (const s of services.value ?? []) {
    const list = map.get(s.category_name) ?? []
    list.push(s)
    map.set(s.category_name, list)
  }
  return [...map.entries()]
})

const hhmm = (t: string | null) => (t ? t.slice(0, 5) : '')
const timeText = (r: { is_closed: boolean; opens_at: string | null; closes_at: string | null }) =>
  r.is_closed ? 'ปิด' : `${hhmm(r.opens_at)} – ${hhmm(r.closes_at)}${(r.closes_at ?? '') < (r.opens_at ?? '') ? ' (วันถัดไป)' : ''}`

useHead({ title: () => `${detail.value?.branch?.name ?? 'สาขา'} — Ifeew's Thaimassage` })
</script>

<template>
  <div v-if="detail?.branch">
    <v-btn variant="text" prepend-icon="mdi-arrow-left" to="/branches" class="mb-2">สาขาทั้งหมด</v-btn>
    <h1 class="m-0 mb-1 text-2xl font-semibold text-cocoa">{{ detail.branch.name }}</h1>
    <p class="m-0 mb-4 text-sm text-light-brown">{{ detail.branch.address }}</p>
    <div class="mb-6 flex flex-wrap gap-2">
      <v-btn v-if="detail.branch.phone" :href="`tel:${detail.branch.phone.replace(/\s|-/g, '')}`" variant="tonal" color="primary" prepend-icon="mdi-phone-outline">
        {{ detail.branch.phone }}
      </v-btn>
      <v-btn v-if="detail.branch.map_url" :href="detail.branch.map_url" target="_blank" rel="noopener" variant="text" prepend-icon="mdi-map-marker-outline">
        แผนที่
      </v-btn>
    </div>

    <v-card class="mb-6 p-5">
      <p class="m-0 mb-3 font-medium">เวลาทำการ</p>
      <div v-for="h in detail.hours" :key="h.iso_dow" class="flex justify-between py-1 text-sm">
        <span>{{ isoDowLabels[h.iso_dow] }}</span>
        <span :class="h.is_closed ? 'text-red-700' : ''">{{ timeText(h) }}</span>
      </div>
      <template v-if="detail.holidays.length">
        <p class="m-0 mb-2 mt-4 font-medium">วันหยุด / เวลาพิเศษ</p>
        <div v-for="h in detail.holidays" :key="h.holiday_date" class="flex justify-between py-1 text-sm">
          <span>{{ new Date(`${h.holiday_date}T00:00:00+07:00`).toLocaleDateString('th-TH', { dateStyle: 'medium', timeZone: 'Asia/Bangkok' }) }} · {{ h.name }}</span>
          <span :class="h.is_closed ? 'text-red-700' : ''">{{ timeText(h) }}</span>
        </div>
      </template>
    </v-card>

    <h2 class="m-0 mb-4 text-lg font-semibold text-cocoa">บริการ</h2>
    <p v-if="!services?.length" class="text-light-brown">ยังไม่มีบริการที่เปิดจอง</p>
    <div v-for="[category, items] in grouped" :key="category" class="mb-6">
      <p class="m-0 mb-2 text-sm font-medium text-light-brown">{{ category }}</p>
      <div class="grid gap-3">
        <ServiceCard v-for="s in items" :key="s.branch_service_id" :item="s" />
      </div>
    </div>
  </div>
  <v-alert v-else type="info" variant="tonal" text="ไม่พบสาขานี้" />
</template>
