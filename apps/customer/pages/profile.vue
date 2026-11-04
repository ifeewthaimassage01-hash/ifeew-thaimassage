<script setup lang="ts">
import { personNameSchema, thaiPhoneSchema } from '@ifeew/shared'

definePageMeta({ middleware: 'auth' })

const supabase = useSupabaseClient()
const user = useSupabaseUser()
const { code } = useCompany()
const { customer, refresh } = useCustomer()

const form = reactive({ firstName: '', lastName: '', phone: '' })
const saving = ref(false)
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)
const deleteDialog = ref(false)
const deleteReason = ref('')

watch(
  customer,
  (c) => {
    if (c) Object.assign(form, { firstName: c.first_name, lastName: c.last_name, phone: c.phone })
  },
  { immediate: true },
)

onMounted(() => refresh().catch(() => {}))

async function save() {
  message.value = null
  const first = personNameSchema.safeParse(form.firstName)
  const phone = thaiPhoneSchema.safeParse(form.phone)
  if (!first.success || !phone.success) {
    message.value = { type: 'error', text: 'กรุณาตรวจสอบชื่อและเบอร์โทร' }
    return
  }
  saving.value = true
  const { error } = await supabase.rpc('update_my_customer', {
    p_company_code: code, p_first_name: first.data, p_last_name: form.lastName.trim(), p_phone: phone.data,
  })
  saving.value = false
  message.value = error ? { type: 'error', text: error.message } : { type: 'success', text: 'บันทึกข้อมูลแล้ว' }
  await refresh()
}

async function toggleMarketing(granted: boolean | null) {
  const { error } = await supabase.rpc('set_my_marketing_consent', { p_company_code: code, p_granted: !!granted })
  if (error) message.value = { type: 'error', text: error.message }
  await refresh()
}

async function exportData() {
  const { data, error } = await supabase.rpc('export_my_data', { p_company_code: code })
  if (error) {
    message.value = { type: 'error', text: error.message }
    return
  }
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `ifeew-my-data-${new Date().toISOString().slice(0, 10)}.json`
  a.click()
  URL.revokeObjectURL(url)
}

async function requestDeletion() {
  const { error } = await supabase.rpc('request_my_data_deletion', { p_company_code: code, p_reason: deleteReason.value })
  deleteDialog.value = false
  message.value = error
    ? { type: 'error', text: error.message }
    : { type: 'success', text: 'ส่งคำขอลบข้อมูลแล้ว ร้านจะดำเนินการและแจ้งผลให้ทราบ' }
  await refresh()
}
</script>

<template>
  <div class="mx-auto grid max-w-md gap-4">
    <v-alert v-if="message" :type="message.type" variant="tonal" closable :text="message.text" @click:close="message = null" />

    <v-card class="p-6">
      <h1 class="m-0 mb-1 text-xl font-semibold text-cocoa">ข้อมูลส่วนตัว</h1>
      <p class="m-0 mb-6 text-sm text-light-brown">{{ user?.email }}</p>
      <v-progress-linear v-if="!customer" indeterminate color="primary" />
      <v-form v-else @submit.prevent="save">
        <div class="grid grid-cols-2 gap-x-3">
          <v-text-field v-model="form.firstName" label="ชื่อ" />
          <v-text-field v-model="form.lastName" label="นามสกุล" />
        </div>
        <v-text-field v-model="form.phone" label="เบอร์โทร" type="tel" inputmode="tel" />
        <v-btn type="submit" color="primary" block :loading="saving">บันทึก</v-btn>
      </v-form>
    </v-card>

    <v-card v-if="customer" class="p-6">
      <p class="m-0 mb-3 text-lg font-medium">ความเป็นส่วนตัว</p>
      <p class="m-0 text-sm">
        รับทราบนโยบายความเป็นส่วนตัว ฉบับ {{ customer.consents.PRIVACY_NOTICE?.version ?? '-' }}
        <span class="text-light-brown">
          ({{ customer.consents.PRIVACY_NOTICE ? new Date(customer.consents.PRIVACY_NOTICE.recorded_at).toLocaleDateString('th-TH', { timeZone: 'Asia/Bangkok' }) : '-' }})
        </span>
      </p>
      <v-switch
        :model-value="customer.consents.MARKETING?.granted ?? false"
        color="primary"
        label="รับข่าวสารและโปรโมชัน"
        hide-details
        @update:model-value="toggleMarketing"
      />
      <div class="mt-4 flex flex-col gap-2">
        <v-btn variant="tonal" color="primary" prepend-icon="mdi-download-outline" @click="exportData">ดาวน์โหลดข้อมูลของฉัน</v-btn>
        <v-btn
          variant="text"
          color="error"
          prepend-icon="mdi-account-remove-outline"
          :disabled="customer.pending_deletion"
          @click="deleteDialog = true"
        >
          {{ customer.pending_deletion ? 'ส่งคำขอลบข้อมูลแล้ว รอดำเนินการ' : 'ขอลบข้อมูลของฉัน' }}
        </v-btn>
      </div>
    </v-card>

    <v-dialog v-model="deleteDialog" max-width="440">
      <v-card class="p-6">
        <p class="m-0 mb-2 text-lg font-medium">ขอลบข้อมูลส่วนบุคคล</p>
        <p class="m-0 mb-4 text-sm text-light-brown">
          ร้านจะลบชื่อ เบอร์โทร และอีเมลของคุณ และปิดบัญชีนี้ ข้อมูลการเงินที่กฎหมายกำหนดจะถูกเก็บไว้โดยไม่ระบุตัวตน
        </p>
        <v-textarea v-model="deleteReason" label="เหตุผล (ไม่บังคับ)" rows="2" variant="outlined" />
        <div class="flex justify-end gap-2">
          <v-btn variant="text" @click="deleteDialog = false">ยกเลิก</v-btn>
          <v-btn color="error" @click="requestDeletion">ส่งคำขอ</v-btn>
        </div>
      </v-card>
    </v-dialog>
  </div>
</template>
