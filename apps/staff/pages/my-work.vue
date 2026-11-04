<script setup lang="ts">
// งานของฉัน (หมอ): บริการที่ทำเสร็จ + ค่ามือประมาณการของตัวเอง (ยอดจ่ายจริงออกในระบบคอมมิชชัน)
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
  <div class="max-w-4xl">
    <h1 class="m-0 mb-4 text-2xl font-semibold text-cocoa">งานของฉัน</h1>

    <div class="mb-4 flex flex-wrap items-center gap-2">
      <v-btn variant="tonal" size="small" @click="preset('today')">วันนี้</v-btn>
      <v-btn variant="tonal" size="small" @click="preset('week')">7 วัน</v-btn>
      <v-btn variant="tonal" size="small" @click="preset('month')">เดือนนี้</v-btn>
      <v-text-field v-model="from" type="date" label="ตั้งแต่" hide-details density="compact" class="max-w-44" />
      <v-text-field v-model="to" type="date" label="ถึง" hide-details density="compact" class="max-w-44" />
    </div>

    <v-alert v-if="error" type="error" variant="tonal" class="mb-4" :text="error" />
    <v-progress-linear v-if="loading" indeterminate color="primary" />

    <template v-if="data">
      <div class="mb-4 grid gap-4 sm:grid-cols-3">
        <v-card class="p-5">
          <p class="m-0 text-sm text-light-brown">บริการที่ทำเสร็จ</p>
          <p class="m-0 mt-1 text-3xl font-semibold">{{ data.total_count }}</p>
        </v-card>
        <v-card class="p-5">
          <p class="m-0 text-sm text-light-brown">เวลาทำงาน</p>
          <p class="m-0 mt-1 text-3xl font-semibold">{{ formatDuration(data.total_minutes) }}</p>
        </v-card>
        <v-card class="p-5">
          <p class="m-0 text-sm text-light-brown">ค่ามือ (ประมาณการ)</p>
          <p class="m-0 mt-1 text-3xl font-semibold">{{ formatBaht(Number(data.total_fee_estimate)) }}</p>
        </v-card>
      </div>
      <p class="m-0 mb-3 text-xs text-light-brown">
        ค่ามือเป็นยอดประมาณการจากราคาที่ตั้งไว้ (ถ้าส่งต่อหมอระหว่างบริการ แบ่งตามเวลาที่ทำจริง) ยอดจ่ายจริงยืนยันโดยเจ้าของร้าน
      </p>

      <v-card v-if="earnings" class="mb-4 p-4">
        <p class="m-0 mb-2 font-medium">รายได้ที่ร้านจะจ่าย</p>
        <p class="m-0 text-sm">
          ค้างจ่าย <b>{{ formatBaht(Number(earnings.unpaid)) }}</b>
          <template v-if="Number(earnings.unpaid_tips)"> · ทิป (โอน/QR) ค้างจ่าย {{ formatBaht(Number(earnings.unpaid_tips)) }}</template>
        </p>
        <div v-if="earnings.days.length" class="mt-2 text-sm">
          <p v-for="d in earnings.days" :key="d.business_date" class="m-0">
            {{ d.business_date }} · ค่ามือ {{ formatBaht(Number(d.service ?? 0)) }}
            <template v-if="Number(d.guarantee)"> · <b>ประกันมือเติม {{ formatBaht(Number(d.guarantee)) }}</b></template>
            <span v-if="d.clock_in_at" class="text-light-brown"> · ลงเวลา {{ bangkokTime(d.clock_in_at) }}–{{ d.clock_out_at ? bangkokTime(d.clock_out_at) : '?' }}</span>
          </p>
        </div>
        <p v-if="earnings.payouts.length" class="m-0 mt-2 text-sm text-light-brown">
          จ่ายล่าสุด {{ earnings.payouts[0]!.paid_at.slice(0, 10) }} · {{ formatBaht(Number(earnings.payouts[0]!.net_amount)) }}
        </p>
        <p class="m-0 mt-1 text-xs text-light-brown">ค่ามือเข้าเกณฑ์จ่ายเมื่อบริการจบและลูกค้าจ่ายครบ · ประกันมือคิดเมื่อลงเวลาเข้า-ออกครบกะ</p>
      </v-card>

      <p v-if="!data.rows.length" class="text-light-brown">ยังไม่มีงานในช่วงนี้</p>
      <div class="grid gap-2">
        <v-card v-for="r in data.rows" :key="r.assignment_id" class="flex flex-wrap items-center justify-between gap-2 p-4">
          <div>
            <p class="m-0 font-medium">คิว {{ formatQueueNumber(r.queue_number) }} · {{ r.service_name }} {{ formatDuration(r.duration_minutes) }}</p>
            <p class="m-0 text-sm text-light-brown">
              {{ r.business_date }} · {{ r.branch_name }} · {{ bangkokTime(r.started_at) }}–{{ bangkokTime(r.ended_at) }} ({{ r.worked_minutes }} นาที)
              <span v-if="r.handover"> · ส่งต่อ/รับต่อ</span><span v-if="r.off_shift"> · นอกกะ</span>
            </p>
          </div>
          <p class="m-0 text-lg font-semibold">{{ r.fee_estimate != null ? formatBaht(Number(r.fee_estimate)) : '-' }}</p>
        </v-card>
      </div>
    </template>
  </div>
</template>
