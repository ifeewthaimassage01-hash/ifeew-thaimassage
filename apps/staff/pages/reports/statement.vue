<script setup lang="ts">
// OWNER: Statement ของร้าน (รายการเงินเข้า/ออกเรียงตามเวลา + ยอดสะสม) — RPC shop_statement (migration 080)
//   จอ: รายการแบบ list จัดกลุ่มตามวัน (อ่านง่ายบนมือถือ)
//   PDF: ปุ่มดาวน์โหลด → หน้าต่างพิมพ์ของเบราว์เซอร์ → "บันทึกเป็น PDF" · เอกสารพิมพ์เป็นตารางแบบ statement ธนาคาร (A4)
import { FileDown } from '@lucide/vue'
import { bangkokToday } from '@ifeew/shared'

definePageMeta({ ownerOnly: true })

interface StatementRow { date: string; time: string | null; branch: string | null; branch_code: string | null; title: string; detail: string | null; in: number; out: number }
interface Statement {
  company: { name: string; legal_name: string | null; tax_id: string | null } | null
  branch: { name: string; code: string; address: string | null; phone: string | null } | null
  from: string
  to: string
  generated_at: string
  rows: StatementRow[]
}

const supabase = useSupabaseClient()
const { company, branches } = useAccess()

const today = bangkokToday()
const branchId = ref<string | null>(null)
const from = ref(`${today.slice(0, 7)}-01`)
const to = ref(today)
const data = ref<Statement | null>(null)
const loading = ref(false)
const error = ref<string | null>(null)

const branchItems = computed(() => [{ value: null, title: 'ทุกสาขา' }, ...branches.value.map((b) => ({ value: b.branch_id, title: b.name }))])

async function load() {
  if (!company.value) return
  loading.value = true
  try {
    data.value = (await must(supabase.rpc('shop_statement', {
      p_company_id: company.value.company_id, p_branch_id: branchId.value, p_from: from.value, p_to: to.value,
    }))) as unknown as Statement
    error.value = null
  } catch (e) {
    error.value = errorText(e, 'โหลด statement ไม่สำเร็จ')
  } finally {
    loading.value = false
  }
}
watch([branchId, from, to, () => company.value?.company_id], load, { immediate: true })

// ยอดสะสม (เริ่ม 0 ต้นงวด)
const rows = computed(() => {
  let bal = 0
  return (data.value?.rows ?? []).map((r) => {
    bal += Number(r.in) - Number(r.out)
    return { ...r, in: Number(r.in), out: Number(r.out), balance: bal }
  })
})
const sumIn = computed(() => rows.value.reduce((s, r) => s + r.in, 0))
const sumOut = computed(() => rows.value.reduce((s, r) => s + r.out, 0))
const countIn = computed(() => rows.value.filter((r) => r.in > 0).length)
const countOut = computed(() => rows.value.filter((r) => r.out > 0).length)
const net = computed(() => sumIn.value - sumOut.value)
const allBranches = computed(() => !data.value?.branch)
// PDF: แสดงวันที่เฉพาะแถวแรกของแต่ละวัน
const docRows = computed(() => rows.value.map((r, i) => ({ ...r, firstOfDay: i === 0 || rows.value[i - 1]!.date !== r.date })))

// จอ: จัดกลุ่มตามวัน (ใหม่สุดก่อน)
const days = computed(() => {
  const m = new Map<string, typeof rows.value>()
  for (const r of rows.value) m.set(r.date, [...(m.get(r.date) ?? []), r])
  return [...m.entries()].reverse().map(([date, list]) => ({
    date, list: [...list].reverse(),
    in: list.reduce((s, r) => s + r.in, 0), out: list.reduce((s, r) => s + r.out, 0),
  }))
})

const money = (n: number) => n.toLocaleString('th-TH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
const signed = (n: number) => (n < 0 ? `-${money(-n)}` : money(n))
const shortDate = (d: string) => new Date(`${d}T12:00:00+07:00`).toLocaleDateString('th-TH', { day: '2-digit', month: '2-digit', year: '2-digit', timeZone: 'Asia/Bangkok' })
const longDate = (d: string) => new Date(`${d}T12:00:00+07:00`).toLocaleDateString('th-TH', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric', timeZone: 'Asia/Bangkok' })
const printedAt = computed(() => data.value
  ? new Date(data.value.generated_at).toLocaleString('th-TH', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Bangkok' })
  : '')

function downloadPdf() {
  if (!data.value) return
  const prev = document.title
  // ชื่อไฟล์ที่เบราว์เซอร์เสนอตอน "บันทึกเป็น PDF"
  document.title = `statement_${data.value.branch?.code ?? 'ALL'}_${from.value}_${to.value}`
  const restore = () => {
    document.title = prev
    window.removeEventListener('afterprint', restore)
  }
  window.addEventListener('afterprint', restore)
  window.print()
}
</script>

<template>
  <div>
    <div class="mx-auto max-w-4xl print:hidden">
      <PageHeader title="Statement ร้าน" description="รายการเงินเข้า–ออกของร้านเรียงตามเวลา พร้อมยอดสะสม ดาวน์โหลดเป็น PDF ได้">
        <template #actions>
          <Button :disabled="!data || loading" @click="downloadPdf"><FileDown /> ดาวน์โหลด PDF</Button>
        </template>
      </PageHeader>

      <FilterPanel label="ตัวกรอง statement">
        <FilterRow label="สาขา">
          <SelectField v-model="branchId" :items="branchItems" aria-label="สาขา" class="w-full sm:w-64" />
        </FilterRow>
        <FilterRow label="ช่วงวันที่">
          <DateRangeFilter v-model:from="from" v-model:to="to" :presets="['month', 'last-month', 'year']" :max="today" />
        </FilterRow>
      </FilterPanel>

      <Alert v-if="error" variant="destructive" class="mb-4"><AlertDescription>{{ error }}</AlertDescription></Alert>
      <LoadingBar v-if="loading" class="mb-3" />

      <template v-if="data">
        <!-- สรุปช่วง -->
        <ul class="m-0 mb-6 grid list-none grid-cols-2 gap-3 p-0 sm:grid-cols-3">
          <li class="grid gap-1 rounded-[18px] border border-border bg-card p-4">
            <span class="text-sm text-muted-foreground">เงินเข้า · {{ countIn }} รายการ</span>
            <span class="num text-xl font-semibold text-success-ink">{{ money(sumIn) }}</span>
          </li>
          <li class="grid gap-1 rounded-[18px] border border-border bg-card p-4">
            <span class="text-sm text-muted-foreground">เงินออก · {{ countOut }} รายการ</span>
            <span class="num text-xl font-semibold text-danger-ink">{{ money(sumOut) }}</span>
          </li>
          <li class="col-span-2 grid gap-1 rounded-[18px] bg-primary p-4 text-primary-foreground sm:col-span-1">
            <span class="text-sm opacity-90">คงเหลือสุทธิ</span>
            <span class="num text-2xl font-bold">{{ signed(net) }}</span>
          </li>
        </ul>

        <p v-if="!rows.length" class="m-0 rounded-[18px] border border-border bg-card px-4 py-10 text-center text-sm text-muted-foreground">ไม่มีรายการในช่วงนี้</p>

        <!-- รายการตามวัน -->
        <section v-for="g in days" :key="g.date" class="mb-4 overflow-hidden rounded-[18px] border border-border bg-card" :aria-label="longDate(g.date)">
          <header class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 bg-muted/60 px-4 py-2.5 sm:px-5">
            <h2 class="m-0 text-[15px] font-semibold text-heading">{{ longDate(g.date) }}</h2>
            <p class="num m-0 text-sm text-muted-foreground">
              <span v-if="g.in" class="text-success-ink">+{{ money(g.in) }}</span>
              <span v-if="g.in && g.out"> · </span>
              <span v-if="g.out" class="text-danger-ink">−{{ money(g.out) }}</span>
            </p>
          </header>
          <ul class="m-0 grid list-none divide-y divide-border p-0">
            <li v-for="(r, i) in g.list" :key="i" class="grid grid-cols-[minmax(0,1fr)_auto] gap-x-4 gap-y-0.5 px-4 py-3 sm:px-5">
              <span class="font-medium text-heading">{{ r.title }}</span>
              <span class="num grid text-right font-semibold">
                <span v-if="r.in" class="text-success-ink">+{{ money(r.in) }}</span>
                <span v-if="r.out" class="text-danger-ink">−{{ money(r.out) }}</span>
              </span>
              <span class="min-w-0 truncate text-sm text-muted-foreground">
                <span class="num">{{ r.time ?? 'ทั้งวัน' }}</span><template v-if="allBranches && r.branch"> · {{ r.branch }}</template><template v-if="r.detail"> · {{ r.detail }}</template>
              </span>
              <span class="num text-right text-sm text-muted-foreground">คงเหลือ {{ signed(r.balance) }}</span>
            </li>
          </ul>
        </section>

        <p class="m-0 mt-2 text-sm text-muted-foreground">
          เงินเข้า = ค่าบริการที่ชำระแล้วและมัดจำที่ริบ · เงินออก = ค่ามือหมอ การันตี/ปรับค่าแรง รายจ่าย และคืนเงินลูกค้า · ไม่รวมทิป · ยอดคงเหลือเริ่มนับ 0 ที่วันแรกของช่วง
        </p>
      </template>
    </div>

    <!-- เอกสารสำหรับพิมพ์ / PDF (แสดงเฉพาะตอนพิมพ์) · สีกำหนดตายตัว ไม่ขึ้นกับธีมมืด/สว่างของเครื่อง -->
    <Teleport to="body">
      <article v-if="data" id="statement-doc" class="sd">
        <header class="sd-head">
          <div class="sd-brand">
            <BrandMark class="sd-mark" />
            <div>
              <p class="sd-company">{{ data.company?.name }}</p>
              <p v-if="data.company?.legal_name && data.company.legal_name !== data.company.name" class="sd-sub">{{ data.company.legal_name }}</p>
              <p v-if="data.company?.tax_id" class="sd-sub">เลขประจำตัวผู้เสียภาษี <span class="sd-num">{{ data.company.tax_id }}</span></p>
            </div>
          </div>
          <div class="sd-title">
            <p class="sd-eyebrow">SHOP STATEMENT</p>
            <p class="sd-h1">รายการเดินบัญชีร้าน</p>
          </div>
        </header>

        <section class="sd-info">
          <dl class="sd-meta">
            <dt>สาขา</dt><dd>{{ data.branch ? data.branch.name : 'ทุกสาขา' }}</dd>
            <template v-if="data.branch?.address"><dt>ที่อยู่</dt><dd>{{ data.branch.address }}</dd></template>
            <template v-if="data.branch?.phone"><dt>โทร</dt><dd class="sd-num">{{ data.branch.phone }}</dd></template>
            <dt>ช่วงวันที่</dt><dd class="sd-num">{{ shortDate(data.from) }} – {{ shortDate(data.to) }}</dd>
            <dt>ออกเอกสาร</dt><dd class="sd-num">{{ printedAt }} น.</dd>
          </dl>
          <div class="sd-sum">
            <div class="sd-sum-row"><span>เงินเข้า <small>{{ countIn }} รายการ</small></span><span class="sd-num sd-in">{{ money(sumIn) }}</span></div>
            <div class="sd-sum-row"><span>เงินออก <small>{{ countOut }} รายการ</small></span><span class="sd-num sd-out">{{ money(sumOut) }}</span></div>
            <div class="sd-sum-net"><span>คงเหลือสุทธิ</span><span class="sd-num">{{ signed(net) }} <small>บาท</small></span></div>
          </div>
        </section>

        <table class="sd-table">
          <colgroup>
            <col class="sd-c-date"><col><col class="sd-c-amt"><col class="sd-c-amt"><col class="sd-c-amt"><col v-if="allBranches" class="sd-c-br">
          </colgroup>
          <thead>
            <tr>
              <th>วันที่</th>
              <th>รายการ</th>
              <th class="r">เงินออก</th>
              <th class="r">เงินเข้า</th>
              <th class="r">ยอดคงเหลือ</th>
              <th v-if="allBranches" class="c">สาขา</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="!rows.length"><td :colspan="allBranches ? 6 : 5" class="sd-empty">ไม่มีรายการในช่วงนี้</td></tr>
            <tr v-for="(r, i) in docRows" :key="i" :class="{ 'sd-newday': r.firstOfDay && i > 0 }">
              <td class="sd-num">
                <span v-if="r.firstOfDay" class="sd-date">{{ shortDate(r.date) }}</span>
                <span class="sd-time">{{ r.time ?? '' }}</span>
              </td>
              <td>
                {{ r.title }}
                <span v-if="r.detail" class="sd-detail">{{ r.detail }}</span>
              </td>
              <td class="r sd-num sd-out">{{ r.out ? money(r.out) : '' }}</td>
              <td class="r sd-num sd-in">{{ r.in ? money(r.in) : '' }}</td>
              <td class="r sd-num sd-bal" :class="{ 'sd-neg': r.balance < 0 }">{{ signed(r.balance) }}</td>
              <td v-if="allBranches" class="c sd-br">{{ r.branch ? (provinceAbbr(r.branch) ?? r.branch_code) : 'HQ' }}</td>
            </tr>
          </tbody>
          <tfoot v-if="rows.length">
            <tr>
              <td colspan="2">รวม {{ rows.length }} รายการ</td>
              <td class="r sd-num sd-out">{{ money(sumOut) }}</td>
              <td class="r sd-num sd-in">{{ money(sumIn) }}</td>
              <td class="r sd-num sd-bal" :class="{ 'sd-neg': net < 0 }">{{ signed(net) }}</td>
              <td v-if="allBranches" />
            </tr>
          </tfoot>
        </table>

        <footer class="sd-foot">
          <p>เงินเข้า = ค่าบริการที่ชำระแล้วและมัดจำที่ริบ · เงินออก = ค่ามือหมอ การันตี/ปรับค่าแรง รายจ่าย และคืนเงินลูกค้า · ไม่รวมทิป</p>
          <p>ยอดคงเหลือเริ่มนับ 0 ณ วันแรกของช่วง · เอกสารนี้ออกจากระบบโดยอัตโนมัติ ไม่ใช่ใบเสร็จรับเงิน</p>
        </footer>
      </article>
    </Teleport>
  </div>
</template>

<style>
#statement-doc { display: none; }
@media print {
  @page {
    size: A4;
    margin: 12mm 11mm 14mm;
    @bottom-right { content: "หน้า " counter(page) " / " counter(pages); font-size: 8pt; color: #8a7b6d; font-family: sans-serif; }
  }
  html, body { background: #fff !important; }
  /* เอกสารถูก teleport ไปใต้ body → ซ่อนแอปทั้งหมด เหลือแต่เอกสาร */
  body > *:not(#statement-doc) { display: none !important; }
  #statement-doc { display: block; }
}

.sd {
  --ink: #2f261f; --heading: #514337; --muted: #8a7b6d; --line: #e6dbcf; --tint: #f6efe7;
  --teak: #93704f; --in: #3f6b4e; --out: #9e5149;
  color: var(--ink); font-size: 9.5pt; line-height: 1.45;
  -webkit-print-color-adjust: exact; print-color-adjust: exact;
}
.sd p { margin: 0; }
.sd-num { font-variant-numeric: tabular-nums; }

.sd-head {
  display: flex; align-items: flex-end; justify-content: space-between; gap: 24px;
  padding-bottom: 14px; border-bottom: 2.5pt solid var(--teak);
}
.sd-brand { display: flex; align-items: center; gap: 12px; }
.sd-mark { width: 40px; height: 58px; object-fit: contain; }
.sd-company { font-size: 16pt; font-weight: 700; color: var(--heading); line-height: 1.2; }
.sd-sub { font-size: 8.5pt; color: var(--muted); }
.sd-title { text-align: right; }
.sd-eyebrow { font-size: 7.5pt; font-weight: 600; letter-spacing: .18em; color: var(--teak); }
.sd-h1 { font-size: 15pt; font-weight: 700; color: var(--heading); line-height: 1.25; }

.sd-info { display: grid; grid-template-columns: 1fr 230px; gap: 20px; padding: 16px 0 18px; }
.sd-meta { display: grid; grid-template-columns: auto 1fr; gap: 4px 16px; margin: 0; align-content: start; }
.sd-meta dt { color: var(--muted); }
.sd-meta dd { margin: 0; color: var(--ink); }
.sd-sum { background: var(--tint); border-radius: 10px; padding: 10px 14px; display: grid; gap: 4px; break-inside: avoid; }
.sd-sum-row { display: flex; justify-content: space-between; gap: 12px; }
.sd-sum-row small { color: var(--muted); font-size: 8pt; margin-left: 4px; }
.sd-sum-net {
  display: flex; justify-content: space-between; align-items: baseline; gap: 12px;
  margin-top: 4px; padding-top: 6px; border-top: 1px solid var(--line);
  font-weight: 700; color: var(--heading);
}
.sd-sum-net .sd-num { font-size: 13pt; }
.sd-sum-net small { font-size: 8pt; font-weight: 400; color: var(--muted); }
.sd-in { color: var(--in); }
.sd-out { color: var(--out); }

.sd-table { width: 100%; border-collapse: collapse; table-layout: fixed; }
.sd-c-date { width: 76px; }
.sd-c-amt { width: 84px; }
.sd-c-br { width: 66px; }
.sd-table thead { display: table-header-group; }
.sd-table tfoot { display: table-row-group; }
.sd-table th { white-space: nowrap;
  background: var(--tint); color: var(--heading); font-weight: 600; font-size: 8.5pt;
  text-align: left; padding: 7px 8px; border-bottom: 1px solid var(--line);
}
.sd-table td { padding: 6px 8px; vertical-align: top; border-bottom: 1px solid #f0e8de; overflow-wrap: anywhere; }
.sd-table tbody tr { break-inside: avoid; }
.sd-table tr.sd-newday td { border-top: 1px solid var(--line); }
.sd-table .r { text-align: right; }
.sd-table .c { text-align: center; }
.sd-date { display: block; white-space: nowrap; font-weight: 600; color: var(--heading); }
.sd-time { display: block; font-size: 8pt; color: var(--muted); }
.sd-detail { display: block; font-size: 8pt; color: var(--muted); }
.sd-bal { font-weight: 600; color: var(--heading); }
.sd-neg { color: var(--out); }
.sd-br { white-space: nowrap; }
.sd-empty { text-align: center; color: var(--muted); padding: 24px 8px !important; }
.sd-table tfoot td {
  border-top: 1.5pt solid var(--heading); border-bottom: none; padding-top: 8px;
  font-weight: 700; color: var(--heading);
}

.sd-foot { margin-top: 18px; padding-top: 10px; border-top: 1px solid var(--line); font-size: 7.5pt; color: var(--muted); display: grid; gap: 2px; }
</style>
