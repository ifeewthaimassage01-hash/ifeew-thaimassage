<script setup lang="ts">
import { personNameSchema, thaiPhoneSchema } from '@ifeew/shared'

// ผู้ใช้ที่มีบัญชีแล้วแต่ยังไม่เป็นลูกค้าของบริษัทนี้ (เช่น เพิ่งยืนยันอีเมล)
definePageMeta({ middleware: 'auth' })

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
  <v-card class="mx-auto max-w-md p-6">
    <h1 class="m-0 mb-1 text-xl font-semibold text-cocoa">ข้อมูลของคุณ</h1>
    <p class="m-0 mb-6 text-sm text-light-brown">กรอกข้อมูลเพื่อเริ่มใช้งานการจอง</p>
    <v-form @submit.prevent="submit">
      <div class="grid grid-cols-2 gap-x-3">
        <v-text-field v-model="form.firstName" label="ชื่อ" autocomplete="given-name" />
        <v-text-field v-model="form.lastName" label="นามสกุล" autocomplete="family-name" />
      </div>
      <v-text-field v-model="form.phone" label="เบอร์โทร" type="tel" inputmode="tel" autocomplete="tel" />
      <ConsentFields v-model:privacy="privacy" v-model:marketing="marketing" :policies="policies ?? null" />
      <v-alert v-if="error" type="error" variant="tonal" class="mb-4" :text="error" />
      <v-btn type="submit" color="primary" block :loading="loading">บันทึก</v-btn>
    </v-form>
  </v-card>
</template>
