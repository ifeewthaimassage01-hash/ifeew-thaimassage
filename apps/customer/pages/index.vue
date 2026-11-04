<script setup lang="ts">
const { data: branches, pending } = await useBranches()
</script>

<template>
  <div>
    <section class="mb-8 rounded-card bg-soft-pink/60 p-6 shadow-soft">
      <h1 class="m-0 text-2xl font-semibold text-cocoa">ผ่อนคลายกับนวดไทยแท้</h1>
      <p class="m-0 mt-2 text-cocoa/80">เลือกสาขาใกล้คุณ จองออนไลน์ได้ทันที เลือกบริการและเวลาที่สะดวก</p>
      <div class="mt-4 flex gap-2"><v-btn to="/book" color="primary">จองบริการ</v-btn><v-btn to="/branches" variant="tonal" color="primary">ดูสาขาทั้งหมด</v-btn></div>
    </section>

    <h2 class="m-0 mb-4 text-lg font-semibold text-cocoa">สาขาของเรา</h2>
    <v-progress-linear v-if="pending" indeterminate color="primary" />
    <div class="grid gap-4">
      <BranchCard v-for="b in (branches ?? []).slice(0, 3)" :key="b.id" :branch="b" />
    </div>
  </div>
</template>
