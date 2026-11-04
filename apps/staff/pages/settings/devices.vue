<script setup lang="ts">
// OWNER: ผูกเครื่องนี้กับสาขา / ดูและยกเลิกเครื่องที่ผูกไว้
import type { Tables } from '@ifeew/shared'

definePageMeta({ ownerOnly: true })

type Device = Pick<
  Tables<'branch_devices'>,
  'id' | 'branch_id' | 'name' | 'status' | 'paired_at' | 'last_seen_at' | 'revoked_at' | 'revoke_reason'
>

const supabase = useSupabaseClient()
const { company, branches } = useAccess()
const { token, savePairing, forget } = useStaffDevice()

const devices = ref<Device[]>([])
const loading = ref(false)
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)

const pairBranchId = ref<string | null>(branches.value[0]?.branch_id ?? null)
const pairName = ref('')
const pairing = ref(false)

const revokeTarget = ref<Device | null>(null)
const revokeReason = ref('')
const revoking = ref(false)

const branchName = (id: string) => branches.value.find((b) => b.branch_id === id)?.name ?? '-'
const fmt = (v: string | null) => (v ? new Date(v).toLocaleString('th-TH', { timeZone: 'Asia/Bangkok' }) : '-')

async function load() {
  if (!company.value) return
  loading.value = true
  const { data, error } = await supabase
    .from('branch_devices')
    .select('id, branch_id, name, status, paired_at, last_seen_at, revoked_at, revoke_reason')
    .eq('company_id', company.value.company_id)
    .order('paired_at', { ascending: false })
  loading.value = false
  if (error) {
    message.value = { type: 'error', text: 'โหลดรายการเครื่องไม่สำเร็จ' }
    return
  }
  devices.value = data ?? []
}

async function pair() {
  if (!pairBranchId.value || !pairName.value.trim()) {
    message.value = { type: 'error', text: 'กรุณาเลือกสาขาและตั้งชื่อเครื่อง' }
    return
  }
  pairing.value = true
  message.value = null
  const { data, error } = await supabase.rpc('pair_branch_device', {
    p_branch_id: pairBranchId.value,
    p_name: pairName.value.trim(),
  })
  pairing.value = false
  if (error) {
    message.value = { type: 'error', text: 'ผูกเครื่องไม่สำเร็จ' }
    return
  }
  savePairing((data as { device_token: string }).device_token)
  pairName.value = ''
  message.value = { type: 'success', text: 'ผูกเครื่องนี้กับสาขาเรียบร้อย พนักงานสามารถเข้าสู่ระบบด้วย PIN ได้แล้ว' }
  await load()
}

async function confirmRevoke() {
  if (!revokeTarget.value || revokeReason.value.trim().length < 3) return
  revoking.value = true
  const { error } = await supabase.rpc('revoke_branch_device', {
    p_device_id: revokeTarget.value.id,
    p_reason: revokeReason.value.trim(),
  })
  revoking.value = false
  if (error) {
    message.value = { type: 'error', text: 'ยกเลิกเครื่องไม่สำเร็จ' }
    return
  }
  revokeTarget.value = null
  revokeReason.value = ''
  message.value = { type: 'success', text: 'ยกเลิกเครื่องแล้ว' }
  await load()
}

// PIN ของเจ้าของร้าน (ใช้ login บนเครื่องสาขาที่ผูกแล้ว)
const ownerPin = ref({ has_pin: false, pin_updated_at: null as string | null })
const pinForm = reactive({ pin: '', confirm: '' })
const pinSaving = ref(false)

async function loadOwnerPin() {
  if (!company.value) return
  const { data } = await supabase.rpc('my_owner_pin_status', { p_company_id: company.value.company_id })
  if (data) ownerPin.value = data as unknown as typeof ownerPin.value
}

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
  message.value = { type: 'success', text: 'บันทึก PIN เจ้าของร้านแล้ว — ใช้ได้บนทุกเครื่องที่ผูกกับสาขา' }
  await loadOwnerPin()
}

onMounted(() => {
  load()
  loadOwnerPin()
})
</script>

<template>
  <div>
    <h1 class="m-0 mb-6 text-2xl font-semibold text-cocoa">ตั้งค่าเครื่องประจำสาขา</h1>

    <v-alert v-if="message" :type="message.type" variant="tonal" class="mb-6" closable :text="message.text" @click:close="message = null" />

    <v-card class="mb-6 p-6">
      <p class="m-0 mb-1 text-lg font-medium">PIN เจ้าของร้าน</p>
      <p class="m-0 mb-4 text-sm text-light-brown">
        {{ ownerPin.has_pin ? 'ตั้ง PIN แล้ว — ที่หน้าเข้าสู่ระบบของเครื่องสาขา กดชื่อเจ้าของร้านแล้วใส่ PIN' : 'ยังไม่ได้ตั้ง PIN' }}
        · ตัวเลข 6 หลัก ห้ามเลขซ้ำ/เรียง · อย่าให้ใครเห็นตอนกด เพราะ PIN นี้เข้าถึงข้อมูลการเงินทั้งหมด
      </p>
      <v-form class="grid gap-x-4 md:grid-cols-3" @submit.prevent="saveOwnerPin">
        <v-text-field v-model="pinForm.pin" label="PIN ใหม่" type="password" inputmode="numeric" maxlength="6" autocomplete="new-password" />
        <v-text-field v-model="pinForm.confirm" label="ยืนยัน PIN" type="password" inputmode="numeric" maxlength="6" autocomplete="new-password" />
        <v-btn type="submit" color="primary" :loading="pinSaving" class="!h-auto">{{ ownerPin.has_pin ? 'เปลี่ยน PIN' : 'ตั้ง PIN' }}</v-btn>
      </v-form>
    </v-card>

    <v-card class="mb-6 p-6">
      <p class="m-0 mb-1 text-lg font-medium">ผูกเครื่องนี้กับสาขา</p>
      <p class="m-0 mb-4 text-sm text-light-brown">
        {{ token ? 'เครื่องนี้ผูกไว้แล้ว การผูกใหม่จะแทนที่ค่าเดิมในเครื่องนี้' : 'เครื่องนี้ยังไม่ได้ผูก' }}
      </p>
      <div class="grid gap-4 md:grid-cols-3">
        <v-select v-model="pairBranchId" :items="branches" item-title="name" item-value="branch_id" label="สาขา" />
        <v-text-field v-model="pairName" label="ชื่อเครื่อง เช่น iPad หน้าร้าน" maxlength="100" />
        <v-btn color="primary" :loading="pairing" @click="pair">ผูกเครื่องนี้</v-btn>
      </div>
      <v-btn v-if="token" variant="text" color="error" class="mt-2" @click="forget">ลบการผูกออกจากเครื่องนี้</v-btn>
    </v-card>

    <v-card class="p-2">
      <v-data-table
        :items="devices"
        :loading="loading"
        :headers="[
          { title: 'ชื่อเครื่อง', key: 'name' },
          { title: 'สาขา', key: 'branch_id' },
          { title: 'สถานะ', key: 'status' },
          { title: 'ผูกเมื่อ', key: 'paired_at' },
          { title: 'ใช้งานล่าสุด', key: 'last_seen_at' },
          { title: '', key: 'actions', sortable: false, align: 'end' },
        ]"
        no-data-text="ยังไม่มีเครื่องที่ผูกไว้"
      >
        <template #[`item.branch_id`]="{ item }">{{ branchName(item.branch_id) }}</template>
        <template #[`item.status`]="{ item }">
          <v-chip :color="item.status === 'ACTIVE' ? 'success' : 'error'" variant="tonal" size="small">
            {{ item.status === 'ACTIVE' ? 'ใช้งาน' : 'ยกเลิกแล้ว' }}
          </v-chip>
        </template>
        <template #[`item.paired_at`]="{ item }">{{ fmt(item.paired_at) }}</template>
        <template #[`item.last_seen_at`]="{ item }">{{ fmt(item.last_seen_at) }}</template>
        <template #[`item.actions`]="{ item }">
          <v-btn v-if="item.status === 'ACTIVE'" variant="text" color="error" @click="revokeTarget = item">ยกเลิก</v-btn>
        </template>
      </v-data-table>
    </v-card>

    <v-dialog :model-value="!!revokeTarget" max-width="440" @update:model-value="revokeTarget = null">
      <v-card class="p-6">
        <p class="m-0 mb-4 text-lg font-medium">ยกเลิกเครื่อง “{{ revokeTarget?.name }}”</p>
        <v-textarea v-model="revokeReason" label="เหตุผล (บังคับ)" rows="2" variant="outlined" />
        <div class="flex justify-end gap-2">
          <v-btn variant="text" @click="revokeTarget = null">ปิด</v-btn>
          <v-btn color="error" :loading="revoking" :disabled="revokeReason.trim().length < 3" @click="confirmRevoke">
            ยืนยันยกเลิก
          </v-btn>
        </div>
      </v-card>
    </v-dialog>
  </div>
</template>
