<script setup lang="ts">
// ประวัติการใช้บริการของสมาชิก (เฉพาะบริการที่ทำเสร็จแล้ว)
import { bangkokDateLong, bangkokTime, formatBaht, formatDuration, type ServiceHistoryRow } from '@ifeew/shared'

definePageMeta({ middleware: 'auth' })
useHead({ title: "ประวัติการใช้บริการ — Ifeew's Thaimassage" })

const supabase = useSupabaseClient()
const { code } = useCompany()
const rows = ref<ServiceHistoryRow[]>([])
const loading = ref(true)

onMounted(async () => {
  const { data } = await supabase.rpc('my_service_history', { p_company_code: code })
  rows.value = (data ?? []) as unknown as ServiceHistoryRow[]
  loading.value = false
})
</script>

<template>
  <div>
    <div class="mb-4 flex items-center justify-between">
      <h1 class="m-0 text-2xl font-semibold text-cocoa">ประวัติการใช้บริการ</h1>
      <v-btn to="/bookings" variant="text">การจองของฉัน</v-btn>
    </div>
    <v-progress-linear v-if="loading" indeterminate color="primary" />
    <p v-else-if="!rows.length" class="text-light-brown">ยังไม่มีประวัติการใช้บริการ</p>

    <div class="grid gap-3">
      <v-card v-for="(r, n) in rows" :key="n" class="p-4">
        <div class="flex items-start justify-between gap-3">
          <div>
            <p class="m-0 font-medium">{{ r.service_name }} {{ formatDuration(r.duration_minutes) }}</p>
            <p class="m-0 text-sm text-light-brown">
              {{ bangkokDateLong(r.started_at) }} · {{ bangkokTime(r.started_at) }} น. · {{ r.branch_name }}
            </p>
            <p v-if="r.therapists.length" class="m-0 text-sm">หมอ: {{ r.therapists.join(', ') }}</p>
          </div>
          <p class="m-0 font-semibold text-cocoa">{{ formatBaht(Number(r.line_total)) }}</p>
        </div>
      </v-card>
    </div>
  </div>
</template>
