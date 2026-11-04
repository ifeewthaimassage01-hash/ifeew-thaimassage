<script setup lang="ts">
// OWNER: บริการ + ช่วงเวลา + ราคา + ค่าแรงหมอนวด (ต่อสาขา) และหมวดหมู่
// แก้ราคา/ค่าแรงเดิม = step-up TOTP + เหตุผล (DB บังคับ)
import {
  bangkokToday,
  formatBaht,
  formatDuration,
  type BranchServicePricing,
  type PricingOption,
  type Tables,
} from '@ifeew/shared'

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
  if (hasExistingPrice.value && f.reason.trim().length < 3) return 'กรุณาระบุเหตุผลการเปลี่ยนราคา'
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
  const reason = window.prompt('เหตุผลที่ยกเลิกราคาที่ตั้งล่วงหน้า')
  if (!reason || reason.trim().length < 3) return
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
    <h1 class="m-0 mb-4 text-2xl font-semibold text-cocoa">บริการและราคา</h1>
    <v-tabs v-model="tab" color="primary" class="mb-4">
      <v-tab value="services">บริการ · {{ activeBranch?.name }}</v-tab>
      <v-tab value="categories">หมวดหมู่</v-tab>
    </v-tabs>

    <v-alert v-if="message" :type="message.type" variant="tonal" class="mb-4" closable :text="message.text" @click:close="message = null" />

    <!-- บริการ -->
    <template v-if="tab === 'services'">
      <div class="mb-4 flex justify-end">
        <v-btn color="primary" prepend-icon="mdi-plus" @click="openService()">เพิ่มบริการ</v-btn>
      </div>
      <v-progress-linear v-if="loading" indeterminate color="primary" />
      <div class="grid gap-4 lg:grid-cols-2">
        <v-card v-for="s in services" :key="s.id" class="p-5" :class="s.is_active ? '' : 'opacity-50'">
          <div class="flex items-start justify-between gap-3">
            <div>
              <p class="m-0 text-xs text-light-brown">{{ categoryName(s.category_id) }}</p>
              <p class="m-0 text-lg font-medium">{{ s.name }}</p>
              <p v-if="s.name_en" class="m-0 text-sm text-light-brown">{{ s.name_en }}</p>
            </div>
            <v-chip v-if="!s.is_active" color="error" variant="tonal" size="small">ปิดใช้งาน</v-chip>
            <v-chip v-else-if="!pricingOf(s.id)" variant="tonal" size="small">ยังไม่ขายที่สาขานี้</v-chip>
            <v-chip v-else-if="!pricingOf(s.id)!.is_active" color="warning" variant="tonal" size="small">หยุดขายที่สาขานี้</v-chip>
          </div>

          <div v-if="activeOptions(s.id).length" class="mt-3 grid gap-1">
            <div v-for="o in activeOptions(s.id)" :key="o.option_id" class="grid grid-cols-3 rounded-lg bg-cream px-3 py-2 text-sm">
              <span class="font-medium">{{ formatDuration(o.duration_minutes) }}</span>
              <span>{{ formatBaht(Number(o.current!.price)) }}</span>
              <span class="text-light-brown">ค่าแรง {{ formatBaht(Number(o.current!.therapist_fee)) }}</span>
              <span v-if="o.scheduled" class="col-span-3 text-xs text-light-brown">
                ล่วงหน้า {{ fmt(o.scheduled.effective_from) }}: {{ formatBaht(Number(o.scheduled.price)) }} / ค่าแรง {{ formatBaht(Number(o.scheduled.therapist_fee)) }}
              </span>
            </div>
          </div>

          <div class="mt-4 flex flex-wrap gap-2">
            <v-btn variant="tonal" color="primary" prepend-icon="mdi-pencil-outline" @click="openService(s)">แก้ไข</v-btn>
            <v-btn v-if="pricingOf(s.id)" variant="text" @click="toggleAtBranch(s)">
              {{ pricingOf(s.id)!.is_active ? 'หยุดขายที่สาขานี้' : 'เปิดขายที่สาขานี้' }}
            </v-btn>
            <v-btn v-if="pricingOf(s.id)" variant="text" icon="mdi-history" aria-label="ประวัติราคา" @click="historyService = s" />
          </div>
        </v-card>
      </div>
    </template>

    <!-- หมวดหมู่ -->
    <template v-else>
      <div class="mb-4 flex justify-end">
        <v-btn color="primary" prepend-icon="mdi-plus" @click="openCategory()">เพิ่มหมวดหมู่</v-btn>
      </div>
      <v-card class="p-2">
        <v-table>
          <thead><tr><th>ลำดับ</th><th>ชื่อ</th><th>รายละเอียด</th><th>สถานะ</th><th /></tr></thead>
          <tbody>
            <tr v-for="c in categories" :key="c.id" :class="c.is_active ? '' : 'opacity-50'">
              <td>{{ c.sort_order }}</td>
              <td>{{ c.name }}</td>
              <td>{{ c.description || '-' }}</td>
              <td>{{ c.is_active ? 'เปิดใช้งาน' : 'ปิดใช้งาน' }}</td>
              <td class="text-right">
                <v-btn size="small" variant="text" @click="openCategory(c)">แก้ไข</v-btn>
                <v-btn size="small" variant="text" :color="c.is_active ? 'error' : 'primary'" @click="toggleCategory(c)">
                  {{ c.is_active ? 'ปิด' : 'เปิด' }}
                </v-btn>
              </td>
            </tr>
          </tbody>
        </v-table>
      </v-card>
    </template>

    <!-- ฟอร์มบริการ -->
    <v-dialog v-model="dialog" max-width="560" scrollable>
      <v-card class="p-6">
        <p class="m-0 mb-4 text-lg font-medium">{{ editing ? 'แก้ไขบริการ' : 'เพิ่มบริการ' }} · {{ activeBranch?.name }}</p>
        <div class="max-h-[70vh] overflow-y-auto pr-1">
          <v-text-field v-model="form.name" label="ชื่อรายการ *" maxlength="150" />
          <v-text-field v-model="form.name_en" label="ชื่อภาษาอังกฤษ (sub)" maxlength="150" />
          <v-select v-model="form.category_id" :items="categories.filter((c) => c.is_active)" item-title="name" item-value="id" label="หมวดหมู่ *" />

          <p class="m-0 mb-2 text-sm font-medium">เพิ่มช่วงเวลา (นาที) เช่น 3 ชม = 180</p>
          <div class="mb-4 flex gap-2">
            <v-text-field v-model="newMinutes" placeholder="นาทีอื่น เช่น 180" type="number" min="5" max="600" hide-details @keydown.enter.prevent="addDuration" />
            <v-btn variant="outlined" prepend-icon="mdi-plus" class="!h-auto" @click="addDuration">เพิ่มเวลา</v-btn>
          </div>

          <p class="m-0 mb-2 text-sm font-medium">ช่วงเวลาที่ขาย + ราคา + ค่าแรง (บาท)</p>
          <div v-for="(o, i) in form.options" :key="o.duration_minutes" class="mb-3 rounded-2xl border border-beige p-4">
            <div class="mb-3 flex items-center justify-between">
              <span class="rounded-full border border-light-brown bg-beige px-4 py-1 text-sm font-medium">{{ formatDuration(o.duration_minutes) }}</span>
              <v-btn icon="mdi-trash-can-outline" color="error" variant="tonal" size="small" aria-label="ลบช่วงเวลา" @click="form.options.splice(i, 1)" />
            </div>
            <div class="grid grid-cols-2 gap-3">
              <v-text-field v-model="o.price" label="ราคา (฿) *" type="number" min="0" hide-details />
              <v-text-field v-model="o.therapist_fee" label="ค่าแรง (฿)" type="number" min="0" hide-details />
            </div>
          </div>
          <p v-if="!form.options.length" class="text-sm text-red-700">ยังไม่มีช่วงเวลา</p>

          <v-checkbox v-if="branches.length > 1" v-model="form.applyAll" color="primary" hide-details
            :label="`ใช้ช่วงเวลาและราคานี้กับทุกสาขา (${branches.length} สาขา)`" />

          <template v-if="hasExistingPrice || form.applyAll">
            <v-switch v-model="form.immediate" color="primary" label="ราคามีผลทันที" hide-details />
            <div v-if="!form.immediate" class="grid grid-cols-2 gap-3">
              <v-text-field v-model="form.date" type="date" label="วันที่มีผล" />
              <v-text-field v-model="form.time" type="time" label="เวลา" />
            </div>
            <v-text-field v-model="form.reason" :label="hasExistingPrice ? 'เหตุผลการเปลี่ยนราคา *' : 'เหตุผล'" class="mt-2" />
            <p class="m-0 mb-2 text-xs text-light-brown">การแก้ราคาเดิมต้องยืนยันรหัส Authenticator · รายการที่ขายไปแล้วใช้ราคาเดิมตาม Snapshot</p>
          </template>

          <div v-if="scheduledOptions.length" class="mb-3 rounded-xl bg-cream p-3 text-sm">
            <p class="m-0 mb-1 font-medium">ราคาที่ตั้งล่วงหน้า</p>
            <div v-for="o in scheduledOptions" :key="o.option_id" class="flex items-center justify-between">
              <span>{{ formatDuration(o.duration_minutes) }} · {{ formatBaht(Number(o.scheduled!.price)) }} · มีผล {{ fmt(o.scheduled!.effective_from) }}</span>
              <v-btn size="small" variant="text" color="error" @click="cancelScheduled(o)">ยกเลิก</v-btn>
            </div>
          </div>

          <v-textarea v-model="form.description" label="รายละเอียด" rows="2" variant="outlined" />
          <v-file-input v-model="image" label="รูปบริการ (JPG/PNG/WebP ไม่เกิน 2 MB)" accept="image/jpeg,image/png,image/webp" prepend-icon="mdi-image-outline" variant="outlined" />
          <v-switch v-if="editing" v-model="form.is_active" color="primary" label="เปิดใช้งานบริการ" hide-details />
        </div>
        <div class="mt-4 flex justify-end gap-2">
          <v-btn variant="text" @click="dialog = false">ยกเลิก</v-btn>
          <v-btn color="primary" :loading="saving" @click="save">บันทึก</v-btn>
        </div>
      </v-card>
    </v-dialog>

    <!-- ประวัติราคา -->
    <v-dialog :model-value="!!historyService" max-width="760" @update:model-value="historyService = null">
      <v-card class="p-6">
        <p class="m-0 mb-4 text-lg font-medium">ประวัติราคา {{ historyService?.name }} · {{ activeBranch?.name }}</p>
        <div v-for="o in historyOptions" :key="o.option_id" class="mb-4">
          <p class="m-0 mb-1 font-medium">{{ formatDuration(o.duration_minutes) }} <span v-if="!o.is_active" class="text-xs text-red-700">(ปิดแล้ว)</span></p>
          <v-table density="compact">
            <thead><tr><th>มีผลตั้งแต่</th><th>ถึง</th><th>ราคา</th><th>ค่าแรง</th><th>เหตุผล</th><th>สถานะ</th></tr></thead>
            <tbody>
              <tr v-for="h in o.history ?? []" :key="h.id" :class="h.status === 'CANCELLED' ? 'opacity-50' : ''">
                <td>{{ fmt(h.effective_from) }}</td>
                <td>{{ h.effective_to ? fmt(h.effective_to) : '-' }}</td>
                <td>{{ formatBaht(Number(h.price)) }}</td>
                <td>{{ formatBaht(Number(h.therapist_fee)) }}</td>
                <td>{{ h.reason }}</td>
                <td>{{ h.status === 'CANCELLED' ? 'ยกเลิก' : 'ใช้งาน' }}</td>
              </tr>
            </tbody>
          </v-table>
        </div>
        <div class="mt-2 flex justify-end"><v-btn variant="text" @click="historyService = null">ปิด</v-btn></div>
      </v-card>
    </v-dialog>

    <!-- หมวดหมู่ -->
    <v-dialog v-model="catDialog" max-width="460">
      <v-card class="p-6">
        <p class="m-0 mb-4 text-lg font-medium">{{ catEditing ? 'แก้ไขหมวดหมู่' : 'เพิ่มหมวดหมู่' }}</p>
        <v-text-field v-model="catForm.name" label="ชื่อหมวดหมู่" maxlength="100" />
        <v-text-field v-model="catForm.description" label="รายละเอียด" maxlength="500" />
        <v-text-field v-model="catForm.sort_order" label="ลำดับ" type="number" />
        <div class="flex justify-end gap-2">
          <v-btn variant="text" @click="catDialog = false">ยกเลิก</v-btn>
          <v-btn color="primary" :loading="saving" @click="saveCategory">บันทึก</v-btn>
        </div>
      </v-card>
    </v-dialog>
  </div>
</template>
