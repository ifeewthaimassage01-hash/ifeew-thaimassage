<script setup lang="ts">
// OWNER: ประเภททรัพยากร, จำนวนต่อสาขา, ทรัพยากรที่แต่ละบริการใช้, บัญชีรับมัดจำของสาขา
import type { Tables } from '@ifeew/shared'

definePageMeta({ ownerOnly: true })

type ResourceType = Tables<'resource_types'>
type BranchResource = Tables<'branch_resources'>
type ServiceResource = Tables<'service_resources'>
type Service = Tables<'services'>
type PaymentAccount = Tables<'branch_payment_accounts'>

const supabase = useSupabaseClient()
const { company, activeBranch } = useAccess()

const types = ref<ResourceType[]>([])
const branchRes = ref<BranchResource[]>([])
const serviceRes = ref<ServiceResource[]>([])
const services = ref<Service[]>([])
const account = ref<PaymentAccount | null>(null)
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)
const saving = ref(false)
const ok = (text: string) => (message.value = { type: 'success', text })
const fail = (e: unknown, fallback?: string) => (message.value = { type: 'error', text: errorText(e, fallback) })

// ฟอร์มจำนวนต่อสาขา
const qty = ref<Record<string, { total_quantity: number | string; status: BranchResource['status'] }>>({})
// ฟอร์มบัญชีรับเงิน
const accountForm = ref({ promptpay_id: '', account_name: '', bank_name: '', slipok_branch_id: '', is_active: true })

async function load() {
  if (!company.value || !activeBranch.value) return
  const cid = company.value.company_id
  const bid = activeBranch.value.branch_id
  const [t, br, sr, s, pa] = await Promise.all([
    supabase.from('resource_types').select('*').eq('company_id', cid).order('name'),
    supabase.from('branch_resources').select('*').eq('branch_id', bid),
    supabase.from('service_resources').select('*').eq('company_id', cid),
    supabase.from('services').select('*').eq('company_id', cid).eq('is_active', true).order('sort_order'),
    supabase.from('branch_payment_accounts').select('*').eq('branch_id', bid).maybeSingle(),
  ])
  types.value = t.data ?? []
  branchRes.value = br.data ?? []
  serviceRes.value = sr.data ?? []
  services.value = s.data ?? []
  account.value = pa.data ?? null
  qty.value = Object.fromEntries(
    types.value.map((x) => {
      const r = branchRes.value.find((b) => b.resource_type_id === x.id)
      return [x.id, { total_quantity: r?.total_quantity ?? 0, status: r?.status ?? 'ACTIVE' }]
    }),
  )
  accountForm.value = {
    promptpay_id: account.value?.promptpay_id ?? '',
    account_name: account.value?.account_name ?? '',
    bank_name: account.value?.bank_name ?? '',
    slipok_branch_id: account.value?.slipok_branch_id ?? '',
    is_active: account.value?.is_active ?? true,
  }
}

watch(() => activeBranch.value?.branch_id, load, { immediate: true })

// ---------------------------------------------------------------------------
// ประเภททรัพยากร
// ---------------------------------------------------------------------------
async function addType() {
  const name = window.prompt('ชื่อประเภททรัพยากร เช่น เบาะนวดไทย, เก้าอี้นวดเท้า')
  if (!name?.trim() || !company.value) return
  try {
    await must(supabase.from('resource_types').insert({ company_id: company.value.company_id, name: name.trim() }))
    await load()
  } catch (e) {
    fail(e, 'เพิ่มไม่สำเร็จ (ชื่อซ้ำหรือไม่)')
  }
}

async function toggleType(t: ResourceType) {
  try {
    await must(supabase.from('resource_types').update({ is_active: !t.is_active }).eq('id', t.id))
    await load()
  } catch (e) {
    fail(e)
  }
}

// ---------------------------------------------------------------------------
// จำนวนต่อสาขา
// ---------------------------------------------------------------------------
async function saveQuantities() {
  if (!company.value || !activeBranch.value) return
  saving.value = true
  try {
    for (const t of types.value) {
      const f = qty.value[t.id]!
      const n = Number(f.total_quantity)
      if (!Number.isInteger(n) || n < 0) throw new Error(`จำนวน ${t.name} ไม่ถูกต้อง`)
      const existing = branchRes.value.find((b) => b.resource_type_id === t.id)
      if (existing) {
        if (existing.total_quantity !== n || existing.status !== f.status) {
          await must(supabase.from('branch_resources').update({ total_quantity: n, status: f.status }).eq('id', existing.id))
        }
      } else if (n > 0) {
        await must(supabase.from('branch_resources').insert({
          company_id: company.value.company_id, branch_id: activeBranch.value.branch_id,
          resource_type_id: t.id, total_quantity: n, status: f.status,
        }))
      }
    }
    ok('บันทึกจำนวนเตียงและอุปกรณ์แล้ว')
    await load()
  } catch (e) {
    fail(e, 'บันทึกไม่สำเร็จ')
  } finally {
    saving.value = false
  }
}

// ---------------------------------------------------------------------------
// ทรัพยากรที่บริการใช้
// ---------------------------------------------------------------------------
const svcDialog = ref(false)
const svcTarget = ref<Service | null>(null)
const svcItems = ref<Array<{ resource_type_id: string; quantity: number | string }>>([])

function openService(s: Service) {
  svcTarget.value = s
  const current = serviceRes.value.filter((r) => r.service_id === s.id)
  svcItems.value = current.length
    ? current.map((r) => ({ resource_type_id: r.resource_type_id, quantity: r.quantity }))
    : [{ resource_type_id: types.value.find((t) => t.is_active)?.id ?? '', quantity: 1 }]
  svcDialog.value = true
}

async function saveService() {
  if (!svcTarget.value) return
  saving.value = true
  try {
    await must(supabase.rpc('set_service_resources', {
      p_service_id: svcTarget.value.id,
      p_items: svcItems.value.filter((i) => i.resource_type_id).map((i) => ({
        resource_type_id: i.resource_type_id, quantity: Number(i.quantity) || 1,
      })),
    }))
    svcDialog.value = false
    ok('บันทึกการใช้ทรัพยากรของบริการแล้ว')
    await load()
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}

const usageText = (s: Service) =>
  serviceRes.value
    .filter((r) => r.service_id === s.id)
    .map((r) => `${types.value.find((t) => t.id === r.resource_type_id)?.name ?? '?'} × ${r.quantity}`)
    .join(', ') || 'ยังไม่กำหนด (จองไม่ได้)'

// ---------------------------------------------------------------------------
// บัญชีรับมัดจำ
// ---------------------------------------------------------------------------
async function saveAccount() {
  if (!company.value || !activeBranch.value) return
  const f = accountForm.value
  const pp = f.promptpay_id.replace(/[^0-9]/g, '')
  if (!/^(0[0-9]{9}|[0-9]{13}|[0-9]{15})$/.test(pp) || !f.account_name.trim()) {
    fail(null, 'PromptPay ต้องเป็นเบอร์มือถือ 10 หลัก / เลขประจำตัว 13 หลัก / e-Wallet 15 หลัก และต้องมีชื่อบัญชี')
    return
  }
  const payload = {
    promptpay_id: pp,
    account_name: f.account_name.trim(),
    bank_name: f.bank_name.trim() || null,
    slipok_branch_id: f.slipok_branch_id.trim() || null,
    is_active: f.is_active,
  }
  saving.value = true
  try {
    if (account.value) await must(supabase.from('branch_payment_accounts').update(payload).eq('id', account.value.id))
    else await must(supabase.from('branch_payment_accounts').insert({
      ...payload, company_id: company.value.company_id, branch_id: activeBranch.value.branch_id,
    }))
    ok('บันทึกบัญชีรับมัดจำแล้ว')
    await load()
  } catch (e) {
    fail(e)
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="grid gap-6">
    <h1 class="m-0 text-2xl font-semibold text-cocoa">เตียงและอุปกรณ์ · {{ activeBranch?.name }}</h1>
    <v-alert v-if="message" :type="message.type" variant="tonal" closable :text="message.text" @click:close="message = null" />

    <v-card class="p-6">
      <div class="mb-4 flex items-center justify-between">
        <p class="m-0 text-lg font-medium">จำนวนที่สาขานี้</p>
        <v-btn variant="tonal" prepend-icon="mdi-plus" @click="addType">เพิ่มประเภท</v-btn>
      </div>
      <div v-for="t in types" :key="t.id" class="grid grid-cols-[1fr_120px_180px_auto] items-center gap-3" :class="t.is_active ? '' : 'opacity-50'">
        <span class="font-medium">{{ t.name }}</span>
        <v-text-field v-model="qty[t.id]!.total_quantity" type="number" min="0" label="จำนวน" hide-details class="my-1" />
        <v-select v-model="qty[t.id]!.status" hide-details label="สถานะ" class="my-1"
          :items="[{ value: 'ACTIVE', title: 'ใช้งาน' }, { value: 'MAINTENANCE', title: 'ซ่อมบำรุง' }, { value: 'DISABLED', title: 'ปิด' }]" />
        <v-btn variant="text" size="small" @click="toggleType(t)">{{ t.is_active ? 'ปิดประเภท' : 'เปิดประเภท' }}</v-btn>
      </div>
      <p class="m-0 mt-2 text-xs text-light-brown">ลดจำนวนต่ำกว่าที่ถูกจองไว้ในอนาคตไม่ได้ · ซ่อมบำรุง/ปิด = จองไม่ได้</p>
      <div class="mt-4 flex justify-end"><v-btn color="primary" :loading="saving" @click="saveQuantities">บันทึกจำนวน</v-btn></div>
    </v-card>

    <v-card class="p-6">
      <p class="m-0 mb-4 text-lg font-medium">บริการใช้อะไร (ทุกสาขา ทุกระยะเวลา)</p>
      <div v-for="s in services" :key="s.id" class="flex items-center justify-between border-b border-beige py-2">
        <div>
          <p class="m-0 font-medium">{{ s.name }}</p>
          <p class="m-0 text-sm text-light-brown">{{ usageText(s) }}</p>
        </div>
        <v-btn size="small" variant="tonal" color="primary" @click="openService(s)">กำหนด</v-btn>
      </div>
    </v-card>

    <v-card class="p-6">
      <p class="m-0 mb-1 text-lg font-medium">บัญชีรับมัดจำของสาขา</p>
      <p class="m-0 mb-4 text-sm text-light-brown">ลูกค้าจะเห็น QR PromptPay ของบัญชีนี้ · SlipOK Branch ID ต้องผูกกับบัญชีเดียวกันในระบบ SlipOK</p>
      <div class="grid gap-x-4 md:grid-cols-2">
        <v-text-field v-model="accountForm.promptpay_id" label="PromptPay (เบอร์/เลขประจำตัว/e-Wallet)" inputmode="numeric" />
        <v-text-field v-model="accountForm.account_name" label="ชื่อบัญชี" />
        <v-text-field v-model="accountForm.bank_name" label="ธนาคาร" />
        <v-text-field v-model="accountForm.slipok_branch_id" label="SlipOK Branch ID (ว่าง = พนักงานตรวจสลิปเอง)" />
      </div>
      <v-switch v-model="accountForm.is_active" color="primary" label="เปิดใช้งาน" hide-details />
      <div class="mt-2 flex justify-end"><v-btn color="primary" :loading="saving" @click="saveAccount">บันทึกบัญชี</v-btn></div>
    </v-card>

    <v-dialog v-model="svcDialog" max-width="480">
      <v-card class="p-6">
        <p class="m-0 mb-4 text-lg font-medium">{{ svcTarget?.name }} ใช้</p>
        <div v-for="(i, idx) in svcItems" :key="idx" class="flex items-center gap-2">
          <v-select v-model="i.resource_type_id" :items="types.filter((t) => t.is_active)" item-title="name" item-value="id" label="ประเภท" hide-details class="mb-2" />
          <v-text-field v-model="i.quantity" type="number" min="1" max="10" label="จำนวน" hide-details class="mb-2 w-24" />
          <v-btn v-if="svcItems.length > 1" icon="mdi-close" size="small" variant="text" aria-label="ลบ" @click="svcItems.splice(idx, 1)" />
        </div>
        <v-btn variant="text" size="small" prepend-icon="mdi-plus" @click="svcItems.push({ resource_type_id: '', quantity: 1 })">เพิ่ม</v-btn>
        <div class="mt-4 flex justify-end gap-2">
          <v-btn variant="text" @click="svcDialog = false">ยกเลิก</v-btn>
          <v-btn color="primary" :loading="saving" @click="saveService">บันทึก</v-btn>
        </div>
      </v-card>
    </v-dialog>
  </div>
</template>
