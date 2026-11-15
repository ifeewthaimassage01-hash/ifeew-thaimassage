<script setup lang="ts">
// หัวเว็บ: เข้าสู่ระบบด้วย LINE (ไม่ใช่สมาชิก — ใช้รับยืนยันการจอง/เตือนนัดทาง LINE)
// ยังไม่เข้าสู่ระบบ → ปุ่ม · เข้าสู่ระบบแล้ว → รูป + ชื่อ LINE พร้อมเมนูออกจากระบบ
// แสดงเมื่อร้านเปิดใช้ LINE แล้วเท่านั้น
import { CalendarCheck, LogOut, MessageCircle, UserPlus } from '@lucide/vue'
import { toast } from 'vue-sonner'

const line = useLiff()
const busy = ref(false)

async function login() {
  busy.value = true
  try {
    await line.login()
  } catch (e) {
    toast.error(e instanceof Error ? e.message : 'เข้าสู่ระบบด้วย LINE ไม่สำเร็จ')
  } finally {
    busy.value = false
  }
}

async function logout() {
  await line.logout()
  toast.success('ออกจากระบบ LINE แล้ว')
}
</script>

<template>
  <template v-if="line.available.value">
    <DropdownMenu v-if="line.user.value">
      <DropdownMenuTrigger as-child>
        <button
          type="button"
          class="flex h-11 max-w-[200px] items-center gap-2 rounded-full bg-card py-1 pr-1 pl-1 text-[15px] text-heading shadow-soft focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none sm:pr-4"
          :aria-label="`บัญชี LINE ${line.user.value.name}`"
        >
          <img v-if="line.user.value.picture" :src="line.user.value.picture" alt="" class="size-9 shrink-0 rounded-full" referrerpolicy="no-referrer" />
          <span v-else class="grid size-9 shrink-0 place-items-center rounded-full bg-[#06C755] text-white" aria-hidden="true"><MessageCircle class="size-[18px]" /></span>
          <span class="truncate max-sm:sr-only">{{ line.user.value.name }}</span>
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" class="w-72 p-3">
        <p class="m-0 truncate text-[15px] font-semibold text-heading">{{ line.user.value.name }}</p>
        <p class="m-0 mt-0.5 text-sm text-muted-foreground">การจองตอนเข้าสู่ระบบจะได้ข้อความยืนยันและเตือนนัดทาง LINE และดูได้ที่ "การจองของฉัน"</p>
        <a
          v-if="line.isFriend.value === false && line.addFriendUrl.value"
          :href="line.addFriendUrl.value"
          class="mt-3 flex items-center gap-2 rounded-lg bg-secondary px-3 py-2 text-sm text-heading no-underline"
        >
          <UserPlus class="size-4 shrink-0" aria-hidden="true" /> เพิ่มเพื่อน LINE ของร้านก่อน จึงจะได้รับข้อความ
        </a>
        <DropdownMenuSeparator class="my-3" />
        <DropdownMenuItem @select="navigateTo('/check-booking')"><CalendarCheck /> การจองของฉัน</DropdownMenuItem>
        <DropdownMenuItem class="text-danger-ink" @select="logout"><LogOut /> ออกจากระบบ LINE</DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>

    <Button
      v-else-if="!line.restoring.value"
      variant="outline"
      class="h-11 rounded-full bg-card px-3 sm:px-4"
      :disabled="busy"
      aria-label="เข้าสู่ระบบด้วย LINE"
      @click="login"
    >
      <span class="grid size-6 place-items-center rounded-full bg-[#06C755] text-white" aria-hidden="true"><MessageCircle class="size-3.5" /></span>
      <span class="max-sm:sr-only">เข้าสู่ระบบด้วย LINE</span>
    </Button>
  </template>
</template>
