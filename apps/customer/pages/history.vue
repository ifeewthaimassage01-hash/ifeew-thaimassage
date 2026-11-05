<script setup lang="ts">
// ประวัติการนวด (บริการที่ทำเสร็จแล้ว): การ์ดสรุป → ตาราง (เดสก์ท็อป) / รายการ (มือถือ)
import { Clock, Receipt, Sparkles } from '@lucide/vue'
import { bangkokDateLong, bangkokTime, formatBaht, formatDuration, type ServiceHistoryRow } from '@ifeew/shared'

definePageMeta({ middleware: 'auth' })
useHead({ title: "ประวัติการนวด — Ifeew's Thaimassage" })

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
const favourite = computed(() => {
  const count = new Map<string, number>()
  for (const r of rows.value) count.set(r.service_name, (count.get(r.service_name) ?? 0) + 1)
  return [...count.entries()].sort((a, b) => b[1] - a[1])[0] ?? null
})
</script>

<template>
  <div>
    <PageHeader title="ประวัติการนวด" description="บริการที่ใช้แล้ว พร้อมหมอที่นวดให้ เพื่อจองคนเดิมครั้งหน้า">
      <template #actions>
        <Button as-child variant="outline"><NuxtLink to="/bookings">การจองของฉัน</NuxtLink></Button>
      </template>
    </PageHeader>

    <div class="mb-8 grid gap-4 sm:grid-cols-3">
      <StatCard label="จำนวนครั้ง" :icon="Receipt" :value="loading ? null : rows.length" :hint="loading ? undefined : `รวม ${formatBaht(totalSpent)}`" />
      <StatCard label="เวลานวดรวม" :icon="Clock" :value="loading ? null : rows.length ? formatDuration(totalMinutes) : '0 นาที'" hint="ทุกสาขา" />
      <StatCard label="บริการที่ใช้บ่อย" :icon="Sparkles" :value="loading ? null : favourite?.[0] ?? '—'" :hint="favourite ? `${favourite[1]} ครั้ง` : 'ยังไม่มีข้อมูล'" />
    </div>

    <div v-if="loading" class="grid gap-2"><Skeleton v-for="n in 4" :key="n" class="h-14 rounded-lg" /></div>
    <Alert v-else-if="failed" variant="destructive"><AlertDescription>โหลดประวัติไม่สำเร็จ กรุณารีเฟรชหน้านี้</AlertDescription></Alert>
    <EmptyState v-else-if="!rows.length" title="ยังไม่มีประวัติการนวด" description="ประวัติจะขึ้นหลังใช้บริการที่ร้านเสร็จ">
      <Button as-child><NuxtLink to="/book">จองคิว</NuxtLink></Button>
    </EmptyState>

    <template v-else>
      <div class="hidden overflow-hidden rounded-xl border border-border bg-card md:block">
        <Table>
          <TableHeader>
            <TableRow class="hover:bg-transparent">
              <TableHead>วันที่</TableHead>
              <TableHead>บริการ</TableHead>
              <TableHead>สาขา</TableHead>
              <TableHead>หมอ</TableHead>
              <TableHead class="text-right">ค่าบริการ</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow v-for="(r, n) in rows" :key="n">
              <TableCell>
                <span class="text-heading">{{ bangkokDateLong(r.started_at) }}</span>
                <span class="num block text-sm text-muted-foreground">{{ bangkokTime(r.started_at) }} น.</span>
              </TableCell>
              <TableCell>{{ r.service_name }} <span class="text-muted-foreground">{{ formatDuration(r.duration_minutes) }}</span></TableCell>
              <TableCell>{{ r.branch_name }}</TableCell>
              <TableCell>{{ r.therapists.length ? r.therapists.join(', ') : '—' }}</TableCell>
              <TableCell class="num text-right text-heading">{{ formatBaht(Number(r.line_total)) }}</TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </div>

      <div class="grid overflow-hidden rounded-xl border border-border bg-card md:hidden">
        <div v-for="(r, n) in rows" :key="n" class="flex items-start gap-3 border-b border-border px-4 py-3.5 last:border-0">
          <div class="min-w-0 flex-1">
            <p class="m-0 font-medium text-heading">{{ r.service_name }} <span class="font-normal text-muted-foreground">{{ formatDuration(r.duration_minutes) }}</span></p>
            <p class="m-0 text-sm text-muted-foreground">{{ bangkokDateLong(r.started_at) }} · {{ r.branch_name }}</p>
            <p v-if="r.therapists.length" class="m-0 text-sm">หมอ {{ r.therapists.join(', ') }}</p>
          </div>
          <span class="num shrink-0 font-semibold text-heading">{{ formatBaht(Number(r.line_total)) }}</span>
        </div>
      </div>
    </template>
  </div>
</template>
