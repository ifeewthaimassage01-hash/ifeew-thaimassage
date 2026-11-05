<script setup lang="ts">
import { ArrowRight, MapPin, Phone } from '@lucide/vue'
import type { PublicBranch } from '~/composables/useBranches'
import type { TodayHours } from '~/composables/useOpenToday'

defineProps<{ branch: PublicBranch; hours?: TodayHours | null }>()
const tel = (p: string) => `tel:${p.replace(/\s|-/g, '')}`
</script>

<template>
  <Card class="gap-0 py-0">
    <div class="grid gap-4 p-5">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <h3 class="m-0 text-[17px] font-semibold leading-snug">
            <NuxtLink :to="`/branches/${branch.id}`" class="text-heading no-underline hover:text-primary">{{ branch.name }}</NuxtLink>
          </h3>
          <p v-if="branch.address" class="m-0 mt-0.5 flex items-start gap-1.5 text-[15px] text-muted-foreground">
            <MapPin class="mt-1 size-4 shrink-0 text-muted-soft" :stroke-width="1.75" aria-hidden="true" />{{ branch.address }}
          </p>
        </div>
        <Button as-child variant="ghost" size="icon-sm" class="-mt-1 -mr-2 text-muted-foreground" :aria-label="`รายละเอียด ${branch.name}`">
          <NuxtLink :to="`/branches/${branch.id}`"><ArrowRight /></NuxtLink>
        </Button>
      </div>
      <OpenToday :hours="hours" />
    </div>
    <div class="flex flex-wrap gap-2 border-t border-border px-5 py-3">
      <Button as-child size="sm"><NuxtLink :to="{ path: '/book', query: { branch: branch.id } }">จองสาขานี้</NuxtLink></Button>
      <Button v-if="branch.phone" as-child variant="outline" size="sm">
        <a :href="tel(branch.phone)"><Phone /> <span class="num">{{ branch.phone }}</span></a>
      </Button>
      <Button v-if="branch.map_url" as-child variant="ghost" size="sm">
        <a :href="branch.map_url" target="_blank" rel="noopener"><MapPin /> แผนที่</a>
      </Button>
    </div>
  </Card>
</template>
