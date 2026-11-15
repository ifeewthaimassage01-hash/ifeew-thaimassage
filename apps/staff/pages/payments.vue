<script setup lang="ts">
// เลิกใช้หน้าชำระเงินแยกแล้ว — การเก็บเงินอยู่ที่หน้าคิว (คิวที่นวดเสร็จแต่ยังไม่จ่ายแสดง "รอชำระเงิน")
// คงไว้เป็นทางผ่านสำหรับลิงก์เดิม (แจ้งเตือน LINE/Push "บริการเสร็จ" ชี้มาที่ /payments)
await navigateTo('/queue', { replace: true })
</script>

<template>
  <div />
</template>
