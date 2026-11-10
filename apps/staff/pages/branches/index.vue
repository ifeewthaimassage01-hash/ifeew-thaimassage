<script setup lang="ts">
// OWNER: รายการสาขา เพิ่ม/แก้ไข/ปิดใช้งาน
import { Clock, ImageOff, MapPin, Pencil, Plus, Trash2 } from '@lucide/vue'
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

// รูปสาขา (bucket branch-images: {company_id}/{branch_id}/{file})
const imageFile = ref<File | null>(null)
const currentImage = ref<string | null>(null)
const removeImage = ref(false)
const { url: imgUrl, upload: uploadImage } = useImageUpload()
const imageUrl = (path: string | null | undefined) => imgUrl('branch', path, 800)
const imagePreview = computed(() => (imageFile.value ? URL.createObjectURL(imageFile.value) : removeImage.value ? null : imageUrl(currentImage.value)))
function resetImage(path: string | null) {
  imageFile.value = null
  currentImage.value = path
  removeImage.value = false
}

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
  resetImage(null)
  dialog.value = true
}

function openEdit(b: Branch) {
  editingId.value = b.id
  Object.assign(branchForm.value, {
    code: b.code, name: b.name, address: b.address ?? '', phone: b.phone ?? '',
    map_url: b.map_url ?? '', sort_order: b.sort_order, is_active: b.is_active,
  })
  resetImage(b.image_path ?? null)
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
  const file = imageFile.value
  if (file && (!IMAGE_TYPES.includes(file.type) || file.size > IMAGE_MAX_BYTES)) {
    message.value = { type: 'error', text: 'รูปสาขาต้องเป็น JPG/PNG/WebP ขนาดไม่เกิน 5 MB' }
    return
  }
  saving.value = true
  try {
    let id = editingId.value
    if (id) {
      await must(supabase.from('branches').update(payload).eq('id', id))
    } else {
      const created = await must(supabase.from('branches').insert({ ...payload, company_id: company.value.company_id }).select('id').single())
      id = created?.id ?? null
    }
    if (!id) throw new Error('บันทึกสาขาไม่สำเร็จ')
    if (file) {
      // อัปโหลดขึ้น Cloudinary (ลายเซ็นจาก Edge Function cloudinary-sign) แล้วเก็บ "cloudinary:<public_id>"
      const path = await uploadImage('branch', id, file)
      await must(supabase.from('branches').update({ image_path: path }).eq('id', id))
    } else if (removeImage.value && currentImage.value) {
      await must(supabase.from('branches').update({ image_path: null }).eq('id', id))
    }
  } catch (e) {
    message.value = { type: 'error', text: errorText(e, 'บันทึกสาขาไม่สำเร็จ') }
    return
  } finally {
    saving.value = false
  }
  dialog.value = false
  message.value = { type: 'success', text: 'บันทึกสาขาแล้ว' }
  await Promise.all([load(), refreshAccess()])
}

// ลบสาขา: ได้เฉพาะสาขาที่ยังไม่มีประวัติการใช้งาน (DB ตรวจและแจ้งเหตุผลเอง) · ต้องยืนยันตัวตนซ้ำ (step-up)
const { confirm } = useDialog()
const { run } = useStepUp()
const deletingId = ref<string | null>(null)
async function removeBranch(b: Branch) {
  const ok = await confirm({
    title: `ลบสาขา "${b.name}"?`,
    description: 'ลบได้เฉพาะสาขาที่ยังไม่เคยมีการจอง ออเดอร์ หรือข้อมูลการเงิน เวลาทำการ บริการ ราคา และอุปกรณ์ของสาขาจะถูกลบด้วย ย้อนกลับไม่ได้ ถ้าสาขามีประวัติแล้วให้ใช้ "ปิดใช้งาน" แทน',
    confirmText: 'ลบสาขา',
    destructive: true,
  })
  if (!ok) return
  deletingId.value = b.id
  try {
    await run(() => must(supabase.rpc('delete_branch', { p_branch_id: b.id })))
    message.value = { type: 'success', text: `ลบสาขา ${b.name} แล้ว` }
    await Promise.all([load(), refreshAccess()])
  } catch (e) {
    if ((e as Error)?.message !== 'STEP_UP_CANCELLED') message.value = { type: 'error', text: errorText(e, 'ลบสาขาไม่สำเร็จ') }
  } finally {
    deletingId.value = null
  }
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
      <Card v-for="b in branches" :key="b.id" class="gap-0 overflow-hidden py-0">
        <div class="aspect-[16/6] overflow-hidden bg-secondary">
          <img v-if="b.image_path" :src="imageUrl(b.image_path) ?? undefined" :alt="`รูปสาขา ${b.name}`" class="size-full object-cover" loading="lazy">
          <div v-else class="grid size-full place-items-center gap-1 text-[13px] text-muted-foreground"><MapPin class="size-7 text-brand-accent" :stroke-width="1.5" aria-hidden="true" /></div>
        </div>
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
          <Button
            v-if="branches.length > 1"
            variant="ghost"
            size="sm"
            class="ml-auto text-danger-ink hover:bg-danger-soft hover:text-danger-ink"
            :disabled="deletingId === b.id"
            @click="removeBranch(b)"
          ><Trash2 /> {{ deletingId === b.id ? 'กำลังลบ…' : 'ลบ' }}</Button>
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
            <TextField v-model="branchForm.phone" numeric="digits" label="เบอร์โทร" type="tel" />
            <TextField v-model="branchForm.sort_order" label="ลำดับการแสดง" numeric="integer" />
          </div>
          <TextField v-model="branchForm.address" label="ที่อยู่" />
          <TextField v-model="branchForm.map_url" label="ลิงก์แผนที่" placeholder="https://..." />
          <div class="grid gap-2">
            <Label for="branch-image">รูปสาขา</Label>
            <div class="flex flex-wrap items-start gap-3">
              <div class="aspect-[16/9] w-40 shrink-0 overflow-hidden rounded-lg border border-border bg-secondary">
                <img v-if="imagePreview" :src="imagePreview" alt="ตัวอย่างรูปสาขา" class="size-full object-cover">
                <span v-else class="grid size-full place-items-center text-muted-soft"><ImageOff class="size-6" aria-hidden="true" /></span>
              </div>
              <div class="grid min-w-0 flex-1 gap-2">
                <input
                  id="branch-image"
                  type="file"
                  accept="image/jpeg,image/png,image/webp"
                  aria-describedby="branch-image-hint"
                  class="text-sm file:mr-3 file:rounded-md file:border-0 file:bg-secondary file:px-3 file:py-1.5 file:text-heading"
                  @change="(e) => { imageFile = (e.target as HTMLInputElement).files?.[0] ?? null; removeImage = false }"
                >
                <p id="branch-image-hint" class="m-0 text-sm text-muted-foreground">รูปหน้าร้านแนวนอน JPG, PNG หรือ WebP ไม่เกิน 5 MB · แสดงในหน้าแรกและหน้าสาขาของลูกค้า</p>
                <Button v-if="currentImage && !imageFile && !removeImage" type="button" variant="ghost" size="sm" class="w-fit text-danger-ink" @click="removeImage = true">ลบรูป</Button>
                <p v-if="removeImage" class="m-0 text-sm text-danger-ink">รูปจะถูกเอาออกเมื่อกดบันทึก</p>
              </div>
            </div>
          </div>
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
