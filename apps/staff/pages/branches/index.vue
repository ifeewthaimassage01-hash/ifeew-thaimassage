<script setup lang="ts">
// OWNER: รายการสาขา เพิ่ม/แก้ไข/ปิดใช้งาน
import { Clock, Pencil, Plus } from '@lucide/vue'
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
    <PageHeader title="สาขา" description="เพิ่มและแก้ไขข้อมูลสาขา ตั้งเวลาทำการและวันหยุด">
      <template #actions><Button @click="openCreate"><Plus /> เพิ่มสาขา</Button></template>
    </PageHeader>

    <MessageAlert :message="message" class="mb-6" @close="message = null" />
    <LoadingBar v-if="loading" class="mb-4" />
    <EmptyState v-if="!loading && !branches.length" title="ยังไม่มีสาขา" description="เพิ่มสาขาแรกเพื่อเริ่มรับคิวและการจอง">
      <Button @click="openCreate"><Plus /> เพิ่มสาขา</Button>
    </EmptyState>

    <div class="grid items-start gap-4 md:grid-cols-2">
      <Card v-for="b in branches" :key="b.id" class="gap-0 py-0">
        <div class="flex items-start justify-between gap-3 p-5">
          <div class="min-w-0">
            <p class="m-0 text-sm text-muted-foreground"><span class="num">{{ b.code }}</span></p>
            <h2 class="m-0 text-[17px] font-semibold">{{ b.name }}</h2>
            <p class="m-0 mt-1 text-[15px] text-muted-foreground">{{ b.address || 'ยังไม่ระบุที่อยู่' }}</p>
            <p v-if="b.phone" class="num m-0 text-[15px] text-muted-foreground">{{ b.phone }}</p>
          </div>
          <Badge :variant="b.is_active ? 'success' : 'neutral'" dot>{{ b.is_active ? 'เปิดใช้งาน' : 'ปิดใช้งาน' }}</Badge>
        </div>
        <div class="flex flex-wrap gap-2 border-t border-border px-5 py-3">
          <Button variant="outline" size="sm" @click="openEdit(b)"><Pencil /> แก้ไข</Button>
          <Button as-child variant="ghost" size="sm"><NuxtLink :to="`/branches/${b.id}`"><Clock /> เวลาทำการและวันหยุด</NuxtLink></Button>
        </div>
      </Card>
    </div>

    <Dialog v-model:open="dialog">
      <DialogContent class="sm:max-w-xl">
        <DialogHeader>
          <DialogTitle>{{ editingId ? 'แก้ไขสาขา' : 'เพิ่มสาขา' }}</DialogTitle>
          <DialogDescription>ข้อมูลนี้แสดงในหน้าจองของลูกค้า</DialogDescription>
        </DialogHeader>
        <form class="grid gap-4" @submit.prevent="save">
          <div class="grid gap-4 sm:grid-cols-2">
            <TextField v-model="branchForm.code" label="รหัสสาขา (A-Z 0-9)" maxlength="10" hint="แก้ไม่ได้หลังสาขาออกเอกสารแล้ว" />
            <TextField v-model="branchForm.name" label="ชื่อสาขา" />
            <TextField v-model="branchForm.phone" label="เบอร์โทร" type="tel" />
            <TextField v-model="branchForm.sort_order" label="ลำดับการแสดง" type="number" />
          </div>
          <TextField v-model="branchForm.address" label="ที่อยู่" />
          <TextField v-model="branchForm.map_url" label="ลิงก์แผนที่" placeholder="https://..." />
          <SwitchField v-model="branchForm.is_active" label="เปิดใช้งาน" hint="ปิดแล้วลูกค้าจะไม่เห็นสาขานี้ในหน้าจอง" />
          <DialogFooter class="gap-2">
            <Button type="button" variant="outline" @click="dialog = false">ยกเลิก</Button>
            <Button type="submit" :disabled="saving">{{ saving ? 'กำลังบันทึก…' : 'บันทึก' }}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  </div>
</template>
