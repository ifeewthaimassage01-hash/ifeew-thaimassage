<script setup lang="ts">
// ประวัติการจองของสมาชิก
import { bangkokDateLong, bangkokTime, bookingStatusLabels, type BookingView } from '@ifeew/shared'

definePageMeta({ middleware: 'auth' })
useHead({ title: "การจองของฉัน — Ifeew's Thaimassage" })

const supabase = useSupabaseClient()
const { code } = useCompany()
const bookings = ref<BookingView[]>([])
const loading = ref(true)

onMounted(async () => {
  const { data } = await supabase.rpc('my_bookings', { p_company_code: code })
  bookings.value = (data ?? []) as unknown as BookingView[]
  loading.value = false
})

const upcoming = computed(() => bookings.value.filter((b) => ['PENDING', 'CONFIRMED'].includes(b.status)))
const past = computed(() => bookings.value.filter((b) => !['PENDING', 'CONFIRMED'].includes(b.status)))
</script>

<template>
  <div>
    <div class="mb-4 flex items-center justify-between">
      <h1 class="m-0 text-2xl font-semibold text-cocoa">การจองของฉัน</h1>
      <v-btn to="/book" color="primary" prepend-icon="mdi-plus">จองใหม่</v-btn>
    </div>
    <v-progress-linear v-if="loading" indeterminate color="primary" />
    <p v-else-if="!bookings.length" class="text-light-brown">ยังไม่มีการจอง</p>

    <template v-for="[title, list] in ([['กำลังจะถึง', upcoming], ['ที่ผ่านมา', past]] as const)" :key="title">
      <h2 v-if="list.length" class="m-0 mb-2 mt-4 text-lg font-medium">{{ title }}</h2>
      <div class="grid gap-3">
        <v-card v-for="b in list" :key="b.booking_id" :to="`/bookings/${b.booking_id}`" class="p-4">
          <div class="flex items-start justify-between gap-3">
            <div>
              <p class="m-0 font-medium">{{ bangkokDateLong(b.starts_at) }} · {{ bangkokTime(b.starts_at) }} น.</p>
              <p class="m-0 text-sm text-light-brown">{{ b.branch.name }} · {{ b.items.map((i) => i.service_name).join(', ') }}</p>
            </div>
            <v-chip size="small" variant="tonal">{{ bookingStatusLabels[b.status] }}</v-chip>
          </div>
        </v-card>
      </div>
    </template>
  </div>
</template>
