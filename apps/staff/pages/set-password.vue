<script setup lang="ts">
// ตั้งรหัสผ่านจากลิงก์อีเมล (เชิญเจ้าของร้านครั้งแรก / ลืมรหัสผ่าน) แล้วเข้าสู่ระบบ
import { passwordSchema } from '@ifeew/shared'

definePageMeta({ layout: 'blank' })

const supabase = useSupabaseClient()
const user = useSupabaseUser()
const { clear: clearAccess } = useAccess()

const password = ref('')
const confirm = ref('')
const saving = ref(false)
const error = ref<string | null>(null)
const waiting = ref(true)

// supabase-js อ่าน token จากลิงก์เอง — รอสักครู่ถ้ายังไม่มี session ถือว่าลิงก์ใช้ไม่ได้
onMounted(() => {
  setTimeout(() => (waiting.value = false), 4000)
})

async function save() {
  error.value = null
  const parsed = passwordSchema.safeParse(password.value)
  if (!parsed.success) {
    error.value = parsed.error.issues[0]?.message ?? 'รหัสผ่านไม่ถูกต้อง'
    return
  }
  if (password.value !== confirm.value) {
    error.value = 'รหัสผ่านทั้งสองช่องไม่ตรงกัน'
    return
  }
  saving.value = true
  try {
    const { error: err } = await supabase.auth.updateUser({ password: parsed.data })
    if (err) {
      error.value = /weak|pwned|leaked/i.test(err.message) ? 'รหัสผ่านนี้คาดเดาง่ายหรือเคยรั่วไหล กรุณาใช้รหัสอื่น' : 'ตั้งรหัสผ่านไม่สำเร็จ ลิงก์อาจหมดอายุ'
      return
    }
    password.value = ''
    confirm.value = ''
    clearAccess()
    await navigateTo('/')
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="min-h-screen bg-cream px-4 py-10">
    <v-card class="mx-auto max-w-md p-6">
      <h1 class="m-0 mb-1 text-2xl font-semibold text-cocoa">ตั้งรหัสผ่าน</h1>
      <p class="m-0 mb-4 text-sm text-light-brown">อย่างน้อย 10 ตัวอักษร มีตัวพิมพ์เล็ก ตัวพิมพ์ใหญ่ และตัวเลข</p>
      <template v-if="user">
        <p class="m-0 mb-4 text-sm">บัญชี: {{ user.email }}</p>
        <v-form @submit.prevent="save">
          <v-text-field v-model="password" label="รหัสผ่านใหม่" type="password" autocomplete="new-password" />
          <v-text-field v-model="confirm" label="ยืนยันรหัสผ่าน" type="password" autocomplete="new-password" />
          <v-alert v-if="error" type="error" variant="tonal" class="mb-4" :text="error" />
          <v-btn type="submit" color="primary" block :loading="saving">บันทึกรหัสผ่าน</v-btn>
        </v-form>
      </template>
      <v-progress-linear v-else-if="waiting" indeterminate color="primary" />
      <template v-else>
        <v-alert type="warning" variant="tonal" text="ลิงก์ไม่ถูกต้องหรือหมดอายุ กรุณาขอลิงก์ใหม่ที่หน้าเข้าสู่ระบบ" />
        <v-btn class="mt-4" block variant="tonal" to="/login">ไปหน้าเข้าสู่ระบบ</v-btn>
      </template>
    </v-card>
  </div>
</template>
