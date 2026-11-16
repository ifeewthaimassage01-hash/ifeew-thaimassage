<script setup lang="ts">
// OWNER: PIN เจ้าของร้าน (ใช้เข้าระบบที่หน้า login แท็บเจ้าของร้าน)
// เลิกใช้การผูกเครื่องกับสาขาแล้ว — พนักงานเลือกสาขาจากหน้า login ได้เลย (migration 030)
definePageMeta({ ownerOnly: true })

const supabase = useSupabaseClient()
const { company } = useAccess()

const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)
const ownerPin = ref({ has_pin: false, pin_updated_at: null as string | null })
const pinForm = reactive({ pin: '', confirm: '' })
const pinSaving = ref(false)

async function loadOwnerPin() {
  if (!company.value) return
  const { data } = await supabase.rpc('my_owner_pin_status', { p_company_id: company.value.company_id })
  if (data) ownerPin.value = data as unknown as typeof ownerPin.value
}
watch(() => company.value?.company_id, loadOwnerPin, { immediate: true })

async function saveOwnerPin() {
  if (!company.value) return
  if (!/^[0-9]{6}$/.test(pinForm.pin) || pinForm.pin !== pinForm.confirm) {
    message.value = { type: 'error', text: 'PIN ต้องเป็นตัวเลข 6 หลัก และกรอกให้ตรงกันทั้งสองช่อง' }
    return
  }
  pinSaving.value = true
  const { error } = await supabase.rpc('set_my_owner_pin', { p_company_id: company.value.company_id, p_pin: pinForm.pin })
  pinSaving.value = false
  pinForm.pin = ''
  pinForm.confirm = ''
  if (error) {
    message.value = { type: 'error', text: error.message }
    return
  }
  message.value = { type: 'success', text: 'บันทึก PIN เจ้าของร้านแล้ว ใช้เข้าระบบได้ทุกเครื่อง' }
  await loadOwnerPin()
}
</script>

<template>
  <div class="mx-auto max-w-2xl">
    <PageHeader title="PIN เจ้าของร้าน" description="ใช้เข้าระบบที่หน้าเข้าสู่ระบบ แท็บเจ้าของร้าน" />
    <MessageAlert :message="message" class="mb-6" @close="message = null" />

    <SectionCard title="PIN เจ้าของร้าน">
      <template #actions><Badge :variant="ownerPin.has_pin ? 'success' : 'pending'" dot>{{ ownerPin.has_pin ? 'ตั้งแล้ว' : 'ยังไม่ได้ตั้ง' }}</Badge></template>
      <p class="m-0 mb-4 text-sm text-muted-foreground">
        ตัวเลข 6 หลัก ห้ามเลขซ้ำหรือเรียง อย่าให้ใครเห็นตอนกด เพราะ PIN นี้เข้าถึงข้อมูลการเงินทั้งหมด
      </p>
      <form class="grid items-end gap-3 sm:grid-cols-[1fr_1fr_auto]" @submit.prevent="saveOwnerPin">
        <TextField v-model="pinForm.pin" numeric="digits" label="PIN ใหม่" type="password" inputmode="numeric" maxlength="6" autocomplete="new-password" />
        <TextField v-model="pinForm.confirm" numeric="digits" label="ยืนยัน PIN" type="password" inputmode="numeric" maxlength="6" autocomplete="new-password" />
        <Button type="submit" :disabled="pinSaving">{{ ownerPin.has_pin ? 'เปลี่ยน PIN' : 'ตั้ง PIN' }}</Button>
      </form>
    </SectionCard>
  </div>
</template>
