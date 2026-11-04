<script setup lang="ts">
import { formatBaht, formatDuration } from '@ifeew/shared'
import type { CatalogItem } from '~/composables/useCatalog'

// แถวบริการ: รูป (หรือ tile สีประจำหมวด) · ชื่อ · ราคาแต่ละระยะเวลา ชิดขวาเป็นตัวเลขตาราง
const props = defineProps<{ item: CatalogItem; branchName?: string }>()
const image = computed(() => serviceImageUrl(props.item.image_path))
const initial = computed(() => props.item.name.trim().charAt(0))
</script>

<template>
  <NuxtLink
    :to="`/services/${item.branch_service_id}`"
    class="group flex gap-4 rounded-xl border bg-card p-4 text-foreground no-underline transition-colors hover:border-input"
  >
    <div class="size-16 shrink-0 overflow-hidden rounded-lg sm:size-20" :class="image ? 'bg-muted' : categoryTint(item.category_name)">
      <img v-if="image" :src="image" :alt="item.name" class="size-full object-cover" loading="lazy">
      <span v-else class="grid size-full place-items-center text-2xl font-semibold" aria-hidden="true">{{ initial }}</span>
    </div>
    <div class="min-w-0 flex-1">
      <p class="m-0 text-sm text-muted-foreground">{{ item.category_name }}<span v-if="branchName"> · {{ branchName }}</span></p>
      <h3 class="m-0 text-[17px] font-semibold leading-snug group-hover:underline">{{ item.name }}</h3>
      <p v-if="item.name_en" class="m-0 text-sm text-muted-foreground">{{ item.name_en }}</p>
      <ul class="m-0 mt-2 grid list-none gap-0.5 p-0">
        <li v-for="o in item.options" :key="o.option_id" class="flex max-w-xs justify-between gap-4 text-[15px]">
          <span class="text-muted-foreground">{{ formatDuration(o.duration_minutes) }}</span>
          <span class="num font-semibold">{{ formatBaht(o.price) }}</span>
        </li>
      </ul>
    </div>
  </NuxtLink>
</template>
