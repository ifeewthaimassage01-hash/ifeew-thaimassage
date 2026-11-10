<script setup lang="ts">
// แผงจองด่วน (หน้าแรก): สาขา → บริการ → วัน → เวลาว่างจริง (get_available_slots) → ไปหน้า /book พร้อมค่าที่เลือก
// ไม่สร้างการจองที่นี่ — การยืนยันจริงอยู่ที่หน้า /book เท่านั้น
import { CalendarDays, Clock, Flower2, MapPin, Search } from '@lucide/vue'
import { addDays, bangkokToday, formatDuration, type AvailableSlot } from '@ifeew/shared'
import type { PublicBranch } from '~/composables/useBranches'
import type { CatalogItem } from '~/composables/useCatalog'

const props = defineProps<{ branches: PublicBranch[]; catalog: CatalogItem[] }>()
const supabase = useSupabaseClient()

const today = bangkokToday()
const branchId = ref<string | null>(props.branches.length === 1 ? props.branches[0]!.id : null)
const serviceId = ref<string | null>(null)
const date = ref(addDays(today, 1))
const slotAt = ref<string | null>(null)

const services = computed(() => props.catalog.filter((c) => c.branch_id === branchId.value))
const service = computed(() => services.value.find((s) => s.branch_service_id === serviceId.value) ?? null)
// ระยะเวลาสั้นสุดของบริการ (เปลี่ยนได้ที่หน้าจอง)
const option = computed(() => service.value?.options[0] ?? null)
const serviceItems = computed(() =>
  services.value.map((s) => ({ value: s.branch_service_id, title: s.options.length > 1 ? s.name : `${s.name} · ${formatDuration(s.options[0]!.duration_minutes)}` })),
)

watch(branchId, () => {
  if (!services.value.some((s) => s.branch_service_id === serviceId.value)) serviceId.value = null
})

// เวลาว่างจริงของวันที่เลือก
const slots = ref<AvailableSlot[]>([])
const loadingSlots = ref(false)
let seq = 0
watch(
  [branchId, () => option.value?.option_id, date],
  async () => {
    slotAt.value = null
    slots.value = []
    if (!branchId.value || !option.value || !date.value) return
    const mine = ++seq
    loadingSlots.value = true
    const { data, error } = await supabase.rpc('get_available_slots', {
      p_branch_id: branchId.value, p_date: date.value, p_option_ids: [option.value.option_id],
    })
    if (mine !== seq) return
    loadingSlots.value = false
    slots.value = error ? [] : ((data ?? []) as unknown as AvailableSlot[])
  },
)
const timeItems = computed(() => slots.value.map((s) => ({ value: s.starts_at, title: `${s.time} น.` })))
const timePlaceholder = computed(() =>
  !option.value ? 'เลือกบริการก่อน' : loadingSlots.value ? 'กำลังโหลด…' : slots.value.length ? 'ทุกเวลา' : 'ไม่มีเวลาว่าง',
)

function go() {
  const query: Record<string, string> = {}
  if (branchId.value) query.branch = branchId.value
  if (serviceId.value) query.service = serviceId.value
  // เวลาว่างคำนวณจากระยะเวลาสั้นสุด จึงส่ง option นี้ไปด้วย (เปลี่ยนได้ที่หน้าจอง)
  if (option.value) query.option = option.value.option_id
  if (date.value) query.date = date.value
  if (slotAt.value && option.value) query.time = slotAt.value
  navigateTo({ path: '/book', query })
}

const label = 'flex items-center gap-2 text-[14px] font-medium text-heading'
</script>

<template>
  <form
    class="grid grid-cols-1 gap-4 rounded-2xl border border-border bg-card p-4 shadow-soft sm:p-5 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_minmax(0,1.35fr)_auto] lg:items-end lg:gap-0 lg:divide-x lg:divide-border lg:px-2 lg:py-5"
    aria-label="จองคิวด่วน"
    @submit.prevent="go"
  >
    <div class="grid gap-2 lg:px-5">
      <span :class="label"><MapPin class="size-[18px] text-brand-accent" :stroke-width="1.6" aria-hidden="true" /> เลือกสาขา</span>
      <SelectField v-model="branchId" :items="branches" item-title="name" item-value="id" placeholder="เลือกสาขา" aria-label="เลือกสาขา" />
    </div>
    <div class="grid gap-2 lg:px-5">
      <span :class="label"><Flower2 class="size-[18px] text-brand-accent" :stroke-width="1.6" aria-hidden="true" /> เลือกบริการ</span>
      <SelectField v-model="serviceId" :items="serviceItems" :disabled="!branchId" :placeholder="branchId ? 'เลือกบริการ' : 'เลือกสาขาก่อน'" aria-label="เลือกบริการ" />
    </div>
    <div class="grid gap-2 lg:px-5">
      <span :class="label"><CalendarDays class="size-[18px] text-brand-accent" :stroke-width="1.6" aria-hidden="true" /> เลือกวันและเวลา</span>
      <div class="grid grid-cols-[minmax(0,1fr)_minmax(0,1fr)] gap-2">
        <Input v-model="date" type="date" :min="today" :max="addDays(today, 13)" aria-label="วันที่" class="num" />
        <div class="relative min-w-0">
          <SelectField v-model="slotAt" :items="timeItems" :disabled="!timeItems.length" :placeholder="timePlaceholder" aria-label="เวลา" class="[&_button]:pl-9" />
          <Clock class="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-soft" aria-hidden="true" />
        </div>
      </div>
    </div>
    <div class="lg:px-5">
      <Button type="submit" size="lg" class="h-12 w-full rounded-full px-7 lg:w-auto"><Search class="lg:hidden" /> ค้นหาช่วงเวลา</Button>
    </div>
  </form>
</template>
