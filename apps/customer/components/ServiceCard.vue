<script setup lang="ts">
import { Clock, HandHeart } from '@lucide/vue'
import { formatBaht, formatDuration } from '@ifeew/shared'
import type { CatalogItem } from '~/composables/useCatalog'

// การ์ดบริการ
//   layout="card" (ค่าเริ่มต้น): รูปบน · หมวด · ชื่อ · ระยะเวลา · ราคาเริ่มต้น — ทั้งการ์ดเป็นลิงก์
//   layout="row" (หน้าแรก ตามภาพอ้างอิง): รูปซ้าย · ชื่อ · คำอธิบาย · ระยะเวลา+ราคาเริ่มต้น · ปุ่ม "จองเลย"
const props = withDefaults(defineProps<{ item: CatalogItem; branchName?: string; layout?: 'card' | 'row' }>(), { layout: 'card' })
const image = computed(() => serviceImageUrl(props.item.image_path) ?? fallbackServiceImage(props.item.name))
const cheapest = computed(() => props.item.options.reduce((a, b) => (b.price < a.price ? b : a), props.item.options[0]!))
const from = computed(() => cheapest.value.price)
const durations = computed(() => props.item.options.map((o) => formatDuration(o.duration_minutes)).join(' · '))
const detail = computed(() => `/services/${props.item.branch_service_id}`)
</script>

<template>
  <NuxtLink
    v-if="layout === 'card'"
    :to="detail"
    class="group flex flex-col overflow-hidden rounded-xl border border-border bg-card text-foreground no-underline shadow-soft transition-colors hover:border-input"
  >
    <div class="aspect-[16/10] overflow-hidden bg-secondary">
      <img v-if="image" :src="image" :alt="item.name" class="size-full object-cover transition-transform duration-300 group-hover:scale-[1.02]" loading="lazy">
      <div v-else class="grid size-full place-items-center"><HandHeart class="size-10 text-brand-accent" :stroke-width="1.5" aria-hidden="true" /></div>
    </div>
    <div class="flex flex-1 flex-col gap-1 p-4">
      <p class="m-0 text-sm text-muted-foreground">{{ item.category_name }}<span v-if="branchName"> · {{ branchName }}</span></p>
      <h3 class="m-0 text-[17px] font-semibold leading-snug">{{ item.name }}</h3>
      <p v-if="item.name_en" class="m-0 text-sm text-muted-foreground">{{ item.name_en }}</p>
      <div class="mt-auto flex items-end justify-between gap-3 pt-3">
        <span class="flex items-center gap-1.5 text-sm text-muted-foreground"><Clock class="size-4" :stroke-width="1.75" aria-hidden="true" />{{ durations }}</span>
        <span class="text-right text-sm text-muted-foreground">เริ่ม <span class="num text-[17px] font-semibold text-heading">{{ formatBaht(from) }}</span></span>
      </div>
    </div>
  </NuxtLink>

  <article v-else class="group flex min-h-32 overflow-hidden rounded-2xl border border-border bg-card shadow-soft">
    <NuxtLink :to="detail" class="relative w-[38%] max-w-40 shrink-0 overflow-hidden bg-secondary" :aria-label="item.name" tabindex="-1">
      <img v-if="image" :src="image" alt="" class="absolute inset-0 size-full object-cover transition-transform duration-300 group-hover:scale-[1.03]" loading="lazy">
      <span v-else class="absolute inset-0 grid place-items-center"><HandHeart class="size-9 text-brand-accent" :stroke-width="1.5" aria-hidden="true" /></span>
    </NuxtLink>
    <div class="flex min-w-0 flex-1 flex-col gap-1 p-4">
      <h3 class="m-0 text-[16px] font-semibold leading-snug">
        <NuxtLink :to="detail" class="text-heading no-underline hover:text-primary">{{ item.name }}</NuxtLink>
      </h3>
      <p class="m-0 line-clamp-1 text-[13px] text-muted-foreground">{{ item.description || item.name_en || item.category_name }}</p>
      <div class="mt-auto flex flex-wrap items-center gap-x-3 gap-y-2 pt-3">
        <span class="flex items-center gap-1 text-[13px] text-muted-foreground"><Clock class="size-3.5" :stroke-width="1.75" aria-hidden="true" /><span class="num">{{ formatDuration(cheapest.duration_minutes) }}</span></span>
        <span class="num text-[15px] font-semibold text-heading">{{ formatBaht(from) }}</span>
        <Button as-child variant="outline" size="sm" class="ml-auto h-8 rounded-full px-4">
          <NuxtLink :to="{ path: '/book', query: { branch: item.branch_id, service: item.branch_service_id, option: cheapest.option_id } }">จองเลย</NuxtLink>
        </Button>
      </div>
    </div>
  </article>
</template>
