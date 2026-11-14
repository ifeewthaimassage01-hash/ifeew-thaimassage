<script setup lang="ts">
// ติดตามการจองด้วย Tracking Token (ลูกค้า Guest / ลิงก์ที่ร้านส่งให้) — ดูสถานะ · ชำระมัดจำ · ยกเลิกการจองเอง
import { RefreshCw } from '@lucide/vue'
import { toast } from 'vue-sonner'
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

// ยกเลิกเองได้เมื่อยังไม่ถึงคิว และสลิปไม่ได้รอตรวจ (ระยะเวลาก่อนนัดตรวจที่ระบบ)
const canCancel = computed(
  () => !!booking.value && ['PENDING', 'CONFIRMED'].includes(booking.value.status) && booking.value.deposit_status !== 'PENDING_REVIEW',
)
const cancelOpen = ref(false)
const cancelReason = ref('')
const cancelling = ref(false)

async function confirmCancel() {
  cancelling.value = true
  try {
    const view = await call<BookingView>('booking-tracking', { token: token.value, action: 'cancel', reason: cancelReason.value.trim() })
    booking.value = { ...booking.value!, ...view }
    cancelOpen.value = false
    toast.success('ยกเลิกการจองแล้ว')
  } catch (e) {
    toast.error(edgeErrorText(e, 'ยกเลิกไม่สำเร็จ กรุณาติดต่อร้าน'))
  } finally {
    cancelling.value = false
  }
}
</script>

<template>
  <div>
    <PageHeader title="สถานะการจอง" description="เก็บลิงก์หน้านี้ไว้ดูสถานะ และอย่าส่งต่อให้ผู้อื่น">
      <template #actions>
        <Button variant="outline" :disabled="loading" @click="load"><RefreshCw :class="loading ? 'animate-spin' : ''" /> โหลดสถานะล่าสุด</Button>
      </template>
    </PageHeader>
    <div v-if="loading && !booking" class="grid gap-4 md:grid-cols-2"><Skeleton class="h-80 rounded-xl" /><Skeleton class="h-80 rounded-xl" /></div>
    <Alert v-else-if="error" variant="info">
      <AlertDescription>{{ error }} · <NuxtLink to="/check-booking">ตรวจสอบการจองด้วยเบอร์โทร</NuxtLink></AlertDescription>
    </Alert>
    <BookingDetail
      v-else-if="booking"
      :booking="booking"
      :token="token"
      :can-cancel="canCancel"
      @updated="(v) => (booking = { ...booking!, ...v })"
      @cancel="cancelReason = ''; cancelOpen = true"
    />

    <Dialog v-model:open="cancelOpen">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>ยกเลิกการจองนี้?</DialogTitle>
          <DialogDescription>เมื่อยกเลิกแล้ว คิวจะถูกปล่อยให้ลูกค้าท่านอื่น ถ้าโอนมัดจำแล้ว ร้านจะติดต่อกลับเรื่องการคืนเงิน</DialogDescription>
        </DialogHeader>
        <div class="grid gap-1.5">
          <Label for="cancel-reason">เหตุผล <span class="font-normal text-muted-foreground">(ไม่บังคับ)</span></Label>
          <Textarea id="cancel-reason" v-model="cancelReason" rows="2" maxlength="500" placeholder="เช่น ติดธุระ" />
        </div>
        <DialogFooter class="gap-2">
          <Button variant="outline" :disabled="cancelling" @click="cancelOpen = false">ไม่ยกเลิก</Button>
          <Button variant="destructive" :disabled="cancelling" @click="confirmCancel">{{ cancelling ? 'กำลังยกเลิก…' : 'ยืนยันยกเลิก' }}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
