<script setup lang="ts">
import { Clock, HandHeart } from '@lucide/vue'
import { formatBaht, formatDuration } from '@ifeew/shared'
import type { CatalogItem } from '~/composables/useCatalog'

// การ์ดบริการ: รูป (หรือพื้นทรายเรียบ + ไอคอนเส้น) · หมวด · ชื่อ · ระยะเวลา · ราคาเริ่มต้น
const props = defineProps<{ item: CatalogItem; branchName?: string }>()
const image = computed(() => serviceImageUrl(props.item.image_path))
const from = computed(() => Math.min(...props.item.options.map((o) => o.price)))
const durations = computed(() => props.item.options.map((o) => formatDuration(o.duration_minutes)).join(' · '))
</script>

<template>
  <NuxtLink
    :to="`/services/${item.branch_service_id}`"
    class="group flex flex-col overflow-hidden rounded-xl border border-border bg-card text-foreground no-underline transition-colors hover:border-input"
  >
    <div class="aspect-[16/10] overflow-hidden bg-secondary/60">
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
</template>
