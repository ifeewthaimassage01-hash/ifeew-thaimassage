<script setup lang="ts">
// OWNER: พนักงาน — เพิ่ม, แก้ไข, รูป, ตั้ง PIN, ย้ายสาขา, ประวัติย้าย, เปลี่ยนสถานะ
// การกระทำเสี่ยงสูงทั้งหมดผ่าน useStepUp (DB บังคับ TOTP ภายใน 5 นาที)
import { ArrowLeftRight, EllipsisVertical, History, KeyRound, Pencil, UserCog, UserPlus } from '@lucide/vue'
import {
  bangkokToday,
  employeeCodeSchema,
  employeeStatusLabels,
  nicknameSchema,
  pinSchema,
  reasonSchema,
  type Tables,
} from '@ifeew/shared'


const { confirm, prompt } = useDialog()
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
  const reason = await prompt({ title: 'ยกเลิกการย้ายสาขา', label: 'เหตุผล', minLength: 3, confirmText: 'ยกเลิกการย้าย', cancelText: 'ปิด', destructive: true })
  if (reason === null) return
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
  if (statusForm.status === 'RESIGNED' && !(await confirm({ title: `บันทึกการลาออกของ ${e.nickname}?`, description: 'เปลี่ยนกลับไม่ได้', confirmText: 'บันทึกลาออก', destructive: true }))) return
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
    <PageHeader title="พนักงาน" description="พนักงานเข้าสู่ระบบด้วยการเลือกชื่อและกด PIN บนเครื่องประจำสาขาเท่านั้น">
      <template #actions><Button @click="openCreate"><UserPlus /> เพิ่มพนักงาน</Button></template>
    </PageHeader>

    <MessageAlert :message="message" class="mb-6" @close="message = null" />

    <SectionCard :description="`${visible.length} คน`" flush>
      <template #header>
        <div>
          <h2 class="m-0 text-base font-semibold">รายชื่อพนักงาน</h2>
          <p class="m-0 mt-0.5 text-sm text-muted-foreground"><span class="num">{{ visible.length }}</span> คน</p>
        </div>
      </template>
      <template #actions><SwitchField v-model="showResigned" label="แสดงผู้ลาออก" class="gap-3" /></template>
      <LoadingBar v-if="loading" />
      <div class="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow class="hover:bg-transparent">
              <TableHead>พนักงาน</TableHead><TableHead>สาขา</TableHead><TableHead>เริ่มงาน</TableHead><TableHead>สถานะ</TableHead>
              <TableHead class="w-12 text-right"><span class="sr-only">จัดการ</span></TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow v-for="item in visible" :key="item.id">
              <TableCell>
                <div class="flex items-center gap-3">
                  <span class="grid size-10 shrink-0 place-items-center overflow-hidden rounded-full bg-secondary font-semibold text-heading">
                    <img v-if="item.photo_path && photoUrls[item.photo_path]" :src="photoUrls[item.photo_path]" :alt="item.nickname" class="size-full object-cover">
                    <template v-else>{{ item.nickname.slice(0, 1) }}</template>
                  </span>
                  <span>
                    <span class="block font-medium text-heading">{{ item.nickname }}</span>
                    <span class="num block text-sm text-muted-foreground">{{ item.employee_code }}</span>
                  </span>
                </div>
              </TableCell>
              <TableCell>
                {{ branchName(currentBranch(item)) }}
                <span v-if="pendingBranch(item)" class="block text-sm text-pending-ink">
                  ย้ายไป {{ branchName(pendingBranch(item)!.branch_id) }} {{ fmt(pendingBranch(item)!.effective_from) }}
                </span>
              </TableCell>
              <TableCell class="num">{{ new Date(`${item.start_date}T00:00:00+07:00`).toLocaleDateString('th-TH', { dateStyle: 'medium', timeZone: 'Asia/Bangkok' }) }}</TableCell>
              <TableCell>
                <Badge dot :variant="item.status === 'ACTIVE' ? 'success' : item.status === 'INACTIVE' ? 'pending' : 'neutral'">{{ employeeStatusLabels[item.status as Status] }}</Badge>
              </TableCell>
              <TableCell class="text-right">
                <DropdownMenu>
                  <DropdownMenuTrigger as-child>
                    <Button variant="ghost" size="icon-sm" :aria-label="`จัดการ ${item.nickname}`"><EllipsisVertical /></Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end" class="w-52">
                    <DropdownMenuItem @select="openEdit(item)"><Pencil /> แก้ไขข้อมูล/รูป</DropdownMenuItem>
                    <DropdownMenuItem v-if="item.status === 'ACTIVE'" @select="pinTarget = item; newPin = ''; pinDialog = true"><KeyRound /> ตั้ง PIN ใหม่</DropdownMenuItem>
                    <DropdownMenuItem v-if="item.status !== 'RESIGNED'" @select="openTransfer(item)"><ArrowLeftRight /> ย้ายสาขา</DropdownMenuItem>
                    <DropdownMenuItem @select="openHistory(item)"><History /> ประวัติย้ายสาขา</DropdownMenuItem>
                    <template v-if="item.status !== 'RESIGNED'">
                      <DropdownMenuSeparator />
                      <DropdownMenuItem @select="openStatus(item)"><UserCog /> เปลี่ยนสถานะ</DropdownMenuItem>
                    </template>
                  </DropdownMenuContent>
                </DropdownMenu>
              </TableCell>
            </TableRow>
            <TableRow v-if="!loading && !visible.length" class="hover:bg-transparent">
              <TableCell colspan="5" class="py-8 text-center text-muted-foreground">ยังไม่มีพนักงาน</TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </div>
    </SectionCard>

    <!-- เพิ่มพนักงาน -->
    <Dialog v-model:open="createDialog">
      <DialogContent class="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>เพิ่มพนักงาน</DialogTitle>
          <DialogDescription>พนักงานเข้าสู่ระบบด้วยการเลือกชื่อ + PIN บนเครื่องประจำสาขาเท่านั้น</DialogDescription>
        </DialogHeader>
        <form class="grid gap-4" @submit.prevent="submitCreate">
          <div class="grid gap-4 sm:grid-cols-2">
            <TextField v-model="createForm.employee_code" label="รหัสพนักงาน" maxlength="20" />
            <TextField v-model="createForm.nickname" label="ชื่อเล่น" maxlength="60" />
            <SelectField v-model="createForm.branch_id" :items="branches" item-title="name" item-value="branch_id" label="สาขา" placeholder="เลือกสาขา" />
            <TextField v-model="createForm.start_date" type="date" label="วันเริ่มงาน" />
            <TextField v-model="createForm.pin" numeric="digits" label="PIN 6 หลัก" inputmode="numeric" maxlength="6" type="password" autocomplete="new-password" />
          </div>
          <DialogFooter class="gap-2">
            <Button type="button" variant="outline" @click="createDialog = false">ยกเลิก</Button>
            <Button type="submit" :disabled="creating">เพิ่มพนักงาน</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>

    <!-- แก้ไข -->
    <Dialog v-model:open="editDialog">
      <DialogContent class="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>แก้ไข {{ editTarget?.nickname }}</DialogTitle>
          <DialogDescription>ข้อมูลและรูปที่แสดงในหน้าเข้าสู่ระบบ</DialogDescription>
        </DialogHeader>
        <form class="grid gap-4" @submit.prevent="submitEdit">
          <div class="grid gap-4 sm:grid-cols-2">
            <TextField v-model="editForm.employee_code" label="รหัสพนักงาน" maxlength="20" />
            <TextField v-model="editForm.nickname" label="ชื่อเล่น" maxlength="60" />
            <TextField v-model="editForm.start_date" type="date" label="วันเริ่มงาน" />
          </div>
          <div class="grid gap-1.5">
            <Label for="emp-photo">รูปพนักงาน</Label>
            <input
              id="emp-photo"
              type="file"
              accept="image/jpeg,image/png,image/webp"
              aria-describedby="emp-photo-hint"
              class="block w-full cursor-pointer rounded-lg border border-input bg-card text-[15px] file:mr-3 file:h-10 file:cursor-pointer file:border-0 file:bg-secondary file:px-4 file:font-medium file:text-heading"
              @change="(e) => (photoFile = (e.target as HTMLInputElement).files?.[0] ?? null)"
            >
            <p id="emp-photo-hint" class="m-0 text-sm text-muted-foreground">JPG, PNG หรือ WebP ไม่เกิน 2 MB</p>
          </div>
          <DialogFooter class="gap-2">
            <Button type="button" variant="outline" @click="editDialog = false">ยกเลิก</Button>
            <Button type="submit" :disabled="saving">บันทึก</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>

    <!-- ตั้ง PIN -->
    <Dialog v-model:open="pinDialog">
      <DialogContent class="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle>ตั้ง PIN ใหม่ให้ {{ pinTarget?.nickname }}</DialogTitle>
          <DialogDescription>ตัวเลข 6 หลัก แจ้งพนักงานด้วยตัวเอง</DialogDescription>
        </DialogHeader>
        <form class="grid gap-4" @submit.prevent="submitPin">
          <TextField v-model="newPin" numeric="digits" label="PIN 6 หลัก" inputmode="numeric" maxlength="6" type="password" autocomplete="new-password" />
          <DialogFooter class="gap-2">
            <Button type="button" variant="outline" @click="pinDialog = false">ยกเลิก</Button>
            <Button type="submit" :disabled="saving">บันทึก</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>

    <!-- ย้ายสาขา -->
    <Dialog v-model:open="transferDialog">
      <DialogContent class="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>ย้ายสาขา {{ transferTarget?.nickname }}</DialogTitle>
          <DialogDescription>ปัจจุบัน: {{ transferTarget ? branchName(currentBranch(transferTarget)) : '' }}</DialogDescription>
        </DialogHeader>
        <form class="grid gap-4" @submit.prevent="submitTransfer">
          <SelectField v-model="transferForm.to_branch_id" :items="branches" item-title="name" item-value="branch_id" label="สาขาปลายทาง" placeholder="เลือกสาขา" />
          <SwitchField v-model="transferForm.immediate" label="มีผลทันที" />
          <div v-if="!transferForm.immediate" class="grid grid-cols-2 gap-4">
            <TextField v-model="transferForm.date" type="date" label="วันที่มีผล" />
            <TimeField v-model="transferForm.time" label="เวลา" />
          </div>
          <TextareaField v-model="transferForm.reason" label="เหตุผล" hint="บังคับ · ถ้ายังมีกะที่สาขาเดิมหลังวันมีผล ระบบจะไม่ให้ย้าย" rows="2" />
          <DialogFooter class="gap-2">
            <Button type="button" variant="outline" @click="transferDialog = false">ยกเลิก</Button>
            <Button type="submit" :disabled="saving">บันทึกการย้าย</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>

    <!-- ประวัติย้ายสาขา -->
    <Dialog v-model:open="historyDialog">
      <DialogContent class="max-h-[90dvh] grid-rows-[auto_minmax(0,1fr)_auto] sm:max-w-3xl">
        <DialogHeader>
          <DialogTitle>ประวัติย้ายสาขา {{ historyTarget?.nickname }}</DialogTitle>
          <DialogDescription>การย้ายที่ยังไม่ถึงวันมีผลยกเลิกได้</DialogDescription>
        </DialogHeader>
        <div class="-mx-6 overflow-auto px-6">
          <div class="overflow-x-auto rounded-lg border border-border">
            <Table>
              <TableHeader>
                <TableRow class="hover:bg-transparent">
                  <TableHead>มีผล</TableHead><TableHead>จาก</TableHead><TableHead>ไป</TableHead><TableHead>เหตุผล</TableHead><TableHead>สถานะ</TableHead>
                  <TableHead class="text-right"><span class="sr-only">การทำงาน</span></TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                <TableRow v-for="t in transfers" :key="t.id" :class="t.status === 'CANCELLED' ? 'text-muted-foreground' : ''">
                  <TableCell class="num">{{ fmt(t.effective_from) }}</TableCell>
                  <TableCell>{{ t.from_branch_id ? branchName(t.from_branch_id) : 'เริ่มงาน' }}</TableCell>
                  <TableCell>{{ branchName(t.to_branch_id) }}</TableCell>
                  <TableCell class="max-w-56 whitespace-normal">{{ t.status === 'CANCELLED' ? `${t.reason} (ยกเลิก: ${t.cancel_reason})` : t.reason }}</TableCell>
                  <TableCell>
                    <Badge :variant="t.status === 'CANCELLED' ? 'neutral' : new Date(t.effective_from) > new Date() ? 'pending' : 'success'">
                      {{ t.status === 'CANCELLED' ? 'ยกเลิก' : new Date(t.effective_from) > new Date() ? 'รอมีผล' : 'มีผลแล้ว' }}
                    </Badge>
                  </TableCell>
                  <TableCell class="text-right">
                    <Button v-if="t.status === 'ACTIVE' && t.from_branch_id && new Date(t.effective_from) > new Date()" variant="ghost" size="sm" class="text-danger-ink" @click="cancelTransfer(t)">ยกเลิก</Button>
                  </TableCell>
                </TableRow>
                <TableRow v-if="!transfers.length" class="hover:bg-transparent">
                  <TableCell colspan="6" class="py-6 text-center text-muted-foreground">ยังไม่มีประวัติ</TableCell>
                </TableRow>
              </TableBody>
            </Table>
          </div>
        </div>
        <DialogFooter><Button variant="outline" @click="historyDialog = false">ปิด</Button></DialogFooter>
      </DialogContent>
    </Dialog>

    <!-- เปลี่ยนสถานะ -->
    <Dialog v-model:open="statusDialog">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>เปลี่ยนสถานะ {{ statusTarget?.nickname }}</DialogTitle>
          <DialogDescription>สถานะมีผลต่อการเข้าสู่ระบบและตารางงาน</DialogDescription>
        </DialogHeader>
        <form class="grid gap-4" @submit.prevent="submitStatus">
          <SelectField v-model="statusForm.status" :items="statusOptions" label="สถานะใหม่" />
          <Alert v-if="statusForm.status === 'RESIGNED'" variant="destructive">
            <AlertDescription>ลาออกเปลี่ยนกลับไม่ได้: ปิดสิทธิ์ทุกสาขา ยกเลิกกะและการย้ายในอนาคต และลบ PIN</AlertDescription>
          </Alert>
          <Alert v-else-if="statusForm.status === 'INACTIVE'" variant="info">
            <AlertDescription>ระงับ: เข้าสู่ระบบไม่ได้และลบ PIN แต่คงสาขาไว้ เปิดใช้ใหม่ได้ภายหลัง</AlertDescription>
          </Alert>
          <TextareaField v-model="statusForm.reason" label="เหตุผล" hint="บังคับ" rows="2" />
          <DialogFooter class="gap-2">
            <Button type="button" variant="outline" @click="statusDialog = false">ยกเลิก</Button>
            <Button type="submit" :variant="statusForm.status === 'RESIGNED' ? 'destructive' : 'default'" :disabled="saving">ยืนยัน</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  </div>
</template>
