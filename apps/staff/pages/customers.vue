<script setup lang="ts">
// ลูกค้า: ค้นหาด้วยเบอร์เต็ม (ผลปิดบัง) -> เปิดดูรายละเอียด (บันทึก audit) -> แก้ไข / จับคู่ Guest
// OWNER: คำขอลบข้อมูล (PDPA)
import { personNameSchema, reasonSchema, thaiPhoneSchema, type CustomerDetail, type Tables } from '@ifeew/shared'

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
    if (!window.confirm('ยืนยันลบข้อมูลส่วนบุคคลของลูกค้ารายนี้? ย้อนกลับไม่ได้')) return
  } else {
    note = window.prompt('เหตุผลที่ปฏิเสธ (เช่น มีข้อผูกพันทางกฎหมาย)')
    if (!note || note.trim().length < 3) return
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
    <h1 class="m-0 mb-4 text-2xl font-semibold text-cocoa">ลูกค้า</h1>

    <v-tabs v-if="isOwner" v-model="tab" color="primary" class="mb-4">
      <v-tab value="search">ค้นหาลูกค้า</v-tab>
      <v-tab value="requests">คำขอลบข้อมูล (PDPA)</v-tab>
    </v-tabs>

    <v-alert v-if="message" :type="message.type" variant="tonal" class="mb-4" closable :text="message.text" @click:close="message = null" />

    <template v-if="tab === 'search'">
      <v-card class="mb-4 p-5">
        <v-form class="flex flex-wrap items-start gap-3" @submit.prevent="search">
          <v-text-field v-model="phone" label="เบอร์โทรเต็ม" type="tel" inputmode="tel" class="min-w-[240px] flex-1" hide-details autofocus />
          <v-btn type="submit" color="primary" :loading="searching" prepend-icon="mdi-magnify">ค้นหา</v-btn>
          <v-btn variant="tonal" color="primary" prepend-icon="mdi-account-plus-outline" @click="openCreate">เพิ่มลูกค้า</v-btn>
        </v-form>
        <p class="m-0 mt-2 text-xs text-light-brown">ค้นหาได้ด้วยเบอร์โทรเต็มเท่านั้น ผลลัพธ์แสดงข้อมูลบางส่วน และการเปิดดูรายละเอียดจะถูกบันทึก</p>
      </v-card>

      <div class="grid gap-4 lg:grid-cols-2">
        <v-card v-if="results" class="p-2">
          <v-list v-if="results.length" lines="two">
            <v-list-item
              v-for="r in results"
              :key="r.customer_id"
              :title="r.display_name"
              :subtitle="r.phone_masked"
              :active="selected?.customer_id === r.customer_id"
              rounded="lg"
              @click="open(r)"
            >
              <template #append>
                <v-chip :color="r.is_member ? 'primary' : 'grey'" variant="tonal" size="small" class="mr-2">
                  {{ r.is_member ? 'สมาชิก' : 'Guest' }}
                </v-chip>
                <v-btn
                  v-if="!r.is_member && results.length > 1"
                  variant="text"
                  size="small"
                  prepend-icon="mdi-link-variant"
                  @click.stop="openMerge(r)"
                >จับคู่</v-btn>
              </template>
            </v-list-item>
          </v-list>
          <p v-else class="m-4 text-light-brown">ไม่พบลูกค้าเบอร์นี้</p>
        </v-card>

        <v-card v-if="selected" class="p-5">
          <div class="mb-4 flex items-center justify-between">
            <p class="m-0 text-lg font-medium">{{ selected.first_name }} {{ selected.last_name }}</p>
            <v-chip :color="selected.is_member ? 'primary' : 'grey'" variant="tonal" size="small">
              {{ selected.is_member ? 'สมาชิก' : 'Guest' }}
            </v-chip>
          </div>
          <p v-if="selected.is_member" class="m-0 mb-3 text-xs text-light-brown">ชื่อ เบอร์ และอีเมลของสมาชิก ลูกค้าแก้เองในแอป พนักงานแก้ได้เฉพาะหมายเหตุ</p>
          <div class="grid grid-cols-2 gap-x-3">
            <v-text-field v-model="editForm.first_name" label="ชื่อ" :disabled="selected.is_member" />
            <v-text-field v-model="editForm.last_name" label="นามสกุล" :disabled="selected.is_member" />
            <v-text-field v-model="editForm.phone" label="เบอร์โทร" :disabled="selected.is_member" />
            <v-text-field v-model="editForm.email" label="อีเมล" :disabled="selected.is_member" />
          </div>
          <v-textarea v-model="editForm.staff_note" label="หมายเหตุของร้าน (ลูกค้าไม่เห็น)" rows="2" variant="outlined" />
          <p class="m-0 mb-3 text-xs text-light-brown">
            รับข่าวสาร: {{ selected.marketing_consent === null ? 'ไม่ได้ระบุ' : selected.marketing_consent ? 'ยินยอม' : 'ไม่ยินยอม' }}
          </p>
          <div class="flex justify-end">
            <v-btn color="primary" :loading="saving" @click="saveCustomer">บันทึก</v-btn>
          </div>
        </v-card>
      </div>
    </template>

    <v-card v-else class="p-2">
      <v-table>
        <thead><tr><th>วันที่ขอ</th><th>ลูกค้า</th><th>เหตุผล</th><th>สถานะ</th><th /></tr></thead>
        <tbody>
          <tr v-for="r in requests" :key="r.id">
            <td>{{ new Date(r.requested_at).toLocaleString('th-TH', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Bangkok' }) }}</td>
            <td>{{ r.customer ? `${r.customer.first_name} ${r.customer.last_name}` : '-' }}</td>
            <td>{{ r.reason || '-' }}</td>
            <td>{{ statusLabel[r.status] }}<div v-if="r.response_note" class="text-xs text-light-brown">{{ r.response_note }}</div></td>
            <td class="text-right">
              <template v-if="r.status === 'PENDING'">
                <v-btn variant="text" @click="processRequest(r, false)">ปฏิเสธ</v-btn>
                <v-btn variant="tonal" color="error" @click="processRequest(r, true)">ลบข้อมูล</v-btn>
              </template>
            </td>
          </tr>
          <tr v-if="!requests.length"><td colspan="5" class="text-center text-light-brown">ไม่มีคำขอ</td></tr>
        </tbody>
      </v-table>
    </v-card>

    <!-- เพิ่มลูกค้า -->
    <v-dialog v-model="createDialog" max-width="520">
      <v-card class="p-6">
        <p class="m-0 mb-4 text-lg font-medium">เพิ่มลูกค้า</p>
        <div class="grid grid-cols-2 gap-x-3">
          <v-text-field v-model="createForm.first_name" label="ชื่อ" />
          <v-text-field v-model="createForm.last_name" label="นามสกุล (ไม่บังคับ)" />
          <v-text-field v-model="createForm.phone" label="เบอร์โทร" type="tel" />
          <v-text-field v-model="createForm.email" label="อีเมล (ไม่บังคับ)" type="email" />
        </div>
        <v-textarea v-model="createForm.staff_note" label="หมายเหตุของร้าน" rows="2" variant="outlined" />
        <v-checkbox v-model="createForm.privacy" color="primary" label="แจ้งนโยบายความเป็นส่วนตัวให้ลูกค้ารับทราบแล้ว" hide-details />
        <div class="mt-4 flex justify-end gap-2">
          <v-btn variant="text" @click="createDialog = false">ยกเลิก</v-btn>
          <v-btn color="primary" :loading="saving" @click="submitCreate">เพิ่มลูกค้า</v-btn>
        </div>
      </v-card>
    </v-dialog>

    <!-- จับคู่ -->
    <v-dialog v-model="mergeDialog" max-width="480">
      <v-card class="p-6">
        <p class="m-0 mb-1 text-lg font-medium">จับคู่ลูกค้า Guest</p>
        <p class="m-0 mb-4 text-sm text-light-brown">
          รวม “{{ mergeSource?.display_name }}” เข้ากับลูกค้าที่เลือก ใช้เมื่อยืนยันกับลูกค้าแล้วว่าเป็นคนเดียวกัน
        </p>
        <v-select v-model="mergeTarget" :items="mergeTargets" label="รวมเข้ากับ" />
        <v-textarea v-model="mergeReason" label="เหตุผล (บังคับ)" rows="2" variant="outlined" />
        <div class="flex justify-end gap-2">
          <v-btn variant="text" @click="mergeDialog = false">ยกเลิก</v-btn>
          <v-btn color="primary" :loading="saving" @click="submitMerge">ยืนยันจับคู่</v-btn>
        </div>
      </v-card>
    </v-dialog>
  </div>
</template>
