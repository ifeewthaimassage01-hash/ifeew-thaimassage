<script setup lang="ts">
// ปุ่มกระดิ่งบน topbar: เปิด/ปิดแจ้งเตือนเข้ามือถือของเครื่องนี้
// (จองใหม่ · ส่งสลิปมัดจำ · ลูกค้ายกเลิก · รับลูกค้าหน้าร้าน · บริการเสร็จ)
import { Bell, BellOff, BellRing } from '@lucide/vue'
import { toast } from 'vue-sonner'

const { state, busy, sync, enable, disable } = usePushNotifications()
const { company, activeBranchId } = useAccess()

onMounted(() => sync().catch(() => {}))
// โหลดข้อมูลร้านเสร็จ / เปลี่ยนสาขา → อัปเดตเครื่องนี้ให้รับแจ้งเตือนของสาขาที่เลือก
watch([() => company.value?.company_id, activeBranchId], () => sync().catch(() => {}))

const label = computed(() => (state.value === 'on' ? 'แจ้งเตือนเปิดอยู่' : 'เปิดแจ้งเตือน'))

const events = ['มีการจองใหม่', 'ลูกค้าส่งสลิปมัดจำ', 'ลูกค้ายกเลิกการจอง', 'รับลูกค้าหน้าร้าน', 'บริการเสร็จ']

async function turnOn() {
  try {
    if (await enable()) toast.success('เปิดแจ้งเตือนบนเครื่องนี้แล้ว')
    else if (state.value === 'denied') toast.warning('เบราว์เซอร์บล็อกการแจ้งเตือนไว้ ไปที่การตั้งค่าเว็บไซต์แล้วอนุญาตการแจ้งเตือน')
  } catch (e) {
    toast.error(e instanceof Error ? `เปิดแจ้งเตือนไม่สำเร็จ: ${e.message}` : 'เปิดแจ้งเตือนไม่สำเร็จ')
  }
}

async function turnOff() {
  try {
    await disable()
    toast.success('ปิดแจ้งเตือนบนเครื่องนี้แล้ว')
  } catch {
    toast.error('ปิดแจ้งเตือนไม่สำเร็จ')
  }
}
</script>

<template>
  <DropdownMenu v-if="state !== 'loading' && state !== 'unsupported'">
    <DropdownMenuTrigger as-child>
      <Button variant="ghost" size="icon" class="relative size-10 rounded-full text-heading" :aria-label="label">
        <BellRing v-if="state === 'on'" class="size-5" />
        <Bell v-else class="size-5" />
        <span v-if="state === 'on'" class="absolute top-2 right-2 size-2 rounded-full bg-success ring-2 ring-background" aria-hidden="true" />
      </Button>
    </DropdownMenuTrigger>
    <DropdownMenuContent align="end" class="w-72 p-3">
      <p class="m-0 text-[15px] font-semibold text-heading">แจ้งเตือนเข้ามือถือ</p>
      <p class="m-0 mt-0.5 text-sm text-muted-foreground">เครื่องนี้จะเด้งแจ้งเตือนเมื่อ</p>
      <ul class="m-0 mt-2 grid list-none gap-1 p-0 text-sm text-heading">
        <li v-for="e in events" :key="e" class="flex items-center gap-2"><span class="size-1.5 rounded-full bg-brand-accent" aria-hidden="true" />{{ e }}</li>
      </ul>

      <div class="mt-3 border-t border-border pt-3">
        <template v-if="state === 'on'">
          <p class="m-0 mb-2 flex items-center gap-1.5 text-sm text-success-ink"><BellRing class="size-4" /> เปิดอยู่บนเครื่องนี้</p>
          <Button variant="outline" size="sm" class="w-full" :disabled="busy" @click="turnOff"><BellOff /> ปิดแจ้งเตือน</Button>
        </template>
        <Button v-else-if="state === 'off'" size="sm" class="w-full" :disabled="busy" @click="turnOn">
          <Bell /> {{ busy ? 'กำลังเปิด…' : 'เปิดแจ้งเตือนบนเครื่องนี้' }}
        </Button>
        <p v-else-if="state === 'denied'" class="m-0 text-sm text-danger-ink">
          เบราว์เซอร์บล็อกการแจ้งเตือนไว้ กดไอคอนแม่กุญแจข้างช่อง URL → การแจ้งเตือน → อนุญาต แล้วรีเฟรชหน้า
        </p>
        <p v-else-if="state === 'ios-install'" class="m-0 text-sm text-muted-foreground">
          iPhone/iPad: กดปุ่มแชร์ → <span class="font-medium text-heading">เพิ่มไปยังหน้าจอโฮม</span> แล้วเปิดแอปจากไอคอน จึงจะเปิดแจ้งเตือนได้
        </p>
      </div>
    </DropdownMenuContent>
  </DropdownMenu>
</template>
