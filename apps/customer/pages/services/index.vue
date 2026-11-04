<script setup lang="ts">
useHead({ title: "บริการ — Ifeew's Thaimassage" })

// คำถามของหน้า: "มีบริการอะไร นานเท่าไร ราคาเท่าไร" — กรองตามสาขาได้
const { data: branches } = await useBranches()
const ALL = 'all'
const selected = ref<string>(ALL)
const branchId = computed(() => (selected.value === ALL ? null : selected.value))
const { data: services, pending, error } = await useCatalog(branchId)

const branchName = (id: string) => branches.value?.find((b) => b.id === id)?.name ?? ''

const grouped = computed(() => {
  const map = new Map<string, NonNullable<typeof services.value>>()
  for (const s of services.value ?? []) map.set(s.category_name, [...(map.get(s.category_name) ?? []), s])
  return [...map.entries()]
})
</script>

<template>
  <div class="grid gap-6">
    <div class="flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 class="m-0 text-[28px] font-semibold leading-tight tracking-tight">บริการและราคา</h1>
        <p class="m-0 mt-1 text-muted-foreground"><span class="num">{{ services?.length ?? 0 }}</span> บริการ{{ branchId ? ` ที่${branchName(branchId)}` : ' ทุกสาขา' }} · ชำระค่าบริการที่ร้าน</p>
      </div>
      <div class="grid w-full gap-1.5 sm:w-64">
        <Label for="branch-filter">สาขา</Label>
        <Select v-model="selected">
          <SelectTrigger id="branch-filter" class="w-full"><SelectValue placeholder="ทุกสาขา" /></SelectTrigger>
          <SelectContent>
            <SelectItem :value="ALL">ทุกสาขา</SelectItem>
            <SelectItem v-for="b in branches ?? []" :key="b.id" :value="b.id">{{ b.name }}</SelectItem>
          </SelectContent>
        </Select>
      </div>
    </div>

    <div v-if="pending" class="grid gap-3"><Skeleton v-for="n in 3" :key="n" class="h-28 rounded-xl" /></div>
    <Alert v-else-if="error" variant="destructive"><AlertDescription>โหลดรายการบริการไม่สำเร็จ กรุณาลองใหม่</AlertDescription></Alert>
    <p v-else-if="!services?.length" class="m-0 rounded-lg border border-dashed px-4 py-3 text-muted-foreground">{{ branchId ? 'สาขานี้ยังไม่เปิดจองบริการออนไลน์' : 'ยังไม่มีบริการที่เปิดจองออนไลน์' }} โทรจองที่สาขาได้</p>

    <section v-for="[category, items] in grouped" :key="category" class="grid gap-3">
      <h2 class="m-0 flex items-center gap-2 text-lg font-semibold">
        <span class="size-2.5 rounded-full" :class="categoryTint(category)" aria-hidden="true" />{{ category }}
      </h2>
      <div class="grid gap-3 md:grid-cols-2">
        <ServiceCard
          v-for="s in items"
          :key="s.branch_service_id"
          :item="s"
          :branch-name="branchId ? undefined : branchName(s.branch_id)"
        />
      </div>
    </section>
  </div>
</template>
