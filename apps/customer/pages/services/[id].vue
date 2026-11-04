<script setup lang="ts">
import { formatBaht, formatDuration } from '@ifeew/shared'
import { groupCatalog, type CatalogRow } from '~/composables/useCatalog'

// รายละเอียดบริการของสาขา (id = branch_service_id) พร้อมทุกช่วงเวลา/ราคา
const route = useRoute()
const supabase = useSupabaseClient()
const id = computed(() => String(route.params.id))

const { data: item } = await useAsyncData(`service-${id.value}`, async () => {
  const { data } = await supabase
    .from('v_public_branch_services')
    .select('*')
    .eq('branch_service_id', id.value)
    .order('duration_minutes')
  return groupCatalog((data ?? []) as CatalogRow[])[0] ?? null
})

const { data: branches } = await useBranches()
const branch = computed(() => branches.value?.find((b) => b.id === item.value?.branch_id) ?? null)
const image = computed(() => serviceImageUrl(item.value?.image_path ?? null))

useHead({ title: () => `${item.value?.name ?? 'บริการ'} — Ifeew's Thaimassage` })
</script>

<template>
  <div v-if="item">
    <v-btn variant="text" prepend-icon="mdi-arrow-left" to="/services" class="mb-2">บริการทั้งหมด</v-btn>
    <v-card class="overflow-hidden">
      <div class="flex h-56 items-center justify-center bg-beige">
        <img v-if="image" :src="image" :alt="item.name" class="h-full w-full object-cover" >
        <v-icon v-else icon="mdi-spa-outline" size="64" color="primary" />
      </div>
      <div class="p-6">
        <p class="m-0 text-sm text-light-brown">{{ item.category_name }}</p>
        <h1 class="m-0 text-2xl font-semibold text-cocoa">{{ item.name }}</h1>
        <p v-if="item.name_en" class="m-0 mb-3 text-light-brown">{{ item.name_en }}</p>
        <p v-if="item.description" class="m-0 mb-4 whitespace-pre-line">{{ item.description }}</p>

        <p class="m-0 mb-2 font-medium">ระยะเวลาและราคา</p>
        <div class="grid gap-2">
          <div v-for="o in item.options" :key="o.option_id" class="flex items-center justify-between rounded-xl bg-cream px-4 py-3">
            <span><v-icon icon="mdi-clock-outline" size="18" class="mr-1" />{{ formatDuration(o.duration_minutes) }}</span>
            <span class="text-lg font-semibold text-cocoa">{{ formatBaht(o.price) }}</span>
          </div>
        </div>

        <p v-if="branch" class="m-0 mt-4 text-sm">
          สาขา: <NuxtLink :to="`/branches/${branch.id}`" class="text-light-brown">{{ branch.name }}</NuxtLink>
        </p>
        <v-btn color="primary" block class="mt-6" :to="{ path: '/book', query: { branch: item.branch_id, service: item.branch_service_id } }">จองบริการ</v-btn>
      </div>
    </v-card>
  </div>
  <v-alert v-else type="info" variant="tonal" text="ไม่พบบริการนี้" />
</template>
