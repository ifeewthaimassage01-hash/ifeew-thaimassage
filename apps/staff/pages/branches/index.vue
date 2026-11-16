<script setup lang="ts">
// OWNER: รายการสาขา เพิ่ม/แก้ไข/ปิดใช้งาน · แต่ละสาขาบอกว่าพร้อมรับจองออนไลน์หรือยัง (เวลาทำการ บัญชีมัดจำ แผนที่)
import { Check, ChevronRight, CircleAlert, Clock, ImageOff, LocateFixed, MapPin, Pencil, Plus, QrCode, Trash2 } from '@lucide/vue'
import { bangkokToday, type Tables } from '@ifeew/shared'

definePageMeta({ ownerOnly: true })

type Branch = Tables<'branches'>
type Hours = Pick<Tables<'branch_opening_hours'>, 'branch_id' | 'iso_dow' | 'is_closed' | 'opens_at' | 'closes_at'>
type Holiday = Pick<Tables<'branch_holidays'>, 'branch_id' | 'name' | 'is_closed' | 'opens_at' | 'closes_at'>
type Account = Pick<Tables<'branch_payment_accounts'>, 'branch_id' | 'promptpay_id' | 'bank_name' | 'is_active'>

const supabase = useSupabaseClient()
const { company, refresh: refreshAccess } = useAccess()

const branches = ref<Branch[]>([])
const hours = ref<Hours[]>([])
const holidaysToday = ref<Holiday[]>([])
const accounts = ref<Account[]>([])
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

// ---------------------------------------------------------------------------
// ความพร้อมรับจองออนไลน์ของแต่ละสาขา
// ---------------------------------------------------------------------------
const today = bangkokToday()
const todayDow = ((new Date(`${today}T12:00:00+07:00`).getUTCDay() + 6) % 7) + 1 // ISO: จันทร์=1 … อาทิตย์=7
const hm = (t: string | null) => (t ? t.slice(0, 5) : '')

type Check = { ok: boolean; text: string }
function readiness(b: Branch) {
  const week = hours.value.filter((r) => r.branch_id === b.id)
  const hol = holidaysToday.value.find((r) => r.branch_id === b.id)
  const day = week.find((r) => r.iso_dow === todayDow)
  const hoursSet = week.some((r) => !r.is_closed)
  const todayText = hol
    ? (hol.is_closed ? `วันนี้หยุด (${hol.name})` : `วันนี้ ${hm(hol.opens_at)}–${hm(hol.closes_at)} น. (${hol.name})`)
    : day && !day.is_closed ? `วันนี้ ${hm(day.opens_at)}–${hm(day.closes_at)} น.` : 'วันนี้ปิด'
  const acc = accounts.value.find((r) => r.branch_id === b.id)
  const accOk = !!acc?.is_active
  const checks: Record<'hours' | 'deposit' | 'map', Check> = {
    hours: { ok: hoursSet, text: hoursSet ? todayText : 'ยังไม่ตั้งเวลาทำการ' },
    deposit: {
      ok: accOk,
      text: acc ? `PromptPay ${acc.promptpay_id}${acc.bank_name ? ` · ${acc.bank_name}` : ''}${acc.is_active ? '' : ' (ปิดอยู่)'}` : 'ยังไม่มีบัญชีรับมัดจำ',
    },
    map: { ok: !!b.map_url, text: b.map_url ? 'มีลิงก์ Google Maps' : 'ยังไม่มีลิงก์แผนที่' },
  }
  const missing = Object.values(checks).filter((c) => !c.ok).length
  const status = !b.is_active
    ? { variant: 'neutral' as const, text: 'ปิดใช้งาน' }
    : checks.hours.ok && checks.deposit.ok
      ? { variant: 'success' as const, text: 'รับจองออนไลน์ได้' }
      : { variant: 'pending' as const, text: 'ยังตั้งค่าไม่ครบ' }
  return { checks, missing, status }
}
const rowsFor = () => [
  { key: 'hours' as const, label: 'เวลาทำการ', icon: Clock },
  { key: 'deposit' as const, label: 'บัญชีรับมัดจำ', icon: QrCode },
  { key: 'map' as const, label: 'แผนที่', icon: MapPin },
]

// popup ตั้งค่าเฉพาะส่วนของสาขา (เวลาทำการ / บัญชีมัดจำ / พื้นที่เข้าระบบ) · แผนที่ใช้ฟอร์มแก้ไขสาขา
type Panel = 'hours' | 'deposit' | 'lock'
const panel = ref<{ kind: Panel; branch: Branch } | null>(null)
const panelOpen = computed({ get: () => !!panel.value, set: (v) => { if (!v) panel.value = null } })
const PANEL_TEXT: Record<Panel, { title: string; description: string; width: string }> = {
  hours: { title: 'เวลาทำการและวันหยุด', description: 'ใช้คำนวณเวลาว่างในหน้าจองของลูกค้า', width: 'sm:max-w-3xl' },
  deposit: { title: 'บัญชีรับมัดจำ', description: 'ลูกค้าจะเห็น QR PromptPay ของบัญชีนี้ · SlipOK Branch ID ต้องผูกกับบัญชีเดียวกันในระบบ SlipOK', width: 'sm:max-w-xl' },
  lock: { title: 'เข้าระบบได้เฉพาะในร้าน', description: 'พนักงานต้องอยู่ในรัศมีจากร้าน (ตรวจด้วย GPS ของเครื่อง) · เจ้าของร้านและเครื่องที่ผูกกับสาขาเข้าได้ทุกที่', width: 'sm:max-w-2xl' },
}
function openRow(key: 'hours' | 'deposit' | 'map', b: Branch) {
  if (key === 'map') openEdit(b)
  else panel.value = { kind: key, branch: b }
}
// บันทึกบัญชีแล้วปิด popup · เวลาทำการ/วันหยุดเปิดค้างไว้ (มักแก้หลายอย่างต่อกัน) แต่รีเฟรชสถานะการ์ด
function onPanelSaved() {
  if (panel.value?.kind === 'deposit') panel.value = null
  load()
}
const ready = computed(() => Object.fromEntries(branches.value.map((b) => [b.id, readiness(b)])))
const openCount = computed(() => branches.value.filter((b) => ready.value[b.id]?.status.variant === 'success').length)

async function load() {
  if (!company.value) return
  loading.value = true
  const cid = company.value.company_id
  const [b, h, hol, pa] = await Promise.all([
    supabase.from('branches').select('*').eq('company_id', cid).order('sort_order').order('name'),
    supabase.from('branch_opening_hours').select('branch_id, iso_dow, is_closed, opens_at, closes_at').eq('company_id', cid),
    supabase.from('branch_holidays').select('branch_id, name, is_closed, opens_at, closes_at').eq('company_id', cid).eq('holiday_date', today).eq('is_active', true),
    supabase.from('branch_payment_accounts').select('branch_id, promptpay_id, bank_name, is_active').eq('company_id', cid),
  ])
  loading.value = false
  if (b.error) message.value = { type: 'error', text: 'โหลดสาขาไม่สำเร็จ' }
  branches.value = b.data ?? []
  hours.value = h.data ?? []
  holidaysToday.value = hol.data ?? []
  accounts.value = pa.data ?? []
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
  <div class="mx-auto max-w-5xl">
    <PageHeader
      title="สาขา"
      :description="branches.length ? `${branches.length} สาขา · รับจองออนไลน์ได้ ${openCount} สาขา` : 'เพิ่มสาขา ตั้งเวลาทำการ และบัญชีรับมัดจำ'"
    >
      <template #actions><Button @click="openCreate"><Plus /> เพิ่มสาขา</Button></template>
    </PageHeader>

    <MessageAlert :message="message" class="mb-6" @close="message = null" />
    <LoadingBar v-if="loading" class="mb-4" />
    <EmptyState v-if="!loading && !branches.length" title="ยังไม่มีสาขา" description="เพิ่มสาขาแรกเพื่อเริ่มรับคิวและการจอง">
      <Button @click="openCreate"><Plus /> เพิ่มสาขา</Button>
    </EmptyState>

    <div class="grid items-start gap-5 lg:grid-cols-2">
      <article
        v-for="b in branches"
        :key="b.id"
        class="overflow-hidden rounded-xl border border-border bg-card shadow-soft"
        :aria-labelledby="`branch-${b.id}`"
      >
        <!-- หัวการ์ด: รูปหน้าร้านเล็กด้านซ้าย ชื่อ/ที่อยู่ด้านขวา -->
        <div class="flex gap-4 p-4 sm:p-5">
          <div class="size-20 shrink-0 overflow-hidden rounded-xl bg-secondary sm:size-24">
            <img v-if="b.image_path" :src="imageUrl(b.image_path) ?? undefined" alt="" class="size-full object-cover" :class="b.is_active ? '' : 'grayscale'" loading="lazy" decoding="async">
            <span v-else class="grid size-full place-items-center"><MapPin class="size-7 text-brand-accent" :stroke-width="1.5" aria-hidden="true" /></span>
          </div>
          <div class="grid min-w-0 flex-1 content-start gap-1">
            <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
              <h2 :id="`branch-${b.id}`" class="m-0 text-title font-semibold text-balance text-heading">{{ b.name }}</h2>
              <span class="num rounded-md bg-muted px-1.5 text-[13px] text-muted-foreground">{{ b.code }}</span>
            </div>
            <Badge :variant="ready[b.id]?.status.variant" dot>{{ ready[b.id]?.status.text }}</Badge>
            <p class="m-0 mt-1 text-sm text-muted-foreground">{{ b.address || 'ยังไม่ระบุที่อยู่' }}</p>
            <a v-if="b.phone" :href="`tel:${b.phone}`" class="num w-fit text-sm text-muted-foreground underline-offset-4 hover:text-heading hover:underline">{{ b.phone }}</a>
          </div>
        </div>

        <!-- ความพร้อม: แตะแต่ละแถวเพื่อไปแก้ตรงจุด -->
        <ul class="m-0 grid list-none divide-y divide-border border-t border-border p-0" :aria-label="`ความพร้อมของ${b.name}`">
          <li v-for="row in rowsFor()" :key="row.key">
            <button
              type="button"
              aria-haspopup="dialog"
              class="flex min-h-14 w-full items-center gap-3 px-4 py-2.5 text-left transition-colors hover:bg-muted focus-visible:bg-muted focus-visible:outline-none sm:px-5"
              @click="openRow(row.key, b)"
            >
              <span class="grid size-9 shrink-0 place-items-center rounded-full bg-muted"><component :is="row.icon" class="size-[18px] text-brand-accent" aria-hidden="true" /></span>
              <span class="grid min-w-0 flex-1">
                <span class="text-[13px] font-medium text-muted-foreground">{{ row.label }}</span>
                <span class="num truncate text-[15px]" :class="ready[b.id]?.checks[row.key].ok ? 'text-heading' : 'font-medium text-pending-ink'">{{ ready[b.id]?.checks[row.key].text }}</span>
              </span>
              <Check v-if="ready[b.id]?.checks[row.key].ok" class="size-[18px] shrink-0 text-success-ink" aria-label="ตั้งแล้ว" />
              <CircleAlert v-else class="size-[18px] shrink-0 text-pending-ink" aria-label="ยังไม่ได้ตั้ง" />
              <ChevronRight class="size-4 shrink-0 text-muted-soft" aria-hidden="true" />
            </button>
          </li>
        </ul>

        <div class="flex flex-wrap items-center gap-2 border-t border-border px-4 py-3 sm:px-5">
          <Button variant="outline" size="sm" @click="openEdit(b)"><Pencil /> แก้ไขข้อมูลสาขา</Button>
          <Button variant="ghost" size="sm" aria-haspopup="dialog" @click="panel = { kind: 'lock', branch: b }"><LocateFixed /> พื้นที่เข้าระบบ</Button>
          <Button
            v-if="branches.length > 1"
            variant="ghost"
            size="sm"
            class="ml-auto text-danger-ink hover:bg-danger-soft hover:text-danger-ink"
            :aria-label="`ลบสาขา ${b.name}`"
            :disabled="deletingId === b.id"
            @click="removeBranch(b)"
          ><Trash2 /><span class="hidden sm:inline">{{ deletingId === b.id ? 'กำลังลบ…' : 'ลบ' }}</span></Button>
        </div>
      </article>
    </div>

    <Dialog v-model:open="panelOpen">
      <DialogContent v-if="panel" class="gap-5 p-4 sm:p-6" :class="PANEL_TEXT[panel.kind].width">
        <DialogHeader>
          <DialogTitle class="pr-6">{{ PANEL_TEXT[panel.kind].title }} · {{ panel.branch.name }}</DialogTitle>
          <DialogDescription>{{ PANEL_TEXT[panel.kind].description }}</DialogDescription>
        </DialogHeader>
        <BranchHoursForm v-if="panel.kind === 'hours'" :branch-id="panel.branch.id" :company-id="panel.branch.company_id" @saved="onPanelSaved" />
        <BranchDepositForm v-else-if="panel.kind === 'deposit'" :branch-id="panel.branch.id" :company-id="panel.branch.company_id" @saved="onPanelSaved" />
        <BranchLoginLock v-else plain :branch-id="panel.branch.id" :company-id="panel.branch.company_id" @saved="onPanelSaved" />
      </DialogContent>
    </Dialog>

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
          <TextField v-model="branchForm.map_url" label="ลิงก์ Google Maps" placeholder="https://maps.app.goo.gl/..." hint="เปิด Google Maps ค้นหาร้าน กด “แชร์” แล้วคัดลอกลิงก์มาวาง · ลูกค้ากด “แผนที่” แล้วนำทางมาได้เลย" inputmode="url" />
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
                  class="w-full min-w-0 text-sm file:mr-3 file:rounded-md file:border-0 file:bg-secondary file:px-3 file:py-1.5 file:text-heading"
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
