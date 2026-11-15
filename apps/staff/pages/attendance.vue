<script setup lang="ts">
// ย้ายไปรวมในหน้า ข้อมูลหมอ (/reports/therapists) แล้ว — คงไว้เป็นทางผ่านสำหรับลิงก์เดิม
//   /attendance → แท็บ ตารางเข้างาน · /attendance?tab=guarantee → แท็บ ประกันมือ
definePageMeta({ ownerOnly: true })
const route = useRoute()
await navigateTo(
  { path: '/reports/therapists', query: { tab: route.query.tab === 'guarantee' ? 'guarantee' : 'attendance' } },
  { replace: true },
)
</script>

<template>
  <div />
</template>
