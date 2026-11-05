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
  <Dialog :open="open" @update:open="(v) => !v && !loading && finish(false)">
    <DialogContent class="sm:max-w-sm" :show-close-button="false" @interact-outside.prevent @escape-key-down.prevent>
      <DialogHeader>
        <DialogTitle>ยืนยันตัวตนอีกครั้ง</DialogTitle>
        <DialogDescription>การทำรายการนี้ต้องใช้รหัสจากแอป Authenticator</DialogDescription>
      </DialogHeader>
      <form class="grid gap-4" @submit.prevent="verify">
        <TextField v-model="code" label="รหัส 6 หลัก" inputmode="numeric" autocomplete="one-time-code" maxlength="6" autofocus class="num" />
        <Alert v-if="error" variant="destructive"><AlertDescription>{{ error }}</AlertDescription></Alert>
        <DialogFooter class="gap-2">
          <Button type="button" variant="outline" :disabled="loading" @click="finish(false)">ยกเลิก</Button>
          <Button type="submit" :disabled="loading">{{ loading ? 'กำลังตรวจสอบ…' : 'ยืนยัน' }}</Button>
        </DialogFooter>
      </form>
    </DialogContent>
  </Dialog>
</template>
