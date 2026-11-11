<script setup lang="ts">
// OWNER: ข้อมูลบริษัทและค่าตั้งค่าระดับบริษัท
definePageMeta({ ownerOnly: true })

const supabase = useSupabaseClient()
const { company, refresh: refreshAccess } = useAccess()

const info = reactive({ name: '', legal_name: '', tax_id: '' })
const settings = reactive({
  cancellation_cutoff_hours: 3,
  large_expense_threshold: 5000,
  freelance_fuel_amount: 0,
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
      freelance_fuel_amount: Number(s.data.freelance_fuel_amount),
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
          freelance_fuel_amount: Number(settings.freelance_fuel_amount) || 0,
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

// ล้างข้อมูลการใช้งาน (ถาวร): พิมพ์คำยืนยัน → กล่องยืนยัน → ยืนยันตัวตนซ้ำ (step-up)
const CLEAR_WORD = 'ล้างข้อมูล'
const { confirm } = useDialog()
const { run } = useStepUp()
const clearConfirm = ref('')
const clearing = ref(false)
async function clearTransactions() {
  if (!company.value || clearConfirm.value.trim() !== CLEAR_WORD) return
  const ok = await confirm({
    title: 'ล้างข้อมูลการใช้งานทั้งหมด?',
    description: 'การจอง คิว ออเดอร์ บิล การรับเงิน รายจ่าย ค่ามือ การลงเวลา และประวัติทั้งหมดจะถูกลบถาวร กู้คืนไม่ได้ (บัญชี ร้าน สาขา บริการ พนักงาน และลูกค้ายังอยู่)',
    confirmText: 'ล้างข้อมูล',
    destructive: true,
  })
  if (!ok) return
  clearing.value = true
  try {
    const id = company.value.company_id
    await run(() => must(supabase.rpc('owner_clear_transactions', { p_company_id: id, p_confirm: clearConfirm.value.trim() })))
    clearConfirm.value = ''
    message.value = { type: 'success', text: 'ล้างข้อมูลการใช้งานแล้ว' }
  } catch (e) {
    if ((e as Error)?.message !== 'STEP_UP_CANCELLED') message.value = { type: 'error', text: errorText(e, 'ล้างข้อมูลไม่สำเร็จ') }
  } finally {
    clearing.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="max-w-5xl">
    <PageHeader title="ตั้งค่าบริษัท" description="ข้อมูลบริษัท กติกาการจอง มัดจำ และความปลอดภัยของพนักงาน ใช้กับทุกสาขา">
      <template #actions><Button :disabled="saving" @click="save">{{ saving ? 'กำลังบันทึก…' : 'บันทึกการตั้งค่า' }}</Button></template>
    </PageHeader>
    <MessageAlert :message="message" class="mb-6" @close="message = null" />

    <form class="grid gap-8" @submit.prevent="save">
      <section class="grid gap-4 lg:grid-cols-[260px_minmax(0,1fr)] lg:gap-10" aria-labelledby="s-company">
        <div>
          <h2 id="s-company" class="m-0 text-base font-semibold">ข้อมูลบริษัท</h2>
          <p class="m-0 mt-1 text-sm text-muted-foreground">ใช้ในเอกสารและใบเสร็จ</p>
        </div>
        <Card class="grid gap-4 p-5">
          <TextField v-model="info.name" label="ชื่อที่แสดง" />
          <div class="grid gap-4 sm:grid-cols-2">
            <TextField v-model="info.legal_name" label="ชื่อนิติบุคคล" />
            <TextField v-model="info.tax_id" numeric="digits" label="เลขประจำตัวผู้เสียภาษี" hint="ตัวเลข 13 หลัก" maxlength="13" inputmode="numeric" class="num" />
          </div>
        </Card>
      </section>

      <section class="grid gap-4 border-t border-border pt-8 lg:grid-cols-[260px_minmax(0,1fr)] lg:gap-10" aria-labelledby="s-expense">
        <div>
          <h2 id="s-expense" class="m-0 text-base font-semibold">การยกเลิก รายจ่าย และค่าน้ำมัน</h2>
          <p class="m-0 mt-1 text-sm text-muted-foreground">เงื่อนไขที่ลูกค้าและพนักงานเห็น</p>
        </div>
        <Card class="grid gap-4 p-5 sm:grid-cols-2">
          <TextField v-model="settings.cancellation_cutoff_hours" numeric="integer" label="ยกเลิกการจองได้ก่อนนัด" hint="0-168" suffix="ชั่วโมง" />
          <TextField v-model="settings.large_expense_threshold" type="number" label="รายจ่ายที่ต้องแนบหลักฐาน" hint="ตั้งแต่ยอดนี้ขึ้นไป" suffix="บาท" class="num" />
          <TextField
            v-model="settings.freelance_fuel_amount"
            type="number"
            min="0"
            label="ค่าน้ำมันหมอวิ่ง (ต่อครั้ง)"
            hint="ใช้ตอนเรียกคิวให้หมอวิ่งแล้วติ๊ก “มีค่าน้ำมัน” · บันทึกเป็นรายจ่ายของร้าน · 0 = ไม่ใช้"
            suffix="บาท"
            class="num sm:col-span-2"
          />
        </Card>
      </section>

      <section class="grid gap-4 border-t border-border pt-8 lg:grid-cols-[260px_minmax(0,1fr)] lg:gap-10" aria-labelledby="s-booking">
        <div>
          <h2 id="s-booking" class="m-0 text-base font-semibold">การจองออนไลน์และมัดจำ</h2>
          <p class="m-0 mt-1 text-sm text-muted-foreground">ใช้คำนวณเวลาว่างและยอดมัดจำในหน้าจองของลูกค้า</p>
        </div>
        <Card class="grid gap-4 p-5 sm:grid-cols-2 xl:grid-cols-3">
          <SelectField v-model="settings.booking_slot_minutes" :items="[10, 15, 20, 30, 60]" label="ช่วงเวลาเริ่ม (นาที)" />
          <TextField v-model="settings.booking_buffer_minutes" numeric="integer" label="เวลาเผื่อทำความสะอาด" hint="0-60" suffix="นาที" />
          <TextField v-model="settings.booking_min_lead_minutes" numeric="integer" label="จองล่วงหน้าขั้นต่ำ" suffix="นาที" />
          <TextField v-model="settings.booking_max_advance_days" numeric="integer" label="จองล่วงหน้าได้ไม่เกิน" suffix="วัน" />
          <TextField v-model="settings.booking_max_items" numeric="integer" label="จำนวนคนต่อการจอง" hint="1-10" suffix="คน" />
          <TextField v-model="settings.deposit_per_person" type="number" label="มัดจำต่อคน" suffix="บาท" />
          <TextField v-model="settings.booking_hold_minutes" numeric="integer" label="เวลาให้ชำระมัดจำ" hint="5-60" suffix="นาที" />
          <TextField v-model="settings.guest_max_active_bookings" numeric="integer" label="Guest จองค้างได้ต่อเบอร์" suffix="ครั้ง" />
          <TextField v-model="settings.tracking_token_days_after" numeric="integer" label="ลิงก์ติดตามหมดอายุหลังนัด" suffix="วัน" />
          <TextField v-model="settings.no_show_grace_minutes" numeric="integer" label="บันทึกไม่มาตามนัดได้หลัง" suffix="นาที" />
        </Card>
      </section>

      <section class="grid gap-4 border-t border-border pt-8 lg:grid-cols-[260px_minmax(0,1fr)] lg:gap-10" aria-labelledby="s-security">
        <div>
          <h2 id="s-security" class="m-0 text-base font-semibold">ความปลอดภัยของพนักงาน</h2>
          <p class="m-0 mt-1 text-sm text-muted-foreground">PIN และการออกจากระบบอัตโนมัติ</p>
        </div>
        <Card class="grid gap-4 p-5 sm:grid-cols-3">
          <TextField v-model="settings.staff_pin_max_attempts" numeric="integer" label="กด PIN ผิดได้" hint="3-10" suffix="ครั้ง" />
          <TextField v-model="settings.staff_pin_lockout_minutes" numeric="integer" label="ล็อก PIN" hint="1-1440" suffix="นาที" />
          <p class="m-0 self-center text-sm text-muted-foreground">ออกจากระบบอัตโนมัติทุกวันตอนตี 3 · เข้าสู่ระบบด้วย PIN = ลงเวลาเข้างานของวันนั้น</p>
        </Card>
      </section>

      <div class="flex justify-end border-t border-border pt-6">
        <Button type="submit" :disabled="saving">{{ saving ? 'กำลังบันทึก…' : 'บันทึกการตั้งค่า' }}</Button>
      </div>
    </form>

    <!-- โซนอันตราย: แยกจากฟอร์มตั้งค่า (ไม่ส่งไปกับปุ่มบันทึก) -->
    <section class="mt-10 grid gap-4 border-t border-border pt-8 lg:grid-cols-[260px_minmax(0,1fr)] lg:gap-10" aria-labelledby="s-danger">
      <div>
        <h2 id="s-danger" class="m-0 text-base font-semibold text-danger-ink">ล้างข้อมูลการใช้งาน</h2>
        <p class="m-0 mt-1 text-sm text-muted-foreground">ใช้ก่อนเริ่มเปิดร้านจริง หลังทดลองระบบ</p>
      </div>
      <Card class="grid gap-4 border-danger/40 p-5">
        <div class="grid gap-2 text-[15px]">
          <p class="m-0"><span class="font-medium text-heading">ลบถาวร:</span> การจอง มัดจำ คิว ออเดอร์ บิล การรับเงิน/คืนเงิน สลิป ทิป กะ รายจ่าย ปิดยอดรายวัน ค่ามือ การลงเวลา งวดบัญชี เลขเอกสาร และประวัติการใช้งาน</p>
          <p class="m-0"><span class="font-medium text-heading">เก็บไว้:</span> บัญชีและรหัสผ่าน/PIN ร้าน สาขา บริการและราคา เตียง/อุปกรณ์ พนักงาน และลูกค้า</p>
        </div>
        <form class="grid gap-3 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end" @submit.prevent="clearTransactions">
          <TextField v-model="clearConfirm" :label="`พิมพ์ “${CLEAR_WORD}” เพื่อยืนยัน`" autocomplete="off" />
          <Button type="submit" variant="destructive" :disabled="clearing || clearConfirm.trim() !== CLEAR_WORD">
            {{ clearing ? 'กำลังล้าง…' : 'ล้างข้อมูลทั้งหมด' }}
          </Button>
        </form>
      </Card>
    </section>
  </div>
</template>
