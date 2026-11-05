<script setup lang="ts">
import { Search } from '@lucide/vue'

// ค้นหาบริการ: ค้นด้วยชื่อ · กรองสาขา · กรองหมวด
useHead({ title: "บริการ — Ifeew's Thaimassage" })

const { data: branches } = await useBranches()
const ALL = 'all'
const selected = ref<string>(ALL)
const branchId = computed(() => (selected.value === ALL ? null : selected.value))
const { data: services, pending, error } = await useCatalog(branchId)

const q = ref('')
const category = ref<string>(ALL)
const categories = computed(() => [...new Set((services.value ?? []).map((s) => s.category_name))])
watch(categories, (c) => {
  if (category.value !== ALL && !c.includes(category.value)) category.value = ALL
})

const filtered = computed(() => {
  const term = q.value.trim().toLowerCase()
  return (services.value ?? []).filter(
    (s) =>
      (category.value === ALL || s.category_name === category.value) &&
      (!term || s.name.toLowerCase().includes(term) || (s.name_en ?? '').toLowerCase().includes(term) || s.category_name.toLowerCase().includes(term)),
  )
})

const branchName = (id: string) => branches.value?.find((b) => b.id === id)?.name ?? ''
function reset() {
  q.value = ''
  category.value = ALL
}
</script>

<template>
  <div>
    <PageHeader title="บริการ" description="ทุกบริการชำระค่าบริการที่ร้าน จองล่วงหน้าออนไลน์และโอนมัดจำผ่าน PromptPay" />

    <!-- แถบค้นหาและกรอง -->
    <div class="mb-6 grid gap-3 rounded-xl border border-border bg-card p-4 md:grid-cols-[minmax(0,1fr)_240px]">
      <div class="relative">
        <Label for="svc-search" class="sr-only">ค้นหาบริการ</Label>
        <Search class="pointer-events-none absolute top-1/2 left-3.5 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden="true" />
        <Input id="svc-search" v-model="q" type="search" placeholder="ค้นหา เช่น นวดเท้า, oil" class="pl-10" />
      </div>
      <div>
        <Label for="branch-filter" class="sr-only">สาขา</Label>
        <Select v-model="selected">
          <SelectTrigger id="branch-filter" class="w-full"><SelectValue placeholder="ทุกสาขา" /></SelectTrigger>
          <SelectContent>
            <SelectItem :value="ALL">ทุกสาขา</SelectItem>
            <SelectItem v-for="b in branches ?? []" :key="b.id" :value="b.id">{{ b.name }}</SelectItem>
          </SelectContent>
        </Select>
      </div>
      <div v-if="categories.length > 1" class="flex flex-wrap gap-2 md:col-span-2" role="radiogroup" aria-label="หมวดบริการ">
        <button
          v-for="c in [ALL, ...categories]"
          :key="c"
          type="button"
          role="radio"
          :aria-checked="category === c"
          class="h-9 rounded-md border px-3 text-sm transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
          :class="category === c ? 'border-primary bg-primary text-primary-foreground' : 'border-border bg-card text-foreground hover:border-input hover:text-heading'"
          @click="category = c"
        >{{ c === ALL ? 'ทุกหมวด' : c }}</button>
      </div>
    </div>

    <p v-if="!pending && services?.length" class="m-0 mb-4 text-sm text-muted-foreground">
      พบ <span class="num font-medium text-heading">{{ filtered.length }}</span> บริการ{{ branchId ? ` ที่${branchName(branchId)}` : '' }}
    </p>

    <div v-if="pending" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3"><Skeleton v-for="n in 6" :key="n" class="h-72 rounded-xl" /></div>
    <Alert v-else-if="error" variant="destructive"><AlertDescription>โหลดรายการบริการไม่สำเร็จ กรุณาลองใหม่</AlertDescription></Alert>
    <EmptyState
      v-else-if="!services?.length"
      :title="branchId ? 'สาขานี้ยังไม่เปิดจองบริการออนไลน์' : 'ยังไม่มีบริการที่เปิดจองออนไลน์'"
      description="โทรจองที่สาขาได้ หรือแวะกลับมาดูอีกครั้ง"
    >
      <Button as-child variant="outline"><NuxtLink to="/branches">ดูเบอร์โทรสาขา</NuxtLink></Button>
    </EmptyState>
    <EmptyState v-else-if="!filtered.length" title="ไม่พบบริการที่ค้นหา" description="ลองคำอื่น หรือดูทุกหมวด">
      <Button variant="outline" @click="reset">ล้างการค้นหา</Button>
    </EmptyState>
    <div v-else class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <ServiceCard v-for="s in filtered" :key="s.branch_service_id" :item="s" :branch-name="branchId ? undefined : branchName(s.branch_id)" />
    </div>
  </div>
</template>
