<script setup lang="ts">
// หน้าต่างยืนยันรหัส Authenticator ซ้ำ (ใช้กับ useStepUp)
const supabase = useSupabaseClient()
const { open, finish } = useStepUp()

const code = ref('')
const loading = ref(false)
const error = ref<string | null>(null)

watch(open, (v) => {
  if (v) {
    code.value = ''
    error.value = null
  }
})

async function verify() {
  if (!/^[0-9]{6}$/.test(code.value)) {
    error.value = 'กรุณากรอกรหัส 6 หลัก'
    return
  }
  loading.value = true
  error.value = null
  try {
    const { data, error: listErr } = await supabase.auth.mfa.listFactors()
    const factor = data?.totp.find((f) => f.status === 'verified')
    if (listErr || !factor) {
      error.value = 'ไม่พบ Authenticator ของบัญชีนี้'
      return
    }
    const { error: verifyErr } = await supabase.auth.mfa.challengeAndVerify({ factorId: factor.id, code: code.value })
    if (verifyErr) {
      error.value = 'รหัสไม่ถูกต้องหรือหมดอายุ'
      code.value = ''
      return
    }
    finish(true)
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <v-dialog :model-value="open" max-width="400" persistent>
    <v-card class="p-6">
      <p class="m-0 mb-1 text-lg font-medium">ยืนยันตัวตนอีกครั้ง</p>
      <p class="m-0 mb-4 text-sm text-light-brown">การทำรายการนี้ต้องใช้รหัสจากแอป Authenticator</p>
      <v-form @submit.prevent="verify">
        <v-text-field v-model="code" label="รหัส 6 หลัก" inputmode="numeric" autocomplete="one-time-code" maxlength="6" autofocus />
        <v-alert v-if="error" type="error" variant="tonal" class="mb-4" :text="error" />
        <div class="flex justify-end gap-2">
          <v-btn variant="text" :disabled="loading" @click="finish(false)">ยกเลิก</v-btn>
          <v-btn type="submit" color="primary" :loading="loading">ยืนยัน</v-btn>
        </div>
      </v-form>
    </v-card>
  </v-dialog>
</template>
