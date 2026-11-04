<script setup lang="ts">
import { MapPin, Phone } from '@lucide/vue'
import type { PublicBranch } from '~/composables/useBranches'
import type { TodayHours } from '~/composables/useOpenToday'

const props = defineProps<{ branch: PublicBranch; hours?: TodayHours | null }>()
// วางสองคอลัมน์เฉพาะเมื่อมีแถบเวลาเปิดให้วาด (วันนี้เปิด) ไม่งั้นป้าย 'วันนี้ปิด' จะลอยอยู่กลางการ์ด
const wide = computed(() => !!props.hours && !props.hours.closed)
const tel = (p: string) => `tel:${p.replace(/\s|-/g, '')}`
</script>

<template>
  <!-- @container: การ์ดกว้าง (สาขาเดียวเต็มแถว) วางข้อมูลซ้าย เวลาเปิดขวา; การ์ดแคบเรียงลงมา -->
  <Card class="@container gap-4 py-5">
    <CardContent class="grid gap-4 px-5" :class="wide ? '@2xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] @2xl:gap-x-10' : ''">
      <div class="min-w-0">
        <h3 class="m-0 text-lg font-semibold leading-snug">
          <NuxtLink :to="`/branches/${branch.id}`" class="text-foreground no-underline hover:underline">{{ branch.name }}</NuxtLink>
        </h3>
        <p v-if="branch.address" class="m-0 mt-0.5 text-[15px] text-muted-foreground">{{ branch.address }}</p>
      </div>
      <OpenToday :hours="hours" :class="wide ? '@2xl:row-span-2 @2xl:self-center' : ''" />
      <div class="flex flex-wrap gap-2" :class="wide ? '@2xl:col-start-1' : ''">
        <Button as-child size="sm"><NuxtLink :to="{ path: '/book', query: { branch: branch.id } }">จองสาขานี้</NuxtLink></Button>
        <Button v-if="branch.phone" as-child variant="outline" size="sm">
          <a :href="tel(branch.phone)"><Phone /> <span class="num">{{ branch.phone }}</span></a>
        </Button>
        <Button v-if="branch.map_url" as-child variant="ghost" size="sm">
          <a :href="branch.map_url" target="_blank" rel="noopener"><MapPin /> แผนที่</a>
        </Button>
      </div>
    </CardContent>
  </Card>
</template>
