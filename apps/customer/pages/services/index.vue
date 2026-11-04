<script setup lang="ts">
useHead({ title: "บริการ — Ifeew's Thaimassage" })

const { data: branches } = await useBranches()
const branchId = ref<string | null>(null)
const { data: services, pending } = await useCatalog(branchId)

const branchName = (id: string) => branches.value?.find((b) => b.id === id)?.name ?? ''
const branchItems = computed(() => [{ id: null, name: 'ทุกสาขา' }, ...(branches.value ?? [])])
</script>

<template>
  <div>
    <h1 class="m-0 mb-4 text-2xl font-semibold text-cocoa">บริการ</h1>
    <v-select v-model="branchId" :items="branchItems" item-title="name" item-value="id" label="สาขา" class="max-w-xs" />
    <v-progress-linear v-if="pending" indeterminate color="primary" />
    <p v-else-if="!services?.length" class="text-light-brown">ยังไม่มีบริการที่เปิดจอง</p>
    <div class="grid gap-3">
      <ServiceCard
        v-for="s in services ?? []"
        :key="s.branch_service_id"
        :item="s"
        :branch-name="branchId ? undefined : branchName(s.branch_id)"
      />
    </div>
  </div>
</template>
