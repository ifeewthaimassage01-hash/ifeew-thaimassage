<script setup lang="ts">
// เตียงและอุปกรณ์ตอนนี้ แบบตาราง (grid) — ใช้ในแดชบอร์ดและหน้าร้าน (POS)
// แต่ละช่อง: ชื่อ · ว่างกี่ตัวจากทั้งหมด (ตัวใหญ่) · แถบการใช้งาน · ซ่อมบำรุง/ปิดใช้งาน
import { BedDouble } from '@lucide/vue'
import type { StaffDashboard } from '@ifeew/shared'

defineProps<{ resources: StaffDashboard['resources'] | null; loading?: boolean }>()

const free = (r: StaffDashboard['resources'][number]) => Math.max(0, r.total - r.in_use)
</script>

<template>
  <section class="rounded-xl border border-border bg-card p-4 shadow-soft sm:p-5" aria-labelledby="res-grid-h">
    <h2 id="res-grid-h" class="m-0 mb-3 text-[15px] font-semibold">เตียงและอุปกรณ์ตอนนี้</h2>

    <div v-if="!resources && loading" class="grid grid-cols-[repeat(auto-fill,minmax(min(9.5rem,100%),1fr))] gap-2.5">
      <Skeleton v-for="n in 3" :key="n" class="h-[6.5rem] rounded-lg" />
    </div>
    <p v-else-if="!resources?.length" class="m-0 py-4 text-center text-sm text-muted-foreground">ยังไม่ได้ตั้งค่าเตียงและอุปกรณ์</p>
    <ul v-else class="m-0 grid list-none grid-cols-[repeat(auto-fill,minmax(min(9.5rem,100%),1fr))] gap-2.5 p-0">
      <li
        v-for="r in resources"
        :key="r.resource_type_id"
        class="grid content-between gap-2 rounded-lg border p-3"
        :class="r.status !== 'ACTIVE' ? 'border-danger/40 bg-danger-soft/40' : free(r) > 0 ? 'border-border bg-muted/40' : 'border-pending-ink/30 bg-pending-soft/50'"
      >
        <div class="flex items-start gap-2">
          <span class="grid size-7 shrink-0 place-items-center rounded-full bg-card text-brand-accent" aria-hidden="true"><BedDouble class="size-4" :stroke-width="1.6" /></span>
          <span class="line-clamp-2 min-w-0 text-sm leading-snug font-medium text-heading" :title="r.name">{{ r.name }}</span>
        </div>

        <template v-if="r.status !== 'ACTIVE'">
          <p class="m-0 text-sm font-semibold text-danger-ink">{{ r.status === 'MAINTENANCE' ? 'ซ่อมบำรุง' : 'ปิดใช้งาน' }}</p>
        </template>
        <template v-else>
          <p class="m-0 flex items-baseline gap-1" :class="free(r) > 0 ? 'text-success-ink' : 'text-pending-ink'">
            <span class="text-xs">{{ free(r) > 0 ? 'ว่าง' : 'เต็ม' }}</span>
            <span class="num text-2xl leading-none font-semibold">{{ free(r) }}</span>
            <span class="num text-sm text-muted-foreground">/ {{ r.total }}</span>
          </p>
          <span class="block h-1.5 overflow-hidden rounded-full bg-card" role="img" :aria-label="`ใช้อยู่ ${r.in_use} จาก ${r.total}`">
            <span class="block h-full rounded-full bg-brand-accent" :style="{ width: `${r.total ? Math.min(100, (r.in_use / r.total) * 100) : 0}%` }" />
          </span>
        </template>
      </li>
    </ul>
  </section>
</template>
