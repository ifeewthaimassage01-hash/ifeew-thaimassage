<script setup lang="ts">
import { Clock, HandHeart, MapPin } from '@lucide/vue'
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
  <div v-if="item" class="grid items-start gap-8 lg:grid-cols-[minmax(0,1fr)_360px]">
    <div class="grid gap-6">
      <div class="aspect-[16/9] overflow-hidden rounded-xl border border-border bg-secondary/60">
        <img v-if="image" :src="image" :alt="item.name" class="size-full object-cover">
        <div v-else class="grid size-full place-items-center"><HandHeart class="size-16 text-brand-accent" :stroke-width="1.25" aria-hidden="true" /></div>
      </div>
      <div>
        <Badge variant="default" class="mb-2">{{ item.category_name }}</Badge>
        <h1 class="m-0 text-2xl font-semibold leading-tight tracking-tight md:text-[28px]">{{ item.name }}</h1>
        <p v-if="item.name_en" class="m-0 mt-1 text-muted-foreground">{{ item.name_en }}</p>
      </div>
      <p v-if="item.description" class="m-0 max-w-[65ch] whitespace-pre-line">{{ item.description }}</p>
      <p v-else class="m-0 text-muted-foreground">สอบถามรายละเอียดเพิ่มเติมได้ที่สาขา</p>
    </div>

    <Card class="gap-0 py-0 lg:sticky lg:top-24">
      <div class="border-b border-border p-5">
        <h2 class="m-0 text-base font-semibold">ระยะเวลาและราคา</h2>
      </div>
      <ul class="m-0 grid list-none gap-0 px-5 py-2">
        <li v-for="o in item.options" :key="o.option_id" class="flex items-center justify-between border-b border-border py-3 last:border-0">
          <span class="flex items-center gap-2"><Clock class="size-4 text-muted-soft" :stroke-width="1.75" aria-hidden="true" />{{ formatDuration(o.duration_minutes) }}</span>
          <span class="num text-lg font-semibold text-heading">{{ formatBaht(o.price) }}</span>
        </li>
      </ul>
      <div class="grid gap-3 border-t border-border bg-background/60 p-5">
        <p v-if="branch" class="m-0 flex items-center gap-1.5 text-[15px]">
          <MapPin class="size-4 text-muted-soft" :stroke-width="1.75" aria-hidden="true" />
          <NuxtLink :to="`/branches/${branch.id}`">{{ branch.name }}</NuxtLink>
        </p>
        <Button as-child size="lg" class="w-full">
          <NuxtLink :to="{ path: '/book', query: { branch: item.branch_id, service: item.branch_service_id } }">จองบริการนี้</NuxtLink>
        </Button>
        <p class="m-0 text-center text-sm text-muted-foreground">ชำระค่าบริการที่ร้าน · มัดจำผ่าน PromptPay</p>
      </div>
    </Card>
  </div>
  <EmptyState v-else title="ไม่พบบริการนี้" description="บริการอาจปิดการจองไปแล้ว">
    <Button as-child variant="outline"><NuxtLink to="/services">ดูบริการทั้งหมด</NuxtLink></Button>
  </EmptyState>
</template>
