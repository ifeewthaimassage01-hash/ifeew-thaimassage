<script setup lang="ts">
// งานของฉัน (หมอ): บริการที่ทำเสร็จ + ค่ามือประมาณการของตัวเอง (ยอดจ่ายจริงออกในระบบคอมมิชชัน)
import { CircleCheck, Clock, HandCoins } from '@lucide/vue'
import { addDays, bangkokTime, bangkokToday, formatBaht, formatDuration, formatQueueNumber, type MyEarnings, type WorkHistory } from '@ifeew/shared'

const supabase = useSupabaseClient()

const from = ref(bangkokToday())
const to = ref(bangkokToday())
const data = ref<WorkHistory | null>(null)
const loading = ref(false)
const error = ref<string | null>(null)

async function load() {
  loading.value = true
  try {
    data.value = (await must(supabase.rpc('my_work_history', { p_from: from.value, p_to: to.value }))) as unknown as WorkHistory
    error.value = null
  } catch (e) {
    error.value = errorText(e, 'โหลดไม่สำเร็จ')
  } finally {
    loading.value = false
  }
}

function preset(kind: 'today' | 'week' | 'month') {
  const today = bangkokToday()
  to.value = today
  from.value = kind === 'today' ? today : kind === 'week' ? addDays(today, -6) : `${today.slice(0, 7)}-01`
}

watch([from, to], load, { immediate: true })

// รายได้ (ค่ามือที่ถึงเกณฑ์ + ประกันมือ) และรอบจ่าย
const earnings = ref<MyEarnings | null>(null)
async function loadEarnings() {
  const { data: e } = await supabase.rpc('my_earnings', { p_from: from.value, p_to: to.value })
  earnings.value = (e ?? null) as unknown as MyEarnings | null
}
watch([from, to], loadEarnings, { immediate: true })
</script>

<template>
  <div class="max-w-5xl">
    <PageHeader title="งานของฉัน" description="บริการที่ทำเสร็จและค่ามือประมาณการของคุณ ยอดจ่ายจริงยืนยันโดยเจ้าของร้าน" />

    <div class="mb-6 flex flex-wrap items-end gap-3 rounded-xl border border-border bg-card p-4">
      <div class="grid gap-1.5">
        <span class="text-sm font-medium text-heading">ช่วงเวลา</span>
        <div class="flex flex-wrap gap-2">
          <Button variant="outline" size="sm" @click="preset('today')">วันนี้</Button>
          <Button variant="outline" size="sm" @click="preset('week')">7 วัน</Button>
          <Button variant="outline" size="sm" @click="preset('month')">เดือนนี้</Button>
        </div>
      </div>
      <TextField v-model="from" type="date" label="ตั้งแต่" class="w-44" />
      <TextField v-model="to" type="date" label="ถึง" class="w-44" />
    </div>

    <Alert v-if="error" variant="destructive" class="mb-4"><AlertDescription>{{ error }}</AlertDescription></Alert>
    <LoadingBar v-if="loading" class="mb-3" />

    <div v-if="data" class="grid gap-6">
      <div class="grid gap-4 sm:grid-cols-3">
        <StatCard label="บริการที่ทำเสร็จ" :icon="CircleCheck" :value="data.total_count" />
        <StatCard label="เวลาทำงาน" :icon="Clock" :value="formatDuration(data.total_minutes)" />
        <StatCard label="ค่ามือ (ประมาณการ)" :icon="HandCoins" :value="formatBaht(Number(data.total_fee_estimate))" hint="ถ้าส่งต่อระหว่างบริการ แบ่งตามเวลาที่ทำจริง" />
      </div>

      <SectionCard v-if="earnings" title="รายได้ที่ร้านจะจ่าย" description="ค่ามือเข้าเกณฑ์จ่ายเมื่อบริการจบและลูกค้าจ่ายครบ · ประกันมือคิดเมื่อลงเวลาเข้า-ออกครบกะ" flush>
        <div class="grid gap-4 border-b border-border p-5 sm:grid-cols-2">
          <div>
            <p class="m-0 text-sm text-muted-foreground">ค้างจ่าย</p>
            <p class="num m-0 text-2xl font-semibold text-heading">{{ formatBaht(Number(earnings.unpaid)) }}</p>
            <p v-if="Number(earnings.unpaid_tips)" class="m-0 text-sm text-muted-foreground">ทิป (โอน/QR) ค้างจ่าย <span class="num">{{ formatBaht(Number(earnings.unpaid_tips)) }}</span></p>
          </div>
          <div v-if="earnings.payouts.length">
            <p class="m-0 text-sm text-muted-foreground">จ่ายล่าสุด</p>
            <p class="num m-0 text-2xl font-semibold text-heading">{{ formatBaht(Number(earnings.payouts[0]!.net_amount)) }}</p>
            <p class="num m-0 text-sm text-muted-foreground">{{ earnings.payouts[0]!.paid_at.slice(0, 10) }}</p>
          </div>
        </div>
        <ul v-if="earnings.days.length" class="m-0 grid list-none p-0">
          <li v-for="d in earnings.days" :key="d.business_date" class="flex flex-wrap items-center justify-between gap-2 border-b border-border px-5 py-3 text-[15px] last:border-0">
            <span>
              <span class="num text-heading">{{ d.business_date }}</span>
              <span v-if="d.clock_in_at" class="text-muted-foreground"> · ลงเวลา <span class="num">{{ bangkokTime(d.clock_in_at) }}–{{ d.clock_out_at ? bangkokTime(d.clock_out_at) : '?' }}</span></span>
            </span>
            <span>
              ค่ามือ <span class="num text-heading">{{ formatBaht(Number(d.service ?? 0)) }}</span>
              <Badge v-if="Number(d.guarantee)" variant="success" class="ml-2">ประกันมือเติม {{ formatBaht(Number(d.guarantee)) }}</Badge>
            </span>
          </li>
        </ul>
      </SectionCard>

      <SectionCard title="บริการที่ทำ" :description="`${data.rows.length} รายการ`" flush>
        <EmptyState v-if="!data.rows.length" compact title="ยังไม่มีงานในช่วงนี้" class="m-5" />
        <ul v-else class="m-0 grid list-none p-0">
          <li v-for="r in data.rows" :key="r.assignment_id" class="flex flex-wrap items-center justify-between gap-3 border-b border-border px-5 py-3.5 last:border-0">
            <div class="min-w-0">
              <p class="m-0 font-medium text-heading">คิว <span class="num">{{ formatQueueNumber(r.queue_number) }}</span> · {{ r.service_name }} <span class="font-normal text-muted-foreground">{{ formatDuration(r.duration_minutes) }}</span></p>
              <p class="m-0 text-sm text-muted-foreground">
                <span class="num">{{ r.business_date }}</span> · {{ r.branch_name }} · <span class="num">{{ bangkokTime(r.started_at) }}–{{ bangkokTime(r.ended_at) }}</span> ({{ r.worked_minutes }} นาที)
              </p>
              <div v-if="r.handover || r.off_shift" class="mt-1 flex gap-1.5">
                <Badge v-if="r.handover" variant="neutral">ส่งต่อ/รับต่อ</Badge>
                <Badge v-if="r.off_shift" variant="pending">นอกกะ</Badge>
              </div>
            </div>
            <p class="num m-0 text-lg font-semibold text-heading">{{ r.fee_estimate != null ? formatBaht(Number(r.fee_estimate)) : '—' }}</p>
          </li>
        </ul>
      </SectionCard>
    </div>
  </div>
</template>
