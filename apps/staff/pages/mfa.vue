<script setup lang="ts">
// OWNER ต้องยืนยันตัวตนด้วย TOTP ทุก session (ครั้งแรกจะให้ลงทะเบียน Authenticator)
definePageMeta({ layout: 'blank' })

const supabase = useSupabaseClient()
const { company, clear: clearAccess, refresh } = useAccess()

const loading = ref(true)
const verifying = ref(false)
const error = ref<string | null>(null)
const factorId = ref<string | null>(null)
const enrolling = ref(false)
const qrCode = ref<string | null>(null)
const secret = ref<string | null>(null)
const code = ref('')

async function setup() {
  loading.value = true
  error.value = null
  try {
    if (company.value?.role !== 'OWNER') {
      await navigateTo('/')
      return
    }
    const { data, error: listErr } = await supabase.auth.mfa.listFactors()
    if (listErr) throw listErr

    const verified = data.totp.find((f) => f.status === 'verified')
    if (verified) {
      factorId.value = verified.id
      enrolling.value = false
      return
    }

    // ลบ factor ที่ลงทะเบียนค้างไว้แต่ยังไม่ยืนยัน แล้วลงทะเบียนใหม่
    for (const f of data.all.filter((f) => f.factor_type === 'totp' && f.status === 'unverified')) {
      await supabase.auth.mfa.unenroll({ factorId: f.id })
    }
    const { data: enrolled, error: enrollErr } = await supabase.auth.mfa.enroll({
      factorType: 'totp',
      friendlyName: `Ifeew Owner ${new Date().toISOString().slice(0, 10)}`,
    })
    if (enrollErr) throw enrollErr
    factorId.value = enrolled.id
    qrCode.value = enrolled.totp.qr_code
    secret.value = enrolled.totp.secret
    enrolling.value = true
  } catch {
    error.value = 'ไม่สามารถเตรียมการยืนยันตัวตนได้ กรุณาลองใหม่'
  } finally {
    loading.value = false
  }
}

async function verify() {
  if (!factorId.value || !/^[0-9]{6}$/.test(code.value)) {
    error.value = 'กรุณากรอกรหัส 6 หลักจากแอป Authenticator'
    return
  }
  verifying.value = true
  error.value = null
  try {
    const { error: verifyErr } = await supabase.auth.mfa.challengeAndVerify({
      factorId: factorId.value,
      code: code.value,
    })
    if (verifyErr) {
      error.value = 'รหัสไม่ถูกต้องหรือหมดอายุ'
      code.value = ''
      return
    }
    clearAccess()
    await refresh()
    await navigateTo('/')
  } finally {
    verifying.value = false
  }
}

async function logout() {
  await supabase.auth.signOut()
  clearAccess()
  await navigateTo('/login')
}

onMounted(setup)
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-cream px-4">
    <v-card class="w-full max-w-md p-6">
      <h1 class="m-0 mb-1 text-xl font-semibold text-cocoa">ยืนยันตัวตนเจ้าของร้าน</h1>
      <p class="m-0 mb-6 text-sm text-light-brown">ใช้แอป Authenticator เช่น Google Authenticator หรือ Microsoft Authenticator</p>

      <v-progress-linear v-if="loading" indeterminate color="primary" />

      <template v-else>
        <div v-if="enrolling && qrCode" class="mb-6 text-center">
          <p class="mt-0">สแกน QR นี้ด้วยแอป Authenticator</p>
          <img :src="qrCode" alt="QR สำหรับลงทะเบียน Authenticator" class="mx-auto h-48 w-48 rounded-lg bg-white p-2" >
          <p class="mb-0 mt-3 break-all text-xs text-light-brown">หรือกรอกรหัสด้วยตนเอง: {{ secret }}</p>
        </div>

        <v-form @submit.prevent="verify">
          <v-text-field
            v-model="code"
            label="รหัส 6 หลัก"
            inputmode="numeric"
            autocomplete="one-time-code"
            maxlength="6"
            autofocus
          />
          <v-alert v-if="error" type="error" variant="tonal" class="mb-4" :text="error" />
          <v-btn type="submit" color="primary" block :loading="verifying">ยืนยัน</v-btn>
        </v-form>
      </template>

      <v-btn variant="text" block class="mt-3" @click="logout">ออกจากระบบ</v-btn>
    </v-card>
  </div>
</template>
