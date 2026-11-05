<script setup lang="ts">
// ตารางงานรายสัปดาห์ของสาขาที่เลือก — OWNER จัดกะได้, STAFF ดูอย่างเดียว
import { ChevronLeft, ChevronRight, Copy, Plus } from '@lucide/vue'
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
    <PageHeader title="ตารางงาน" :description="`${activeBranch?.name ?? ''} · ${isOwner ? 'แตะช่องว่างเพื่อเพิ่มกะ แตะกะเพื่อแก้ไข' : 'ดูกะของทีมในสัปดาห์'}`">
      <template #actions>
        <Button v-if="isOwner" variant="outline" :disabled="copying" @click="copyPreviousWeek"><Copy /> คัดลอกสัปดาห์ก่อน</Button>
      </template>
    </PageHeader>

    <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
      <div class="flex items-center gap-1 rounded-lg border border-border bg-card p-1">
        <Button variant="ghost" size="icon-sm" aria-label="สัปดาห์ก่อน" @click="monday = addDays(monday, -7)"><ChevronLeft /></Button>
        <span class="num min-w-[220px] px-2 text-center text-[15px] font-medium text-heading">{{ weekLabel }}</span>
        <Button variant="ghost" size="icon-sm" aria-label="สัปดาห์ถัดไป" @click="monday = addDays(monday, 7)"><ChevronRight /></Button>
        <Button variant="ghost" size="sm" @click="monday = mondayOf(bangkokToday())">สัปดาห์นี้</Button>
      </div>
      <div class="flex flex-wrap items-center gap-4">
        <div class="flex items-center gap-3 text-sm text-muted-foreground" aria-hidden="true">
          <span class="flex items-center gap-1.5"><span class="size-2.5 rounded-sm bg-secondary" />กะ</span>
          <span class="flex items-center gap-1.5"><span class="size-2.5 rounded-sm bg-pending-soft ring-1 ring-brand-accent/40" />ลา</span>
        </div>
        <CheckboxField v-model="showCancelled" label="แสดงกะที่ยกเลิก" />
      </div>
    </div>

    <MessageAlert :message="message" class="mb-4" @close="message = null" />
    <LoadingBar v-if="loading" class="mb-2" />

    <div class="overflow-x-auto rounded-xl border border-border bg-card">
      <table class="w-full min-w-[960px] border-collapse text-sm">
        <thead>
          <tr class="border-b border-border">
            <th scope="col" class="sticky left-0 z-10 w-44 bg-card px-4 py-3 text-left text-[13px] font-medium text-muted-foreground">พนักงาน</th>
            <th
              v-for="(d, i) in days"
              :key="d"
              scope="col"
              class="border-l border-border px-2 py-3 text-left text-[13px] font-medium"
              :class="[d === bangkokToday() ? 'text-heading' : 'text-muted-foreground', i >= 5 ? 'bg-background/60' : '']"
            >
              {{ dayLabel(d, i) }}
              <span v-if="d === bangkokToday()" class="ml-1 inline-block size-1.5 rounded-full bg-primary align-middle" aria-label="วันนี้" />
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="e in employees" :key="e.id" class="border-b border-border last:border-0">
            <th scope="row" class="sticky left-0 z-10 bg-card px-4 py-2 text-left align-top font-normal">
              <span class="block font-medium text-heading">{{ e.nickname }}</span>
              <span class="num block text-[13px] text-muted-foreground">{{ e.employee_code }}</span>
            </th>
            <td v-for="(d, i) in days" :key="d" class="border-l border-border p-1.5 align-top" :class="[d === bangkokToday() ? 'bg-secondary/25' : i >= 5 ? 'bg-background/60' : '']">
              <div class="flex min-h-11 flex-col gap-1">
                <button
                  v-for="s in cellShifts(e.id, d)"
                  :key="s.id"
                  type="button"
                  class="num rounded-md px-2 py-1 text-left text-[13px] font-medium transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
                  :class="[
                    s.status === 'SCHEDULED' ? 'bg-secondary text-heading hover:bg-secondary/70' : s.status === 'LEAVE' ? 'bg-pending-soft text-pending-ink ring-1 ring-brand-accent/40' : 'bg-muted text-muted-foreground line-through',
                    isOwner && s.status !== 'CANCELLED' ? 'cursor-pointer' : 'cursor-default',
                  ]"
                  :aria-label="`${e.nickname} ${s.status === 'LEAVE' ? 'ลา' : shiftText(s)} ${scheduleStatusLabels[s.status]}`"
                  @click="openEdit(s)"
                >{{ s.status === 'LEAVE' ? 'ลา' : shiftText(s) }}</button>
                <button
                  v-if="isOwner"
                  type="button"
                  class="grid h-7 place-items-center rounded-md text-muted-soft transition-colors hover:bg-muted hover:text-heading focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
                  :aria-label="`เพิ่มกะ ${e.nickname} ${dayLabel(d, i)}`"
                  @click="openAdd(e.id, d)"
                ><Plus class="size-4" /></button>
              </div>
            </td>
          </tr>
          <tr v-if="!employees.length && !loading">
            <td :colspan="8" class="p-8 text-center text-muted-foreground">ไม่มีพนักงานหรือกะในสัปดาห์นี้</td>
          </tr>
        </tbody>
      </table>
    </div>

    <Dialog v-model:open="dialog">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{{ editing ? 'แก้ไขกะ' : 'เพิ่มกะ' }}</DialogTitle>
          <DialogDescription>
            {{ employees.find((x) => x.id === form.employee_id)?.nickname }} ·
            {{ form.date ? new Date(`${form.date}T00:00:00+07:00`).toLocaleDateString('th-TH', { dateStyle: 'full', timeZone: 'Asia/Bangkok' }) : '' }}
          </DialogDescription>
        </DialogHeader>
        <form class="grid gap-4" @submit.prevent="save">
          <div class="grid grid-cols-2 gap-4">
            <TimeField v-model="form.start" label="เริ่ม" :disabled="!!editing && editing.status !== 'SCHEDULED'" />
            <TimeField v-model="form.end" label="เลิก" :disabled="!!editing && editing.status !== 'SCHEDULED'"
              :hint="form.end && form.start && form.end <= form.start ? 'เลิกงานวันถัดไป (ข้ามเที่ยงคืน)' : undefined" />
          </div>
          <SelectField
            v-if="editing"
            v-model="form.status"
            :items="(['SCHEDULED', 'LEAVE', 'CANCELLED'] as const).map((v) => ({ value: v, title: scheduleStatusLabels[v] }))"
            label="สถานะ"
          />
          <TextField v-model="form.note" label="หมายเหตุ" maxlength="300" />
          <DialogFooter class="gap-2">
            <Button type="button" variant="outline" @click="dialog = false">ปิด</Button>
            <Button type="submit" :disabled="saving">{{ saving ? 'กำลังบันทึก…' : 'บันทึก' }}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  </div>
</template>
