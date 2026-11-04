<script setup lang="ts">
// OWNER: เวลาทำการรายวันและวันหยุดของสาขา
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
  <div>
    <v-btn variant="text" prepend-icon="mdi-arrow-left" to="/branches" class="mb-2">กลับ</v-btn>
    <h1 class="m-0 mb-6 text-2xl font-semibold text-cocoa">{{ branchName }}</h1>

    <v-alert v-if="message" :type="message.type" variant="tonal" class="mb-6" closable :text="message.text" @click:close="message = null" />

    <v-card class="mb-6 p-6">
      <p class="m-0 mb-1 text-lg font-medium">เวลาทำการ</p>
      <p class="m-0 mb-4 text-sm text-light-brown">ถ้าเวลาปิดน้อยกว่าเวลาเปิด หมายถึงปิดหลังเที่ยงคืนของวันถัดไป</p>
      <div v-for="r in hours" :key="r.id" class="grid grid-cols-[110px_120px_1fr_1fr] items-center gap-3">
        <span class="font-medium">{{ isoDowLabels[r.iso_dow] }}</span>
        <v-switch v-model="r.is_closed" color="error" label="ปิด" hide-details density="compact" />
        <v-text-field v-model="r.opens_at" type="time" label="เปิด" :disabled="r.is_closed" hide-details class="my-1" />
        <v-text-field v-model="r.closes_at" type="time" label="ปิด" :disabled="r.is_closed" hide-details class="my-1" />
      </div>
      <div class="mt-4 flex justify-end">
        <v-btn color="primary" :loading="savingHours" @click="saveHours">บันทึกเวลาทำการ</v-btn>
      </div>
    </v-card>

    <v-card class="p-6">
      <p class="m-0 mb-4 text-lg font-medium">วันหยุด / เวลาพิเศษ</p>
      <div class="grid items-center gap-3 md:grid-cols-[160px_1fr_110px_120px_120px_auto]">
        <v-text-field v-model="holidayForm.holiday_date" type="date" label="วันที่" hide-details />
        <v-text-field v-model="holidayForm.name" label="ชื่อ เช่น สงกรานต์" hide-details />
        <v-switch v-model="holidayForm.is_closed" color="error" label="ปิดทั้งวัน" hide-details density="compact" />
        <v-text-field v-model="holidayForm.opens_at" type="time" label="เปิด" :disabled="holidayForm.is_closed" hide-details />
        <v-text-field v-model="holidayForm.closes_at" type="time" label="ปิด" :disabled="holidayForm.is_closed" hide-details />
        <v-btn color="primary" :loading="savingHoliday" @click="addHoliday">เพิ่ม</v-btn>
      </div>

      <v-table class="mt-4">
        <thead>
          <tr><th>วันที่</th><th>ชื่อ</th><th>เวลา</th><th>สถานะ</th><th /></tr>
        </thead>
        <tbody>
          <tr v-for="h in holidays" :key="h.id" :class="h.is_active ? '' : 'opacity-50'">
            <td>{{ new Date(`${h.holiday_date}T00:00:00+07:00`).toLocaleDateString('th-TH', { dateStyle: 'medium', timeZone: 'Asia/Bangkok' }) }}</td>
            <td>{{ h.name }}</td>
            <td>{{ h.is_closed ? 'ปิดทั้งวัน' : `${hhmm(h.opens_at)} - ${hhmm(h.closes_at)}` }}</td>
            <td>{{ h.is_active ? 'ใช้งาน' : 'ยกเลิกแล้ว' }}</td>
            <td class="text-right">
              <v-btn v-if="h.is_active" variant="text" color="error" @click="deactivateHoliday(h)">ยกเลิก</v-btn>
            </td>
          </tr>
          <tr v-if="!holidays.length"><td colspan="5" class="text-center text-light-brown">ยังไม่มีวันหยุด</td></tr>
        </tbody>
      </v-table>
    </v-card>
  </div>
</template>
