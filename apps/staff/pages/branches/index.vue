<script setup lang="ts">
// OWNER: รายการสาขา เพิ่ม/แก้ไข/ปิดใช้งาน
import type { Tables } from '@ifeew/shared'

definePageMeta({ ownerOnly: true })

type Branch = Tables<'branches'>

const supabase = useSupabaseClient()
const { company, refresh: refreshAccess } = useAccess()

const branches = ref<Branch[]>([])
const loading = ref(false)
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)

const dialog = ref(false)
const saving = ref(false)
const editingId = ref<string | null>(null)
const branchForm = ref({ code: '', name: '', address: '', phone: '', map_url: '', sort_order: 0, is_active: true })

async function load() {
  if (!company.value) return
  loading.value = true
  const { data, error } = await supabase
    .from('branches')
    .select('*')
    .eq('company_id', company.value.company_id)
    .order('sort_order')
    .order('name')
  loading.value = false
  if (error) message.value = { type: 'error', text: 'โหลดสาขาไม่สำเร็จ' }
  branches.value = data ?? []
}

function openCreate() {
  editingId.value = null
  Object.assign(branchForm.value, { code: '', name: '', address: '', phone: '', map_url: '', sort_order: branches.value.length + 1, is_active: true })
  dialog.value = true
}

function openEdit(b: Branch) {
  editingId.value = b.id
  Object.assign(branchForm.value, {
    code: b.code, name: b.name, address: b.address ?? '', phone: b.phone ?? '',
    map_url: b.map_url ?? '', sort_order: b.sort_order, is_active: b.is_active,
  })
  dialog.value = true
}

async function save() {
  if (!company.value) return
  const code = branchForm.value.code.trim().toUpperCase()
  if (!/^[A-Z0-9]{2,10}$/.test(code) || !branchForm.value.name.trim()) {
    message.value = { type: 'error', text: 'รหัสสาขาใช้ A-Z 0-9 ยาว 2-10 ตัว และต้องมีชื่อสาขา' }
    return
  }
  const payload = {
    code,
    name: branchForm.value.name.trim(),
    address: branchForm.value.address.trim() || null,
    phone: branchForm.value.phone.trim() || null,
    map_url: branchForm.value.map_url.trim() || null,
    sort_order: Number(branchForm.value.sort_order) || 0,
    is_active: branchForm.value.is_active,
  }
  saving.value = true
  const { error } = editingId.value
    ? await supabase.from('branches').update(payload).eq('id', editingId.value)
    : await supabase.from('branches').insert({ ...payload, company_id: company.value.company_id })
  saving.value = false
  if (error) {
    message.value = { type: 'error', text: errorText(error, 'บันทึกสาขาไม่สำเร็จ') }
    return
  }
  dialog.value = false
  message.value = { type: 'success', text: 'บันทึกสาขาแล้ว' }
  await Promise.all([load(), refreshAccess()])
}

onMounted(load)
</script>

<template>
  <div>
    <div class="mb-6 flex items-center justify-between">
      <h1 class="m-0 text-2xl font-semibold text-cocoa">สาขา</h1>
      <v-btn color="primary" prepend-icon="mdi-plus" @click="openCreate">เพิ่มสาขา</v-btn>
    </div>

    <v-alert v-if="message" :type="message.type" variant="tonal" class="mb-6" closable :text="message.text" @click:close="message = null" />

    <v-progress-linear v-if="loading" indeterminate color="primary" class="mb-4" />

    <div class="grid gap-4 md:grid-cols-2">
      <v-card v-for="b in branches" :key="b.id" class="p-5">
        <div class="flex items-start justify-between gap-3">
          <div>
            <p class="m-0 text-lg font-medium">{{ b.code }} · {{ b.name }}</p>
            <p class="m-0 mt-1 text-sm text-light-brown">{{ b.address || '-' }}</p>
            <p class="m-0 text-sm text-light-brown">{{ b.phone || '' }}</p>
          </div>
          <v-chip :color="b.is_active ? 'success' : 'error'" variant="tonal" size="small">
            {{ b.is_active ? 'เปิดใช้งาน' : 'ปิดใช้งาน' }}
          </v-chip>
        </div>
        <div class="mt-4 flex gap-2">
          <v-btn variant="tonal" color="primary" prepend-icon="mdi-pencil-outline" @click="openEdit(b)">แก้ไข</v-btn>
          <v-btn variant="text" prepend-icon="mdi-clock-outline" :to="`/branches/${b.id}`">เวลาทำการและวันหยุด</v-btn>
        </div>
      </v-card>
    </div>

    <v-dialog v-model="dialog" max-width="560">
      <v-card class="p-6">
        <p class="m-0 mb-4 text-lg font-medium">{{ editingId ? 'แก้ไขสาขา' : 'เพิ่มสาขา' }}</p>
        <div class="grid gap-x-4 md:grid-cols-2">
          <v-text-field v-model="branchForm.code" label="รหัสสาขา (A-Z 0-9)" maxlength="10" hint="แก้ไม่ได้หลังสาขาออกเอกสารแล้ว" persistent-hint class="mb-2" />
          <v-text-field v-model="branchForm.name" label="ชื่อสาขา" />
          <v-text-field v-model="branchForm.phone" label="เบอร์โทร" type="tel" />
          <v-text-field v-model="branchForm.sort_order" label="ลำดับการแสดง" type="number" />
        </div>
        <v-text-field v-model="branchForm.address" label="ที่อยู่" />
        <v-text-field v-model="branchForm.map_url" label="ลิงก์แผนที่ (https://...)" />
        <v-switch v-model="branchForm.is_active" color="primary" label="เปิดใช้งาน" hide-details />
        <div class="mt-4 flex justify-end gap-2">
          <v-btn variant="text" @click="dialog = false">ยกเลิก</v-btn>
          <v-btn color="primary" :loading="saving" @click="save">บันทึก</v-btn>
        </div>
      </v-card>
    </v-dialog>
  </div>
</template>
