<script setup lang="ts">
import { formatBaht, formatDuration } from '@ifeew/shared'
import type { CatalogItem } from '~/composables/useCatalog'

const props = defineProps<{ item: CatalogItem; branchName?: string }>()
const image = computed(() => serviceImageUrl(props.item.image_path))
</script>

<template>
  <v-card :to="`/services/${item.branch_service_id}`" class="overflow-hidden">
    <div class="flex">
      <div class="flex w-28 shrink-0 items-center justify-center bg-beige">
        <img v-if="image" :src="image" :alt="item.name" class="h-full w-full object-cover" loading="lazy" >
        <v-icon v-else icon="mdi-spa-outline" size="36" color="primary" />
      </div>
      <div class="min-w-0 flex-1 p-4">
        <p class="m-0 text-xs text-light-brown">{{ item.category_name }}<span v-if="branchName"> · {{ branchName }}</span></p>
        <p class="m-0 font-medium text-cocoa">{{ item.name }}</p>
        <p v-if="item.name_en" class="m-0 text-xs text-light-brown">{{ item.name_en }}</p>
        <div class="mt-2 flex flex-wrap gap-2">
          <span v-for="o in item.options" :key="o.option_id" class="rounded-full bg-cream px-3 py-1 text-xs text-cocoa">
            {{ formatDuration(o.duration_minutes) }} · <span class="font-semibold">{{ formatBaht(o.price) }}</span>
          </span>
        </div>
      </div>
    </div>
  </v-card>
</template>
