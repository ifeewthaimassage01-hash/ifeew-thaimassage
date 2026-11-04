<script setup lang="ts">
// ติดตามการจองด้วย Tracking Token (Guest / ลิงก์ที่ร้านส่งให้) — ดูสถานะ + ชำระมัดจำเท่านั้น
import type { BookingView } from '@ifeew/shared'

useHead({
  title: "สถานะการจอง — Ifeew's Thaimassage",
  // ไม่ส่ง URL ที่มี token ไปให้เว็บอื่นผ่าน Referer และไม่ให้ search engine เก็บ
  meta: [{ name: 'referrer', content: 'no-referrer' }, { name: 'robots', content: 'noindex' }],
})

const route = useRoute()
const token = computed(() => String(route.params.token))
const { call } = useEdgeFunction()

const booking = ref<BookingView | null>(null)
const loading = ref(true)
const error = ref<string | null>(null)

async function load() {
  loading.value = true
  error.value = null
  try {
    booking.value = await call<BookingView>('booking-tracking', { token: token.value })
  } catch (e) {
    error.value = edgeErrorText(e, 'ไม่พบการจอง หรือลิงก์หมดอายุแล้ว')
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <div>
    <h1 class="m-0 mb-4 text-2xl font-semibold text-cocoa">สถานะการจอง</h1>
    <v-progress-linear v-if="loading" indeterminate color="primary" />
    <v-alert v-else-if="error" type="info" variant="tonal" :text="error" />
    <template v-else-if="booking">
      <v-alert type="info" variant="tonal" class="mb-4" density="compact"
        text="เก็บลิงก์หน้านี้ไว้เพื่อดูสถานะการจอง (อย่าส่งต่อให้ผู้อื่น)" />
      <BookingDetail :booking="booking" :token="token" @updated="(v) => (booking = { ...booking!, ...v })" />
      <v-btn variant="text" prepend-icon="mdi-refresh" class="mt-2" @click="load">โหลดสถานะล่าสุด</v-btn>
    </template>
  </div>
</template>
