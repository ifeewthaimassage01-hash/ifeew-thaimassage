<script setup lang="ts">
// เนื้อหาแดชบอร์ดสาขา — รับข้อมูลทาง props (pages/index.vue เป็นคนโหลด)
//   หัว (ชื่อสาขา + วันที่) → คิวของฉัน (ถ้ามี) → สรุปการเงิน → ค่าแรงหมอ (เจ้าของร้าน) | เตียงและอุปกรณ์ตอนนี้ (จอใหญ่อยู่คู่กัน)
import { formatDuration, formatQueueNumber, queueStatusLabels, type StaffDashboard } from '@ifeew/shared'

defineProps<{
  dash: StaffDashboard | null
  error: string | null
  isOwner: boolean
  branchName?: string
  branchId?: string
  /** เพิ่มขึ้นเมื่อมีการเปลี่ยนแปลงแบบ realtime → การ์ดสรุปการเงินโหลดใหม่ */
  moneyTick?: number
}>()

// วันที่ของวันทำการ (เวลาไทย) เช่น วันอาทิตย์ที่ 15 พฤศจิกายน 2569
const todayLabel = new Date().toLocaleDateString('th-TH', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: 'Asia/Bangkok' })
</script>

<template>
  <div class="grid grid-cols-1 gap-4 sm:gap-5">
    <header class="grid gap-0.5">
      <h1 class="m-0 text-2xl leading-tight font-semibold md:text-[28px]">{{ branchName ?? 'แดชบอร์ด' }}</h1>
      <p class="m-0 text-[15px] text-muted-foreground">{{ todayLabel }}</p>
    </header>

    <Alert v-if="error" variant="destructive"><AlertDescription>{{ error }}</AlertDescription></Alert>

    <!-- คิวของฉัน (เฉพาะคนที่มีคิวมอบหมาย) -->
    <SectionCard v-if="dash?.my_queue.length" title="คิวของฉัน" :description="`${dash.my_queue.length} คิวที่มอบหมายให้คุณ`">
      <template #actions><Button as-child variant="outline" size="sm"><NuxtLink to="/queue">ไปที่คิว</NuxtLink></Button></template>
      <div class="flex flex-wrap gap-2">
        <NuxtLink
          v-for="q in dash.my_queue"
          :key="q.queue_id"
          to="/queue"
          class="flex items-center gap-3 rounded-lg border border-border bg-muted px-4 py-2.5 text-foreground no-underline hover:border-input"
        >
          <span class="num text-lg font-semibold text-heading">{{ formatQueueNumber(q.queue_number) }}</span>
          <span class="text-[15px]">{{ q.service_name }} <span class="text-muted-foreground">{{ formatDuration(q.duration_minutes) }}</span></span>
          <Badge>{{ queueStatusLabels[q.status] }}</Badge>
        </NuxtLink>
      </div>
    </SectionCard>

    <!-- สรุปการเงิน (เจ้าของร้าน) -->
    <DashboardMoneySummary v-if="isOwner && branchId" :branch-id="branchId" :tick="moneyTick" />

    <!-- จอใหญ่: ค่าแรงหมอ (เจ้าของร้าน) คู่กับ เตียงและอุปกรณ์ -->
    <div class="grid items-start gap-4 sm:gap-5 xl:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
      <DashboardTherapistPay v-if="isOwner && branchId" :branch-id="branchId" :tick="moneyTick" />
      <ResourceGrid v-if="dash || !error" :resources="dash?.resources ?? null" :loading="!dash" />
    </div>
  </div>
</template>
