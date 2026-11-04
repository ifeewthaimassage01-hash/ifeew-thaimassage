<script setup lang="ts">
// OWNER: สรุปงานรายหมอ (จำนวนบริการ เวลา นอกกะ ส่งต่อ ค่ามือประมาณการ)
import { addDays, bangkokToday, formatBaht, formatDuration, type TherapistSummaryRow } from '@ifeew/shared'

definePageMeta({ ownerOnly: true })

const supabase = useSupabaseClient()
const { company, branches } = useAccess()

const branchId = ref<string | null>(null)
const from = ref(`${bangkokToday().slice(0, 7)}-01`)
const to = ref(bangkokToday())
const rows = ref<TherapistSummaryRow[]>([])
const loading = ref(false)
const error = ref<string | null>(null)

const branchItems = computed(() => [{ value: null, title: 'ทุกสาขา' }, ...branches.value.map((b) => ({ value: b.branch_id, title: b.name }))])
const totals = computed(() => ({
  services: rows.value.reduce((s, r) => s + r.services, 0),
  minutes: rows.value.reduce((s, r) => s + r.worked_minutes, 0),
  fee: rows.value.reduce((s, r) => s + Number(r.fee_estimate), 0),
}))

async function load() {
  if (!company.value) return
  loading.value = true
  try {
    rows.value = (await must(supabase.rpc('therapist_work_summary', {
      p_company_id: company.value.company_id, p_branch_id: branchId.value, p_from: from.value, p_to: to.value,
    }))) as unknown as TherapistSummaryRow[]
    error.value = null
  } catch (e) {
    error.value = errorText(e, 'โหลดไม่สำเร็จ')
  } finally {
    loading.value = false
  }
}

watch([branchId, from, to, () => company.value?.company_id], load, { immediate: true })
</script>

<template>
  <div class="max-w-5xl">
    <h1 class="m-0 mb-4 text-2xl font-semibold text-cocoa">สรุปงานหมอ</h1>

    <div class="mb-4 flex flex-wrap items-center gap-2">
      <v-select v-model="branchId" :items="branchItems" label="สาขา" hide-details density="compact" class="max-w-52" />
      <v-text-field v-model="from" type="date" label="ตั้งแต่" hide-details density="compact" class="max-w-44" />
      <v-text-field v-model="to" type="date" label="ถึง" hide-details density="compact" class="max-w-44" />
      <v-btn variant="text" size="small" @click="from = addDays(bangkokToday(), -6); to = bangkokToday()">7 วัน</v-btn>
    </div>

    <v-alert v-if="error" type="error" variant="tonal" class="mb-4" :text="error" />
    <v-progress-linear v-if="loading" indeterminate color="primary" />

    <v-card class="p-2">
      <v-table>
        <thead>
          <tr>
            <th>หมอ</th>
            <th class="text-right">บริการ</th>
            <th class="text-right">เวลาทำงาน</th>
            <th class="text-right">นอกกะ</th>
            <th class="text-right">ส่งต่อ</th>
            <th class="text-right">ค่ามือ (ประมาณการ)</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in rows" :key="r.employee_id">
            <td>{{ r.nickname }} <span class="text-xs text-light-brown">{{ r.employee_code }}</span></td>
            <td class="text-right">{{ r.services }}</td>
            <td class="text-right">{{ formatDuration(r.worked_minutes) }}</td>
            <td class="text-right">{{ r.off_shift_count }}</td>
            <td class="text-right">{{ r.handover_count }}</td>
            <td class="text-right">{{ formatBaht(Number(r.fee_estimate)) }}</td>
          </tr>
          <tr v-if="!rows.length"><td colspan="6" class="text-center text-light-brown">ไม่มีข้อมูลในช่วงนี้</td></tr>
          <tr v-else class="font-semibold">
            <td>รวม</td>
            <td class="text-right">{{ totals.services }}</td>
            <td class="text-right">{{ formatDuration(totals.minutes) }}</td>
            <td />
            <td />
            <td class="text-right">{{ formatBaht(totals.fee) }}</td>
          </tr>
        </tbody>
      </v-table>
    </v-card>
    <p class="m-0 mt-2 text-xs text-light-brown">ค่ามือคิดจากราคาที่ตั้งไว้ต่อบริการ ไม่หักส่วนลด ยอดจ่ายจริงยืนยันในระบบคอมมิชชัน</p>
  </div>
</template>
