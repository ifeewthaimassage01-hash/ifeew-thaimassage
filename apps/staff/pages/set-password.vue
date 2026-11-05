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
  <div class="grid min-h-dvh place-items-center px-4 py-10">
    <Card class="w-full max-w-md gap-5 py-6">
      <CardHeader class="px-6">
        <BrandMark class="mb-2 size-10" />
        <CardTitle as="h1" class="text-2xl">ตั้งรหัสผ่าน</CardTitle>
        <p class="m-0 text-[15px] text-muted-foreground">อย่างน้อย 10 ตัวอักษร มีตัวพิมพ์เล็ก ตัวพิมพ์ใหญ่ และตัวเลข</p>
      </CardHeader>
      <CardContent class="px-6">
        <form v-if="user" class="grid gap-4" novalidate @submit.prevent="save">
          <p class="m-0 rounded-lg bg-muted px-4 py-2.5 text-[15px] text-heading">บัญชี {{ user.email }}</p>
          <TextField v-model="password" label="รหัสผ่านใหม่" type="password" autocomplete="new-password" />
          <TextField v-model="confirm" label="ยืนยันรหัสผ่าน" type="password" autocomplete="new-password" />
          <Alert v-if="error" variant="destructive"><AlertDescription>{{ error }}</AlertDescription></Alert>
          <Button type="submit" size="lg" class="w-full" :disabled="saving">{{ saving ? 'กำลังบันทึก…' : 'บันทึกรหัสผ่าน' }}</Button>
        </form>
        <LoadingBar v-else-if="waiting" />
        <div v-else class="grid gap-4">
          <Alert variant="warning"><AlertDescription>ลิงก์ไม่ถูกต้องหรือหมดอายุ กรุณาขอลิงก์ใหม่ที่หน้าเข้าสู่ระบบ</AlertDescription></Alert>
          <Button as-child variant="outline" class="w-full"><NuxtLink to="/login">ไปหน้าเข้าสู่ระบบ</NuxtLink></Button>
        </div>
      </CardContent>
    </Card>
  </div>
</template>
