<script setup lang="ts">
import { personNameSchema, thaiPhoneSchema } from '@ifeew/shared'

// ผู้ใช้ที่มีบัญชีแล้วแต่ยังไม่เป็นลูกค้าของบริษัทนี้ (เช่น เพิ่งยืนยันอีเมล)
definePageMeta({ middleware: 'auth' })
useHead({ title: "ข้อมูลของคุณ — Ifeew's Thaimassage" })

const supabase = useSupabaseClient()
const route = useRoute()
const { code } = useCompany()
const { refresh } = useCustomer()
const { data: policies } = await usePolicies()

const meta = (await supabase.auth.getUser()).data.user?.user_metadata ?? {}
const form = reactive({
  firstName: String(meta.first_name ?? ''),
  lastName: String(meta.last_name ?? ''),
  phone: String(meta.phone ?? ''),
})
const privacy = ref(false)
const marketing = ref(false)
const loading = ref(false)
const error = ref<string | null>(null)

const redirectTo = computed(() => {
  const r = String(route.query.redirect ?? '/profile')
  return r.startsWith('/') && !r.startsWith('//') ? r : '/profile'
})

async function submit() {
  error.value = null
  const first = personNameSchema.safeParse(form.firstName)
  const phone = thaiPhoneSchema.safeParse(form.phone)
  if (!first.success || !phone.success) {
    error.value = (first.success ? phone : first).error?.issues[0]?.message ?? 'ข้อมูลไม่ถูกต้อง'
    return
  }
  if (!privacy.value || !policies.value?.PRIVACY_NOTICE) {
    error.value = 'กรุณารับทราบนโยบายความเป็นส่วนตัว'
    return
  }
  loading.value = true
  const { error: err } = await supabase.rpc('register_customer', {
    p_company_code: code,
    p_first_name: first.data,
    p_last_name: form.lastName.trim(),
    p_phone: phone.data,
    p_privacy_version_id: policies.value.PRIVACY_NOTICE.id,
    p_marketing_consent: marketing.value,
  })
  loading.value = false
  if (err) {
    error.value = err.message
    return
  }
  await refresh()
  await navigateTo(redirectTo.value)
}
</script>

<template>
  <AuthShell title="ข้อมูลของคุณ" subtitle="กรอกชื่อและเบอร์โทรเพื่อเริ่มจองคิว ร้านใช้เบอร์นี้ติดต่อเรื่องนัดเท่านั้น">
    <form class="grid gap-4" novalidate @submit.prevent="submit">
      <div class="grid grid-cols-2 gap-3">
        <div class="grid gap-1.5"><Label for="c-first">ชื่อ</Label><Input id="c-first" v-model="form.firstName" autocomplete="given-name" required /></div>
        <div class="grid gap-1.5"><Label for="c-last">นามสกุล</Label><Input id="c-last" v-model="form.lastName" autocomplete="family-name" /></div>
      </div>
      <div class="grid gap-1.5"><Label for="c-phone">เบอร์โทร</Label><Input id="c-phone" v-model="form.phone" numeric="digits" type="tel" inputmode="tel" autocomplete="tel" required class="num" /></div>
      <ConsentFields v-model:privacy="privacy" v-model:marketing="marketing" :policies="policies ?? null" />
      <Alert v-if="error" variant="destructive"><AlertDescription>{{ error }}</AlertDescription></Alert>
      <Button type="submit" size="lg" class="w-full" :disabled="loading">{{ loading ? 'กำลังบันทึก…' : 'บันทึกและเริ่มใช้งาน' }}</Button>
    </form>
  </AuthShell>
</template>
