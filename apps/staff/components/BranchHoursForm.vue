<script setup lang="ts">
// OWNER: เวลาทำการรายสัปดาห์ + วันหยุด/เวลาพิเศษของสาขา — ใช้ใน popup หน้า /branches และหน้า /branches/[id]
import { Plus } from '@lucide/vue'
import { isoDowLabels, type Tables } from '@ifeew/shared'

const props = defineProps<{ branchId: string; companyId: string }>()
const emit = defineEmits<{ saved: [] }>()

type Hours = Tables<'branch_opening_hours'>
type Holiday = Tables<'branch_holidays'>

const supabase = useSupabaseClient()
const hours = ref<Array<{ id: string; iso_dow: number; is_closed: boolean; opens_at: string; closes_at: string }>>([])
const holidays = ref<Holiday[]>([])
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)
const savingHours = ref(false)
const holidayForm = reactive({ holiday_date: '', name: '', is_closed: true, opens_at: '', closes_at: '' })
const savingHoliday = ref(false)

const hhmm = (t: string | null) => (t ? t.slice(0, 5) : '')

async function load() {
  const [h, hol] = await Promise.all([
    supabase.from('branch_opening_hours').select('*').eq('branch_id', props.branchId).order('iso_dow'),
    supabase.from('branch_holidays').select('*').eq('branch_id', props.branchId).order('holiday_date', { ascending: false }),
  ])
  hours.value = ((h.data ?? []) as Hours[]).map((r) => ({
    id: r.id, iso_dow: r.iso_dow, is_closed: r.is_closed, opens_at: hhmm(r.opens_at), closes_at: hhmm(r.closes_at),
  }))
  holidays.value = hol.data ?? []
}
watch(() => props.branchId, () => { message.value = null; load() }, { immediate: true })

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
          .update({ is_closed: r.is_closed, opens_at: r.is_closed ? null : r.opens_at, closes_at: r.is_closed ? null : r.closes_at })
          .eq('id', r.id),
      )
    }
    message.value = { type: 'success', text: 'บันทึกเวลาทำการแล้ว' }
    emit('saved')
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
  savingHoliday.value = true
  const { error } = await supabase.from('branch_holidays').insert({
    company_id: props.companyId,
    branch_id: props.branchId,
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
  message.value = { type: 'success', text: 'เพิ่มวันหยุดแล้ว' }
  emit('saved')
  await load()
}

async function deactivateHoliday(h: Holiday) {
  const { error } = await supabase.from('branch_holidays').update({ is_active: false }).eq('id', h.id)
  if (error) message.value = { type: 'error', text: errorText(error) }
  else emit('saved')
  await load()
}
</script>

<template>
  <!-- ใช้ container query: ความกว้างจริงขึ้นกับ popup/การ์ด ไม่ใช่ความกว้างจอ -->
  <div class="@container grid gap-6">
    <MessageAlert :message="message" @close="message = null" />

    <section class="grid gap-3" aria-labelledby="bh-week">
      <div>
        <h3 id="bh-week" class="m-0 text-base font-semibold text-heading">เวลาทำการรายสัปดาห์</h3>
        <p class="m-0 mt-0.5 text-sm text-muted-foreground">ถ้าเวลาปิดน้อยกว่าเวลาเปิด หมายถึงปิดหลังเที่ยงคืนของวันถัดไป</p>
      </div>
      <div class="grid divide-y divide-border rounded-lg border border-border">
        <div
          v-for="r in hours"
          :key="r.id"
          class="grid gap-2.5 px-4 py-3 @2xl:grid-cols-[96px_112px_minmax(0,1fr)_minmax(0,1fr)] @2xl:items-center @2xl:gap-3"
        >
          <!-- มือถือ: ชื่อวัน + ปิดทั้งวัน แถวบน แล้วเวลาเปิด/ปิดคนละแถว -->
          <div class="flex items-center justify-between gap-4 @2xl:contents">
            <span class="font-medium text-heading">{{ isoDowLabels[r.iso_dow] }}</span>
            <CheckboxField v-model="r.is_closed" label="ปิดทั้งวัน" />
          </div>
          <div class="flex items-center gap-3 @2xl:contents">
            <span class="w-8 shrink-0 text-sm text-muted-foreground @2xl:hidden" aria-hidden="true">เปิด</span>
            <TimeField v-model="r.opens_at" :disabled="r.is_closed" :aria-label="`เวลาเปิดวัน${isoDowLabels[r.iso_dow]}`" class="min-w-0 flex-1" />
          </div>
          <div class="flex items-center gap-3 @2xl:contents">
            <span class="w-8 shrink-0 text-sm text-muted-foreground @2xl:hidden" aria-hidden="true">ปิด</span>
            <TimeField v-model="r.closes_at" :disabled="r.is_closed" :aria-label="`เวลาปิดวัน${isoDowLabels[r.iso_dow]}`" class="min-w-0 flex-1" />
          </div>
        </div>
      </div>
      <div class="flex justify-end">
        <Button :disabled="savingHours" @click="saveHours">{{ savingHours ? 'กำลังบันทึก…' : 'บันทึกเวลาทำการ' }}</Button>
      </div>
    </section>

    <section class="grid gap-3 border-t border-border pt-6" aria-labelledby="bh-holiday">
      <h3 id="bh-holiday" class="m-0 text-base font-semibold text-heading">วันหยุดและเวลาพิเศษ</h3>
      <form class="grid items-end gap-3 @md:grid-cols-2" @submit.prevent="addHoliday">
        <TextField v-model="holidayForm.holiday_date" type="date" label="วันที่" />
        <TextField v-model="holidayForm.name" label="ชื่อวัน" placeholder="เช่น สงกรานต์" />
        <CheckboxField v-model="holidayForm.is_closed" label="ปิดทั้งวัน" class="@md:col-span-2" />
        <TimeField v-if="!holidayForm.is_closed" v-model="holidayForm.opens_at" label="เปิด" />
        <TimeField v-if="!holidayForm.is_closed" v-model="holidayForm.closes_at" label="ปิด" />
        <div class="flex justify-end @md:col-span-2">
          <Button type="submit" variant="outline" :disabled="savingHoliday"><Plus /> เพิ่มวันหยุด</Button>
        </div>
      </form>
      <p v-if="!holidays.length" class="m-0 py-4 text-center text-sm text-muted-foreground">ยังไม่มีวันหยุด</p>
      <ul v-else class="m-0 grid list-none divide-y divide-border rounded-lg border border-border p-0">
        <li v-for="h in holidays" :key="h.id" class="flex flex-wrap items-center justify-between gap-x-4 gap-y-2 px-4 py-3" :class="h.is_active ? '' : 'text-muted-foreground'">
          <div class="grid min-w-0 flex-1 basis-48 gap-0.5">
            <p class="m-0 flex flex-wrap items-center gap-x-2 gap-y-1">
              <span class="font-semibold" :class="h.is_active ? 'text-heading' : 'line-through'">{{ h.name }}</span>
              <Badge v-if="!h.is_active" variant="neutral" dot>ยกเลิกแล้ว</Badge>
            </p>
            <p class="m-0 text-[13px]" :class="h.is_active ? 'text-muted-foreground' : ''">
              {{ new Date(`${h.holiday_date}T00:00:00+07:00`).toLocaleDateString('th-TH', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric', timeZone: 'Asia/Bangkok' }) }}
              <span class="num ml-2">{{ h.is_closed ? 'ปิดทั้งวัน' : `เปิด ${hhmm(h.opens_at)}–${hhmm(h.closes_at)}` }}</span>
            </p>
          </div>
          <Button v-if="h.is_active" variant="ghost" size="sm" class="text-danger-ink" @click="deactivateHoliday(h)">ยกเลิกวันหยุด</Button>
        </li>
      </ul>
    </section>
  </div>
</template>
