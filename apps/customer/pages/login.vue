<script setup lang="ts">
import { emailSchema } from '@ifeew/shared'

const supabase = useSupabaseClient()
const route = useRoute()
const { clear: clearCustomer } = useCustomer()

const email = ref('')
const password = ref('')
const loading = ref(false)
const error = ref<string | null>(null)

// อนุญาต redirect เฉพาะ path ภายในเว็บ (กัน open redirect)
const redirectTo = computed(() => {
  const r = String(route.query.redirect ?? '/')
  return r.startsWith('/') && !r.startsWith('//') ? r : '/'
})

async function submit() {
  error.value = null
  const parsed = emailSchema.safeParse(email.value)
  if (!parsed.success || !password.value) {
    error.value = 'กรุณากรอกอีเมลและรหัสผ่าน'
    return
  }
  loading.value = true
  const { error: err } = await supabase.auth.signInWithPassword({ email: parsed.data, password: password.value })
  loading.value = false
  if (err) {
    error.value = 'อีเมลหรือรหัสผ่านไม่ถูกต้อง'
    return
  }
  clearCustomer()
  await navigateTo(redirectTo.value)
}
</script>

<template>
  <v-card class="mx-auto max-w-md p-6">
    <h1 class="m-0 mb-6 text-xl font-semibold text-cocoa">เข้าสู่ระบบ</h1>
    <v-form @submit.prevent="submit">
      <v-text-field v-model="email" label="อีเมล" type="email" autocomplete="email" />
      <v-text-field v-model="password" label="รหัสผ่าน" type="password" autocomplete="current-password" />
      <v-alert v-if="error" type="error" variant="tonal" class="mb-4" :text="error" />
      <v-btn type="submit" color="primary" block :loading="loading">เข้าสู่ระบบ</v-btn>
    </v-form>
    <p class="mb-0 mt-4 text-center text-sm">
      ยังไม่มีบัญชี? <NuxtLink to="/register" class="text-light-brown">สมัครสมาชิก</NuxtLink>
    </p>
  </v-card>
</template>
