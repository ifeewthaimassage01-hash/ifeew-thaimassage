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
    <PageHeader title="ตั้งค่าเครื่องประจำสาขา" description="ผูกเครื่องกับสาขาเพื่อให้พนักงานเข้าด้วย PIN และตั้ง PIN เจ้าของร้าน" />
    <MessageAlert :message="message" class="mb-6" @close="message = null" />

    <div class="grid gap-6">
      <div class="grid items-start gap-6 xl:grid-cols-2">
        <SectionCard title="PIN เจ้าของร้าน">
          <template #actions><Badge :variant="ownerPin.has_pin ? 'success' : 'pending'" dot>{{ ownerPin.has_pin ? 'ตั้งแล้ว' : 'ยังไม่ได้ตั้ง' }}</Badge></template>
          <p class="m-0 mb-4 text-sm text-muted-foreground">
            ตัวเลข 6 หลัก ห้ามเลขซ้ำหรือเรียง ใช้เข้าระบบบนทุกเครื่องที่ผูกกับสาขา อย่าให้ใครเห็นตอนกด เพราะ PIN นี้เข้าถึงข้อมูลการเงินทั้งหมด
          </p>
          <form class="grid items-end gap-3 sm:grid-cols-[1fr_1fr_auto]" @submit.prevent="saveOwnerPin">
            <TextField v-model="pinForm.pin" label="PIN ใหม่" type="password" inputmode="numeric" maxlength="6" autocomplete="new-password" />
            <TextField v-model="pinForm.confirm" label="ยืนยัน PIN" type="password" inputmode="numeric" maxlength="6" autocomplete="new-password" />
            <Button type="submit" :disabled="pinSaving">{{ ownerPin.has_pin ? 'เปลี่ยน PIN' : 'ตั้ง PIN' }}</Button>
          </form>
        </SectionCard>

        <SectionCard title="ผูกเครื่องนี้กับสาขา">
          <template #actions><Badge :variant="token ? 'success' : 'neutral'" dot>{{ token ? 'ผูกแล้ว' : 'ยังไม่ผูก' }}</Badge></template>
          <p class="m-0 mb-4 text-sm text-muted-foreground">{{ token ? 'การผูกใหม่จะแทนที่ค่าเดิมในเครื่องนี้' : 'ผูกแล้วพนักงานจะเลือกชื่อและกด PIN ที่หน้าเข้าสู่ระบบได้' }}</p>
          <form class="grid items-end gap-3 sm:grid-cols-[1fr_1fr_auto]" @submit.prevent="pair">
            <SelectField v-model="pairBranchId" :items="branches" item-title="name" item-value="branch_id" label="สาขา" />
            <TextField v-model="pairName" label="ชื่อเครื่อง" placeholder="เช่น iPad หน้าร้าน" maxlength="100" />
            <Button type="submit" :disabled="pairing">ผูกเครื่องนี้</Button>
          </form>
          <Button v-if="token" variant="ghost" size="sm" class="mt-3 text-danger-ink" @click="forget">ลบการผูกออกจากเครื่องนี้</Button>
        </SectionCard>
      </div>

      <SectionCard title="เครื่องที่ผูกไว้" :description="`${devices.length} เครื่อง`" flush>
        <LoadingBar v-if="loading" />
        <div class="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow class="hover:bg-transparent">
                <TableHead>ชื่อเครื่อง</TableHead><TableHead>สาขา</TableHead><TableHead>สถานะ</TableHead>
                <TableHead>ผูกเมื่อ</TableHead><TableHead>ใช้งานล่าสุด</TableHead>
                <TableHead class="text-right"><span class="sr-only">การทำงาน</span></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              <TableRow v-for="d in devices" :key="d.id">
                <TableCell class="font-medium text-heading">{{ d.name }}</TableCell>
                <TableCell>{{ branchName(d.branch_id) }}</TableCell>
                <TableCell><Badge :variant="d.status === 'ACTIVE' ? 'success' : 'neutral'" dot>{{ d.status === 'ACTIVE' ? 'ใช้งาน' : 'ยกเลิกแล้ว' }}</Badge></TableCell>
                <TableCell class="num">{{ fmt(d.paired_at) }}</TableCell>
                <TableCell class="num">{{ fmt(d.last_seen_at) }}</TableCell>
                <TableCell class="text-right">
                  <Button v-if="d.status === 'ACTIVE'" variant="ghost" size="sm" class="text-danger-ink" @click="revokeTarget = d">ยกเลิก</Button>
                </TableCell>
              </TableRow>
              <TableRow v-if="!loading && !devices.length" class="hover:bg-transparent">
                <TableCell colspan="6" class="py-8 text-center text-muted-foreground">ยังไม่มีเครื่องที่ผูกไว้</TableCell>
              </TableRow>
            </TableBody>
          </Table>
        </div>
      </SectionCard>
    </div>

    <Dialog :open="!!revokeTarget" @update:open="(v) => !v && (revokeTarget = null)">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>ยกเลิกเครื่อง “{{ revokeTarget?.name }}”</DialogTitle>
          <DialogDescription>พนักงานจะเข้าสู่ระบบด้วย PIN บนเครื่องนี้ไม่ได้อีก</DialogDescription>
        </DialogHeader>
        <TextareaField v-model="revokeReason" label="เหตุผล" hint="บังคับ อย่างน้อย 3 ตัวอักษร" rows="2" />
        <DialogFooter class="gap-2">
          <Button variant="outline" @click="revokeTarget = null">ปิด</Button>
          <Button variant="destructive" :disabled="revoking || revokeReason.trim().length < 3" @click="confirmRevoke">ยืนยันยกเลิก</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
