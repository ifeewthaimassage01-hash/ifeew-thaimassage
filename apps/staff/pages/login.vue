<script setup lang="ts">
import { toast } from 'vue-sonner'
import { bangkokTime } from '@ifeew/shared'
import type { DeviceStaff, LoginBranch } from '~/composables/useStaffDevice'

definePageMeta({ layout: 'blank' })

const route = useRoute()
const supabase = useSupabaseClient()
const { listBranchStaff, branchPinLogin, ownerPinLogin, errorMessage } = useStaffDevice()
const { clear: clearAccess } = useAccess()

const mode = ref<'staff' | 'owner'>('staff')
// เลือกสาขาจาก dropdown (ไม่ต้องผูกเครื่อง — migration 030) และจำสาขาล่าสุดไว้ในเครื่อง
const branches = ref<LoginBranch[]>([])
const branchId = useLocalStorage<string | null>('ifeew.login_branch', null)
const loadingBranches = ref(false)
const staff = ref<DeviceStaff[]>([])
const loadingList = ref(false)
const listError = ref<string | null>(null)

const selected = ref<DeviceStaff | null>(null)
const pinLoading = ref(false)
const pinError = ref<string | null>(null)
const pinPad = ref<{ reset: () => void } | null>(null)

const ownerLoading = ref(false)
const ownerError = ref<string | null>(null)

const queryErrors: Record<string, string> = {
  not_staff: 'บัญชีนี้ไม่ใช่บัญชีพนักงานหรือเจ้าของร้าน',
  access: 'ไม่สามารถตรวจสอบสิทธิ์ได้ กรุณาเข้าสู่ระบบใหม่',
  idle: 'ออกจากระบบอัตโนมัติเนื่องจากไม่มีการใช้งาน',
  day_end: 'ออกจากระบบอัตโนมัติเมื่อขึ้นวันใหม่ (ตี 3) · เข้าสู่ระบบเพื่อเริ่มงานวันนี้',
}
const banner = computed(() => queryErrors[String(route.query.error ?? '')] ?? null)

async function loadBranches() {
  loadingBranches.value = true
  listError.value = null
  try {
    const res = await listBranchStaff()
    branches.value = res.branches
    // สาขาที่จำไว้ไม่มีแล้ว → ล้าง; มีสาขาเดียว → เลือกให้เลย
    if (!res.branches.some((b) => b.branch_id === branchId.value)) {
      branchId.value = res.branches.length === 1 ? res.branches[0]!.branch_id : null
    }
  } catch (e) {
    listError.value = errorMessage(e).message
  } finally {
    loadingBranches.value = false
  }
}

async function loadStaff() {
  const id = branchId.value
  staff.value = []
  selected.value = null
  if (!id) return
  loadingList.value = true
  listError.value = null
  try {
    const res = await listBranchStaff(id)
    if (branchId.value !== id) return // เปลี่ยนสาขาระหว่างโหลด
    staff.value = res.staff ?? []
  } catch (e) {
    const err = errorMessage(e)
    listError.value = err.message
    if (err.code === 'BRANCH_INVALID') {
      branchId.value = null
      await loadBranches()
    }
  } finally {
    loadingList.value = false
  }
}
watch(branchId, loadStaff)

async function reload() {
  await loadBranches()
  await loadStaff()
}

// รีเฟรชรายชื่อเองเบื้องหลัง (แทนปุ่มโหลดใหม่) — ทุก 30 วินาที และเมื่อกลับมาที่หน้านี้
//   ไม่ล้างรายชื่อเดิม (ไม่กะพริบ) และข้ามถ้ากำลังกรอก PIN อยู่
async function refreshQuietly() {
  const id = branchId.value
  if (!id || selected.value || pinLoading.value || loadingList.value) return
  try {
    const res = await listBranchStaff(id)
    if (branchId.value === id && !selected.value) {
      staff.value = res.staff ?? []
      listError.value = null
    }
  } catch {
    // เงียบไว้ — รอบถัดไปจะลองใหม่ (ข้อผิดพลาดตอนเลือกสาขาจะแสดงตามปกติ)
  }
}
useIntervalFn(refreshQuietly, 30_000)
const visibility = useDocumentVisibility()
watch(visibility, (v) => v === 'visible' && refreshQuietly())

function choose(s: DeviceStaff) {
  if (s.locked) return
  selected.value = s
  pinError.value = null
}

// เข้าใช้งาน = ลงเวลาเข้างานของวันนั้น (ครั้งแรกของวัน) — ลงไปแล้ว/ไม่ใช่พนักงานสาขาก็ข้ามไป ไม่ขวางการ login
// คืนข้อมูลการเข้างานเมื่อเป็นการเข้าใช้ครั้งแรกของวัน (ลงเวลาสำเร็จ) · ลงไปแล้ว/ไม่ใช่พนักงานสาขา = null
async function clockInToday(branchId: string): Promise<{ nickname: string; clock_in_at: string } | null> {
  const { data, error } = await supabase.rpc('attendance_clock', { p_branch_id: branchId, p_action: 'CLOCK_IN' })
  if (error) {
    if (error.code !== '23514' && error.code !== '42501') console.warn('clock-in', error.message)
    return null
  }
  return data as unknown as { nickname: string; clock_in_at: string }
}

// แจ้งหลังเปลี่ยนหน้า (ตัวแสดงข้อความอยู่ใน layout หลัก ไม่ใช่หน้า login)
function notifyCheckedIn(att: { nickname: string; clock_in_at: string } | null) {
  if (!att) return
  setTimeout(() => {
    toast.success('เช็คชื่อเข้างานสำเร็จ', {
      description: `${att.nickname} · เข้างานเวลา ${bangkokTime(att.clock_in_at)} น.`,
      duration: 6000,
    })
  }, 300)
}

async function submitPin(pin: string) {
  if (!selected.value || !branchId.value) return
  pinLoading.value = true
  pinError.value = null
  try {
    clearAccess()
    const res = await branchPinLogin(branchId.value, selected.value.user_id, pin)
    markLogin()
    const attendance = await clockInToday(res.branch_id)
    await navigateTo('/')
    notifyCheckedIn(attendance)
  } catch (e) {
    const err = errorMessage(e)
    pinError.value =
      err.code === 'INVALID_CREDENTIALS' && err.attemptsLeft != null
        ? `${err.message} (เหลืออีก ${err.attemptsLeft} ครั้ง)`
        : err.message
    pinPad.value?.reset()
    if (err.code === 'PIN_LOCKED') await loadStaff()
  } finally {
    pinLoading.value = false
  }
}

// เจ้าของร้าน: PIN อย่างเดียว (ไม่ต้องใช้เครื่องที่ผูก · ไม่มีทางเข้าด้วยอีเมลในหน้านี้)
const ownerPad = ref<{ reset: () => void } | null>(null)
async function submitOwnerPin(pin: string) {
  ownerLoading.value = true
  ownerError.value = null
  try {
    clearAccess()
    await ownerPinLogin(pin)
    markLogin()
    await navigateTo('/')
  } catch (e) {
    const err = errorMessage(e)
    ownerError.value =
      err.code === 'INVALID_CREDENTIALS' && err.attemptsLeft != null
        ? `${err.message} (เหลืออีก ${err.attemptsLeft} ครั้ง)`
        : err.code === 'INVALID_CREDENTIALS' ? 'PIN ไม่ถูกต้อง หรือยังไม่ได้ตั้ง PIN เจ้าของร้าน' : err.message
    ownerPad.value?.reset()
  } finally {
    ownerLoading.value = false
  }
}

onMounted(reload)
</script>

<template>
  <div class="px-4 py-10 md:py-16">
    <div class="mx-auto max-w-4xl">
      <header class="mb-8 flex flex-col items-center gap-3 text-center">
        <BrandMark class="size-12" />
        <div>
          <h1 class="m-0 text-2xl font-semibold tracking-tight md:text-[28px]">Ifeew's Thaimassage</h1>
          <p class="m-0 mt-1 text-[15px] text-muted-foreground">ระบบพนักงานและเจ้าของร้าน</p>
        </div>
      </header>

      <Alert v-if="banner" variant="info" class="mx-auto mb-6 max-w-md"><AlertDescription>{{ banner }}</AlertDescription></Alert>

      <div class="mb-6 flex justify-center">
        <SegmentedControl
          v-model="mode"
          :items="[{ value: 'staff', label: 'พนักงาน' }, { value: 'owner', label: 'เจ้าของร้าน' }]"
          label="เข้าสู่ระบบในฐานะ"
        />
      </div>

      <!-- พนักงาน: เลือกชื่อ + PIN -->
      <Card v-if="mode === 'staff'" class="gap-0 py-0">
        <div class="border-b border-border px-6 py-4">
          <SelectField
            v-model="branchId"
            :items="branches"
            item-title="name"
            item-value="branch_id"
            label="สาขา"
            :placeholder="loadingBranches ? 'กำลังโหลดสาขา…' : 'เลือกสาขา'"
            :disabled="loadingBranches || branches.length === 0"
            class="w-full sm:w-72"
          />
        </div>

        <div class="p-6">
          <Alert v-if="listError" variant="destructive" class="mb-4"><AlertDescription>{{ listError }}</AlertDescription></Alert>
          <EmptyState v-if="!branchId" compact title="เลือกสาขาก่อน" description="รายชื่อพนักงานของสาขาจะแสดงที่นี่ แตะชื่อของคุณเพื่อกรอก PIN" />
          <div v-else-if="loadingList && !staff.length" class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4">
            <Skeleton v-for="n in 4" :key="n" class="h-36 rounded-xl" />
          </div>
          <EmptyState v-else-if="staff.length === 0 && !listError" compact title="ยังไม่มีพนักงานที่ตั้ง PIN ในสาขานี้" />
          <div v-else class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4">
            <button
              v-for="s in staff"
              :key="s.user_id"
              type="button"
              :disabled="s.locked"
              class="flex flex-col items-center gap-2 rounded-xl border bg-card p-5 text-center transition-colors focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none disabled:cursor-not-allowed disabled:opacity-60"
              :class="selected?.user_id === s.user_id ? 'border-primary ring-2 ring-primary/30' : 'border-border hover:border-input hover:bg-muted'"
              @click="choose(s)"
            >
              <span class="grid size-14 place-items-center overflow-hidden rounded-full bg-secondary text-xl font-semibold text-heading">
                <img v-if="s.photo_url" :src="s.photo_url" :alt="s.display_name" class="size-full object-cover">
                <template v-else>{{ s.display_name.slice(0, 1) }}</template>
              </span>
              <span class="font-medium text-heading">{{ s.display_name }}</span>
              <Badge v-if="s.locked" variant="danger">ล็อกชั่วคราว</Badge>
              <span v-else-if="s.is_owner" class="text-[13px] text-muted-foreground">เจ้าของร้าน</span>
            </button>
          </div>
        </div>
      </Card>

      <!-- เจ้าของร้าน: PIN อย่างเดียว -->
      <Card v-else class="mx-auto max-w-md gap-0 py-6">
        <CardContent class="px-6">
          <h2 class="m-0 mb-5 text-center text-lg font-semibold">กรอก PIN เจ้าของร้าน</h2>
          <PinPad ref="ownerPad" :loading="ownerLoading" :error="ownerError" @submit="submitOwnerPin" />
        </CardContent>
      </Card>
    </div>

    <Dialog :open="!!selected" @update:open="(v) => !v && !pinLoading && (selected = null)">
      <DialogContent class="sm:max-w-sm" @interact-outside.prevent>
        <DialogHeader>
          <DialogTitle>สวัสดี {{ selected?.display_name }}</DialogTitle>
          <DialogDescription>กรอก PIN 6 หลัก</DialogDescription>
        </DialogHeader>
        <PinPad v-if="selected" ref="pinPad" :loading="pinLoading" :error="pinError" @submit="submitPin" />
      </DialogContent>
    </Dialog>
  </div>
</template>
