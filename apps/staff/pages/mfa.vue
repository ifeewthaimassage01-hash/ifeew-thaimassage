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
  <div class="grid min-h-dvh place-items-center px-4 py-10">
    <Card class="w-full max-w-md gap-5 py-6">
      <CardHeader class="px-6">
        <BrandMark class="mb-2 size-10" />
        <CardTitle as="h1" class="text-2xl">ยืนยันตัวตนเจ้าของร้าน</CardTitle>
        <p class="m-0 text-[15px] text-muted-foreground">ใช้แอป Authenticator เช่น Google Authenticator หรือ Microsoft Authenticator</p>
      </CardHeader>
      <CardContent class="grid gap-4 px-6">
        <LoadingBar v-if="loading" />
        <template v-else>
          <figure v-if="enrolling && qrCode" class="m-0 grid justify-items-center gap-2 rounded-lg bg-muted p-4 text-center">
            <figcaption class="text-[15px] text-heading">สแกน QR นี้ด้วยแอป Authenticator</figcaption>
            <img :src="qrCode" alt="QR สำหรับลงทะเบียน Authenticator" class="size-48 rounded-md bg-white p-2">
            <p class="m-0 text-sm break-all text-muted-foreground">หรือกรอกรหัสด้วยตนเอง: <span class="num text-heading">{{ secret }}</span></p>
          </figure>
          <form class="grid gap-4" @submit.prevent="verify">
            <TextField v-model="code" label="รหัส 6 หลัก" inputmode="numeric" autocomplete="one-time-code" maxlength="6" autofocus class="num" />
            <Alert v-if="error" variant="destructive"><AlertDescription>{{ error }}</AlertDescription></Alert>
            <Button type="submit" size="lg" class="w-full" :disabled="verifying">{{ verifying ? 'กำลังตรวจสอบ…' : 'ยืนยัน' }}</Button>
          </form>
        </template>
        <Button variant="ghost" class="w-full" @click="logout">ออกจากระบบ</Button>
      </CardContent>
    </Card>
  </div>
</template>
