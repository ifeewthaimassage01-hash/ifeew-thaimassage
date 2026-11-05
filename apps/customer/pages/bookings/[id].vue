<script setup lang="ts">
// รายละเอียดการจองของสมาชิก + ชำระมัดจำ + ยกเลิก (ก่อนนัดตามนโยบาย)
import { toast } from 'vue-sonner'
import type { BookingView } from '@ifeew/shared'

definePageMeta({ middleware: 'auth' })
useHead({ title: "การจอง — Ifeew's Thaimassage" })

const route = useRoute()
const supabase = useSupabaseClient()
const { code } = useCompany()
const id = computed(() => String(route.params.id))

const booking = ref<BookingView | null>(null)
const loading = ref(true)
const cancelDialog = ref(false)
const cancelReason = ref('')
const cancelling = ref(false)

async function load() {
  const { data } = await supabase.rpc('my_booking', { p_company_code: code, p_booking_id: id.value })
  booking.value = (data ?? null) as unknown as BookingView | null
  loading.value = false
}

const canCancel = computed(
  () => !!booking.value && ['PENDING', 'CONFIRMED'].includes(booking.value.status) && booking.value.deposit_status !== 'PENDING_REVIEW',
)

async function cancel() {
  cancelling.value = true
  const { data, error } = await supabase.rpc('cancel_my_booking', {
    p_company_code: code, p_booking_id: id.value, p_reason: cancelReason.value.trim() || null,
  })
  cancelling.value = false
  cancelDialog.value = false
  if (error) {
    toast.error(error.message)
    return
  }
  booking.value = data as unknown as BookingView
  toast.success(booking.value.deposit_status === 'REFUND_PENDING' ? 'ยกเลิกแล้ว ร้านจะโอนคืนมัดจำให้' : 'ยกเลิกการจองแล้ว')
}

onMounted(load)
</script>

<template>
  <div>
    <PageHeader title="รายละเอียดการจอง" :description="booking?.booking_code ? `รหัสการจอง ${booking.booking_code}` : undefined">
      <template #actions><Button as-child variant="outline"><NuxtLink to="/bookings">การจองทั้งหมด</NuxtLink></Button></template>
    </PageHeader>
    <div v-if="loading" class="grid gap-4 md:grid-cols-2"><Skeleton class="h-80 rounded-xl" /><Skeleton class="h-80 rounded-xl" /></div>
    <EmptyState v-else-if="!booking" title="ไม่พบการจองนี้" description="การจองอาจถูกลบหรือเป็นของบัญชีอื่น">
      <Button as-child variant="outline"><NuxtLink to="/bookings">กลับไปการจองของฉัน</NuxtLink></Button>
    </EmptyState>
    <BookingDetail v-else :booking="booking" :can-cancel="canCancel" @updated="(v) => (booking = { ...booking!, ...v })" @cancel="cancelDialog = true" />

    <Dialog v-model:open="cancelDialog">
      <DialogContent class="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>ยกเลิกการจองนี้?</DialogTitle>
          <DialogDescription>ยกเลิกได้ก่อนเวลานัดตามนโยบายของร้าน ถ้าโอนมัดจำแล้ว ร้านจะโอนคืนให้</DialogDescription>
        </DialogHeader>
        <div class="grid gap-1.5">
          <Label for="cancel-reason">เหตุผล <span class="font-normal text-muted-foreground">(ไม่บังคับ)</span></Label>
          <Textarea id="cancel-reason" v-model="cancelReason" rows="2" />
        </div>
        <DialogFooter class="gap-2">
          <Button variant="outline" @click="cancelDialog = false">ไม่ยกเลิก</Button>
          <Button variant="destructive" :disabled="cancelling" @click="cancel">{{ cancelling ? 'กำลังยกเลิก…' : 'ยืนยันยกเลิก' }}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
