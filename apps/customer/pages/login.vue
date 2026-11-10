<script setup lang="ts">
import { emailSchema } from '@ifeew/shared'

useHead({ title: "เข้าสู่ระบบ — Ifeew's Thaimassage" })

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
  <AuthShell title="เข้าสู่ระบบ" subtitle="ดูการจอง ประวัติการนวด และจองครั้งต่อไปได้เร็วขึ้น">
    <form class="grid gap-4" novalidate @submit.prevent="submit">
      <div class="grid content-start gap-1.5"><Label for="email">อีเมล</Label><Input id="email" v-model="email" type="email" autocomplete="email" required /></div>
      <div class="grid content-start gap-1.5"><Label for="password">รหัสผ่าน</Label><Input id="password" v-model="password" type="password" autocomplete="current-password" required /></div>
      <Alert v-if="error" variant="destructive"><AlertDescription>{{ error }}</AlertDescription></Alert>
      <Button type="submit" size="lg" class="w-full" :disabled="loading">{{ loading ? 'กำลังเข้าสู่ระบบ…' : 'เข้าสู่ระบบ' }}</Button>
    </form>
    <template #footer>
      ยังไม่มีบัญชี? <NuxtLink to="/register">สมัครสมาชิก</NuxtLink>
      <span class="mx-1.5 text-muted-foreground">·</span>
      <NuxtLink to="/book">จองโดยไม่สมัคร</NuxtLink>
    </template>
  </AuthShell>
</template>
