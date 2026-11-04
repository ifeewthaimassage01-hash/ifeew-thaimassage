<script setup lang="ts">
import { emailSchema, passwordSchema, personNameSchema, thaiPhoneSchema } from '@ifeew/shared'
import { z } from 'zod'

// สมัครสมาชิก: signUp (Auth) -> register_customer (DB: ลูกค้า + ความยินยอม)
// ถ้าเปิดยืนยันอีเมล จะยังไม่มี session -> หลังยืนยันและ login ระบบพาไปหน้า /complete-profile
const supabase = useSupabaseClient()
const { code } = useCompany()
const { refresh: refreshCustomer } = useCustomer()
const { data: policies } = await usePolicies()

const form = reactive({ firstName: '', lastName: '', phone: '', email: '', password: '', confirm: '' })
const privacy = ref(false)
const marketing = ref(false)
const loading = ref(false)
const error = ref<string | null>(null)
const done = ref(false)

const schema = z
  .object({
    firstName: personNameSchema,
    lastName: z.string().trim().max(100),
    phone: thaiPhoneSchema,
    email: emailSchema,
    password: passwordSchema,
    confirm: z.string(),
  })
  .refine((v) => v.password === v.confirm, { message: 'รหัสผ่านไม่ตรงกัน', path: ['confirm'] })

async function submit() {
  error.value = null
  const parsed = schema.safeParse(form)
  if (!parsed.success) {
    error.value = parsed.error.issues[0]?.message ?? 'ข้อมูลไม่ถูกต้อง'
    return
  }
  if (!privacy.value || !policies.value?.PRIVACY_NOTICE) {
    error.value = 'กรุณารับทราบนโยบายความเป็นส่วนตัว'
    return
  }
  const v = parsed.data
  loading.value = true
  try {
    const { data, error: err } = await supabase.auth.signUp({
      email: v.email,
      password: v.password,
      options: {
        // ใช้เติมฟอร์มอัตโนมัติในหน้า /complete-profile เท่านั้น (ไม่ใช้ตัดสินสิทธิ์)
        data: { display_name: `${v.firstName} ${v.lastName}`.trim(), first_name: v.firstName, last_name: v.lastName, phone: v.phone },
        emailRedirectTo: `${window.location.origin}/login`,
      },
    })
    if (err) {
      error.value = 'สมัครสมาชิกไม่สำเร็จ กรุณาตรวจสอบข้อมูลแล้วลองใหม่'
      return
    }
    form.password = ''
    form.confirm = ''
    if (!data.session) {
      done.value = true
      return
    }
    const { error: regErr } = await supabase.rpc('register_customer', {
      p_company_code: code,
      p_first_name: v.firstName,
      p_last_name: v.lastName,
      p_phone: v.phone,
      p_privacy_version_id: policies.value.PRIVACY_NOTICE.id,
      p_marketing_consent: marketing.value,
    })
    if (regErr) {
      error.value = regErr.message
      return
    }
    await refreshCustomer()
    await navigateTo('/profile')
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <v-card class="mx-auto max-w-md p-6">
    <h1 class="m-0 mb-6 text-xl font-semibold text-cocoa">สมัครสมาชิก</h1>

    <v-alert v-if="done" type="success" variant="tonal" text="สมัครเรียบร้อย กรุณายืนยันอีเมล แล้วเข้าสู่ระบบเพื่อใช้งาน" />

    <v-form v-else @submit.prevent="submit">
      <div class="grid grid-cols-2 gap-x-3">
        <v-text-field v-model="form.firstName" label="ชื่อ" autocomplete="given-name" />
        <v-text-field v-model="form.lastName" label="นามสกุล" autocomplete="family-name" />
      </div>
      <v-text-field v-model="form.phone" label="เบอร์โทร" type="tel" inputmode="tel" autocomplete="tel" />
      <v-text-field v-model="form.email" label="อีเมล" type="email" autocomplete="email" />
      <v-text-field
        v-model="form.password"
        label="รหัสผ่าน"
        type="password"
        autocomplete="new-password"
        hint="อย่างน้อย 10 ตัว มีตัวพิมพ์เล็ก พิมพ์ใหญ่ และตัวเลข"
        persistent-hint
        class="mb-2"
      />
      <v-text-field v-model="form.confirm" label="ยืนยันรหัสผ่าน" type="password" autocomplete="new-password" />
      <ConsentFields v-model:privacy="privacy" v-model:marketing="marketing" :policies="policies ?? null" />
      <v-alert v-if="error" type="error" variant="tonal" class="mb-4" :text="error" />
      <v-btn type="submit" color="primary" block :loading="loading">สมัครสมาชิก</v-btn>
    </v-form>

    <p class="mb-0 mt-4 text-center text-sm">
      มีบัญชีแล้ว? <NuxtLink to="/login" class="text-light-brown">เข้าสู่ระบบ</NuxtLink>
    </p>
  </v-card>
</template>
