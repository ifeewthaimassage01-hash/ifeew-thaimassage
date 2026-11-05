<script setup lang="ts">
// OWNER: เวลาทำการรายวันและวันหยุดของสาขา
import { Plus } from '@lucide/vue'
import { isoDowLabels, type Tables } from '@ifeew/shared'

definePageMeta({ ownerOnly: true })

type Hours = Tables<'branch_opening_hours'>
type Holiday = Tables<'branch_holidays'>

const route = useRoute()
const supabase = useSupabaseClient()
const branchId = computed(() => String(route.params.id))

const branchName = ref('')
const hours = ref<Array<{ id: string; iso_dow: number; is_closed: boolean; opens_at: string; closes_at: string }>>([])
const holidays = ref<Holiday[]>([])
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)
const savingHours = ref(false)

const holidayForm = reactive({ holiday_date: '', name: '', is_closed: true, opens_at: '', closes_at: '' })
const savingHoliday = ref(false)

const hhmm = (t: string | null) => (t ? t.slice(0, 5) : '')

async function load() {
  const [b, h, hol] = await Promise.all([
    supabase.from('branches').select('name, company_id').eq('id', branchId.value).maybeSingle(),
    supabase.from('branch_opening_hours').select('*').eq('branch_id', branchId.value).order('iso_dow'),
    supabase.from('branch_holidays').select('*').eq('branch_id', branchId.value).order('holiday_date', { ascending: false }),
  ])
  branchName.value = b.data?.name ?? ''
  hours.value = ((h.data ?? []) as Hours[]).map((r) => ({
    id: r.id, iso_dow: r.iso_dow, is_closed: r.is_closed, opens_at: hhmm(r.opens_at), closes_at: hhmm(r.closes_at),
  }))
  holidays.value = hol.data ?? []
}

async function saveHours() {
  for (const r of hours.value) {
    if (!r.is_closed && (!r.opens_at || !r.closes_at || r.opens_at === r.closes_at)) {
      message.value = { type: 'error', text: `กรุณาระบุเวลาเปิด-ปิดของวัน${isoDowLabels[r.iso_dow]}ให้ถูกต้อง` }
      return
    }
  }
  savingHours.value = true
  try {
    for (const r of hours.value) {
      await must(
        supabase
          .from('branch_opening_hours')
          .update({
            is_closed: r.is_closed,
            opens_at: r.is_closed ? null : r.opens_at,
            closes_at: r.is_closed ? null : r.closes_at,
          })
          .eq('id', r.id),
      )
    }
    message.value = { type: 'success', text: 'บันทึกเวลาทำการแล้ว' }
  } catch (e) {
    message.value = { type: 'error', text: errorText(e, 'บันทึกเวลาทำการไม่สำเร็จ') }
  } finally {
    savingHours.value = false
    await load()
  }
}

async function addHoliday() {
  const f = holidayForm
  if (!f.holiday_date || !f.name.trim() || (!f.is_closed && (!f.opens_at || !f.closes_at))) {
    message.value = { type: 'error', text: 'กรุณากรอกวันที่ ชื่อวันหยุด และเวลาเปิดพิเศษ (ถ้าเปิด)' }
    return
  }
  const { data: b } = await supabase.from('branches').select('company_id').eq('id', branchId.value).single()
  if (!b) return
  savingHoliday.value = true
  const { error } = await supabase.from('branch_holidays').insert({
    company_id: b.company_id,
    branch_id: branchId.value,
    holiday_date: f.holiday_date,
    name: f.name.trim(),
    is_closed: f.is_closed,
    opens_at: f.is_closed ? null : f.opens_at,
    closes_at: f.is_closed ? null : f.closes_at,
  })
  savingHoliday.value = false
  if (error) {
    message.value = { type: 'error', text: error.code === '23505' ? 'มีวันหยุดวันนี้อยู่แล้ว' : errorText(error) }
    return
  }
  Object.assign(holidayForm, { holiday_date: '', name: '', is_closed: true, opens_at: '', closes_at: '' })
  await load()
}

async function deactivateHoliday(h: Holiday) {
  const { error } = await supabase.from('branch_holidays').update({ is_active: false }).eq('id', h.id)
  if (error) message.value = { type: 'error', text: errorText(error) }
  await load()
}

onMounted(load)
</script>

<template>
  <div class="max-w-5xl">
    <PageHeader :title="branchName || 'สาขา'" description="เวลาทำการรายวันและวันหยุด/เวลาพิเศษ ใช้คำนวณเวลาว่างในหน้าจองของลูกค้า">
      <template #actions><Button as-child variant="outline"><NuxtLink to="/branches">สาขาทั้งหมด</NuxtLink></Button></template>
    </PageHeader>

    <MessageAlert :message="message" class="mb-6" @close="message = null" />

    <div class="grid gap-6">
      <SectionCard title="เวลาทำการ" description="ถ้าเวลาปิดน้อยกว่าเวลาเปิด หมายถึงปิดหลังเที่ยงคืนของวันถัดไป" flush>
        <div class="grid">
          <div
            v-for="r in hours"
            :key="r.id"
            class="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-4 gap-y-2 border-b border-border px-5 py-3 sm:grid-cols-[120px_120px_minmax(0,1fr)_minmax(0,1fr)]"
          >
            <span class="font-medium text-heading">{{ isoDowLabels[r.iso_dow] }}</span>
            <CheckboxField v-model="r.is_closed" label="ปิดทั้งวัน" />
            <TimeField v-model="r.opens_at" :disabled="r.is_closed" :aria-label="`เวลาเปิดวัน${isoDowLabels[r.iso_dow]}`" />
            <TimeField v-model="r.closes_at" :disabled="r.is_closed" :aria-label="`เวลาปิดวัน${isoDowLabels[r.iso_dow]}`" />
          </div>
        </div>
        <div class="flex justify-end px-5 py-4">
          <Button :disabled="savingHours" @click="saveHours">{{ savingHours ? 'กำลังบันทึก…' : 'บันทึกเวลาทำการ' }}</Button>
        </div>
      </SectionCard>

      <SectionCard title="วันหยุดและเวลาพิเศษ" flush>
        <form class="grid items-end gap-3 border-b border-border p-5 sm:grid-cols-2 lg:grid-cols-[160px_minmax(0,1fr)_auto_200px_200px_auto]" @submit.prevent="addHoliday">
          <TextField v-model="holidayForm.holiday_date" type="date" label="วันที่" />
          <TextField v-model="holidayForm.name" label="ชื่อวัน" placeholder="เช่น สงกรานต์" />
          <CheckboxField v-model="holidayForm.is_closed" label="ปิดทั้งวัน" class="lg:pb-2.5" />
          <TimeField v-model="holidayForm.opens_at" label="เปิด" :disabled="holidayForm.is_closed" />
          <TimeField v-model="holidayForm.closes_at" label="ปิด" :disabled="holidayForm.is_closed" />
          <Button type="submit" :disabled="savingHoliday"><Plus /> เพิ่ม</Button>
        </form>
        <div class="overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow class="hover:bg-transparent">
                <TableHead>วันที่</TableHead><TableHead>ชื่อ</TableHead><TableHead>เวลา</TableHead><TableHead>สถานะ</TableHead>
                <TableHead class="text-right"><span class="sr-only">การทำงาน</span></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              <TableRow v-for="h in holidays" :key="h.id" :class="h.is_active ? '' : 'text-muted-foreground'">
                <TableCell class="text-heading">{{ new Date(`${h.holiday_date}T00:00:00+07:00`).toLocaleDateString('th-TH', { dateStyle: 'medium', timeZone: 'Asia/Bangkok' }) }}</TableCell>
                <TableCell>{{ h.name }}</TableCell>
                <TableCell class="num">{{ h.is_closed ? 'ปิดทั้งวัน' : `${hhmm(h.opens_at)}–${hhmm(h.closes_at)}` }}</TableCell>
                <TableCell><Badge :variant="h.is_active ? 'success' : 'neutral'" dot>{{ h.is_active ? 'ใช้งาน' : 'ยกเลิกแล้ว' }}</Badge></TableCell>
                <TableCell class="text-right">
                  <Button v-if="h.is_active" variant="ghost" size="sm" class="text-danger-ink" @click="deactivateHoliday(h)">ยกเลิก</Button>
                </TableCell>
              </TableRow>
              <TableRow v-if="!holidays.length" class="hover:bg-transparent">
                <TableCell colspan="5" class="py-8 text-center text-muted-foreground">ยังไม่มีวันหยุด</TableCell>
              </TableRow>
            </TableBody>
          </Table>
        </div>
      </SectionCard>
    </div>
  </div>
</template>
