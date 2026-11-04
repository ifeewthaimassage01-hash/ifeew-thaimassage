<script setup lang="ts">
import type { PublicBranch } from '~/composables/useBranches'

defineProps<{ branch: PublicBranch }>()
</script>

<template>
  <v-card class="p-5">
    <div class="flex items-start gap-4">
      <v-avatar size="48" class="bg-pastel-green">
        <v-icon icon="mdi-spa-outline" color="primary" />
      </v-avatar>
      <div class="min-w-0 flex-1">
        <NuxtLink :to="`/branches/${branch.id}`" class="text-lg font-medium text-cocoa no-underline">{{ branch.name }}</NuxtLink>
        <p v-if="branch.address" class="m-0 mt-1 text-sm text-light-brown">{{ branch.address }}</p>
        <div class="mt-3 flex flex-wrap gap-2">
          <v-btn v-if="branch.phone" :href="`tel:${branch.phone.replace(/\s|-/g, '')}`" variant="tonal" color="primary" prepend-icon="mdi-phone-outline">
            {{ branch.phone }}
          </v-btn>
          <v-btn v-if="branch.map_url" :href="branch.map_url" target="_blank" rel="noopener" variant="text" prepend-icon="mdi-map-marker-outline">
            แผนที่
          </v-btn>
        </div>
      </div>
    </div>
  </v-card>
</template>
