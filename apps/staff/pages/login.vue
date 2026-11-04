<script setup lang="ts">
import { emailSchema } from '@ifeew/shared'
import type { DeviceInfo, DeviceStaff } from '~/composables/useStaffDevice'

definePageMeta({ layout: 'blank' })

const route = useRoute()
const supabase = useSupabaseClient()
const { token, listStaff, pinLogin, forget, errorMessage } = useStaffDevice()
const { clear: clearAccess } = useAccess()

const mode = ref<'staff' | 'owner'>(token.value ? 'staff' : 'owner')
const device = ref<DeviceInfo | null>(null)
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

async function loadStaff() {
  if (!token.value) return
  loadingList.value = true
  listError.value = null
  try {
    const res = await listStaff()
    device.value = res.device
    staff.value = res.staff
  } catch (e) {
    const err = errorMessage(e)
    listError.value = err.message
    if (err.code === 'DEVICE_INVALID') forget()
  } finally {
    loadingList.value = false
  }
}

function choose(s: DeviceStaff) {
  if (s.locked) return
  selected.value = s
  pinError.value = null
}

async function submitPin(pin: string) {
  if (!selected.value) return
  pinLoading.value = true
  pinError.value = null
  try {
    clearAccess()
    await pinLogin(selected.value.user_id, pin)
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
    await navigateTo('/mfa')
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

onMounted(loadStaff)
</script>

<template>
  <div class="min-h-screen bg-cream px-4 py-10">
    <div class="mx-auto max-w-4xl">
      <header class="mb-8 text-center">
        <h1 class="m-0 text-3xl font-semibold text-cocoa">Ifeew's Thaimassage</h1>
        <p class="m-0 mt-2 text-light-brown">ระบบพนักงาน</p>
      </header>

      <v-alert v-if="banner" type="info" variant="tonal" class="mb-6" :text="banner" />

      <v-btn-toggle v-model="mode" mandatory color="primary" class="mb-6 flex justify-center" rounded="xl">
        <v-btn value="staff" prepend-icon="mdi-account-group-outline">พนักงาน</v-btn>
        <v-btn value="owner" prepend-icon="mdi-shield-account-outline">เจ้าของร้าน</v-btn>
      </v-btn-toggle>

      <!-- พนักงาน: เลือกชื่อ + PIN -->
      <v-card v-if="mode === 'staff'" class="p-6">
        <template v-if="!token">
          <div class="py-8 text-center">
            <v-icon icon="mdi-tablet-cellphone" size="48" color="primary" />
            <p class="mt-4 text-lg">เครื่องนี้ยังไม่ได้ผูกกับสาขา</p>
            <p class="text-sm text-light-brown">ให้เจ้าของร้านเข้าสู่ระบบ แล้วผูกเครื่องที่เมนู “ตั้งค่าเครื่อง”</p>
          </div>
        </template>

        <template v-else>
          <div class="mb-4 flex items-center justify-between">
            <div>
              <p class="m-0 text-lg font-medium">{{ device?.branch_name ?? 'กำลังโหลด…' }}</p>
              <p class="m-0 text-sm text-light-brown">{{ device?.device_name }}</p>
            </div>
            <v-btn variant="text" icon="mdi-refresh" aria-label="โหลดใหม่" :loading="loadingList" @click="loadStaff" />
          </div>

          <v-alert v-if="listError" type="error" variant="tonal" class="mb-4" :text="listError" />

          <div v-if="!loadingList && staff.length === 0 && !listError" class="py-8 text-center text-light-brown">
            ยังไม่มีพนักงานที่ตั้ง PIN ในสาขานี้
          </div>

          <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4">
            <v-card
              v-for="s in staff"
              :key="s.user_id"
              :disabled="s.locked"
              class="cursor-pointer p-5 text-center"
              :class="selected?.user_id === s.user_id ? 'ring-2 ring-light-brown' : ''"
              @click="choose(s)"
            >
              <v-avatar color="secondary" size="56" class="mb-3">
                <v-img v-if="s.photo_url" :src="s.photo_url" cover />
                <span v-else class="text-xl">{{ s.display_name.slice(0, 1) }}</span>
              </v-avatar>
              <p class="m-0 font-medium">{{ s.display_name }}</p>
              <p v-if="s.locked" class="m-0 mt-1 text-xs text-red-700">ล็อกชั่วคราว</p>
            </v-card>
          </div>
        </template>
      </v-card>

      <!-- เจ้าของร้าน: อีเมล + รหัสผ่าน แล้วต่อด้วย MFA -->
      <v-card v-else class="mx-auto max-w-md p-6">
        <v-form @submit.prevent="ownerLogin">
          <v-text-field v-model="email" label="อีเมล" type="email" autocomplete="username" class="mb-2" />
          <v-text-field
            v-model="password"
            label="รหัสผ่าน"
            type="password"
            autocomplete="current-password"
            class="mb-2"
          />
          <v-alert v-if="ownerError" type="error" variant="tonal" class="mb-4" :text="ownerError" />
          <v-btn type="submit" color="primary" block :loading="ownerLoading">เข้าสู่ระบบ</v-btn>
          <v-btn variant="text" block class="mt-2" :disabled="ownerLoading" @click="forgotPassword">ลืมรหัสผ่าน</v-btn>
          <v-alert v-if="resetSent" type="info" variant="tonal" class="mt-2"
            text="ถ้ามีบัญชีนี้ในระบบ จะได้รับอีเมลลิงก์ตั้งรหัสผ่านใหม่ (ตรวจกล่องจดหมายขยะด้วย)" />
        </v-form>
        <p class="mb-0 mt-4 text-center text-sm text-light-brown">บัญชีเจ้าของร้านต้องยืนยันด้วยแอป Authenticator ทุกครั้ง</p>
      </v-card>
    </div>

    <v-dialog :model-value="!!selected" max-width="420" persistent>
      <v-card v-if="selected" class="p-6">
        <div class="mb-4 flex items-center justify-between">
          <p class="m-0 text-lg font-medium">สวัสดี {{ selected.display_name }}</p>
          <v-btn icon="mdi-close" variant="text" aria-label="ปิด" :disabled="pinLoading" @click="selected = null" />
        </div>
        <p class="mb-4 mt-0 text-sm text-light-brown">กรอก PIN 6 หลัก</p>
        <PinPad ref="pinPad" :loading="pinLoading" :error="pinError" @submit="submitPin" />
      </v-card>
    </v-dialog>
  </div>
</template>
