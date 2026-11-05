<script setup lang="ts">
// OWNER: บริการ + ช่วงเวลา + ราคา + ค่าแรงหมอนวด (ต่อสาขา) และหมวดหมู่
// แก้ราคา/ค่าแรงเดิม = OWNER เท่านั้น (เหตุผลไม่บังคับ — migration 032)
import { History, Pencil, Plus, Trash2 } from '@lucide/vue'
import {
  bangkokToday,
  formatBaht,
  formatDuration,
  type BranchServicePricing,
  type PricingOption,
  type Tables,
} from '@ifeew/shared'


const { prompt } = useDialog()
definePageMeta({ ownerOnly: true })

type Category = Tables<'service_categories'>
type Service = Tables<'services'>

const supabase = useSupabaseClient()
const { company, branches, activeBranch } = useAccess()
const { run } = useStepUp()

const tab = ref<'services' | 'categories'>('services')
const categories = ref<Category[]>([])
const services = ref<Service[]>([])
const pricing = ref<BranchServicePricing[]>([])
const loading = ref(false)
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)
const saving = ref(false)
const ok = (text: string) => (message.value = { type: 'success', text })
const fail = (e: unknown, fallback?: string) => (message.value = { type: 'error', text: errorText(e, fallback) })

const categoryName = (id: string) => categories.value.find((c) => c.id === id)?.name ?? '-'
const pricingOf = (serviceId: string) => pricing.value.find((p) => p.service_id === serviceId) ?? null
const activeOptions = (serviceId: string) => (pricingOf(serviceId)?.options ?? []).filter((o) => o.is_active && o.current)
const fmt = (v: string) => new Date(v).toLocaleString('th-TH', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Bangkok' })

async function load() {
  if (!company.value) return
  loading.value = true
  const cid = company.value.company_id
  const [c, s] = await Promise.all([
    supabase.from('service_categories').select('*').eq('company_id', cid).order('sort_order').order('name'),
    supabase.from('services').select('*').eq('company_id', cid).order('sort_order').order('name'),
  ])
  categories.value = c.data ?? []
  services.value = s.data ?? []
  await loadPricing()
  loading.value = false
}

async function loadPricing() {
  if (!activeBranch.value) return
  try {
    pricing.value = (await must(
      supabase.rpc('owner_service_pricing', { p_branch_id: activeBranch.value.branch_id }),
    )) as unknown as BranchServicePricing[]
  } catch (e) {
    fail(e, 'โหลดราคาไม่สำเร็จ')
  }
}

watch(() => activeBranch.value?.branch_id, loadPricing)
onMounted(load)

// ---------------------------------------------------------------------------
// ฟอร์มบริการ (ตามรูปแบบ: ชื่อ / ชื่ออังกฤษ / ช่วงเวลา + ราคา + ค่าแรง)
// ---------------------------------------------------------------------------
interface OptionRow { duration_minutes: number; price: number | string; therapist_fee: number | string }

const dialog = ref(false)
const editing = ref<Service | null>(null)
const form = ref({
  name: '', name_en: '', category_id: '', description: '', sort_order: 0, is_active: true,
  options: [] as OptionRow[],
  applyAll: false, immediate: true, date: '', time: '00:00', reason: '',
})
const newMinutes = ref<number | string>('')
const image = ref<File | File[] | null>(null)

const hasExistingPrice = computed(() => !!editing.value && activeOptions(editing.value.id).length > 0)
const scheduledOptions = computed<PricingOption[]>(() =>
  editing.value ? (pricingOf(editing.value.id)?.options ?? []).filter((o) => o.scheduled) : [],
)

function openService(s?: Service) {
  editing.value = s ?? null
  const opts = s
    ? activeOptions(s.id).map((o) => ({
        duration_minutes: o.duration_minutes, price: Number(o.current!.price), therapist_fee: Number(o.current!.therapist_fee),
      }))
    : [{ duration_minutes: 60, price: '', therapist_fee: '' }]
  form.value = {
    name: s?.name ?? '',
    name_en: s?.name_en ?? '',
    category_id: s?.category_id ?? categories.value.find((c) => c.is_active)?.id ?? '',
    description: s?.description ?? '',
    sort_order: s?.sort_order ?? services.value.length + 1,
    is_active: s?.is_active ?? true,
    options: opts,
    applyAll: false,
    immediate: true,
    date: bangkokToday(),
    time: '00:00',
    reason: '',
  }
  newMinutes.value = ''
  image.value = null
  dialog.value = true
}

function addDuration() {
  const m = Number(newMinutes.value)
  if (!Number.isInteger(m) || m < 5 || m > 600) {
    fail(null, 'ระบุนาทีเป็นจำนวนเต็ม 5-600')
    return
  }
  if (form.value.options.some((o) => o.duration_minutes === m)) {
    fail(null, `มีช่วงเวลา ${formatDuration(m)} แล้ว`)
    return
  }
  form.value.options.push({ duration_minutes: m, price: '', therapist_fee: '' })
  form.value.options.sort((a, b) => a.duration_minutes - b.duration_minutes)
  newMinutes.value = ''
}

function validate(): string | null {
  const f = form.value
  if (!f.name.trim()) return 'กรุณากรอกชื่อรายการ'
  if (!f.category_id) return 'กรุณาเลือกหมวดหมู่'
  if (!f.options.length) return 'กรุณาเพิ่มช่วงเวลาอย่างน้อย 1 ช่วง'
  for (const o of f.options) {
    const price = Number(o.price)
    const fee = Number(o.therapist_fee || 0)
    if (o.price === '' || !Number.isFinite(price) || price < 0) return `กรุณากรอกราคาช่วง ${formatDuration(o.duration_minutes)}`
    if (!Number.isFinite(fee) || fee < 0) return `ค่าแรงช่วง ${formatDuration(o.duration_minutes)} ไม่ถูกต้อง`
    if (fee > price) return `ค่าแรงช่วง ${formatDuration(o.duration_minutes)} มากกว่าราคา`
  }
  return null
}

async function save() {
  const err = validate()
  if (err) {
    fail(null, err)
    return
  }
  if (!company.value || !activeBranch.value) return
  const f = form.value
  saving.value = true
  try {
    // 1) ข้อมูลบริการกลาง
    const base = {
      name: f.name.trim(),
      name_en: f.name_en.trim() || null,
      category_id: f.category_id,
      description: f.description.trim() || null,
      sort_order: Number(f.sort_order) || 0,
    }
    let id = editing.value?.id
    if (id) {
      await must(supabase.from('services').update({ ...base, is_active: f.is_active }).eq('id', id))
    } else {
      const created = await must(supabase.from('services').insert({ ...base, company_id: company.value.company_id }).select('id').single())
      id = created?.id
    }
    if (!id) throw new Error('บันทึกบริการไม่สำเร็จ')

    const file = Array.isArray(image.value) ? image.value[0] : image.value
    if (file) {
      if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type) || file.size > 2 * 1024 * 1024) {
        throw new Error('รูปต้องเป็น JPG/PNG/WebP ขนาดไม่เกิน 2 MB')
      }
      const ext = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg'
      const path = `${company.value.company_id}/${id}/${Date.now()}.${ext}`
      await must(supabase.storage.from('service-images').upload(path, file, { contentType: file.type }))
      await must(supabase.from('services').update({ image_path: path }).eq('id', id))
    }

    // 2) ช่วงเวลา + ราคา + ค่าแรง (บริการที่ปิดใช้งานไม่ต้องตั้งราคา)
    if (f.is_active) {
      const serviceId = id
      const res = (await run(() =>
        must(
          supabase.rpc('save_branch_service_pricing', {
            p_branch_ids: f.applyAll ? branches.value.map((b) => b.branch_id) : [activeBranch.value!.branch_id],
            p_service_id: serviceId,
            p_options: f.options.map((o) => ({
              duration_minutes: o.duration_minutes, price: Number(o.price), therapist_fee: Number(o.therapist_fee || 0),
            })),
            p_effective_from: f.immediate ? null : `${f.date}T${f.time}:00+07:00`,
            p_reason: f.reason.trim() || null,
          }),
        ),
      )) as { changed: number }
      ok(res.changed ? `บันทึกแล้ว (เปลี่ยน ${res.changed} รายการ)` : 'บันทึกข้อมูลบริการแล้ว (ราคาไม่เปลี่ยน)')
    } else {
      ok('บันทึกข้อมูลบริการแล้ว')
    }
    dialog.value = false
    await load()
  } catch (e) {
    fail(e, 'บันทึกไม่สำเร็จ')
  } finally {
    saving.value = false
  }
}

async function cancelScheduled(o: PricingOption) {
  if (!o.scheduled) return
  const reason = await prompt({ title: 'ยกเลิกราคาที่ตั้งล่วงหน้า', label: 'เหตุผล', minLength: 3, confirmText: 'ยกเลิกราคา', cancelText: 'ปิด', destructive: true })
  if (reason === null) return
  try {
    await run(() => must(supabase.rpc('cancel_scheduled_price', { p_price_history_id: o.scheduled!.id, p_reason: reason.trim() })))
    ok('ยกเลิกราคาล่วงหน้าแล้ว')
    await loadPricing()
  } catch (e) {
    fail(e, 'ยกเลิกไม่สำเร็จ')
  }
}

async function toggleAtBranch(s: Service) {
  const bs = pricingOf(s.id)
  if (!bs) return
  try {
    await must(supabase.from('branch_services').update({ is_active: !bs.is_active }).eq('id', bs.branch_service_id))
    await loadPricing()
  } catch (e) {
    fail(e)
  }
}

// ประวัติราคา
const historyService = ref<Service | null>(null)
const historyOptions = computed(() => (historyService.value ? pricingOf(historyService.value.id)?.options ?? [] : []))

// ---------------------------------------------------------------------------
// หมวดหมู่
// ---------------------------------------------------------------------------
const catDialog = ref(false)
const catEditing = ref<Category | null>(null)
const catForm = ref({ name: '', description: '', sort_order: 0 })

function openCategory(c?: Category) {
  catEditing.value = c ?? null
  catForm.value = { name: c?.name ?? '', description: c?.description ?? '', sort_order: c?.sort_order ?? categories.value.length + 1 }
  catDialog.value = true
}

async function saveCategory() {
  if (!company.value || !catForm.value.name.trim()) return
  const payload = {
    name: catForm.value.name.trim(),
    description: catForm.value.description.trim() || null,
    sort_order: Number(catForm.value.sort_order) || 0,
  }
  saving.value = true
  try {
    if (catEditing.value) await must(supabase.from('service_categories').update(payload).eq('id', catEditing.value.id))
    else await must(supabase.from('service_categories').insert({ ...payload, company_id: company.value.company_id }))
    catDialog.value = false
    await load()
  } catch (e) {
    fail(e, 'บันทึกหมวดหมู่ไม่สำเร็จ (ชื่อซ้ำหรือไม่)')
  } finally {
    saving.value = false
  }
}

async function toggleCategory(c: Category) {
  try {
    await must(supabase.from('service_categories').update({ is_active: !c.is_active }).eq('id', c.id))
    await load()
  } catch (e) {
    fail(e)
  }
}
</script>

<template>
  <div>
    <PageHeader title="บริการและราคา" :description="`ราคาและค่าแรงแยกตามสาขา · กำลังดู ${activeBranch?.name ?? ''}`">
      <template #actions>
        <Button v-if="tab === 'services'" @click="openService()"><Plus /> เพิ่มบริการ</Button>
        <Button v-else @click="openCategory()"><Plus /> เพิ่มหมวดหมู่</Button>
      </template>
    </PageHeader>

    <SegmentedControl v-model="tab" :items="[{ value: 'services', label: 'บริการ' }, { value: 'categories', label: 'หมวดหมู่' }]" label="มุมมอง" class="mb-4" />
    <MessageAlert :message="message" class="mb-4" @close="message = null" />

    <!-- บริการ -->
    <template v-if="tab === 'services'">
      <LoadingBar v-if="loading" class="mb-3" />
      <EmptyState v-if="!loading && !services.length" title="ยังไม่มีบริการ" description="เพิ่มบริการพร้อมช่วงเวลาและราคา แล้วเปิดขายที่สาขา">
        <Button @click="openService()"><Plus /> เพิ่มบริการ</Button>
      </EmptyState>
      <div class="grid items-start gap-4 lg:grid-cols-2">
        <Card v-for="s in services" :key="s.id" class="gap-0 py-0" :class="s.is_active ? '' : 'opacity-70'">
          <div class="flex items-start justify-between gap-3 p-5">
            <div class="min-w-0">
              <p class="m-0 text-sm text-muted-foreground">{{ categoryName(s.category_id) }}</p>
              <h2 class="m-0 text-[17px] font-semibold">{{ s.name }}</h2>
              <p v-if="s.name_en" class="m-0 text-sm text-muted-foreground">{{ s.name_en }}</p>
            </div>
            <Badge v-if="!s.is_active" variant="neutral" dot>ปิดใช้งาน</Badge>
            <Badge v-else-if="!pricingOf(s.id)" variant="neutral">ยังไม่ขายที่สาขานี้</Badge>
            <Badge v-else-if="!pricingOf(s.id)!.is_active" variant="pending" dot>หยุดขายที่สาขานี้</Badge>
            <Badge v-else variant="success" dot>ขายอยู่</Badge>
          </div>

          <div v-if="activeOptions(s.id).length" class="border-t border-border">
            <div class="grid grid-cols-3 px-5 pt-3 pb-1 text-[13px] font-medium text-muted-foreground">
              <span>ระยะเวลา</span><span class="text-right">ราคา</span><span class="text-right">ค่าแรง</span>
            </div>
            <div v-for="o in activeOptions(s.id)" :key="o.option_id" class="grid grid-cols-3 px-5 py-1.5 text-[15px]">
              <span class="text-heading">{{ formatDuration(o.duration_minutes) }}</span>
              <span class="num text-right font-medium text-heading">{{ formatBaht(Number(o.current!.price)) }}</span>
              <span class="num text-right text-muted-foreground">{{ formatBaht(Number(o.current!.therapist_fee)) }}</span>
              <span v-if="o.scheduled" class="col-span-3 text-sm text-pending-ink">
                ราคาใหม่ {{ fmt(o.scheduled.effective_from) }}: <span class="num">{{ formatBaht(Number(o.scheduled.price)) }}</span> / ค่าแรง <span class="num">{{ formatBaht(Number(o.scheduled.therapist_fee)) }}</span>
              </span>
            </div>
            <div class="h-2" />
          </div>

          <div class="flex flex-wrap gap-2 border-t border-border px-5 py-3">
            <Button variant="outline" size="sm" @click="openService(s)"><Pencil /> แก้ไข</Button>
            <Button v-if="pricingOf(s.id)" variant="ghost" size="sm" @click="toggleAtBranch(s)">
              {{ pricingOf(s.id)!.is_active ? 'หยุดขายที่สาขานี้' : 'เปิดขายที่สาขานี้' }}
            </Button>
            <Button v-if="pricingOf(s.id)" variant="ghost" size="sm" class="ml-auto" @click="historyService = s"><History /> ประวัติราคา</Button>
          </div>
        </Card>
      </div>
    </template>

    <!-- หมวดหมู่ -->
    <SectionCard v-else flush>
      <div class="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow class="hover:bg-transparent">
              <TableHead class="w-20">ลำดับ</TableHead><TableHead>ชื่อ</TableHead><TableHead>รายละเอียด</TableHead><TableHead>สถานะ</TableHead>
              <TableHead class="text-right"><span class="sr-only">การทำงาน</span></TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow v-for="c in categories" :key="c.id" :class="c.is_active ? '' : 'text-muted-foreground'">
              <TableCell class="num">{{ c.sort_order }}</TableCell>
              <TableCell class="font-medium text-heading">{{ c.name }}</TableCell>
              <TableCell class="max-w-80 truncate">{{ c.description || '—' }}</TableCell>
              <TableCell><Badge :variant="c.is_active ? 'success' : 'neutral'" dot>{{ c.is_active ? 'เปิดใช้งาน' : 'ปิดใช้งาน' }}</Badge></TableCell>
              <TableCell class="text-right">
                <Button size="sm" variant="ghost" @click="openCategory(c)">แก้ไข</Button>
                <Button size="sm" variant="ghost" :class="c.is_active ? 'text-danger-ink' : ''" @click="toggleCategory(c)">{{ c.is_active ? 'ปิด' : 'เปิด' }}</Button>
              </TableCell>
            </TableRow>
            <TableRow v-if="!categories.length" class="hover:bg-transparent">
              <TableCell colspan="5" class="py-8 text-center text-muted-foreground">ยังไม่มีหมวดหมู่</TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </div>
    </SectionCard>

    <!-- ฟอร์มบริการ -->
    <Dialog v-model:open="dialog">
      <DialogContent class="max-h-[90dvh] grid-rows-[auto_minmax(0,1fr)_auto] sm:max-w-xl">
        <DialogHeader>
          <DialogTitle>{{ editing ? 'แก้ไขบริการ' : 'เพิ่มบริการ' }}</DialogTitle>
          <DialogDescription>ราคาและช่วงเวลาตั้งที่ {{ activeBranch?.name }}</DialogDescription>
        </DialogHeader>
        <div class="-mx-6 grid gap-4 overflow-y-auto px-6">
          <TextField v-model="form.name" label="ชื่อรายการ" maxlength="150" />
          <div class="grid gap-4 sm:grid-cols-2">
            <TextField v-model="form.name_en" label="ชื่อภาษาอังกฤษ (ไม่บังคับ)" maxlength="150" />
            <SelectField v-model="form.category_id" :items="categories.filter((c) => c.is_active)" item-title="name" item-value="id" label="หมวดหมู่" placeholder="เลือกหมวดหมู่" />
          </div>

          <fieldset class="m-0 grid gap-3 rounded-lg border border-border p-4">
            <legend class="px-1 text-sm font-medium text-heading">ช่วงเวลาที่ขาย ราคา และค่าแรง</legend>
            <div class="flex items-end gap-2">
              <TextField v-model="newMinutes" label="เพิ่มช่วงเวลา (นาที)" hint="เช่น 3 ชม. = 180" type="number" min="5" max="600" class="flex-1" @keydown.enter.prevent="addDuration" />
              <Button type="button" variant="outline" class="mb-6" @click="addDuration"><Plus /> เพิ่ม</Button>
            </div>
            <div v-for="(o, i) in form.options" :key="o.duration_minutes" class="grid grid-cols-[96px_minmax(0,1fr)_minmax(0,1fr)_auto] items-end gap-2 rounded-lg bg-background/70 p-3">
              <span class="pb-2.5 text-[15px] font-medium text-heading">{{ formatDuration(o.duration_minutes) }}</span>
              <TextField v-model="o.price" label="ราคา" type="number" min="0" suffix="฿" class="num" />
              <TextField v-model="o.therapist_fee" label="ค่าแรง" type="number" min="0" suffix="฿" class="num" />
              <Button type="button" variant="ghost" size="icon" class="text-danger-ink" :aria-label="`ลบช่วงเวลา ${formatDuration(o.duration_minutes)}`" @click="form.options.splice(i, 1)"><Trash2 /></Button>
            </div>
            <p v-if="!form.options.length" class="m-0 text-sm text-danger-ink">ยังไม่มีช่วงเวลา</p>
          </fieldset>

          <CheckboxField v-if="branches.length > 1" v-model="form.applyAll" :label="`ใช้ช่วงเวลาและราคานี้กับทุกสาขา (${branches.length} สาขา)`" />

          <div v-if="hasExistingPrice || form.applyAll" class="grid gap-3 rounded-lg border border-border p-4">
            <SwitchField v-model="form.immediate" label="ราคามีผลทันที" hint="ปิดเพื่อตั้งราคาล่วงหน้า" />
            <div v-if="!form.immediate" class="grid grid-cols-2 gap-3">
              <TextField v-model="form.date" type="date" label="วันที่มีผล" />
              <TimeField v-model="form.time" label="เวลา" />
            </div>
            <TextField v-model="form.reason" label="หมายเหตุ (ไม่บังคับ)" />
            <p class="m-0 text-sm text-muted-foreground">รายการที่ขายไปแล้วยังใช้ราคาเดิม</p>
          </div>

          <div v-if="scheduledOptions.length" class="grid gap-1 rounded-lg bg-pending-soft p-4 text-[15px] text-pending-ink">
            <p class="m-0 font-medium">ราคาที่ตั้งล่วงหน้า</p>
            <div v-for="o in scheduledOptions" :key="o.option_id" class="flex items-center justify-between gap-2">
              <span>{{ formatDuration(o.duration_minutes) }} · <span class="num">{{ formatBaht(Number(o.scheduled!.price)) }}</span> · มีผล {{ fmt(o.scheduled!.effective_from) }}</span>
              <Button size="sm" variant="ghost" class="text-danger-ink" @click="cancelScheduled(o)">ยกเลิก</Button>
            </div>
          </div>

          <TextareaField v-model="form.description" label="รายละเอียด" rows="2" />
          <div class="grid gap-1.5">
            <Label for="svc-image">รูปบริการ</Label>
            <input
              id="svc-image"
              type="file"
              accept="image/jpeg,image/png,image/webp"
              aria-describedby="svc-image-hint"
              class="block w-full cursor-pointer rounded-lg border border-input bg-card text-[15px] file:mr-3 file:h-10 file:cursor-pointer file:border-0 file:bg-secondary file:px-4 file:font-medium file:text-heading"
              @change="(e) => (image = (e.target as HTMLInputElement).files?.[0] ?? null)"
            >
            <p id="svc-image-hint" class="m-0 text-sm text-muted-foreground">JPG, PNG หรือ WebP ไม่เกิน 2 MB</p>
          </div>
          <SwitchField v-if="editing" v-model="form.is_active" label="เปิดใช้งานบริการ" />
        </div>
        <DialogFooter class="gap-2">
          <Button variant="outline" @click="dialog = false">ยกเลิก</Button>
          <Button :disabled="saving" @click="save">{{ saving ? 'กำลังบันทึก…' : 'บันทึก' }}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>

    <!-- ประวัติราคา -->
    <Dialog :open="!!historyService" @update:open="(v) => !v && (historyService = null)">
      <DialogContent class="max-h-[90dvh] grid-rows-[auto_minmax(0,1fr)_auto] sm:max-w-3xl">
        <DialogHeader>
          <DialogTitle>ประวัติราคา {{ historyService?.name }}</DialogTitle>
          <DialogDescription>{{ activeBranch?.name }}</DialogDescription>
        </DialogHeader>
        <div class="-mx-6 grid gap-5 overflow-y-auto px-6">
          <section v-for="o in historyOptions" :key="o.option_id">
            <h3 class="m-0 mb-2 text-[15px] font-semibold">
              {{ formatDuration(o.duration_minutes) }} <Badge v-if="!o.is_active" variant="neutral" class="ml-1">ปิดแล้ว</Badge>
            </h3>
            <div class="overflow-x-auto rounded-lg border border-border">
              <Table>
                <TableHeader>
                  <TableRow class="hover:bg-transparent">
                    <TableHead>มีผลตั้งแต่</TableHead><TableHead>ถึง</TableHead><TableHead class="text-right">ราคา</TableHead>
                    <TableHead class="text-right">ค่าแรง</TableHead><TableHead>เหตุผล</TableHead><TableHead>สถานะ</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  <TableRow v-for="h in o.history ?? []" :key="h.id" :class="h.status === 'CANCELLED' ? 'text-muted-foreground' : ''">
                    <TableCell class="num">{{ fmt(h.effective_from) }}</TableCell>
                    <TableCell class="num">{{ h.effective_to ? fmt(h.effective_to) : '—' }}</TableCell>
                    <TableCell class="num text-right">{{ formatBaht(Number(h.price)) }}</TableCell>
                    <TableCell class="num text-right">{{ formatBaht(Number(h.therapist_fee)) }}</TableCell>
                    <TableCell class="max-w-56 truncate">{{ h.reason }}</TableCell>
                    <TableCell><Badge :variant="h.status === 'CANCELLED' ? 'neutral' : 'success'">{{ h.status === 'CANCELLED' ? 'ยกเลิก' : 'ใช้งาน' }}</Badge></TableCell>
                  </TableRow>
                </TableBody>
              </Table>
            </div>
          </section>
        </div>
        <DialogFooter><Button variant="outline" @click="historyService = null">ปิด</Button></DialogFooter>
      </DialogContent>
    </Dialog>

    <!-- หมวดหมู่ -->
    <Dialog v-model:open="catDialog">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{{ catEditing ? 'แก้ไขหมวดหมู่' : 'เพิ่มหมวดหมู่' }}</DialogTitle>
          <DialogDescription>หมวดหมู่ใช้จัดกลุ่มบริการในหน้าจองของลูกค้า</DialogDescription>
        </DialogHeader>
        <form class="grid gap-4" @submit.prevent="saveCategory">
          <TextField v-model="catForm.name" label="ชื่อหมวดหมู่" maxlength="100" />
          <TextField v-model="catForm.description" label="รายละเอียด" maxlength="500" />
          <TextField v-model="catForm.sort_order" label="ลำดับ" type="number" class="num" />
          <DialogFooter class="gap-2">
            <Button type="button" variant="outline" @click="catDialog = false">ยกเลิก</Button>
            <Button type="submit" :disabled="saving">บันทึก</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  </div>
</template>
