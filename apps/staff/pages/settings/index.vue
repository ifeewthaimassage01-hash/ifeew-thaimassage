<script setup lang="ts">
// OWNER: ข้อมูลบริษัทและค่าตั้งค่าระดับบริษัท
definePageMeta({ ownerOnly: true })

const supabase = useSupabaseClient()
const { company, refresh: refreshAccess } = useAccess()

const info = reactive({ name: '', legal_name: '', tax_id: '' })
const settings = reactive({
  cancellation_cutoff_hours: 3,
  large_expense_threshold: 5000,
  staff_pin_max_attempts: 5,
  staff_pin_lockout_minutes: 15,
  staff_idle_lock_minutes: 5,
  booking_slot_minutes: 30,
  booking_buffer_minutes: 10,
  booking_hold_minutes: 15,
  booking_max_advance_days: 30,
  booking_min_lead_minutes: 60,
  booking_max_items: 4,
  deposit_per_person: 100,
  guest_max_active_bookings: 3,
  tracking_token_days_after: 7,
  no_show_grace_minutes: 15,
})
const BOOKING_KEYS = [
  'booking_slot_minutes', 'booking_buffer_minutes', 'booking_hold_minutes', 'booking_max_advance_days',
  'booking_min_lead_minutes', 'booking_max_items', 'deposit_per_person', 'guest_max_active_bookings',
  'tracking_token_days_after', 'no_show_grace_minutes',
] as const
const saving = ref(false)
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)

async function load() {
  if (!company.value) return
  const id = company.value.company_id
  const [c, s] = await Promise.all([
    supabase.from('companies').select('name, legal_name, tax_id').eq('id', id).single(),
    supabase.from('company_settings').select('*').eq('company_id', id).single(),
  ])
  if (c.data) Object.assign(info, { name: c.data.name, legal_name: c.data.legal_name ?? '', tax_id: c.data.tax_id ?? '' })
  if (s.data) {
    Object.assign(settings, {
      cancellation_cutoff_hours: s.data.cancellation_cutoff_hours,
      large_expense_threshold: Number(s.data.large_expense_threshold),
      staff_pin_max_attempts: s.data.staff_pin_max_attempts,
      staff_pin_lockout_minutes: s.data.staff_pin_lockout_minutes,
      staff_idle_lock_minutes: s.data.staff_idle_lock_minutes,
    })
    for (const k of BOOKING_KEYS) settings[k] = Number(s.data[k])
  }
}

async function save() {
  if (!company.value) return
  if (info.tax_id && !/^\d{13}$/.test(info.tax_id)) {
    message.value = { type: 'error', text: 'เลขประจำตัวผู้เสียภาษีต้องเป็นตัวเลข 13 หลัก' }
    return
  }
  saving.value = true
  try {
    const id = company.value.company_id
    await must(
      supabase
        .from('companies')
        .update({ name: info.name.trim(), legal_name: info.legal_name.trim() || null, tax_id: info.tax_id.trim() || null })
        .eq('id', id),
    )
    await must(
      supabase
        .from('company_settings')
        .update({
          cancellation_cutoff_hours: Number(settings.cancellation_cutoff_hours),
          large_expense_threshold: Number(settings.large_expense_threshold),
          staff_pin_max_attempts: Number(settings.staff_pin_max_attempts),
          staff_pin_lockout_minutes: Number(settings.staff_pin_lockout_minutes),
          staff_idle_lock_minutes: Number(settings.staff_idle_lock_minutes),
          ...Object.fromEntries(BOOKING_KEYS.map((k) => [k, Number(settings[k])])),
        })
        .eq('company_id', id),
    )
    message.value = { type: 'success', text: 'บันทึกการตั้งค่าแล้ว' }
    await refreshAccess()
  } catch (e) {
    message.value = { type: 'error', text: errorText(e, 'บันทึกไม่สำเร็จ (ตรวจช่วงค่าที่อนุญาต)') }
  } finally {
    saving.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="max-w-3xl">
    <h1 class="m-0 mb-6 text-2xl font-semibold text-cocoa">ตั้งค่าบริษัท</h1>
    <v-alert v-if="message" :type="message.type" variant="tonal" class="mb-6" closable :text="message.text" @click:close="message = null" />

    <v-card class="mb-6 p-6">
      <p class="m-0 mb-4 text-lg font-medium">ข้อมูลบริษัท</p>
      <v-text-field v-model="info.name" label="ชื่อที่แสดง" />
      <v-text-field v-model="info.legal_name" label="ชื่อนิติบุคคล" />
      <v-text-field v-model="info.tax_id" label="เลขประจำตัวผู้เสียภาษี (13 หลัก)" maxlength="13" inputmode="numeric" />
    </v-card>

    <v-card class="mb-6 p-6">
      <p class="m-0 mb-4 text-lg font-medium">การจองและรายจ่าย</p>
      <div class="grid gap-x-4 md:grid-cols-2">
        <v-text-field v-model="settings.cancellation_cutoff_hours" type="number" label="ยกเลิกการจองได้ก่อนนัด (ชั่วโมง)" hint="0-168" persistent-hint class="mb-2" />
        <v-text-field v-model="settings.large_expense_threshold" type="number" label="รายจ่ายที่ต้องแนบหลักฐาน (บาท)" />
      </div>
    </v-card>

    <v-card class="mb-6 p-6">
      <p class="m-0 mb-4 text-lg font-medium">การจองออนไลน์และมัดจำ</p>
      <div class="grid gap-x-4 md:grid-cols-3">
        <v-select v-model="settings.booking_slot_minutes" :items="[10, 15, 20, 30, 60]" label="ช่วงเวลาเริ่ม (นาที)" />
        <v-text-field v-model="settings.booking_buffer_minutes" type="number" label="เวลาเผื่อทำความสะอาด (นาที)" hint="0-60" persistent-hint class="mb-2" />
        <v-text-field v-model="settings.booking_min_lead_minutes" type="number" label="จองล่วงหน้าขั้นต่ำ (นาที)" />
        <v-text-field v-model="settings.booking_max_advance_days" type="number" label="จองล่วงหน้าได้ไม่เกิน (วัน)" />
        <v-text-field v-model="settings.booking_max_items" type="number" label="จำนวนคนต่อการจอง" hint="1-10" persistent-hint class="mb-2" />
        <v-text-field v-model="settings.deposit_per_person" type="number" label="มัดจำต่อคน (บาท)" />
        <v-text-field v-model="settings.booking_hold_minutes" type="number" label="เวลาให้ชำระมัดจำ (นาที)" hint="5-60" persistent-hint class="mb-2" />
        <v-text-field v-model="settings.guest_max_active_bookings" type="number" label="Guest จองค้างได้ต่อเบอร์" />
        <v-text-field v-model="settings.tracking_token_days_after" type="number" label="ลิงก์ติดตามหมดอายุหลังนัด (วัน)" />
        <v-text-field v-model="settings.no_show_grace_minutes" type="number" label="บันทึกไม่มาตามนัดได้หลัง (นาที)" />
      </div>
    </v-card>

    <v-card class="mb-6 p-6">
      <p class="m-0 mb-4 text-lg font-medium">ความปลอดภัยของพนักงาน</p>
      <div class="grid gap-x-4 md:grid-cols-3">
        <v-text-field v-model="settings.staff_pin_max_attempts" type="number" label="กด PIN ผิดได้ (ครั้ง)" hint="3-10" persistent-hint class="mb-2" />
        <v-text-field v-model="settings.staff_pin_lockout_minutes" type="number" label="ล็อก PIN (นาที)" hint="1-1440" persistent-hint class="mb-2" />
        <v-text-field v-model="settings.staff_idle_lock_minutes" type="number" label="ล็อกหน้าจอเมื่อไม่ใช้งาน (นาที)" hint="1-120" persistent-hint />
      </div>
    </v-card>

    <div class="flex justify-end">
      <v-btn color="primary" :loading="saving" @click="save">บันทึกการตั้งค่า</v-btn>
    </div>
  </div>
</template>
