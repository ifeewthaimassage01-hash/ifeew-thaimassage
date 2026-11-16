<script setup lang="ts">
// OWNER: บัญชีรับมัดจำของสาขา (ลูกค้าเห็น QR PromptPay ของบัญชีนี้ในหน้าจอง) — ใช้ใน popup หน้า /branches และหน้า /branches/[id]
import type { Tables } from '@ifeew/shared'

const props = defineProps<{ branchId: string; companyId: string }>()
const emit = defineEmits<{ saved: [] }>()

type PaymentAccount = Tables<'branch_payment_accounts'>

const supabase = useSupabaseClient()
const account = ref<PaymentAccount | null>(null)
const form = reactive({ promptpay_id: '', account_name: '', bank_name: '', slipok_branch_id: '', is_active: true })
const saving = ref(false)
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)

async function load() {
  const { data } = await supabase.from('branch_payment_accounts').select('*').eq('branch_id', props.branchId).maybeSingle()
  account.value = data ?? null
  Object.assign(form, {
    promptpay_id: data?.promptpay_id ?? '',
    account_name: data?.account_name ?? '',
    bank_name: data?.bank_name ?? '',
    slipok_branch_id: data?.slipok_branch_id ?? '',
    is_active: data?.is_active ?? true,
  })
}
watch(() => props.branchId, () => { message.value = null; load() }, { immediate: true })

async function save() {
  const pp = form.promptpay_id.replace(/[^0-9]/g, '')
  if (!/^(0[0-9]{9}|[0-9]{13}|[0-9]{15})$/.test(pp) || !form.account_name.trim()) {
    message.value = { type: 'error', text: 'PromptPay ต้องเป็นเบอร์มือถือ 10 หลัก / เลขประจำตัว 13 หลัก / e-Wallet 15 หลัก และต้องมีชื่อบัญชี' }
    return
  }
  const payload = {
    promptpay_id: pp,
    account_name: form.account_name.trim(),
    bank_name: form.bank_name.trim() || null,
    slipok_branch_id: form.slipok_branch_id.trim() || null,
    is_active: form.is_active,
  }
  saving.value = true
  try {
    if (account.value) await must(supabase.from('branch_payment_accounts').update(payload).eq('id', account.value.id))
    else await must(supabase.from('branch_payment_accounts').insert({ ...payload, company_id: props.companyId, branch_id: props.branchId }))
    message.value = { type: 'success', text: 'บันทึกบัญชีรับมัดจำแล้ว' }
    await load()
    emit('saved')
  } catch (e) {
    message.value = { type: 'error', text: errorText(e, 'บันทึกบัญชีไม่สำเร็จ') }
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <form class="@container grid gap-4" @submit.prevent="save">
    <MessageAlert :message="message" @close="message = null" />
    <div class="grid gap-4 @lg:grid-cols-2">
      <TextField v-model="form.promptpay_id" numeric="digits" label="PromptPay" hint="เบอร์มือถือ 10 หลัก / เลขประจำตัว 13 หลัก / e-Wallet 15 หลัก" inputmode="numeric" class="num" />
      <TextField v-model="form.account_name" label="ชื่อบัญชี" />
      <TextField v-model="form.bank_name" label="ธนาคาร" />
      <TextField v-model="form.slipok_branch_id" label="SlipOK Branch ID" hint="เว้นว่าง = พนักงานตรวจสลิปเอง" />
    </div>
    <SwitchField v-model="form.is_active" label="เปิดใช้งาน" />
    <div class="flex justify-end"><Button type="submit" :disabled="saving">{{ saving ? 'กำลังบันทึก…' : 'บันทึกบัญชี' }}</Button></div>
  </form>
</template>
