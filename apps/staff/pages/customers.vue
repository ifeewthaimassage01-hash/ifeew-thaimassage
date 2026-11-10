<script setup lang="ts">
// ลูกค้า: ค้นหาด้วยเบอร์เต็ม (ผลปิดบัง) -> เปิดดูรายละเอียด (บันทึก audit) -> แก้ไข / จับคู่ Guest
// OWNER: คำขอลบข้อมูล (PDPA)
import { Link2, Search, UserPlus } from '@lucide/vue'
import { personNameSchema, reasonSchema, thaiPhoneSchema, type CustomerDetail, type Tables } from '@ifeew/shared'



const { confirm, prompt } = useDialog()
type SearchRow = { customer_id: string; display_name: string; phone_masked: string; is_member: boolean; created_at: string }
type DataRequest = Tables<'customer_data_requests'> & { customer: { first_name: string; last_name: string } | null }

const supabase = useSupabaseClient()
const { company, isOwner } = useAccess()
const { run } = useStepUp()
const { call } = useEdgeFunction()

const tab = ref<'search' | 'requests'>('search')
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
// จับคู่ Guest -> ลูกค้ารายอื่นที่เบอร์เดียวกัน (พนักงานยืนยัน)
// ---------------------------------------------------------------------------
const mergeDialog = ref(false)
const mergeSource = ref<SearchRow | null>(null)
const mergeTarget = ref<string | null>(null)
const mergeReason = ref('')
const mergeTargets = computed(() =>
  (results.value ?? [])
    .filter((r) => r.customer_id !== mergeSource.value?.customer_id)
    .map((r) => ({ value: r.customer_id, title: `${r.display_name} ${r.is_member ? '(สมาชิก)' : '(Guest)'}` })),
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

// ---------------------------------------------------------------------------
// OWNER: คำขอลบข้อมูล
// ---------------------------------------------------------------------------
const requests = ref<DataRequest[]>([])

async function loadRequests() {
  if (!isOwner.value || !company.value) return
  const { data, error } = await supabase
    .from('customer_data_requests')
    .select('*, customer:customers(first_name, last_name)')
    .eq('company_id', company.value.company_id)
    .order('requested_at', { ascending: false })
    .limit(100)
  if (error) fail(error)
  requests.value = (data ?? []) as unknown as DataRequest[]
}

async function processRequest(r: DataRequest, approve: boolean) {
  let note: string | null = null
  if (approve) {
    if (!(await confirm({ title: 'ลบข้อมูลส่วนบุคคลของลูกค้า?', description: 'ย้อนกลับไม่ได้', confirmText: 'ลบข้อมูล', destructive: true }))) return
  } else {
    note = await prompt({ title: 'ปฏิเสธคำขอลบข้อมูล', label: 'เหตุผล', placeholder: 'เช่น มีข้อผูกพันทางกฎหมาย', multiline: true, minLength: 3, confirmText: 'ปฏิเสธคำขอ' })
    if (note === null) return
  }
  try {
    const res = await run(() =>
      call<{ auth_synced: boolean }>('customer-erasure', { request_id: r.id, approve, note }),
    )
    ok(
      approve
        ? res.auth_synced
          ? 'ลบข้อมูลลูกค้าแล้ว'
          : 'ลบข้อมูลในระบบแล้ว แต่ปิดบัญชีเข้าสู่ระบบไม่สำเร็จ กรุณาแจ้งผู้ดูแลระบบ'
        : 'ปฏิเสธคำขอแล้ว',
    )
    await loadRequests()
  } catch (e) {
    fail(e, 'ดำเนินการไม่สำเร็จ')
  }
}

watch(tab, (t) => {
  if (t === 'requests') loadRequests()
})

const statusLabel = { PENDING: 'รอดำเนินการ', COMPLETED: 'ลบแล้ว', REJECTED: 'ปฏิเสธ' } as const
</script>

<template>
  <div>
    <PageHeader title="ลูกค้า" description="ค้นหาด้วยเบอร์โทรเต็มเท่านั้น ผลลัพธ์แสดงข้อมูลบางส่วน และการเปิดดูรายละเอียดจะถูกบันทึก">
      <template #actions><Button variant="outline" @click="openCreate"><UserPlus /> เพิ่มลูกค้า</Button></template>
    </PageHeader>

    <SegmentedControl
      v-if="isOwner"
      v-model="tab"
      :items="[{ value: 'search', label: 'ค้นหาลูกค้า' }, { value: 'requests', label: 'คำขอลบข้อมูล (PDPA)' }]"
      label="มุมมอง"
      class="mb-4"
    />

    <MessageAlert :message="message" class="mb-4" @close="message = null" />

    <template v-if="tab === 'search'">
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
                <Badge :variant="r.is_member ? 'default' : 'neutral'">{{ r.is_member ? 'สมาชิก' : 'Guest' }}</Badge>
                <Button v-if="!r.is_member && results.length > 1" variant="ghost" size="sm" @click="openMerge(r)"><Link2 /> จับคู่</Button>
              </div>
            </li>
          </ul>
        </SectionCard>

        <SectionCard v-if="selected" :title="`${selected.first_name} ${selected.last_name}`.trim()"
          :description="selected.is_member ? 'ชื่อ เบอร์ และอีเมลของสมาชิก ลูกค้าแก้เองในแอป พนักงานแก้ได้เฉพาะหมายเหตุ' : 'ลูกค้า Guest แก้ข้อมูลได้'">
          <template #actions><Badge :variant="selected.is_member ? 'default' : 'neutral'">{{ selected.is_member ? 'สมาชิก' : 'Guest' }}</Badge></template>
          <form class="grid gap-4" @submit.prevent="saveCustomer">
            <div class="grid gap-4 sm:grid-cols-2">
              <TextField v-model="editForm.first_name" label="ชื่อ" :disabled="selected.is_member" />
              <TextField v-model="editForm.last_name" label="นามสกุล" :disabled="selected.is_member" />
              <TextField v-model="editForm.phone" numeric="digits" label="เบอร์โทร" :disabled="selected.is_member" class="num" />
              <TextField v-model="editForm.email" label="อีเมล" :disabled="selected.is_member" />
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
        <EmptyState v-else-if="results.length" compact title="เลือกลูกค้าเพื่อดูรายละเอียด" />
      </div>
    </template>

    <SectionCard v-else title="คำขอลบข้อมูล (PDPA)" flush>
      <div class="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow class="hover:bg-transparent">
              <TableHead>วันที่ขอ</TableHead><TableHead>ลูกค้า</TableHead><TableHead>เหตุผล</TableHead><TableHead>สถานะ</TableHead>
              <TableHead class="text-right"><span class="sr-only">การทำงาน</span></TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow v-for="r in requests" :key="r.id">
              <TableCell class="num">{{ new Date(r.requested_at).toLocaleString('th-TH', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Bangkok' }) }}</TableCell>
              <TableCell class="text-heading">{{ r.customer ? `${r.customer.first_name} ${r.customer.last_name}` : '—' }}</TableCell>
              <TableCell class="max-w-64 whitespace-normal">{{ r.reason || '—' }}</TableCell>
              <TableCell>
                <Badge dot :variant="r.status === 'COMPLETED' ? 'success' : r.status === 'REJECTED' ? 'neutral' : 'pending'">{{ statusLabel[r.status] }}</Badge>
                <span v-if="r.response_note" class="mt-1 block text-sm whitespace-normal text-muted-foreground">{{ r.response_note }}</span>
              </TableCell>
              <TableCell class="text-right">
                <div v-if="r.status === 'PENDING'" class="flex justify-end gap-2">
                  <Button variant="ghost" size="sm" @click="processRequest(r, false)">ปฏิเสธ</Button>
                  <Button variant="destructive" size="sm" @click="processRequest(r, true)">ลบข้อมูล</Button>
                </div>
              </TableCell>
            </TableRow>
            <TableRow v-if="!requests.length" class="hover:bg-transparent">
              <TableCell colspan="5" class="py-8 text-center text-muted-foreground">ไม่มีคำขอ</TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </div>
    </SectionCard>

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
          <DialogTitle>จับคู่ลูกค้า Guest</DialogTitle>
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
