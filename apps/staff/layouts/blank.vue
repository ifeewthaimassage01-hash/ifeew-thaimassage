<template>
  <!-- หน้าที่ไม่มี sidebar (login, ตั้งรหัสผ่าน, MFA) — แต่ละหน้ากำหนดความกว้างเอง -->
  <div class="min-h-dvh bg-background">
    <slot />
    <Toaster position="top-center" />
  </div>
</template>
