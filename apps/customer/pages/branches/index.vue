<script setup lang="ts">
useHead({ title: "สาขา — Ifeew's Thaimassage" })

// คำถามของหน้า: "สาขาไหนอยู่ใกล้ เปิดอยู่ไหม โทรหาได้อย่างไร"
const { data: branches, pending, error } = await useBranches()
const branchIds = computed(() => (branches.value ?? []).map((b) => b.id))
const { data: hours } = await useOpenToday(branchIds)
</script>

<template>
  <div class="grid gap-6">
    <div>
      <h1 class="m-0 text-[28px] font-semibold leading-tight tracking-tight">สาขาทั้งหมด</h1>
      <p class="m-0 mt-1 text-muted-foreground"><span class="num">{{ branches?.length ?? 0 }}</span> สาขา · เวลาเปิดของวันนี้</p>
    </div>
    <div v-if="pending" class="grid gap-3 md:grid-cols-2"><Skeleton v-for="n in 2" :key="n" class="h-44 rounded-xl" /></div>
    <Alert v-else-if="error" variant="destructive"><AlertDescription>โหลดข้อมูลสาขาไม่สำเร็จ กรุณาลองใหม่</AlertDescription></Alert>
    <p v-else-if="!branches?.length" class="m-0 rounded-lg border border-dashed px-4 py-3 text-muted-foreground">ยังไม่มีสาขาที่เปิดให้บริการ</p>
    <div class="grid items-start gap-4 md:grid-cols-2">
      <BranchCard v-for="b in branches ?? []" :key="b.id" :branch="b" :hours="hours?.[b.id] ?? null" />
    </div>
  </div>
</template>
