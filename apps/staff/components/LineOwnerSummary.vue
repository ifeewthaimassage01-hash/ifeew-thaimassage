<script setup lang="ts">
// สรุปประจำวันส่งเข้า LINE ส่วนตัวของเจ้าของร้าน (migration 077)
//   ผูก: สร้างรหัส → เพิ่มเพื่อน OA → พิมพ์ "เชื่อมเจ้าของ รหัส" ในแชท 1:1 → ระบบเช็กทุก 5 วินาทีจนผูกสำเร็จ
//   ตั้งค่า: เปิด/ปิด + เวลาส่ง (ก่อนเที่ยงวัน = สรุปของเมื่อวาน · ตั้งแต่เที่ยง = ของวันนี้) + ส่งสรุปวันนี้ทันที
import { toast } from 'vue-sonner'

const props = defineProps<{
  companyId: string
  ready: boolean
  addFriendUrl?: string | null
  botBasicId?: string | null
  /** ตัวอย่างการ์ด: ชื่อร้าน ชื่อ/รูป OA และ URL แอปพนักงาน (ปุ่มเปิดแดชบอร์ด) */
  companyName?: string | null
  botName?: string | null
  botPicture?: string | null
  staffUrl?: string | null
  branch?: string
}>()

const supabase = useSupabaseClient()
const { confirm } = useDialog()

interface OwnerSummary { linked: boolean; owner_name: string | null; linked_at: string | null; enabled: boolean; time: string; last_date: string | null }
const state = ref<OwnerSummary | null>(null)
const form = reactive({ enabled: true, time: '00:30' })
const code = ref<{ code: string; expires_at: string } | null>(null)
const busy = ref<'code' | 'save' | 'send' | 'unlink' | null>(null)

async function load() {
  const { data, error } = await supabase.rpc('line_owner_summary_get', { p_company_id: props.companyId })
  if (error) return
  const was = state.value?.linked
  state.value = data as unknown as OwnerSummary
  Object.assign(form, { enabled: state.value.enabled, time: state.value.time })
  if (code.value && state.value.linked && !was) {
    code.value = null
    toast.success('เชื่อม LINE ของเจ้าของร้านแล้ว')
  }
}
watch(() => props.companyId, load, { immediate: true })

// ระหว่างรอพิมพ์รหัสในแชท → เช็กทุก 5 วินาที
const { pause, resume } = useIntervalFn(load, 5000, { immediate: false })
watch(code, (c) => (c ? resume() : pause()))

async function createCode() {
  busy.value = 'code'
  const { data, error } = await supabase.rpc('line_create_link_code', { p_company_id: props.companyId, p_branch_id: null })
  busy.value = null
  if (error) {
    toast.error(error.message || 'สร้างรหัสไม่สำเร็จ')
    return
  }
  code.value = data as unknown as { code: string; expires_at: string }
}

async function save() {
  busy.value = 'save'
  const { error } = await supabase.rpc('line_owner_summary_save', { p_company_id: props.companyId, p_enabled: form.enabled, p_time: form.time })
  busy.value = null
  if (error) {
    toast.error(error.message || 'บันทึกไม่สำเร็จ')
    return
  }
  toast.success(form.enabled ? `จะส่งสรุปทุกวัน เวลา ${form.time} น.` : 'ปิดการส่งสรุปประจำวันแล้ว')
  await load()
}

async function sendNow() {
  busy.value = 'send'
  const { error } = await supabase.rpc('line_owner_summary_send_now', { p_company_id: props.companyId })
  busy.value = null
  if (error) toast.error(error.message || 'ส่งไม่สำเร็จ')
  else toast.success('ส่งสรุปของวันนี้เข้า LINE แล้ว')
}

async function unlink() {
  const ok = await confirm({
    title: 'เลิกส่งสรุปเข้า LINE นี้?',
    description: `${state.value?.owner_name ?? 'LINE ของเจ้าของร้าน'} จะไม่ได้รับสรุปประจำวันอีก เชื่อมใหม่ได้ทุกเมื่อ`,
    confirmText: 'เลิกเชื่อม',
    destructive: true,
  })
  if (!ok) return
  busy.value = 'unlink'
  const { error } = await supabase.rpc('line_owner_unlink', { p_company_id: props.companyId })
  busy.value = null
  if (error) toast.error('เลิกเชื่อมไม่สำเร็จ')
  await load()
}

const command = computed(() => (code.value ? `เชื่อมเจ้าของ ${code.value.code}` : ''))
const covers = computed(() => (form.time < '12:00' ? 'ของเมื่อวาน' : 'ของวันนี้'))
const dirty = computed(() => !!state.value && (form.enabled !== state.value.enabled || form.time !== state.value.time))
async function copy(t: string) {
  try {
    await navigator.clipboard.writeText(t)
    toast.success('คัดลอกแล้ว')
  } catch {
    toast.error('คัดลอกไม่สำเร็จ')
  }
}
</script>

<template>
  <section aria-labelledby="s-owner" class="grid gap-4">
    <div>
      <h2 id="s-owner" class="m-0 text-xl font-semibold text-heading">สรุปประจำวันถึงเจ้าของร้าน</h2>
      <p class="m-0 mt-1 max-w-[65ch] text-[15px] text-muted-foreground">ส่งยอดขาย รายจ่าย ค่าแรงหมอ จำนวนลูกค้า และเรื่องที่ต้องดู เข้า LINE ส่วนตัวของคุณคนเดียว วันละครั้ง</p>
    </div>

    <div class="grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_340px]">
    <div class="grid gap-5 rounded-[18px] border border-border bg-card p-4 sm:p-5">
      <p v-if="!ready" class="m-0 text-[15px] text-muted-foreground">ตั้งค่าขั้นที่ 1–2 (เชื่อมบัญชี LINE OA และ Webhook) ให้เสร็จก่อน</p>

      <!-- ยังไม่ได้เชื่อม -->
      <template v-else-if="state && !state.linked">
        <ol class="m-0 grid list-decimal gap-2 pl-5 text-[15px] text-foreground">
          <li>
            เพิ่มเพื่อน LINE OA ของร้าน
            <a v-if="addFriendUrl" :href="addFriendUrl" target="_blank" rel="noopener" class="text-primary underline underline-offset-2">{{ botBasicId || 'เพิ่มเพื่อน' }}</a>
            <span v-else-if="botBasicId" class="num font-medium text-heading">{{ botBasicId }}</span>
            ด้วย LINE ของคุณเอง
          </li>
          <li>กดสร้างรหัส แล้วพิมพ์ข้อความที่ได้ในแชทกับ OA (แชทส่วนตัว ไม่ใช่ในกลุ่ม)</li>
        </ol>
        <div v-if="code" class="grid gap-2 rounded-xl bg-secondary/60 p-4">
          <p class="m-0 text-sm text-muted-foreground">พิมพ์ในแชทกับ OA (ใช้ได้ 30 นาที ครั้งเดียว)</p>
          <div class="flex flex-wrap items-center gap-2">
            <span class="num rounded-lg bg-card px-3 py-2 text-lg font-semibold text-heading">{{ command }}</span>
            <Button variant="outline" size="sm" @click="copy(command)">คัดลอก</Button>
          </div>
          <p class="m-0 text-sm text-muted-foreground">รอการเชื่อม… หน้านี้จะอัปเดตเองเมื่อสำเร็จ</p>
        </div>
        <div><Button :disabled="busy === 'code'" @click="createCode">{{ code ? 'สร้างรหัสใหม่' : 'สร้างรหัสเชื่อม LINE ของฉัน' }}</Button></div>
      </template>

      <!-- เชื่อมแล้ว -->
      <template v-else-if="state">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <p class="m-0 text-[15px]">
            ส่งเข้า LINE ของ <span class="font-semibold text-heading">{{ state.owner_name ?? 'เจ้าของร้าน' }}</span>
            <span v-if="state.last_date" class="block text-sm text-muted-foreground">ส่งล่าสุด: สรุปของวันที่ <span class="num">{{ state.last_date }}</span></span>
          </p>
          <Button variant="ghost" size="sm" class="text-danger-ink" :disabled="busy === 'unlink'" @click="unlink">เลิกเชื่อม</Button>
        </div>
        <form class="grid gap-4" @submit.prevent="save">
          <SwitchField v-model="form.enabled" label="ส่งสรุปทุกวัน" />
          <div class="grid gap-1.5 sm:max-w-xs">
            <TimeField v-model="form.time" label="เวลาส่ง" :disabled="!form.enabled" />
            <p class="m-0 text-sm text-muted-foreground">ส่งเวลานี้ = สรุป{{ covers }} (ตั้งก่อนเที่ยงวัน จะสรุปของเมื่อวาน)</p>
          </div>
          <div class="flex flex-wrap gap-2">
            <Button type="submit" :disabled="!dirty || busy === 'save'">{{ busy === 'save' ? 'กำลังบันทึก…' : 'บันทึก' }}</Button>
            <Button type="button" variant="outline" :disabled="busy === 'send'" @click="sendNow">{{ busy === 'send' ? 'กำลังส่ง…' : 'ส่งสรุปของวันนี้ตอนนี้' }}</Button>
          </div>
          <p class="m-0 text-sm text-muted-foreground">พิมพ์ “สรุป” ในแชทกับ OA เพื่อดูสรุปของวันนี้ได้ทุกเมื่อ หรือพิมพ์ “เลิกรับสรุป” เพื่อหยุดส่ง</p>
        </form>
      </template>
      <Skeleton v-else class="h-24 rounded-xl" />
    </div>

    <!-- ตัวอย่างการ์ดที่จะได้รับ: หน้าตาเหมือนแชท LINE -->
    <aside class="grid gap-3 lg:sticky lg:top-24" aria-label="ตัวอย่างสรุปประจำวัน">
      <div class="grid content-start gap-2 rounded-[18px] bg-secondary p-3 sm:p-4">
        <span class="justify-self-center rounded-full bg-card/70 px-3 py-0.5 text-xs text-muted-foreground">
          {{ state?.enabled !== false ? `ทุกวัน ${form.time} น.` : 'ปิดการส่งอัตโนมัติอยู่' }}
        </span>
        <div class="mt-2 flex items-start gap-2.5">
          <img v-if="botPicture" :src="botPicture" alt="" class="size-9 shrink-0 rounded-full" />
          <span v-else class="grid size-9 shrink-0 place-items-center rounded-full bg-card text-sm font-semibold text-heading" aria-hidden="true">{{ (botName ?? 'L').slice(0, 1) }}</span>
          <div class="grid min-w-0 gap-1">
            <span class="text-xs text-muted-foreground">{{ botName ?? 'LINE OA ของร้าน' }}</span>
            <LineCardPreview kind="owner" :branch="branch ?? ''" :company="companyName ?? undefined" :staff-url="staffUrl ?? ''" :summary-today="form.time >= '12:00'" />
          </div>
        </div>
      </div>
      <p class="m-0 text-sm text-muted-foreground">ตัวเลขในตัวอย่างเป็นข้อมูลสมมติ ข้อความจริงใช้ยอดของวันนั้น ส่วน “ต้องดู” ขึ้นเฉพาะเมื่อมีเรื่องค้าง</p>
    </aside>
    </div>
  </section>
</template>
