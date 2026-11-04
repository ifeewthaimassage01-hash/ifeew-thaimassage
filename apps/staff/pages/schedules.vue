<script setup lang="ts">
// ตารางงานรายสัปดาห์ของสาขาที่เลือก — OWNER จัดกะได้, STAFF ดูอย่างเดียว
import {
  addDays,
  bangkokIso,
  bangkokToday,
  isoDowLabels,
  mondayOf,
  scheduleStatusLabels,
  shiftRange,
  toBangkokParts,
  type Tables,
} from '@ifeew/shared'

type Shift = Tables<'employee_schedules'>
type Employee = Pick<Tables<'employees'>, 'id' | 'company_id' | 'user_id' | 'nickname' | 'employee_code' | 'status'>

const supabase = useSupabaseClient()
const { company, activeBranch, isOwner } = useAccess()

const monday = ref(mondayOf(bangkokToday()))
const days = computed(() => Array.from({ length: 7 }, (_, i) => addDays(monday.value, i)))
const shifts = ref<Shift[]>([])
const employees = ref<Employee[]>([])
const loading = ref(false)
const showCancelled = ref(false)
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)

const dayLabel = (d: string, i: number) =>
  `${isoDowLabels[i + 1]} ${new Date(`${d}T00:00:00+07:00`).toLocaleDateString('th-TH', { day: 'numeric', month: 'short', timeZone: 'Asia/Bangkok' })}`

const weekLabel = computed(() => {
  const f = (d: string) => new Date(`${d}T00:00:00+07:00`).toLocaleDateString('th-TH', { dateStyle: 'medium', timeZone: 'Asia/Bangkok' })
  return `${f(days.value[0]!)} – ${f(days.value[6]!)}`
})

function cellShifts(employeeId: string, day: string) {
  return shifts.value.filter(
    (s) => s.employee_id === employeeId && toBangkokParts(s.starts_at).date === day && (showCancelled.value || s.status !== 'CANCELLED'),
  )
}

const shiftText = (s: Shift) => `${toBangkokParts(s.starts_at).time}–${toBangkokParts(s.ends_at).time}`
const shiftColor = (s: Shift) => (s.status === 'SCHEDULED' ? 'success' : s.status === 'LEAVE' ? 'warning' : 'grey')

async function load() {
  const branch = activeBranch.value
  if (!branch || !company.value) return
  loading.value = true
  const from = bangkokIso(monday.value, '00:00')
  const to = bangkokIso(addDays(monday.value, 7), '00:00')

  const { data: s, error } = await supabase
    .from('employee_schedules')
    .select('*')
    .eq('branch_id', branch.branch_id)
    .gte('starts_at', from)
    .lt('starts_at', to)
    .order('starts_at')
  if (error) message.value = { type: 'error', text: 'โหลดตารางงานไม่สำเร็จ' }
  shifts.value = s ?? []

  // OWNER: แถว = พนักงานที่สังกัดสาขานี้ในสัปดาห์นั้น, STAFF: แถว = คนที่มีกะ
  const ids = new Set(shifts.value.map((x) => x.employee_id))
  let userIds: string[] = []
  if (isOwner.value) {
    const { data: bm } = await supabase
      .from('branch_memberships')
      .select('user_id, effective_from, effective_to')
      .eq('branch_id', branch.branch_id)
      .eq('status', 'ACTIVE')
      .lt('effective_from', to)
    userIds = (bm ?? []).filter((m) => !m.effective_to || m.effective_to > from).map((m) => m.user_id)
  }
  const { data: emp } = await supabase
    .from('employees')
    .select('id, company_id, user_id, nickname, employee_code, status')
    .eq('company_id', company.value.company_id)
    .order('nickname')
  employees.value = (emp ?? []).filter(
    (e) => ids.has(e.id) || (userIds.includes(e.user_id) && e.status === 'ACTIVE'),
  )
  loading.value = false
}

watch([monday, () => activeBranch.value?.branch_id], load, { immediate: true })

// ---------------------------------------------------------------------------
// เพิ่ม / แก้ไขกะ (OWNER)
// ---------------------------------------------------------------------------
const dialog = ref(false)
const saving = ref(false)
const editing = ref<Shift | null>(null)
const form = reactive({ employee_id: '', date: '', start: '10:00', end: '19:00', status: 'SCHEDULED' as Shift['status'], note: '' })

function openAdd(employeeId: string, day: string) {
  if (!isOwner.value) return
  editing.value = null
  Object.assign(form, { employee_id: employeeId, date: day, start: '10:00', end: '19:00', status: 'SCHEDULED', note: '' })
  dialog.value = true
}

function openEdit(s: Shift) {
  if (!isOwner.value || s.status === 'CANCELLED') return
  editing.value = s
  const a = toBangkokParts(s.starts_at)
  const b = toBangkokParts(s.ends_at)
  Object.assign(form, { employee_id: s.employee_id, date: a.date, start: a.time, end: b.time, status: s.status, note: s.note ?? '' })
  dialog.value = true
}

async function save() {
  const branch = activeBranch.value
  if (!branch || !company.value || !form.start || !form.end) return
  const range = shiftRange(form.date, form.start, form.end)
  saving.value = true
  try {
    if (editing.value) {
      const timesChanged =
        new Date(range.starts_at).getTime() !== new Date(editing.value.starts_at).getTime() ||
        new Date(range.ends_at).getTime() !== new Date(editing.value.ends_at).getTime()
      await must(
        supabase
          .from('employee_schedules')
          .update({
            ...(editing.value.status === 'SCHEDULED' && timesChanged ? range : {}),
            status: form.status,
            note: form.note.trim() || null,
          })
          .eq('id', editing.value.id),
      )
    } else {
      await must(
        supabase.from('employee_schedules').insert({
          company_id: company.value.company_id,
          branch_id: branch.branch_id,
          employee_id: form.employee_id,
          ...range,
          note: form.note.trim() || null,
        }),
      )
    }
    dialog.value = false
    await load()
  } catch (e) {
    const code = (e as { code?: string }).code
    message.value = { type: 'error', text: code === '23P01' ? 'กะซ้อนกับกะอื่นของพนักงานคนนี้' : errorText(e, 'บันทึกกะไม่สำเร็จ') }
  } finally {
    saving.value = false
  }
}

// ---------------------------------------------------------------------------
// คัดลอกสัปดาห์ก่อน
// ---------------------------------------------------------------------------
const copying = ref(false)
async function copyPreviousWeek() {
  const branch = activeBranch.value
  if (!branch) return
  copying.value = true
  try {
    const res = (await must(
      supabase.rpc('copy_schedule_week', {
        p_branch_id: branch.branch_id,
        p_source_monday: addDays(monday.value, -7),
        p_target_monday: monday.value,
      }),
    )) as { copied: number; skipped: number }
    message.value = {
      type: 'success',
      text: `คัดลอก ${res.copied} กะ${res.skipped ? ` (ข้าม ${res.skipped} กะที่ซ้อนหรือพนักงานไม่ได้สังกัดสาขาแล้ว)` : ''}`,
    }
    await load()
  } catch (e) {
    message.value = { type: 'error', text: errorText(e, 'คัดลอกไม่สำเร็จ') }
  } finally {
    copying.value = false
  }
}
</script>

<template>
  <div>
    <div class="mb-6 flex flex-wrap items-center justify-between gap-3">
      <h1 class="m-0 text-2xl font-semibold text-cocoa">ตารางงาน · {{ activeBranch?.name }}</h1>
      <div class="flex flex-wrap items-center gap-2">
        <v-btn icon="mdi-chevron-left" variant="text" aria-label="สัปดาห์ก่อน" @click="monday = addDays(monday, -7)" />
        <span class="min-w-[220px] text-center font-medium">{{ weekLabel }}</span>
        <v-btn icon="mdi-chevron-right" variant="text" aria-label="สัปดาห์ถัดไป" @click="monday = addDays(monday, 7)" />
        <v-btn variant="text" @click="monday = mondayOf(bangkokToday())">สัปดาห์นี้</v-btn>
        <v-btn v-if="isOwner" variant="tonal" color="primary" prepend-icon="mdi-content-copy" :loading="copying" @click="copyPreviousWeek">
          คัดลอกสัปดาห์ก่อน
        </v-btn>
      </div>
    </div>

    <v-alert v-if="message" :type="message.type" variant="tonal" class="mb-4" closable :text="message.text" @click:close="message = null" />
    <v-switch v-model="showCancelled" color="primary" label="แสดงกะที่ยกเลิก" hide-details density="compact" class="mb-2" />
    <v-progress-linear v-if="loading" indeterminate color="primary" />

    <v-card class="overflow-x-auto p-2">
      <table class="w-full min-w-[900px] border-collapse text-sm">
        <thead>
          <tr>
            <th class="w-40 p-2 text-left">พนักงาน</th>
            <th v-for="(d, i) in days" :key="d" class="p-2 text-left" :class="d === bangkokToday() ? 'text-light-brown' : ''">
              {{ dayLabel(d, i) }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="e in employees" :key="e.id" class="border-t border-beige">
            <td class="p-2 font-medium">{{ e.nickname }}<div class="text-xs text-light-brown">{{ e.employee_code }}</div></td>
            <td v-for="d in days" :key="d" class="p-1 align-top">
              <div class="flex min-h-[44px] flex-col gap-1">
                <v-chip
                  v-for="s in cellShifts(e.id, d)"
                  :key="s.id"
                  :color="shiftColor(s)"
                  variant="tonal"
                  size="small"
                  :class="s.status === 'CANCELLED' ? 'line-through' : ''"
                  @click="openEdit(s)"
                >
                  {{ s.status === 'LEAVE' ? 'ลา' : shiftText(s) }}
                </v-chip>
                <v-btn v-if="isOwner" size="small" variant="text" icon="mdi-plus" aria-label="เพิ่มกะ" class="self-start" @click="openAdd(e.id, d)" />
              </div>
            </td>
          </tr>
          <tr v-if="!employees.length && !loading">
            <td :colspan="8" class="p-6 text-center text-light-brown">ไม่มีพนักงานหรือกะในสัปดาห์นี้</td>
          </tr>
        </tbody>
      </table>
    </v-card>

    <v-dialog v-model="dialog" max-width="460">
      <v-card class="p-6">
        <p class="m-0 mb-1 text-lg font-medium">{{ editing ? 'แก้ไขกะ' : 'เพิ่มกะ' }}</p>
        <p class="m-0 mb-4 text-sm text-light-brown">
          {{ employees.find((x) => x.id === form.employee_id)?.nickname }} ·
          {{ new Date(`${form.date}T00:00:00+07:00`).toLocaleDateString('th-TH', { dateStyle: 'full', timeZone: 'Asia/Bangkok' }) }}
        </p>
        <div class="grid grid-cols-2 gap-4">
          <v-text-field v-model="form.start" type="time" label="เริ่ม" :disabled="!!editing && editing.status !== 'SCHEDULED'" />
          <v-text-field v-model="form.end" type="time" label="เลิก" :disabled="!!editing && editing.status !== 'SCHEDULED'" />
        </div>
        <p v-if="form.end && form.start && form.end <= form.start" class="m-0 mb-2 text-xs text-light-brown">เลิกงานวันถัดไป (ข้ามเที่ยงคืน)</p>
        <v-select
          v-if="editing"
          v-model="form.status"
          :items="(['SCHEDULED', 'LEAVE', 'CANCELLED'] as const).map((v) => ({ value: v, title: scheduleStatusLabels[v] }))"
          label="สถานะ"
        />
        <v-text-field v-model="form.note" label="หมายเหตุ" maxlength="300" />
        <div class="flex justify-end gap-2">
          <v-btn variant="text" @click="dialog = false">ปิด</v-btn>
          <v-btn color="primary" :loading="saving" @click="save">บันทึก</v-btn>
        </div>
      </v-card>
    </v-dialog>
  </div>
</template>
