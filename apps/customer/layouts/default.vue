<script setup lang="ts">
const user = useSupabaseUser()
const supabase = useSupabaseClient()
const { clear } = useCustomer()

async function logout() {
  await supabase.auth.signOut()
  clear()
  await navigateTo('/')
}
</script>

<template>
  <v-app>
    <v-app-bar flat color="background" density="comfortable">
      <NuxtLink to="/" class="ml-4 text-lg font-semibold text-cocoa no-underline">Ifeew's Thaimassage</NuxtLink>
      <v-spacer />
      <v-btn to="/services" variant="text">บริการ</v-btn>
      <v-btn to="/branches" variant="text">สาขา</v-btn>
      <v-btn to="/book" variant="flat" color="primary" class="mr-1">จอง</v-btn>
      <template v-if="user">
        <v-btn to="/bookings" variant="text" icon="mdi-calendar-check-outline" aria-label="การจองของฉัน" />
        <v-btn to="/profile" variant="text" icon="mdi-account-circle-outline" aria-label="โปรไฟล์" />
        <v-btn variant="text" icon="mdi-logout" aria-label="ออกจากระบบ" @click="logout" />
      </template>
      <v-btn v-else to="/login" variant="tonal" color="primary" class="mr-2">เข้าสู่ระบบ</v-btn>
    </v-app-bar>
    <v-main>
      <div class="mx-auto max-w-3xl px-4 py-6">
        <slot />
      </div>
    </v-main>
  </v-app>
</template>
