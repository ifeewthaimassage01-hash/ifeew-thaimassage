<script setup lang="ts">
import { RefreshCw } from '@lucide/vue'
import { emailSchema } from '@ifeew/shared'
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

const email = ref('')
const password = ref('')
const ownerLoading = ref(false)
const ownerError = ref<string | null>(null)

const queryErrors: Record<string, string> = {
  not_staff: 'บัญชีนี้ไม่ใช่บัญชีพนักงานหรือเจ้าของร้าน',
  access: 'ไม่สามารถตรวจสอบสิทธิ์ได้ กรุณาเข้าสู่ระบบใหม่',
  idle: 'ออกจากระบบอัตโนมัติเนื่องจากไม่มีการใช้งาน',
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

function choose(s: DeviceStaff) {
  if (s.locked) return
  selected.value = s
  pinError.value = null
}

async function submitPin(pin: string) {
  if (!selected.value || !branchId.value) return
  pinLoading.value = true
  pinError.value = null
  try {
    clearAccess()
    await branchPinLogin(branchId.value, selected.value.user_id, pin)
    await navigateTo('/')
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

async function ownerLogin() {
  ownerError.value = null
  const parsed = emailSchema.safeParse(email.value)
  if (!parsed.success || !password.value) {
    ownerError.value = 'กรุณากรอกอีเมลและรหัสผ่านให้ถูกต้อง'
    return
  }
  ownerLoading.value = true
  try {
    clearAccess()
    const { error } = await supabase.auth.signInWithPassword({ email: parsed.data, password: password.value })
    if (error) {
      ownerError.value = 'อีเมลหรือรหัสผ่านไม่ถูกต้อง'
      return
    }
    password.value = ''
    await navigateTo('/')
  } finally {
    ownerLoading.value = false
  }
}

// ลืมรหัสผ่าน (เจ้าของร้าน): ส่งลิงก์ไปหน้า /set-password — ไม่บอกว่ามีอีเมลนี้ในระบบหรือไม่
const resetSent = ref(false)
async function forgotPassword() {
  ownerError.value = null
  const parsed = emailSchema.safeParse(email.value)
  if (!parsed.success) {
    ownerError.value = 'กรอกอีเมลก่อน แล้วกด “ลืมรหัสผ่าน”'
    return
  }
  ownerLoading.value = true
  try {
    await supabase.auth.resetPasswordForEmail(parsed.data, { redirectTo: `${window.location.origin}/set-password` })
    resetSent.value = true
  } finally {
    ownerLoading.value = false
  }
}

// เจ้าของร้าน: PIN อย่างเดียว (ไม่ต้องใช้เครื่องที่ผูก)
const useEmail = ref(false)
const ownerPad = ref<{ reset: () => void } | null>(null)
async function submitOwnerPin(pin: string) {
  ownerLoading.value = true
  ownerError.value = null
  try {
    clearAccess()
    await ownerPinLogin(pin)
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
        <div class="flex flex-wrap items-end justify-between gap-3 border-b border-border px-6 py-4">
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
          <Button variant="ghost" size="icon" aria-label="โหลดรายชื่อใหม่" :disabled="loadingList || loadingBranches" @click="reload">
            <RefreshCw :class="loadingList || loadingBranches ? 'animate-spin' : ''" />
          </Button>
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
              :class="selected?.user_id === s.user_id ? 'border-primary ring-2 ring-primary/30' : 'border-border hover:border-input hover:bg-muted/40'"
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

      <!-- เจ้าของร้าน: PIN อย่างเดียว (สำรอง: อีเมล + รหัสผ่าน สำหรับครั้งแรก/ลืม PIN) -->
      <Card v-else class="mx-auto max-w-md gap-0 py-6">
        <CardContent class="px-6">
          <template v-if="!useEmail">
            <h2 class="m-0 mb-5 text-center text-lg font-semibold">กรอก PIN เจ้าของร้าน</h2>
            <PinPad ref="ownerPad" :loading="ownerLoading" :error="ownerError" @submit="submitOwnerPin" />
            <Button variant="link" class="mt-4 w-full" @click="useEmail = true; ownerError = null">
              เข้าด้วยอีเมล (ครั้งแรก / ลืม PIN)
            </Button>
          </template>
          <form v-else class="grid gap-4" novalidate @submit.prevent="ownerLogin">
            <h2 class="m-0 text-lg font-semibold">เข้าด้วยอีเมล</h2>
            <TextField v-model="email" label="อีเมล" type="email" autocomplete="username" />
            <TextField v-model="password" label="รหัสผ่าน" type="password" autocomplete="current-password" />
            <Alert v-if="ownerError" variant="destructive"><AlertDescription>{{ ownerError }}</AlertDescription></Alert>
            <Button type="submit" size="lg" class="w-full" :disabled="ownerLoading">{{ ownerLoading ? 'กำลังเข้าสู่ระบบ…' : 'เข้าสู่ระบบ' }}</Button>
            <Alert v-if="resetSent" variant="info">
              <AlertDescription>ถ้ามีบัญชีนี้ในระบบ จะได้รับอีเมลลิงก์ตั้งรหัสผ่านใหม่ (ตรวจกล่องจดหมายขยะด้วย)</AlertDescription>
            </Alert>
            <div class="flex flex-wrap justify-between gap-2">
              <Button type="button" variant="ghost" size="sm" :disabled="ownerLoading" @click="forgotPassword">ลืมรหัสผ่าน</Button>
              <Button type="button" variant="ghost" size="sm" @click="useEmail = false; ownerError = null">กลับไปใช้ PIN</Button>
            </div>
            <p class="m-0 text-center text-sm text-muted-foreground">เข้าแล้วตั้ง PIN ที่เมนู “ตั้งค่าเครื่อง” → “PIN เจ้าของร้าน”</p>
          </form>
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
