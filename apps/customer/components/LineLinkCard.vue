<script setup lang="ts">
// ปุ่ม "เชื่อม LINE" ในหน้าสถานะการจอง: ผูกการจองกับ LINE ของลูกค้า → ได้ข้อความยืนยันและเตือนก่อนถึงนัด
// แสดงเมื่อร้านเปิดใช้ LINE และการจองยังไม่จบ · ในแอป LINE เชื่อมได้ทันที · เว็บปกติไปเข้าสู่ระบบ LINE แล้วกลับมาที่ /line-callback
import { Check, MessageCircle } from '@lucide/vue'
import { toast } from 'vue-sonner'

const props = defineProps<{ token: string; linked: boolean; status: string }>()
const emit = defineEmits<{ linked: [] }>()

const line = useLiff()
const { call } = useEdgeFunction()
const busy = ref(false)

onMounted(() => line.config())

const active = computed(() => ['PENDING', 'CONFIRMED'].includes(props.status))
const show = computed(() => line.available.value === true && (active.value || props.linked))

async function connect() {
  busy.value = true
  try {
    try {
      sessionStorage.setItem(LINE_LINK_KEY, props.token)
    } catch {}
    const idToken = await line.loginOrToken('/line-callback')
    if (!idToken) return // กำลังพาไปหน้า LINE
    await call('booking-tracking', { token: props.token, action: 'line_link', id_token: idToken })
    try {
      sessionStorage.removeItem(LINE_LINK_KEY)
    } catch {}
    toast.success('เชื่อม LINE แล้ว')
    emit('linked')
  } catch (e) {
    toast.error((e as { data?: unknown }).data ? edgeErrorText(e, 'เชื่อม LINE ไม่สำเร็จ') : e instanceof Error ? e.message : 'เชื่อม LINE ไม่สำเร็จ')
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <section
    v-if="show"
    class="mt-4 flex flex-col gap-4 rounded-[14px] border border-border bg-card p-4 sm:flex-row sm:items-center sm:p-5"
    aria-labelledby="line-link-title"
  >
    <span
      class="grid size-11 shrink-0 place-items-center rounded-full"
      :class="linked ? 'bg-success-soft text-success-ink' : 'bg-[#06C755] text-white'"
      aria-hidden="true"
    >
      <Check v-if="linked" class="size-5" />
      <MessageCircle v-else class="size-5" />
    </span>
    <div class="grid min-w-0 flex-1 gap-0.5">
      <h2 id="line-link-title" class="m-0 text-base font-semibold text-heading">
        {{ linked ? 'เชื่อม LINE แล้ว' : 'รับข้อความเตือนนัดทาง LINE' }}
      </h2>
      <p class="m-0 text-[15px] text-muted-foreground">
        <template v-if="linked">
          เราจะส่งข้อความเตือนก่อนถึงเวลานัดทาง LINE
          <template v-if="line.isFriend.value === false && line.addFriendUrl.value">
            <a :href="line.addFriendUrl.value" class="font-medium text-primary underline underline-offset-2">เพิ่มเพื่อน LINE ของร้าน</a> ก่อน จึงจะได้รับข้อความ
          </template>
        </template>
        <template v-else>ได้รายละเอียดการจองนี้ในแชท และข้อความเตือนก่อนถึงเวลานัด</template>
      </p>
    </div>
    <Button
      v-if="!linked"
      class="h-11 shrink-0 px-5"
      :disabled="busy"
      @click="connect"
    >
      {{ busy ? 'กำลังเชื่อม…' : 'เชื่อม LINE' }}
    </Button>
  </section>
</template>
