<script setup lang="ts">
// ติดตามการจองด้วย Tracking Token (Guest / ลิงก์ที่ร้านส่งให้) — ดูสถานะ + ชำระมัดจำเท่านั้น
import { RefreshCw } from '@lucide/vue'
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
    <PageHeader title="สถานะการจอง" description="เก็บลิงก์หน้านี้ไว้ดูสถานะ และอย่าส่งต่อให้ผู้อื่น">
      <template #actions>
        <Button variant="outline" :disabled="loading" @click="load"><RefreshCw :class="loading ? 'animate-spin' : ''" /> โหลดสถานะล่าสุด</Button>
      </template>
    </PageHeader>
    <div v-if="loading && !booking" class="grid gap-4 md:grid-cols-2"><Skeleton class="h-80 rounded-xl" /><Skeleton class="h-80 rounded-xl" /></div>
    <Alert v-else-if="error" variant="info"><AlertDescription>{{ error }}</AlertDescription></Alert>
    <BookingDetail v-else-if="booking" :booking="booking" :token="token" @updated="(v) => (booking = { ...booking!, ...v })" />
  </div>
</template>
