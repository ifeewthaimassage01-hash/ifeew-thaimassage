<script setup lang="ts">
// รายการการจอง แบ่ง "กำลังจะถึง" / "ที่ผ่านมา" — กดเปิด /t/<token> (token ชั่วคราว 30 นาที)
// ใช้ในหน้าตรวจสอบการจอง ทั้งแบบค้นหาด้วยเบอร์โทรและ "การจองของฉัน" (LINE)
import { ChevronRight } from '@lucide/vue'
import { bangkokDateLong, bangkokTime, bookingStatusLabels, type BookingView } from '@ifeew/shared'

const props = defineProps<{ bookings: Array<BookingView & { tracking_token?: string | null }> }>()

const isUpcoming = (b: BookingView) => ['PENDING', 'CONFIRMED'].includes(b.status)
const upcoming = computed(() => props.bookings.filter(isUpcoming).sort((a, b) => a.starts_at.localeCompare(b.starts_at)))
const past = computed(() => props.bookings.filter((b) => !isUpcoming(b)).sort((a, b) => b.starts_at.localeCompare(a.starts_at)))
const services = (b: BookingView) => b.items.map((i) => i.service_name).join(', ')
</script>

<template>
  <div class="grid gap-6">
    <section v-for="sec in ([['กำลังจะถึง', upcoming], ['ที่ผ่านมา', past]] as const)" v-show="sec[1].length" :key="sec[0]">
      <h2 class="mb-2 text-[15px] font-medium text-muted-foreground">
        {{ sec[0] }} <span class="num">{{ sec[1].length }}</span>
      </h2>
      <ul class="m-0 grid list-none overflow-hidden rounded-xl border border-border bg-card p-0">
        <li v-for="b in sec[1]" :key="b.booking_id" class="border-b border-border last:border-0">
          <NuxtLink
            :to="`/t/${b.tracking_token}`"
            class="flex items-center gap-3 px-4 py-3.5 text-foreground no-underline transition-colors hover:bg-muted active:bg-muted"
          >
            <div class="min-w-0 flex-1">
              <p class="m-0 font-medium text-heading">{{ bangkokDateLong(b.starts_at) }}</p>
              <p class="m-0 text-sm text-muted-foreground">
                <span class="num">{{ bangkokTime(b.starts_at) }}–{{ bangkokTime(b.ends_at) }}</span> น. {{ b.branch.name }}
              </p>
              <p class="m-0 truncate text-sm text-muted-foreground">{{ services(b) }}</p>
              <span v-if="b.can_upload_slip" class="text-[13px] font-medium text-pending-ink">ต้องโอนมัดจำ</span>
            </div>
            <Badge :variant="bookingStatusVariant(b.status)" dot>{{ bookingStatusLabels[b.status] }}</Badge>
            <ChevronRight class="size-4 shrink-0 text-muted-soft" aria-hidden="true" />
          </NuxtLink>
        </li>
      </ul>
    </section>
  </div>
</template>
