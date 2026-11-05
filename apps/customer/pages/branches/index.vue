<script setup lang="ts">
useHead({ title: "สาขา — Ifeew's Thaimassage" })

const { data: branches, pending, error } = await useBranches()
const branchIds = computed(() => (branches.value ?? []).map((b) => b.id))
const { data: hours } = await useOpenToday(branchIds)
</script>

<template>
  <div>
    <PageHeader title="สาขา">
      <template #description><span class="num">{{ branches?.length ?? 0 }}</span> สาขา · เวลาเปิดของวันนี้ โทรหรือจองออนไลน์ได้จากแต่ละสาขา</template>
    </PageHeader>
    <div v-if="pending" class="grid gap-4 md:grid-cols-2"><Skeleton v-for="n in 2" :key="n" class="h-44 rounded-xl" /></div>
    <Alert v-else-if="error" variant="destructive"><AlertDescription>โหลดข้อมูลสาขาไม่สำเร็จ กรุณาลองใหม่</AlertDescription></Alert>
    <EmptyState v-else-if="!branches?.length" title="ยังไม่มีสาขาที่เปิดให้บริการ" />
    <div v-else class="grid items-start gap-4 md:grid-cols-2">
      <BranchCard v-for="b in branches" :key="b.id" :branch="b" :hours="hours?.[b.id] ?? null" />
    </div>
  </div>
</template>
