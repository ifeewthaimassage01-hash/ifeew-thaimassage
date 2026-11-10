<script setup lang="ts">
// เนื้อหาแดชบอร์ดสาขา — รับข้อมูลทาง props (pages/index.vue เป็นคนโหลด)
//   คิวของฉัน (ถ้ามี) → สรุปการเงิน (เจ้าของร้าน) → เตียงและอุปกรณ์ตอนนี้
import { BedDouble } from '@lucide/vue'
import { formatDuration, formatQueueNumber, queueStatusLabels, type StaffDashboard } from '@ifeew/shared'

defineProps<{
  dash: StaffDashboard | null
  error: string | null
  isOwner: boolean
  branchName?: string
  branchId?: string
}>()
</script>

<template>
  <div class="grid grid-cols-1 gap-5">
    <h1 class="sr-only">แดชบอร์ด {{ branchName }}</h1>

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
    <DashboardMoneySummary v-if="isOwner && branchId" :branch-id="branchId" />

    <!-- เตียงและอุปกรณ์ -->
    <Skeleton v-if="!dash && !error" class="h-40 rounded-xl" />
    <section v-else-if="dash" class="rounded-xl border border-border bg-card p-5 shadow-soft" aria-labelledby="res-h">
      <h2 id="res-h" class="m-0 mb-3 text-[15px] font-semibold">เตียงและอุปกรณ์ตอนนี้</h2>
      <p v-if="!dash.resources.length" class="m-0 py-4 text-center text-sm text-muted-foreground">ยังไม่ได้ตั้งค่าเตียงและอุปกรณ์</p>
      <ul v-else class="m-0 grid list-none gap-x-8 p-0 md:grid-cols-2">
        <li v-for="r in dash.resources" :key="r.resource_type_id" class="flex items-center gap-3 border-b border-border/70 py-2.5">
          <span class="grid size-8 shrink-0 place-items-center rounded-full bg-muted text-brand-accent" aria-hidden="true"><BedDouble class="size-4" :stroke-width="1.6" /></span>
          <span class="min-w-0 flex-1">
            <span class="block truncate text-[14px] text-heading">{{ r.name }}</span>
            <span class="mt-1 block h-1.5 overflow-hidden rounded-full bg-muted" role="img" :aria-label="`ใช้อยู่ ${r.in_use} จาก ${r.total}`">
              <span class="block h-full rounded-full bg-brand-accent" :style="{ width: `${r.total ? Math.min(100, (r.in_use / r.total) * 100) : 0}%` }" />
            </span>
          </span>
          <Badge v-if="r.status !== 'ACTIVE'" variant="danger" class="shrink-0">{{ r.status === 'MAINTENANCE' ? 'ซ่อมบำรุง' : 'ปิดใช้งาน' }}</Badge>
          <Badge v-else :variant="r.total - r.in_use > 0 ? 'success' : 'pending'" class="shrink-0">
            ว่าง <span class="num">{{ Math.max(0, r.total - r.in_use) }}/{{ r.total }}</span>
          </Badge>
        </li>
      </ul>
    </section>
  </div>
</template>
