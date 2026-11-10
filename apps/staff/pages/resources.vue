<script setup lang="ts">
// OWNER: ประเภททรัพยากร, จำนวนต่อสาขา, ทรัพยากรที่แต่ละบริการใช้, บัญชีรับมัดจำของสาขา
import { Pencil, Plus, Trash2, X } from '@lucide/vue'
import type { Tables } from '@ifeew/shared'



const { prompt } = useDialog()
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
  const name = await prompt({ title: 'เพิ่มประเภททรัพยากร', label: 'ชื่อประเภท', placeholder: 'เช่น เบาะนวดไทย, เก้าอี้นวดเท้า', minLength: 1, maxLength: 100, confirmText: 'เพิ่ม' })
  if (name === null || !company.value) return
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

async function renameType(t: ResourceType) {
  const name = await prompt({ title: 'แก้ชื่อประเภท', label: 'ชื่อประเภท', defaultValue: t.name, minLength: 1, maxLength: 100, confirmText: 'บันทึก' })
  if (name === null || name.trim() === t.name) return
  try {
    await must(supabase.from('resource_types').update({ name: name.trim() }).eq('id', t.id))
    ok('แก้ชื่อแล้ว')
    await load()
  } catch (e) {
    fail(e, 'แก้ชื่อไม่สำเร็จ (ชื่อซ้ำหรือไม่)')
  }
}

// ลบประเภท (ทุกสาขา) — เฉพาะที่ยังไม่เคยถูกใช้ในคิว
const { remove, deletingId } = useDeleteRecord()
async function removeType(t: ResourceType) {
  try {
    const r = await remove(t.id, { fn: 'delete_resource_type', args: { p_resource_type_id: t.id } }, {
      title: `ลบ "${t.name}"?`,
      description: 'จำนวนในทุกสาขาและการผูกกับบริการจะถูกลบด้วย ย้อนกลับไม่ได้ ถ้าเคยถูกใช้ในคิวแล้ว ให้ใช้ "ปิดประเภท" แทน',
    })
    if (r === 'deleted') {
      ok(`ลบ ${t.name} แล้ว`)
      await load()
    }
  } catch (e) {
    fail(e, 'ลบไม่สำเร็จ')
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
  <div>
    <PageHeader title="เตียงและอุปกรณ์" :description="`${activeBranch?.name ?? ''} · จำนวนต่อสาขา ทรัพยากรที่แต่ละบริการใช้ และบัญชีรับมัดจำ`" />
    <MessageAlert :message="message" class="mb-6" @close="message = null" />

    <div class="grid gap-6">
      <SectionCard title="จำนวนที่สาขานี้" description="ลดจำนวนต่ำกว่าที่ถูกจองไว้ในอนาคตไม่ได้ · ซ่อมบำรุง/ปิด = จองไม่ได้" flush>
        <template #actions><Button variant="outline" size="sm" @click="addType"><Plus /> เพิ่มประเภท</Button></template>
        <EmptyState v-if="!types.length" compact title="ยังไม่มีประเภทเตียงหรืออุปกรณ์" description="เช่น เบาะนวดไทย, เก้าอี้นวดเท้า" class="m-5" />
        <div
          v-for="t in types"
          :key="t.id"
          class="grid grid-cols-2 items-end gap-3 border-b border-border px-5 py-3 sm:grid-cols-[minmax(0,1fr)_120px_180px_auto]"
          :class="t.is_active ? '' : 'text-muted-foreground'"
        >
          <span class="col-span-2 self-center font-medium text-heading sm:col-span-1">
            {{ t.name }} <Badge v-if="!t.is_active" variant="neutral" class="ml-1">ปิดประเภท</Badge>
          </span>
          <TextField v-model="qty[t.id]!.total_quantity" numeric="integer" min="0" :aria-label="`จำนวน ${t.name}`" class="num" />
          <SelectField v-model="qty[t.id]!.status" :aria-label="`สถานะ ${t.name}`"
            :items="[{ value: 'ACTIVE', title: 'ใช้งาน' }, { value: 'MAINTENANCE', title: 'ซ่อมบำรุง' }, { value: 'DISABLED', title: 'ปิด' }]" />
          <div class="col-span-2 flex flex-wrap justify-end gap-1 sm:col-span-1">
            <Button variant="ghost" size="sm" :aria-label="`แก้ชื่อ ${t.name}`" @click="renameType(t)"><Pencil /></Button>
            <Button variant="ghost" size="sm" @click="toggleType(t)">{{ t.is_active ? 'ปิดประเภท' : 'เปิดประเภท' }}</Button>
            <Button variant="ghost" size="sm" class="text-danger-ink hover:bg-danger-soft hover:text-danger-ink" :aria-label="`ลบ ${t.name}`" :disabled="deletingId === t.id" @click="removeType(t)"><Trash2 /></Button>
          </div>
        </div>
        <div v-if="types.length" class="flex justify-end px-5 py-4">
          <Button :disabled="saving" @click="saveQuantities">บันทึกจำนวน</Button>
        </div>
      </SectionCard>

      <SectionCard title="บริการใช้อะไร" description="ใช้กับทุกสาขาและทุกระยะเวลา บริการที่ยังไม่กำหนดจะจองออนไลน์ไม่ได้" flush>
        <ul class="m-0 grid list-none p-0">
          <li v-for="s in services" :key="s.id" class="flex items-center justify-between gap-3 border-b border-border px-5 py-3 last:border-0">
            <div class="min-w-0">
              <p class="m-0 font-medium text-heading">{{ s.name }}</p>
              <p class="m-0 text-sm" :class="serviceRes.some((r) => r.service_id === s.id) ? 'text-muted-foreground' : 'text-pending-ink'">{{ usageText(s) }}</p>
            </div>
            <Button size="sm" variant="outline" @click="openService(s)">กำหนด</Button>
          </li>
          <li v-if="!services.length" class="px-5 py-8 text-center text-muted-foreground">ยังไม่มีบริการที่เปิดใช้งาน</li>
        </ul>
      </SectionCard>

      <SectionCard title="บัญชีรับมัดจำของสาขา" description="ลูกค้าจะเห็น QR PromptPay ของบัญชีนี้ · SlipOK Branch ID ต้องผูกกับบัญชีเดียวกันในระบบ SlipOK">
        <form class="grid gap-4" @submit.prevent="saveAccount">
          <div class="grid gap-4 md:grid-cols-2">
            <TextField v-model="accountForm.promptpay_id" numeric="digits" label="PromptPay" hint="เบอร์มือถือ 10 หลัก / เลขประจำตัว 13 หลัก / e-Wallet 15 หลัก" inputmode="numeric" class="num" />
            <TextField v-model="accountForm.account_name" label="ชื่อบัญชี" />
            <TextField v-model="accountForm.bank_name" label="ธนาคาร" />
            <TextField v-model="accountForm.slipok_branch_id" label="SlipOK Branch ID" hint="เว้นว่าง = พนักงานตรวจสลิปเอง" />
          </div>
          <SwitchField v-model="accountForm.is_active" label="เปิดใช้งาน" />
          <div class="flex justify-end"><Button type="submit" :disabled="saving">บันทึกบัญชี</Button></div>
        </form>
      </SectionCard>
    </div>

    <Dialog v-model:open="svcDialog">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{{ svcTarget?.name }} ใช้</DialogTitle>
          <DialogDescription>เลือกประเภทและจำนวนที่บริการนี้ต้องใช้ต่อ 1 คน</DialogDescription>
        </DialogHeader>
        <div class="grid gap-3">
          <div v-for="(i, idx) in svcItems" :key="idx" class="grid grid-cols-[minmax(0,1fr)_90px_auto] items-end gap-2">
            <SelectField v-model="i.resource_type_id" :items="types.filter((t) => t.is_active)" item-title="name" item-value="id" :label="idx === 0 ? 'ประเภท' : undefined" :aria-label="`ประเภทที่ ${idx + 1}`" />
            <TextField v-model="i.quantity" numeric="integer" min="1" max="10" :label="idx === 0 ? 'จำนวน' : undefined" :aria-label="`จำนวนที่ ${idx + 1}`" class="num" />
            <Button v-if="svcItems.length > 1" variant="ghost" size="icon" :aria-label="`ลบรายการที่ ${idx + 1}`" @click="svcItems.splice(idx, 1)"><X /></Button>
            <span v-else class="size-10" />
          </div>
          <Button variant="outline" size="sm" class="w-fit" @click="svcItems.push({ resource_type_id: '', quantity: 1 })"><Plus /> เพิ่ม</Button>
        </div>
        <DialogFooter class="gap-2">
          <Button variant="outline" @click="svcDialog = false">ยกเลิก</Button>
          <Button :disabled="saving" @click="saveService">บันทึก</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
