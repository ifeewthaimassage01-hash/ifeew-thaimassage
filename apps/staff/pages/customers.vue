<script setup lang="ts">
// ลูกค้า (Guest ทั้งหมด): ค้นหาด้วยเบอร์เต็ม (ผลปิดบัง) -> เปิดดูรายละเอียด (บันทึก audit) -> แก้ไข / จับคู่
import { CalendarClock, Link2, MapPin, Search, UserPlus, Users } from '@lucide/vue'
import {
  bangkokDateLong,
  bangkokTime,
  bookingStatusLabels,
  depositStatusLabels,
  formatBaht,
  formatDuration,
  personNameSchema,
  reasonSchema,
  thaiPhoneSchema,
  type BookingStatus,
  type CustomerDetail,
} from '@ifeew/shared'

type SearchRow = { customer_id: string; display_name: string; phone_masked: string; is_member: boolean; created_at: string }

const supabase = useSupabaseClient()
const { company } = useAccess()

const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)
const ok = (text: string) => (message.value = { type: 'success', text })
const fail = (e: unknown, fallback?: string) => (message.value = { type: 'error', text: errorText(e, fallback) })

// ---------------------------------------------------------------------------
// ค้นหา
// ---------------------------------------------------------------------------
const phone = ref('')
const searching = ref(false)
const results = ref<SearchRow[] | null>(null)

async function search() {
  const p = thaiPhoneSchema.safeParse(phone.value)
  if (!p.success || !company.value) {
    fail(null, 'กรุณากรอกเบอร์โทรให้ครบ เช่น 0812345678')
    return
  }
  searching.value = true
  message.value = null
  try {
    results.value = (await must(
      supabase.rpc('search_customers_by_phone', { p_company_id: company.value.company_id, p_phone: p.data }),
    )) as SearchRow[]
    selected.value = null
  } catch (e) {
    fail(e)
  } finally {
    searching.value = false
  }
}

// ค้นหาจากช่องค้นหาบน topbar (/customers?phone=...)
const route = useRoute()
watch(
  [() => route.query.phone, () => company.value?.company_id],
  ([q, cid]) => {
    if (typeof q !== 'string' || !q || !cid) return
    phone.value = q
    search()
  },
  { immediate: true },
)

// ---------------------------------------------------------------------------
// รายละเอียด + แก้ไข
// ---------------------------------------------------------------------------
const selected = ref<CustomerDetail | null>(null)
const editForm = reactive({ first_name: '', last_name: '', phone: '', email: '', staff_note: '' })
const saving = ref(false)

// ประวัติการจอง: สีป้ายสถานะ + แยกนัดที่จะถึง / ที่ผ่านมา
const bookingTone: Record<BookingStatus, string> = {
  PENDING: 'bg-pending-soft text-pending-ink',
  CONFIRMED: 'bg-success-soft text-success-ink',
  CHECKED_IN: 'bg-success-soft text-success-ink',
  COMPLETED: 'bg-secondary text-heading',
  CANCELLED: 'bg-danger-soft text-danger-ink',
  NO_SHOW: 'bg-danger-soft text-danger-ink',
  EXPIRED: 'bg-muted text-muted-foreground',
}
const isUpcoming = (b: CustomerDetail['bookings'][number]) =>
  ['PENDING', 'CONFIRMED', 'CHECKED_IN'].includes(b.status) && new Date(b.ends_at).getTime() > Date.now()
const upcomingBookings = computed(() => (selected.value?.bookings ?? []).filter(isUpcoming).reverse())
const pastBookings = computed(() => (selected.value?.bookings ?? []).filter((b) => !isUpcoming(b)))
const bookingGroups = computed(() =>
  [
    { key: 'upcoming', label: 'นัดที่จะถึง', items: upcomingBookings.value },
    { key: 'past', label: 'ที่ผ่านมา', items: pastBookings.value },
  ].filter((g) => g.items.length),
)

async function open(row: SearchRow) {
  try {
    selected.value = (await must(supabase.rpc('get_customer', { p_customer_id: row.customer_id }))) as unknown as CustomerDetail
    const c = selected.value
    Object.assign(editForm, {
      first_name: c.first_name, last_name: c.last_name, phone: c.phone ?? '', email: c.email ?? '', staff_note: c.staff_note ?? '',
    })
  } catch (e) {
    fail(e)
  }
}

async function saveCustomer() {
  const c = selected.value
  if (!c) return
  const first = personNameSchema.safeParse(editForm.first_name)
  const ph = thaiPhoneSchema.safeParse(editForm.phone)
  if (!first.success || !ph.success) {
    fail(null, 'กรุณาตรวจสอบชื่อและเบอร์โทร')
    return
  }
  saving.value = true
  try {
    await must(
      supabase.rpc('update_customer', {
        p_customer_id: c.customer_id,
        p_first_name: first.data,
        p_last_name: editForm.last_name.trim(),
        p_phone: ph.data,
        p_email: editForm.email.trim() || null,
        p_staff_note: editForm.staff_note.trim() || null,
      }),
    )
    ok('บันทึกข้อมูลลูกค้าแล้ว')
    await open({ customer_id: c.customer_id } as SearchRow)
  } catch (e) {
    fail(e, 'บันทึกไม่สำเร็จ')
  } finally {
    saving.value = false
  }
}

// ---------------------------------------------------------------------------
// จับคู่ลูกค้า -> ลูกค้ารายอื่นที่เบอร์เดียวกัน (พนักงานยืนยัน)
// ---------------------------------------------------------------------------
const mergeDialog = ref(false)
const mergeSource = ref<SearchRow | null>(null)
const mergeTarget = ref<string | null>(null)
const mergeReason = ref('')
const mergeTargets = computed(() =>
  (results.value ?? [])
    .filter((r) => r.customer_id !== mergeSource.value?.customer_id)
    .map((r) => ({ value: r.customer_id, title: `${r.display_name} · ${r.phone_masked}` })),
)

function openMerge(row: SearchRow) {
  mergeSource.value = row
  mergeTarget.value = mergeTargets.value[0]?.value ?? null
  mergeReason.value = ''
  mergeDialog.value = true
}

async function submitMerge() {
  const reason = reasonSchema.safeParse(mergeReason.value)
  if (!mergeSource.value || !mergeTarget.value || !reason.success) {
    fail(null, 'กรุณาเลือกลูกค้าปลายทางและระบุเหตุผล')
    return
  }
  saving.value = true
  try {
    await must(
      supabase.rpc('merge_customers', {
        p_source_id: mergeSource.value.customer_id, p_target_id: mergeTarget.value, p_reason: reason.data,
      }),
    )
    mergeDialog.value = false
    ok('จับคู่ลูกค้าแล้ว')
    await search()
  } catch (e) {
    fail(e, 'จับคู่ไม่สำเร็จ')
  } finally {
    saving.value = false
  }
}

// ---------------------------------------------------------------------------
// เพิ่มลูกค้า (Walk-in / โทรจอง)
// ---------------------------------------------------------------------------
const createDialog = ref(false)
const createForm = reactive({ first_name: '', last_name: '', phone: '', email: '', staff_note: '', privacy: false })

function openCreate() {
  Object.assign(createForm, { first_name: '', last_name: '', phone: phone.value, email: '', staff_note: '', privacy: false })
  createDialog.value = true
}

async function submitCreate() {
  const first = personNameSchema.safeParse(createForm.first_name)
  const ph = thaiPhoneSchema.safeParse(createForm.phone)
  if (!first.success || !ph.success || !company.value) {
    fail(null, 'กรุณาตรวจสอบชื่อและเบอร์โทร')
    return
  }
  if (!createForm.privacy) {
    fail(null, 'กรุณาแจ้งนโยบายความเป็นส่วนตัวให้ลูกค้ารับทราบก่อน')
    return
  }
  saving.value = true
  try {
    await must(
      supabase.rpc('create_customer', {
        p_company_id: company.value.company_id,
        p_first_name: first.data,
        p_last_name: createForm.last_name.trim(),
        p_phone: ph.data,
        p_email: createForm.email.trim() || null,
        p_staff_note: createForm.staff_note.trim() || null,
        p_privacy_acknowledged: true,
      }),
    )
    createDialog.value = false
    phone.value = ph.data
    ok('เพิ่มลูกค้าแล้ว')
    await search()
  } catch (e) {
    fail(e, 'เพิ่มลูกค้าไม่สำเร็จ')
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <!-- ความกว้างเท่าหน้าการจอง (max-w-4xl กึ่งกลาง) -->
  <div class="mx-auto max-w-4xl">
    <PageHeader title="ลูกค้า" description="ค้นหาด้วยเบอร์โทรเต็มเท่านั้น ผลลัพธ์แสดงข้อมูลบางส่วน และการเปิดดูรายละเอียดจะถูกบันทึก">
      <template #actions><Button variant="outline" @click="openCreate"><UserPlus /> เพิ่มลูกค้า</Button></template>
    </PageHeader>

    <MessageAlert :message="message" class="mb-4" @close="message = null" />

      <form class="mb-6 flex flex-wrap items-end gap-3 rounded-xl border border-border bg-card p-4" @submit.prevent="search">
        <TextField v-model="phone" numeric="digits" label="เบอร์โทรเต็ม" type="tel" inputmode="tel" class="num min-w-[240px] flex-1" autofocus />
        <Button type="submit" :disabled="searching"><Search /> {{ searching ? 'กำลังค้นหา…' : 'ค้นหา' }}</Button>
      </form>

      <EmptyState v-if="!results" title="ค้นหาลูกค้าด้วยเบอร์โทร" description="กรอกเบอร์โทรเต็มของลูกค้าแล้วกดค้นหา" />
      <div v-else class="grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)]">
        <SectionCard title="ผลการค้นหา" :description="`${results.length} รายการ`" flush>
          <EmptyState v-if="!results.length" compact title="ไม่พบลูกค้าเบอร์นี้" class="m-5">
            <Button variant="outline" size="sm" @click="openCreate">เพิ่มเป็นลูกค้าใหม่</Button>
          </EmptyState>
          <ul v-else class="m-0 grid list-none p-0">
            <li v-for="r in results" :key="r.customer_id" class="border-b border-border last:border-0">
              <div class="flex items-center gap-3 px-3 py-2" :class="selected?.customer_id === r.customer_id ? 'bg-secondary' : ''">
                <button
                  type="button"
                  class="flex min-w-0 flex-1 items-center gap-3 rounded-lg px-2 py-1.5 text-left transition-colors hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
                  :aria-pressed="selected?.customer_id === r.customer_id"
                  @click="open(r)"
                >
                  <span class="grid size-9 shrink-0 place-items-center rounded-full bg-secondary text-sm font-semibold text-heading">{{ r.display_name.slice(0, 1) }}</span>
                  <span class="min-w-0">
                    <span class="block truncate font-medium text-heading">{{ r.display_name }}</span>
                    <span class="num block text-sm text-muted-foreground">{{ r.phone_masked }}</span>
                  </span>
                </button>
                <Button v-if="results.length > 1" variant="ghost" size="sm" @click="openMerge(r)"><Link2 /> จับคู่</Button>
              </div>
            </li>
          </ul>
        </SectionCard>

        <div v-if="selected" class="grid gap-6">
        <SectionCard :title="`${selected.first_name} ${selected.last_name}`.trim()"
          description="แก้ชื่อ เบอร์โทร อีเมล และหมายเหตุของลูกค้าได้">
          <form class="grid gap-4" @submit.prevent="saveCustomer">
            <div class="grid gap-4 sm:grid-cols-2">
              <TextField v-model="editForm.first_name" label="ชื่อ" />
              <TextField v-model="editForm.last_name" label="นามสกุล" />
              <TextField v-model="editForm.phone" numeric="digits" label="เบอร์โทร" class="num" />
              <TextField v-model="editForm.email" label="อีเมล" />
            </div>
            <TextareaField v-model="editForm.staff_note" label="หมายเหตุของร้าน" hint="ลูกค้าไม่เห็น" rows="2" />
            <div class="flex flex-wrap items-center justify-between gap-3">
              <p class="m-0 text-sm text-muted-foreground">
                รับข่าวสาร: <span class="text-heading">{{ selected.marketing_consent === null ? 'ไม่ได้ระบุ' : selected.marketing_consent ? 'ยินยอม' : 'ไม่ยินยอม' }}</span>
              </p>
              <Button type="submit" :disabled="saving">{{ saving ? 'กำลังบันทึก…' : 'บันทึก' }}</Button>
            </div>
          </form>
        </SectionCard>

        <!-- ประวัติการจอง -->
        <SectionCard title="การจอง" :description="selected.bookings.length ? `${selected.bookings.length} รายการ${selected.bookings.length >= 50 ? ' (ล่าสุด 50)' : ''}` : undefined" flush>
          <EmptyState v-if="!selected.bookings.length" compact title="ยังไม่มีการจอง" class="m-5" />
          <div v-else class="grid">
            <section v-for="g in bookingGroups" :key="g.key">
              <h3 class="m-0 border-b border-border bg-muted/50 px-5 py-2 text-sm font-medium text-muted-foreground">
                {{ g.label }} <span class="num">· {{ g.items.length }}</span>
              </h3>
              <ul class="m-0 grid list-none p-0">
                <li v-for="b in g.items" :key="b.booking_id" class="grid gap-2 border-b border-border px-5 py-4 last:border-0">
                  <div class="flex flex-wrap items-start justify-between gap-2">
                    <p class="m-0 flex items-center gap-2 font-semibold text-heading">
                      <CalendarClock class="size-4 shrink-0 text-brand-accent" aria-hidden="true" />
                      <span>{{ bangkokDateLong(b.starts_at) }} · <span class="num">{{ bangkokTime(b.starts_at) }}–{{ bangkokTime(b.ends_at) }} น.</span></span>
                    </p>
                    <span class="shrink-0 rounded-full px-2.5 py-0.5 text-[13px] font-medium" :class="bookingTone[b.status]">{{ bookingStatusLabels[b.status] }}</span>
                  </div>
                  <p class="m-0 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted-foreground">
                    <span class="flex items-center gap-1"><MapPin class="size-3.5" aria-hidden="true" />{{ b.branch_name }}</span>
                    <span class="flex items-center gap-1"><Users class="size-3.5" aria-hidden="true" /><span class="num">{{ b.items_count }}</span> คน</span>
                    <span>{{ b.channel === 'ONLINE' ? 'จองออนไลน์' : 'ร้านจองให้' }}</span>
                    <span v-if="b.booking_code" class="num">{{ b.booking_code }}</span>
                  </p>
                  <ol class="m-0 grid list-none gap-1 rounded-lg bg-muted/60 p-3 text-[15px]">
                    <li v-for="(it, idx) in b.items" :key="idx" class="grid grid-cols-[3.5rem_minmax(0,1fr)_auto] items-baseline gap-2">
                      <span class="text-sm text-muted-foreground">คนที่ {{ idx + 1 }}</span>
                      <span class="min-w-0 text-heading">{{ it.service_name }} <span class="text-muted-foreground">{{ formatDuration(it.duration_minutes) }}</span></span>
                      <span class="num text-right text-heading">{{ formatBaht(Number(it.price)) }}</span>
                    </li>
                  </ol>
                  <div class="flex flex-wrap items-center justify-between gap-2 text-sm">
                    <span class="text-muted-foreground">
                      {{ depositStatusLabels[b.deposit_status] }}<template v-if="Number(b.deposit_required) > 0"> · <span class="num">{{ formatBaht(Number(b.deposit_required)) }}</span></template>
                    </span>
                    <span class="font-medium text-heading">รวม <span class="num">{{ formatBaht(Number(b.total_amount)) }}</span></span>
                  </div>
                  <p v-if="b.customer_note" class="m-0 text-sm"><span class="text-muted-foreground">หมายเหตุลูกค้า:</span> {{ b.customer_note }}</p>
                </li>
              </ul>
            </section>
          </div>
        </SectionCard>
        </div>
        <EmptyState v-else-if="results.length" compact title="เลือกลูกค้าเพื่อดูรายละเอียด" />
      </div>

    <!-- เพิ่มลูกค้า -->
    <Dialog v-model:open="createDialog">
      <DialogContent class="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>เพิ่มลูกค้า</DialogTitle>
          <DialogDescription>ลูกค้า Guest ที่มาที่ร้าน ใช้เบอร์โทรเป็นตัวระบุ</DialogDescription>
        </DialogHeader>
        <form class="grid gap-4" @submit.prevent="submitCreate">
          <div class="grid gap-4 sm:grid-cols-2">
            <TextField v-model="createForm.first_name" label="ชื่อ" />
            <TextField v-model="createForm.last_name" label="นามสกุล (ไม่บังคับ)" />
            <TextField v-model="createForm.phone" numeric="digits" label="เบอร์โทร" type="tel" class="num" />
            <TextField v-model="createForm.email" label="อีเมล (ไม่บังคับ)" type="email" />
          </div>
          <TextareaField v-model="createForm.staff_note" label="หมายเหตุของร้าน" rows="2" />
          <CheckboxField v-model="createForm.privacy" label="แจ้งนโยบายความเป็นส่วนตัวให้ลูกค้ารับทราบแล้ว" />
          <DialogFooter class="gap-2">
            <Button type="button" variant="outline" @click="createDialog = false">ยกเลิก</Button>
            <Button type="submit" :disabled="saving">เพิ่มลูกค้า</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>

    <!-- จับคู่ -->
    <Dialog v-model:open="mergeDialog">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>จับคู่ลูกค้า</DialogTitle>
          <DialogDescription>รวม “{{ mergeSource?.display_name }}” เข้ากับลูกค้าที่เลือก ใช้เมื่อยืนยันกับลูกค้าแล้วว่าเป็นคนเดียวกัน</DialogDescription>
        </DialogHeader>
        <form class="grid gap-4" @submit.prevent="submitMerge">
          <SelectField v-model="mergeTarget" :items="mergeTargets" label="รวมเข้ากับ" placeholder="เลือกลูกค้า" />
          <TextareaField v-model="mergeReason" label="เหตุผล" hint="บังคับ" rows="2" />
          <DialogFooter class="gap-2">
            <Button type="button" variant="outline" @click="mergeDialog = false">ยกเลิก</Button>
            <Button type="submit" :disabled="saving">ยืนยันจับคู่</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  </div>
</template>
