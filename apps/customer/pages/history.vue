<script setup lang="ts">
// ประวัติการใช้บริการของสมาชิก (เฉพาะบริการที่ทำเสร็จแล้ว) — "เคยนวดอะไร กับหมอคนไหน"
import { bangkokDateLong, bangkokTime, formatBaht, formatDuration, type ServiceHistoryRow } from '@ifeew/shared'

definePageMeta({ middleware: 'auth' })
useHead({ title: "ประวัติการใช้บริการ — Ifeew's Thaimassage" })

const supabase = useSupabaseClient()
const { code } = useCompany()
const rows = ref<ServiceHistoryRow[]>([])
const loading = ref(true)
const failed = ref(false)

onMounted(async () => {
  const { data, error } = await supabase.rpc('my_service_history', { p_company_code: code })
  failed.value = !!error
  rows.value = (data ?? []) as unknown as ServiceHistoryRow[]
  loading.value = false
})

const totalSpent = computed(() => rows.value.reduce((s, r) => s + Number(r.line_total), 0))
const totalMinutes = computed(() => rows.value.reduce((s, r) => s + r.duration_minutes, 0))
</script>

<template>
  <div class="grid gap-6">
    <div class="flex flex-wrap items-end justify-between gap-3">
      <div>
        <h1 class="m-0 text-[28px] font-semibold leading-tight tracking-tight">ประวัติการนวด</h1>
        <p v-if="!loading && rows.length" class="m-0 mt-1 text-muted-foreground">
          <span class="num">{{ rows.length }}</span> ครั้ง · รวม {{ formatDuration(totalMinutes) }} · <span class="num">{{ formatBaht(totalSpent) }}</span>
        </p>
      </div>
      <Button as-child variant="outline"><NuxtLink to="/bookings">การจองของฉัน</NuxtLink></Button>
    </div>

    <div v-if="loading" class="grid gap-3"><Skeleton v-for="n in 3" :key="n" class="h-20 rounded-xl" /></div>
    <Alert v-else-if="failed" variant="destructive"><AlertDescription>โหลดประวัติไม่สำเร็จ กรุณารีเฟรชหน้านี้</AlertDescription></Alert>
    <div v-else-if="!rows.length" class="grid justify-items-start gap-3 rounded-xl border border-dashed p-6">
      <p class="m-0">ยังไม่มีประวัติการนวด ประวัติจะขึ้นหลังใช้บริการที่ร้านเสร็จ</p>
      <Button as-child><NuxtLink to="/book">จองคิว</NuxtLink></Button>
    </div>

    <Card v-else class="gap-0 py-1">
      <div v-for="(r, n) in rows" :key="n" class="flex items-start gap-4 border-b border-border/70 px-5 py-4 last:border-0">
        <div class="min-w-0 flex-1">
          <p class="m-0 font-medium">{{ r.service_name }} <span class="font-normal text-muted-foreground">{{ formatDuration(r.duration_minutes) }}</span></p>
          <p class="m-0 text-[15px] text-muted-foreground">{{ bangkokDateLong(r.started_at) }} · <span class="num">{{ bangkokTime(r.started_at) }}</span> น. · {{ r.branch_name }}</p>
          <p v-if="r.therapists.length" class="m-0 text-[15px]">หมอ {{ r.therapists.join(', ') }}</p>
        </div>
        <p class="num m-0 shrink-0 text-right font-semibold">{{ formatBaht(Number(r.line_total)) }}</p>
      </div>
    </Card>
  </div>
</template>
