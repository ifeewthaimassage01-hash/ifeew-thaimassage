<script setup lang="ts">
// แถบ "มีสลิปมัดจำรอตรวจ N รายการ · ตรวจเลย" — ตรวจสลิปให้ลูกค้าได้เร็ว
// - ไม่ส่ง count: นับเอง (สาขาที่เลือกอยู่ · ทุกวัน) ทุก 60 วินาทีขณะเปิดหน้า แล้วกดไปหน้าการจองที่กรองรอตรวจไว้
// - ส่ง count (หน้าการจอง): ใช้ตัวเลขที่หน้าโหลดมาแล้ว และส่ง event open ให้หน้าเปลี่ยนตัวกรองเอง
import { ReceiptText } from '@lucide/vue'

const props = defineProps<{ count?: number }>()
const emit = defineEmits<{ open: [] }>()

// ตาราง bookings ไม่อยู่ใน database.types.ts (เขียนเอง) → นับแบบไม่มี type · RLS จำกัดเฉพาะสาขาที่มีสิทธิ์
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const supabase = useSupabaseClient<any>()
const { activeBranch } = useAccess()
const own = ref(0)
const shown = computed(() => props.count ?? own.value)

async function refresh() {
  if (props.count !== undefined || !activeBranch.value) return
  const { count, error } = await supabase
    .from('bookings')
    .select('id', { count: 'exact', head: true })
    .eq('branch_id', activeBranch.value.branch_id)
    .eq('deposit_status', 'PENDING_REVIEW')
  if (!error) own.value = count ?? 0
}
watch(() => activeBranch.value?.branch_id, refresh, { immediate: true })
useLiveInterval(refresh, 60_000)

function open() {
  if (props.count !== undefined) emit('open')
  else navigateTo({ path: '/bookings', query: { show: 'review' } })
}
</script>

<template>
  <button
    v-if="shown > 0"
    type="button"
    class="mb-4 flex w-full items-center gap-3 rounded-2xl border border-pending-ink/20 bg-pending-soft px-4 py-3 text-left text-pending-ink transition-colors hover:border-pending-ink/40 focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
    @click="open"
  >
    <ReceiptText class="size-5 shrink-0" aria-hidden="true" />
    <span class="min-w-0 flex-1 text-[15px] font-medium">มีสลิปมัดจำรอตรวจ <span class="num">{{ shown }}</span> รายการ</span>
    <span class="shrink-0 text-sm font-semibold underline underline-offset-2">ตรวจเลย</span>
  </button>
</template>
