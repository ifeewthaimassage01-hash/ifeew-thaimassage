<script setup lang="ts">
useHead({ title: "สาขา — Ifeew's Thaimassage" })
const { data: branches, pending, error } = await useBranches()
</script>

<template>
  <div>
    <h1 class="m-0 mb-4 text-2xl font-semibold text-cocoa">สาขาทั้งหมด</h1>
    <v-progress-linear v-if="pending" indeterminate color="primary" />
    <v-alert v-else-if="error" type="error" variant="tonal" text="โหลดข้อมูลสาขาไม่สำเร็จ กรุณาลองใหม่" />
    <p v-else-if="!branches?.length" class="text-light-brown">ยังไม่มีสาขาที่เปิดให้บริการ</p>
    <div class="grid gap-4">
      <BranchCard v-for="b in branches ?? []" :key="b.id" :branch="b" />
    </div>
  </div>
</template>
