<script setup lang="ts">
// OWNER: พนักงาน — เพิ่ม, แก้ไข, รูป, ตั้ง PIN, ย้ายสาขา, ประวัติย้าย, เปลี่ยนสถานะ
// การกระทำเสี่ยงสูงทั้งหมดผ่าน useStepUp (DB บังคับ TOTP ภายใน 5 นาที)
import {
  bangkokToday,
  employeeCodeSchema,
  employeeStatusLabels,
  nicknameSchema,
  pinSchema,
  reasonSchema,
  type Tables,
} from '@ifeew/shared'

definePageMeta({ ownerOnly: true })

type Employee = Tables<'employees'>
type BranchMembership = Tables<'branch_memberships'>
type Transfer = Tables<'employee_transfers'>
type Status = Employee['status']

const supabase = useSupabaseClient()
const { company, branches } = useAccess()
const { run } = useStepUp()
const { call } = useEdgeFunction()

const employees = ref<Employee[]>([])
const memberships = ref<BranchMembership[]>([])
const photoUrls = ref<Record<string, string>>({})
const loading = ref(false)
const showResigned = ref(false)
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)

const branchName = (id: string | null | undefined) => branches.value.find((b) => b.branch_id === id)?.name ?? '-'
const fmt = (v: string) => new Date(v).toLocaleString('th-TH', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Bangkok' })

function currentBranch(e: Employee): string | null {
  const now = Date.now()
  return (
    memberships.value.find(
      (m) =>
        m.user_id === e.user_id && m.status === 'ACTIVE' &&
        new Date(m.effective_from).getTime() <= now &&
        (!m.effective_to || new Date(m.effective_to).getTime() > now),
    )?.branch_id ?? null
  )
}

function pendingBranch(e: Employee): BranchMembership | null {
  return memberships.value.find((m) => m.user_id === e.user_id && m.status === 'ACTIVE' && new Date(m.effective_from).getTime() > Date.now()) ?? null
}

const visible = computed(() => employees.value.filter((e) => showResigned.value || e.status !== 'RESIGNED'))

async function load() {
  if (!company.value) return
  loading.value = true
  const [emp, bm] = await Promise.all([
    supabase.from('employees').select('*').eq('company_id', company.value.company_id).order('employee_code'),
    supabase.from('branch_memberships').select('*').eq('company_id', company.value.company_id),
  ])
  loading.value = false
  if (emp.error || bm.error) {
    message.value = { type: 'error', text: 'โหลดข้อมูลพนักงานไม่สำเร็จ' }
    return
  }
  employees.value = emp.data ?? []
  memberships.value = bm.data ?? []

  const paths = employees.value.map((e) => e.photo_path).filter((p): p is string => !!p)
  if (paths.length) {
    const { data } = await supabase.storage.from('employee-photos').createSignedUrls(paths, 3600)
    const entries: Array<[string, string]> = []
    for (const d of data ?? []) if (d.path && d.signedUrl) entries.push([d.path, d.signedUrl])
    photoUrls.value = Object.fromEntries(entries)
  }
}

function ok(text: string) {
  message.value = { type: 'success', text }
}
function fail(e: unknown, fallback?: string) {
  message.value = { type: 'error', text: errorText(e, fallback) }
}

// ---------------------------------------------------------------------------
// เพิ่มพนักงาน (Edge Function staff-create)
// ---------------------------------------------------------------------------
const createDialog = ref(false)
const creating = ref(false)
const createForm = reactive({ employee_code: '', nickname: '', branch_id: '', start_date: '', pin: '' })

function openCreate() {
  Object.assign(createForm, {
    employee_code: '', nickname: '', branch_id: branches.value[0]?.branch_id ?? '', start_date: bangkokToday(), pin: '',
  })
  createDialog.value = true
}

async function submitCreate() {
  const code = employeeCodeSchema.safeParse(createForm.employee_code)
  const nick = nicknameSchema.safeParse(createForm.nickname)
  const pin = pinSchema.safeParse(createForm.pin)
  if (!code.success || !nick.success || !pin.success || !createForm.branch_id || !createForm.start_date) {
    fail(null, [code, nick, pin].find((r) => !r.success)?.error?.issues[0]?.message ?? 'กรุณากรอกข้อมูลให้ครบ')
    return
  }
  creating.value = true
  try {
    await run(() =>
      call('staff-create', {
        company_id: company.value!.company_id,
        branch_id: createForm.branch_id,
        employee_code: code.data,
        nickname: nick.data,
        start_date: createForm.start_date,
        pin: pin.data,
      }),
    )
    createDialog.value = false
    ok(`เพิ่มพนักงาน ${nick.data} แล้ว`)
    await load()
  } catch (e) {
    fail(e, 'เพิ่มพนักงานไม่สำเร็จ')
  } finally {
    creating.value = false
  }
}

// ---------------------------------------------------------------------------
// แก้ไขข้อมูลทั่วไป + รูป
// ---------------------------------------------------------------------------
const editDialog = ref(false)
const editTarget = ref<Employee | null>(null)
const editForm = reactive({ employee_code: '', nickname: '', start_date: '' })
const photoFile = ref<File | File[] | null>(null)
const saving = ref(false)

function openEdit(e: Employee) {
  editTarget.value = e
  Object.assign(editForm, { employee_code: e.employee_code, nickname: e.nickname, start_date: e.start_date })
  photoFile.value = null
  editDialog.value = true
}

async function submitEdit() {
  const e = editTarget.value
  if (!e) return
  const code = employeeCodeSchema.safeParse(editForm.employee_code)
  const nick = nicknameSchema.safeParse(editForm.nickname)
  if (!code.success || !nick.success || !editForm.start_date) {
    fail(null, 'กรุณาตรวจสอบรหัส ชื่อเล่น และวันเริ่มงาน')
    return
  }
  saving.value = true
  try {
    let photo_path = e.photo_path
    const file = Array.isArray(photoFile.value) ? photoFile.value[0] : photoFile.value
    if (file) {
      if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type) || file.size > 2 * 1024 * 1024) {
        throw new Error('รูปต้องเป็น JPG/PNG/WebP ขนาดไม่เกิน 2 MB')
      }
      const ext = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg'
      photo_path = `${e.company_id}/${e.id}/${Date.now()}.${ext}`
      await must(supabase.storage.from('employee-photos').upload(photo_path, file, { contentType: file.type }))
    }
    await must(
      supabase
        .from('employees')
        .update({ employee_code: code.data, nickname: nick.data, start_date: editForm.start_date, photo_path })
        .eq('id', e.id),
    )
    editDialog.value = false
    ok('บันทึกข้อมูลพนักงานแล้ว')
    await load()
  } catch (err) {
    fail(err, 'บันทึกไม่สำเร็จ')
  } finally {
    saving.value = false
  }
}

// ---------------------------------------------------------------------------
// ตั้ง PIN ใหม่
// ---------------------------------------------------------------------------
const pinDialog = ref(false)
const pinTarget = ref<Employee | null>(null)
const newPin = ref('')

async function submitPin() {
  const e = pinTarget.value
  const pin = pinSchema.safeParse(newPin.value)
  if (!e || !pin.success) {
    fail(null, 'PIN ต้องเป็นตัวเลข 6 หลัก')
    return
  }
  saving.value = true
  try {
    await run(() => must(supabase.rpc('set_staff_pin', { p_company_id: e.company_id, p_user_id: e.user_id, p_pin: pin.data })))
    pinDialog.value = false
    newPin.value = ''
    ok(`ตั้ง PIN ใหม่ให้ ${e.nickname} แล้ว`)
  } catch (err) {
    fail(err, 'ตั้ง PIN ไม่สำเร็จ')
  } finally {
    saving.value = false
  }
}

// ---------------------------------------------------------------------------
// ย้ายสาขา
// ---------------------------------------------------------------------------
const transferDialog = ref(false)
const transferTarget = ref<Employee | null>(null)
const transferForm = reactive({ to_branch_id: '', immediate: true, date: '', time: '08:00', reason: '' })

function openTransfer(e: Employee) {
  transferTarget.value = e
  Object.assign(transferForm, {
    to_branch_id: branches.value.find((b) => b.branch_id !== currentBranch(e))?.branch_id ?? '',
    immediate: true, date: bangkokToday(), time: '08:00', reason: '',
  })
  transferDialog.value = true
}

async function submitTransfer() {
  const e = transferTarget.value
  const reason = reasonSchema.safeParse(transferForm.reason)
  if (!e || !transferForm.to_branch_id || !reason.success) {
    fail(null, 'กรุณาเลือกสาขาปลายทางและระบุเหตุผล')
    return
  }
  const effective = transferForm.immediate
    ? new Date().toISOString()
    : `${transferForm.date}T${transferForm.time}:00+07:00`
  saving.value = true
  try {
    await run(() =>
      must(
        supabase.rpc('transfer_employee', {
          p_employee_id: e.id,
          p_to_branch_id: transferForm.to_branch_id,
          p_effective_from: effective,
          p_reason: reason.data,
        }),
      ),
    )
    transferDialog.value = false
    ok(`บันทึกการย้ายสาขาของ ${e.nickname} แล้ว`)
    await load()
  } catch (err) {
    fail(err, 'ย้ายสาขาไม่สำเร็จ')
  } finally {
    saving.value = false
  }
}

// ---------------------------------------------------------------------------
// ประวัติย้ายสาขา + ยกเลิกการย้ายที่ยังไม่มีผล
// ---------------------------------------------------------------------------
const historyDialog = ref(false)
const historyTarget = ref<Employee | null>(null)
const transfers = ref<Transfer[]>([])

async function openHistory(e: Employee) {
  historyTarget.value = e
  const { data } = await supabase
    .from('employee_transfers')
    .select('*')
    .eq('employee_id', e.id)
    .order('effective_from', { ascending: false })
  transfers.value = data ?? []
  historyDialog.value = true
}

async function cancelTransfer(t: Transfer) {
  const reason = window.prompt('เหตุผลที่ยกเลิกการย้าย')
  if (!reason || reason.trim().length < 3) return
  try {
    await run(() => must(supabase.rpc('cancel_employee_transfer', { p_transfer_id: t.id, p_reason: reason.trim() })))
    ok('ยกเลิกการย้ายแล้ว')
    await load()
    if (historyTarget.value) await openHistory(historyTarget.value)
  } catch (err) {
    fail(err, 'ยกเลิกการย้ายไม่สำเร็จ')
  }
}

// ---------------------------------------------------------------------------
// เปลี่ยนสถานะ (Edge Function staff-set-status: DB + ban/unban Auth)
// ---------------------------------------------------------------------------
const statusDialog = ref(false)
const statusTarget = ref<Employee | null>(null)
const statusForm = reactive<{ status: Status; reason: string }>({ status: 'INACTIVE', reason: '' })

const statusOptions = computed(() => {
  const s = statusTarget.value?.status
  const opts: Status[] = s === 'ACTIVE' ? ['INACTIVE', 'RESIGNED'] : s === 'INACTIVE' ? ['ACTIVE', 'RESIGNED'] : []
  return opts.map((v) => ({ value: v, title: employeeStatusLabels[v] }))
})

function openStatus(e: Employee) {
  statusTarget.value = e
  statusForm.status = e.status === 'ACTIVE' ? 'INACTIVE' : 'ACTIVE'
  statusForm.reason = ''
  statusDialog.value = true
}

async function submitStatus() {
  const e = statusTarget.value
  const reason = reasonSchema.safeParse(statusForm.reason)
  if (!e || !reason.success) {
    fail(null, 'กรุณาระบุเหตุผล')
    return
  }
  if (statusForm.status === 'RESIGNED' && !window.confirm(`ยืนยันบันทึกการลาออกของ ${e.nickname}? เปลี่ยนกลับไม่ได้`)) return
  saving.value = true
  try {
    const res = await run(() =>
      call<{ auth_synced: boolean }>('staff-set-status', { employee_id: e.id, status: statusForm.status, reason: reason.data }),
    )
    statusDialog.value = false
    ok(
      res.auth_synced
        ? `เปลี่ยนสถานะ ${e.nickname} เป็น "${employeeStatusLabels[statusForm.status]}" แล้ว`
        : 'เปลี่ยนสถานะแล้ว แต่ซิงก์บัญชี Auth ไม่สำเร็จ (สิทธิ์ใน DB ถูกปิดแล้ว) กรุณาแจ้งผู้ดูแลระบบ',
    )
    if (statusForm.status === 'ACTIVE') message.value!.text += ' — อย่าลืมตั้ง PIN ใหม่'
    await load()
  } catch (err) {
    fail(err, 'เปลี่ยนสถานะไม่สำเร็จ')
  } finally {
    saving.value = false
  }
}

onMounted(load)
</script>

<template>
  <div>
    <div class="mb-6 flex flex-wrap items-center justify-between gap-3">
      <h1 class="m-0 text-2xl font-semibold text-cocoa">พนักงาน</h1>
      <div class="flex items-center gap-3">
        <v-switch v-model="showResigned" color="primary" label="แสดงผู้ลาออก" hide-details density="compact" />
        <v-btn color="primary" prepend-icon="mdi-account-plus-outline" @click="openCreate">เพิ่มพนักงาน</v-btn>
      </div>
    </div>

    <v-alert v-if="message" :type="message.type" variant="tonal" class="mb-6" closable :text="message.text" @click:close="message = null" />

    <v-card class="p-2">
      <v-data-table
        :items="visible"
        :loading="loading"
        item-value="id"
        no-data-text="ยังไม่มีพนักงาน"
        :headers="[
          { title: '', key: 'photo', sortable: false, width: 64 },
          { title: 'รหัส', key: 'employee_code' },
          { title: 'ชื่อเล่น', key: 'nickname' },
          { title: 'สาขา', key: 'branch', sortable: false },
          { title: 'เริ่มงาน', key: 'start_date' },
          { title: 'สถานะ', key: 'status' },
          { title: '', key: 'actions', sortable: false, align: 'end' },
        ]"
      >
        <template #[`item.photo`]="{ item }">
          <v-avatar size="40" color="secondary">
            <v-img v-if="item.photo_path && photoUrls[item.photo_path]" :src="photoUrls[item.photo_path]" cover />
            <span v-else>{{ item.nickname.slice(0, 1) }}</span>
          </v-avatar>
        </template>
        <template #[`item.branch`]="{ item }">
          <span>{{ branchName(currentBranch(item)) }}</span>
          <div v-if="pendingBranch(item)" class="text-xs text-light-brown">
            ย้ายไป {{ branchName(pendingBranch(item)!.branch_id) }} {{ fmt(pendingBranch(item)!.effective_from) }}
          </div>
        </template>
        <template #[`item.start_date`]="{ item }">
          {{ new Date(`${item.start_date}T00:00:00+07:00`).toLocaleDateString('th-TH', { dateStyle: 'medium', timeZone: 'Asia/Bangkok' }) }}
        </template>
        <template #[`item.status`]="{ item }">
          <v-chip :color="item.status === 'ACTIVE' ? 'success' : item.status === 'INACTIVE' ? 'warning' : 'error'" variant="tonal" size="small">
            {{ employeeStatusLabels[item.status] }}
          </v-chip>
        </template>
        <template #[`item.actions`]="{ item }">
          <v-menu>
            <template #activator="{ props }">
              <v-btn v-bind="props" icon="mdi-dots-vertical" variant="text" aria-label="จัดการ" />
            </template>
            <v-list density="comfortable">
              <v-list-item prepend-icon="mdi-pencil-outline" title="แก้ไขข้อมูล/รูป" @click="openEdit(item)" />
              <v-list-item v-if="item.status === 'ACTIVE'" prepend-icon="mdi-dialpad" title="ตั้ง PIN ใหม่" @click="pinTarget = item; newPin = ''; pinDialog = true" />
              <v-list-item v-if="item.status !== 'RESIGNED'" prepend-icon="mdi-swap-horizontal" title="ย้ายสาขา" @click="openTransfer(item)" />
              <v-list-item prepend-icon="mdi-history" title="ประวัติย้ายสาขา" @click="openHistory(item)" />
              <v-list-item v-if="item.status !== 'RESIGNED'" prepend-icon="mdi-account-cog-outline" title="เปลี่ยนสถานะ" @click="openStatus(item)" />
            </v-list>
          </v-menu>
        </template>
      </v-data-table>
    </v-card>

    <!-- เพิ่มพนักงาน -->
    <v-dialog v-model="createDialog" max-width="520">
      <v-card class="p-6">
        <p class="m-0 mb-4 text-lg font-medium">เพิ่มพนักงาน</p>
        <div class="grid gap-x-4 md:grid-cols-2">
          <v-text-field v-model="createForm.employee_code" label="รหัสพนักงาน" maxlength="20" />
          <v-text-field v-model="createForm.nickname" label="ชื่อเล่น" maxlength="60" />
          <v-select v-model="createForm.branch_id" :items="branches" item-title="name" item-value="branch_id" label="สาขา" />
          <v-text-field v-model="createForm.start_date" type="date" label="วันเริ่มงาน" />
          <v-text-field v-model="createForm.pin" label="PIN 6 หลัก" inputmode="numeric" maxlength="6" type="password" autocomplete="new-password" />
        </div>
        <p class="m-0 text-xs text-light-brown">พนักงานเข้าสู่ระบบด้วยการเลือกชื่อ + PIN บนเครื่องประจำสาขาเท่านั้น</p>
        <div class="mt-4 flex justify-end gap-2">
          <v-btn variant="text" @click="createDialog = false">ยกเลิก</v-btn>
          <v-btn color="primary" :loading="creating" @click="submitCreate">เพิ่มพนักงาน</v-btn>
        </div>
      </v-card>
    </v-dialog>

    <!-- แก้ไข -->
    <v-dialog v-model="editDialog" max-width="520">
      <v-card class="p-6">
        <p class="m-0 mb-4 text-lg font-medium">แก้ไข {{ editTarget?.nickname }}</p>
        <div class="grid gap-x-4 md:grid-cols-2">
          <v-text-field v-model="editForm.employee_code" label="รหัสพนักงาน" maxlength="20" />
          <v-text-field v-model="editForm.nickname" label="ชื่อเล่น" maxlength="60" />
          <v-text-field v-model="editForm.start_date" type="date" label="วันเริ่มงาน" />
        </div>
        <v-file-input v-model="photoFile" label="รูปพนักงาน (JPG/PNG/WebP ไม่เกิน 2 MB)" accept="image/jpeg,image/png,image/webp" prepend-icon="mdi-camera-outline" variant="outlined" />
        <div class="mt-4 flex justify-end gap-2">
          <v-btn variant="text" @click="editDialog = false">ยกเลิก</v-btn>
          <v-btn color="primary" :loading="saving" @click="submitEdit">บันทึก</v-btn>
        </div>
      </v-card>
    </v-dialog>

    <!-- ตั้ง PIN -->
    <v-dialog v-model="pinDialog" max-width="400">
      <v-card class="p-6">
        <p class="m-0 mb-4 text-lg font-medium">ตั้ง PIN ใหม่ให้ {{ pinTarget?.nickname }}</p>
        <v-text-field v-model="newPin" label="PIN 6 หลัก" inputmode="numeric" maxlength="6" type="password" autocomplete="new-password" />
        <div class="flex justify-end gap-2">
          <v-btn variant="text" @click="pinDialog = false">ยกเลิก</v-btn>
          <v-btn color="primary" :loading="saving" @click="submitPin">บันทึก</v-btn>
        </div>
      </v-card>
    </v-dialog>

    <!-- ย้ายสาขา -->
    <v-dialog v-model="transferDialog" max-width="520">
      <v-card class="p-6">
        <p class="m-0 mb-1 text-lg font-medium">ย้ายสาขา {{ transferTarget?.nickname }}</p>
        <p class="m-0 mb-4 text-sm text-light-brown">ปัจจุบัน: {{ transferTarget ? branchName(currentBranch(transferTarget)) : '' }}</p>
        <v-select v-model="transferForm.to_branch_id" :items="branches" item-title="name" item-value="branch_id" label="สาขาปลายทาง" />
        <v-switch v-model="transferForm.immediate" color="primary" label="มีผลทันที" hide-details />
        <div v-if="!transferForm.immediate" class="grid grid-cols-2 gap-4">
          <v-text-field v-model="transferForm.date" type="date" label="วันที่มีผล" />
          <v-text-field v-model="transferForm.time" type="time" label="เวลา" />
        </div>
        <v-textarea v-model="transferForm.reason" label="เหตุผล (บังคับ)" rows="2" variant="outlined" class="mt-2" />
        <p class="m-0 text-xs text-light-brown">ถ้ายังมีกะที่สาขาเดิมหลังวันมีผล ระบบจะไม่ให้ย้าย ให้ยกเลิกหรือแก้กะก่อน</p>
        <div class="mt-4 flex justify-end gap-2">
          <v-btn variant="text" @click="transferDialog = false">ยกเลิก</v-btn>
          <v-btn color="primary" :loading="saving" @click="submitTransfer">บันทึกการย้าย</v-btn>
        </div>
      </v-card>
    </v-dialog>

    <!-- ประวัติย้ายสาขา -->
    <v-dialog v-model="historyDialog" max-width="720">
      <v-card class="p-6">
        <p class="m-0 mb-4 text-lg font-medium">ประวัติย้ายสาขา {{ historyTarget?.nickname }}</p>
        <v-table>
          <thead><tr><th>มีผล</th><th>จาก</th><th>ไป</th><th>เหตุผล</th><th>สถานะ</th><th /></tr></thead>
          <tbody>
            <tr v-for="t in transfers" :key="t.id" :class="t.status === 'CANCELLED' ? 'opacity-50' : ''">
              <td>{{ fmt(t.effective_from) }}</td>
              <td>{{ t.from_branch_id ? branchName(t.from_branch_id) : 'เริ่มงาน' }}</td>
              <td>{{ branchName(t.to_branch_id) }}</td>
              <td>{{ t.status === 'CANCELLED' ? `${t.reason} (ยกเลิก: ${t.cancel_reason})` : t.reason }}</td>
              <td>{{ t.status === 'CANCELLED' ? 'ยกเลิก' : new Date(t.effective_from) > new Date() ? 'รอมีผล' : 'มีผลแล้ว' }}</td>
              <td class="text-right">
                <v-btn
                  v-if="t.status === 'ACTIVE' && t.from_branch_id && new Date(t.effective_from) > new Date()"
                  variant="text" color="error" @click="cancelTransfer(t)"
                >ยกเลิก</v-btn>
              </td>
            </tr>
          </tbody>
        </v-table>
        <div class="mt-4 flex justify-end"><v-btn variant="text" @click="historyDialog = false">ปิด</v-btn></div>
      </v-card>
    </v-dialog>

    <!-- เปลี่ยนสถานะ -->
    <v-dialog v-model="statusDialog" max-width="480">
      <v-card class="p-6">
        <p class="m-0 mb-4 text-lg font-medium">เปลี่ยนสถานะ {{ statusTarget?.nickname }}</p>
        <v-select v-model="statusForm.status" :items="statusOptions" label="สถานะใหม่" />
        <v-alert v-if="statusForm.status === 'RESIGNED'" type="warning" variant="tonal" class="mb-4"
          text="ลาออกเปลี่ยนกลับไม่ได้: ปิดสิทธิ์ทุกสาขา ยกเลิกกะและการย้ายในอนาคต และลบ PIN" />
        <v-alert v-else-if="statusForm.status === 'INACTIVE'" type="info" variant="tonal" class="mb-4"
          text="ระงับ: เข้าสู่ระบบไม่ได้และลบ PIN แต่คงสาขาไว้ เปิดใช้ใหม่ได้ภายหลัง" />
        <v-textarea v-model="statusForm.reason" label="เหตุผล (บังคับ)" rows="2" variant="outlined" />
        <div class="flex justify-end gap-2">
          <v-btn variant="text" @click="statusDialog = false">ยกเลิก</v-btn>
          <v-btn :color="statusForm.status === 'RESIGNED' ? 'error' : 'primary'" :loading="saving" @click="submitStatus">ยืนยัน</v-btn>
        </div>
      </v-card>
    </v-dialog>
  </div>
</template>
