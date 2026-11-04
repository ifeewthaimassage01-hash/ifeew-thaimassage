<script setup lang="ts">
import { ArrowLeft } from '@lucide/vue'
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
  <div class="grid gap-4">
    <NuxtLink to="/services" class="inline-flex w-fit items-center gap-1.5 text-[15px] text-muted-foreground no-underline hover:text-foreground">
      <ArrowLeft class="size-4" /> บริการทั้งหมด
    </NuxtLink>

    <div v-if="item" class="grid items-start gap-6 md:grid-cols-[minmax(0,1fr)_360px]">
      <div class="grid gap-4">
        <div class="aspect-[16/9] overflow-hidden rounded-xl" :class="image ? 'bg-muted' : categoryTint(item.category_name)">
          <img v-if="image" :src="image" :alt="item.name" class="size-full object-cover">
          <span v-else class="grid size-full place-items-center text-6xl font-semibold" aria-hidden="true">{{ item.name.trim().charAt(0) }}</span>
        </div>
        <div>
          <p class="m-0 text-[15px] text-muted-foreground">{{ item.category_name }}<template v-if="branch"> · {{ branch.name }}</template></p>
          <h1 class="m-0 text-[28px] font-semibold leading-tight tracking-tight">{{ item.name }}</h1>
          <p v-if="item.name_en" class="m-0 text-muted-foreground">{{ item.name_en }}</p>
        </div>
        <p v-if="item.description" class="m-0 max-w-[65ch] whitespace-pre-line">{{ item.description }}</p>
      </div>

      <Card class="gap-4 py-5 md:sticky md:top-20">
        <CardHeader class="px-5"><CardTitle>ระยะเวลาและราคา</CardTitle></CardHeader>
        <CardContent class="grid gap-4 px-5">
          <ul class="m-0 grid list-none gap-0 p-0">
            <li v-for="o in item.options" :key="o.option_id" class="flex items-baseline justify-between border-b border-border/70 py-2.5 last:border-0">
              <span>{{ formatDuration(o.duration_minutes) }}</span>
              <span class="num text-lg font-semibold">{{ formatBaht(o.price) }}</span>
            </li>
          </ul>
          <p class="m-0 text-sm text-muted-foreground">ชำระค่าบริการที่ร้าน · มัดจำผ่าน PromptPay ตอนจอง</p>
          <Button as-child size="lg" class="w-full">
            <NuxtLink :to="{ path: '/book', query: { branch: item.branch_id, service: item.branch_service_id } }">จองบริการนี้</NuxtLink>
          </Button>
          <p v-if="branch" class="m-0 text-sm">
            สาขา <NuxtLink :to="`/branches/${branch.id}`">{{ branch.name }}</NuxtLink>
          </p>
        </CardContent>
      </Card>
    </div>
    <Alert v-else variant="info"><AlertDescription>ไม่พบบริการนี้ อาจปิดการจองไปแล้ว</AlertDescription></Alert>
  </div>
</template>
