<script setup lang="ts">
import { emailSchema, passwordSchema, personNameSchema, thaiPhoneSchema } from '@ifeew/shared'
import { z } from 'zod'

// สมัครสมาชิก: signUp (Auth) -> register_customer (DB: ลูกค้า + ความยินยอม)
// ถ้าเปิดยืนยันอีเมล จะยังไม่มี session -> หลังยืนยันและ login ระบบพาไปหน้า /complete-profile
useHead({ title: "สมัครสมาชิก — Ifeew's Thaimassage" })

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
  <AuthShell title="สมัครสมาชิก" subtitle="ใช้เวลาไม่ถึงนาที จองครั้งต่อไปไม่ต้องกรอกข้อมูลซ้ำ">
    <Alert v-if="done" variant="success"><AlertDescription>สมัครเรียบร้อย กรุณายืนยันอีเมล แล้วเข้าสู่ระบบเพื่อใช้งาน</AlertDescription></Alert>

    <form v-else class="grid gap-4" novalidate @submit.prevent="submit">
      <div class="grid grid-cols-2 gap-3">
        <div class="grid gap-1.5"><Label for="r-first">ชื่อ</Label><Input id="r-first" v-model="form.firstName" autocomplete="given-name" required /></div>
        <div class="grid gap-1.5"><Label for="r-last">นามสกุล</Label><Input id="r-last" v-model="form.lastName" autocomplete="family-name" /></div>
      </div>
      <div class="grid gap-1.5"><Label for="r-phone">เบอร์โทร</Label><Input id="r-phone" v-model="form.phone" type="tel" inputmode="tel" autocomplete="tel" required class="num" /></div>
      <div class="grid gap-1.5"><Label for="r-email">อีเมล</Label><Input id="r-email" v-model="form.email" type="email" autocomplete="email" required /></div>
      <div class="grid gap-1.5">
        <Label for="r-pass">รหัสผ่าน</Label>
        <Input id="r-pass" v-model="form.password" type="password" autocomplete="new-password" required aria-describedby="r-pass-hint" />
        <p id="r-pass-hint" class="m-0 text-sm text-muted-foreground">อย่างน้อย 10 ตัว มีตัวพิมพ์เล็ก พิมพ์ใหญ่ และตัวเลข</p>
      </div>
      <div class="grid gap-1.5"><Label for="r-confirm">ยืนยันรหัสผ่าน</Label><Input id="r-confirm" v-model="form.confirm" type="password" autocomplete="new-password" required /></div>
      <ConsentFields v-model:privacy="privacy" v-model:marketing="marketing" :policies="policies ?? null" />
      <Alert v-if="error" variant="destructive"><AlertDescription>{{ error }}</AlertDescription></Alert>
      <Button type="submit" size="lg" class="w-full" :disabled="loading">{{ loading ? 'กำลังสมัคร…' : 'สมัครสมาชิก' }}</Button>
    </form>

    <template #footer>มีบัญชีแล้ว? <NuxtLink to="/login">เข้าสู่ระบบ</NuxtLink></template>
  </AuthShell>
</template>
