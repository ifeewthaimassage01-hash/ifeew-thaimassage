<script setup lang="ts">
// โปรไฟล์ (settings two-column): ป้ายด้านซ้าย + แผงด้านขวา, หนึ่งปุ่มบันทึกต่อแผง, การลบข้อมูลอยู่ท้ายสุด
import { Download } from '@lucide/vue'
import { personNameSchema, thaiPhoneSchema } from '@ifeew/shared'

definePageMeta({ middleware: 'auth' })
useHead({ title: "โปรไฟล์ — Ifeew's Thaimassage" })

const supabase = useSupabaseClient()
const user = useSupabaseUser()
const { code } = useCompany()
const { customer, refresh } = useCustomer()

const form = reactive({ firstName: '', lastName: '', phone: '' })
const marketing = ref(false)
const saving = ref<'profile' | 'privacy' | null>(null)
const saved = ref<'profile' | 'privacy' | null>(null)
const message = ref<{ type: 'success' | 'destructive'; text: string } | null>(null)
const deleteDialog = ref(false)
const deleteReason = ref('')
const deleting = ref(false)

watch(
  customer,
  (c) => {
    if (!c) return
    Object.assign(form, { firstName: c.first_name, lastName: c.last_name, phone: c.phone })
    marketing.value = c.consents.MARKETING?.granted ?? false
  },
  { immediate: true },
)

onMounted(() => refresh().catch(() => {}))

const privacyDate = computed(() => {
  const p = customer.value?.consents.PRIVACY_NOTICE
  return p ? new Date(p.recorded_at).toLocaleDateString('th-TH', { dateStyle: 'medium', timeZone: 'Asia/Bangkok' }) : null
})

async function saveProfile() {
  message.value = null
  saved.value = null
  const first = personNameSchema.safeParse(form.firstName)
  const phone = thaiPhoneSchema.safeParse(form.phone)
  if (!first.success || !phone.success) {
    message.value = { type: 'destructive', text: 'กรุณาตรวจสอบชื่อและเบอร์โทร' }
    return
  }
  saving.value = 'profile'
  const { error } = await supabase.rpc('update_my_customer', {
    p_company_code: code, p_first_name: first.data, p_last_name: form.lastName.trim(), p_phone: phone.data,
  })
  saving.value = null
  if (error) message.value = { type: 'destructive', text: error.message }
  else saved.value = 'profile'
  await refresh()
}

async function savePrivacy() {
  message.value = null
  saved.value = null
  saving.value = 'privacy'
  const { error } = await supabase.rpc('set_my_marketing_consent', { p_company_code: code, p_granted: marketing.value })
  saving.value = null
  if (error) message.value = { type: 'destructive', text: error.message }
  else saved.value = 'privacy'
  await refresh()
}

async function exportData() {
  const { data, error } = await supabase.rpc('export_my_data', { p_company_code: code })
  if (error) {
    message.value = { type: 'destructive', text: error.message }
    return
  }
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `ifeew-my-data-${new Date().toISOString().slice(0, 10)}.json`
  a.click()
  URL.revokeObjectURL(url)
}

async function requestDeletion() {
  deleting.value = true
  const { error } = await supabase.rpc('request_my_data_deletion', { p_company_code: code, p_reason: deleteReason.value })
  deleting.value = false
  deleteDialog.value = false
  message.value = error
    ? { type: 'destructive', text: error.message }
    : { type: 'success', text: 'ส่งคำขอลบข้อมูลแล้ว ร้านจะดำเนินการและแจ้งผลให้ทราบ' }
  await refresh()
}
</script>

<template>
  <div class="grid gap-6">
    <div>
      <h1 class="m-0 text-[28px] font-semibold leading-tight tracking-tight">โปรไฟล์</h1>
      <p class="m-0 mt-1 text-muted-foreground">{{ user?.email }}</p>
    </div>
    <Alert v-if="message" :variant="message.type"><AlertDescription>{{ message.text }}</AlertDescription></Alert>

    <div v-if="!customer" class="grid gap-4"><Skeleton class="h-56 rounded-xl" /><Skeleton class="h-40 rounded-xl" /></div>

    <template v-else>
      <!-- ข้อมูลส่วนตัว -->
      <section class="grid gap-4 md:grid-cols-[minmax(0,1fr)_minmax(0,2fr)] md:gap-10" aria-labelledby="s-profile">
        <div>
          <h2 id="s-profile" class="m-0 text-lg font-semibold">ข้อมูลส่วนตัว</h2>
          <p class="m-0 mt-1 text-[15px] text-muted-foreground">ร้านใช้ชื่อและเบอร์นี้ยืนยันนัดและติดต่อเรื่องการจอง</p>
        </div>
        <form class="grid gap-4 rounded-xl bg-card p-5 ring-1 ring-border" novalidate @submit.prevent="saveProfile">
          <div class="grid grid-cols-2 gap-3">
            <div class="grid gap-1.5"><Label for="p-first">ชื่อ</Label><Input id="p-first" v-model="form.firstName" autocomplete="given-name" /></div>
            <div class="grid gap-1.5"><Label for="p-last">นามสกุล</Label><Input id="p-last" v-model="form.lastName" autocomplete="family-name" /></div>
          </div>
          <div class="grid gap-1.5 sm:w-1/2"><Label for="p-phone">เบอร์โทร</Label><Input id="p-phone" v-model="form.phone" type="tel" inputmode="tel" autocomplete="tel" class="num" /></div>
          <div class="flex items-center justify-end gap-3">
            <span v-if="saved === 'profile'" class="text-sm text-tint-green-ink" role="status">บันทึกแล้ว</span>
            <Button type="submit" :disabled="saving === 'profile'">{{ saving === 'profile' ? 'กำลังบันทึก…' : 'บันทึก' }}</Button>
          </div>
        </form>
      </section>

      <!-- ความเป็นส่วนตัว -->
      <section class="grid gap-4 border-t border-border/70 pt-6 md:grid-cols-[minmax(0,1fr)_minmax(0,2fr)] md:gap-10" aria-labelledby="s-privacy">
        <div>
          <h2 id="s-privacy" class="m-0 text-lg font-semibold">ความเป็นส่วนตัว</h2>
          <p class="m-0 mt-1 text-[15px] text-muted-foreground">
            รับทราบนโยบายฉบับ <span class="num">{{ customer.consents.PRIVACY_NOTICE?.version ?? '—' }}</span>
            <template v-if="privacyDate"> เมื่อ {{ privacyDate }}</template>
          </p>
        </div>
        <div class="grid gap-4 rounded-xl bg-card p-5 ring-1 ring-border">
          <div class="flex items-start justify-between gap-4">
            <div>
              <Label for="p-marketing" class="text-[15px]">รับข่าวสารและโปรโมชัน</Label>
              <p class="m-0 mt-0.5 text-sm text-muted-foreground">ส่วนลดและเวลาพิเศษของสาขา เปลี่ยนใจได้ทุกเมื่อ</p>
            </div>
            <Switch id="p-marketing" v-model="marketing" />
          </div>
          <div class="flex items-center justify-end gap-3">
            <span v-if="saved === 'privacy'" class="text-sm text-tint-green-ink" role="status">บันทึกแล้ว</span>
            <Button :disabled="saving === 'privacy'" @click="savePrivacy">{{ saving === 'privacy' ? 'กำลังบันทึก…' : 'บันทึก' }}</Button>
          </div>
        </div>
      </section>

      <!-- ข้อมูลของฉัน -->
      <section class="grid gap-4 border-t border-border/70 pt-6 md:grid-cols-[minmax(0,1fr)_minmax(0,2fr)] md:gap-10" aria-labelledby="s-data">
        <div>
          <h2 id="s-data" class="m-0 text-lg font-semibold">ข้อมูลของฉัน</h2>
          <p class="m-0 mt-1 text-[15px] text-muted-foreground">ดาวน์โหลดสำเนา หรือขอให้ร้านลบข้อมูลส่วนบุคคล</p>
        </div>
        <div class="grid gap-4 rounded-xl bg-card p-5 ring-1 ring-border">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <p class="m-0 text-[15px]">ไฟล์ JSON ที่มีข้อมูลส่วนตัว การจอง และความยินยอมทั้งหมด</p>
            <Button variant="outline" @click="exportData"><Download /> ดาวน์โหลด</Button>
          </div>
          <div class="flex flex-wrap items-center justify-between gap-3 border-t border-border/70 pt-4">
            <p class="m-0 text-[15px]">
              <template v-if="customer.pending_deletion">ส่งคำขอลบข้อมูลแล้ว รอร้านดำเนินการ</template>
              <template v-else>ลบชื่อ เบอร์โทร และอีเมล แล้วปิดบัญชีนี้</template>
            </p>
            <Button
              variant="outline"
              class="border-destructive/40 text-destructive hover:bg-tint-danger"
              :disabled="customer.pending_deletion"
              @click="deleteDialog = true"
            >ขอลบข้อมูล</Button>
          </div>
        </div>
      </section>
    </template>

    <Dialog v-model:open="deleteDialog">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>ขอลบข้อมูลส่วนบุคคล</DialogTitle>
          <DialogDescription>
            ร้านจะลบชื่อ เบอร์โทร และอีเมลของ {{ user?.email }} และปิดบัญชีนี้ ข้อมูลการเงินที่กฎหมายกำหนดจะถูกเก็บไว้โดยไม่ระบุตัวตน
          </DialogDescription>
        </DialogHeader>
        <div class="grid gap-1.5">
          <Label for="del-reason">เหตุผล <span class="font-normal text-muted-foreground">(ไม่บังคับ)</span></Label>
          <Textarea id="del-reason" v-model="deleteReason" rows="2" />
        </div>
        <DialogFooter class="gap-2">
          <Button variant="outline" @click="deleteDialog = false">ยกเลิก</Button>
          <Button variant="destructive" :disabled="deleting" @click="requestDeletion">{{ deleting ? 'กำลังส่ง…' : 'ส่งคำขอลบข้อมูล' }}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
