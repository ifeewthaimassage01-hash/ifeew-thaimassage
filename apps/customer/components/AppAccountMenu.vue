<script setup lang="ts">
// บัญชีใน topbar: ยังไม่ login = ปุ่มเข้าสู่ระบบ/สมัคร · login แล้ว = avatar + dropdown
import { CalendarCheck, CalendarSearch, ChevronDown, History, LogIn, LogOut, UserPlus, UserRound } from '@lucide/vue'

const user = useSupabaseUser()
const supabase = useSupabaseClient()
const { customer, ensure, clear } = useCustomer()

onMounted(() => ensure().catch(() => {}))
watch(user, () => ensure().catch(() => {}))

const name = computed(() => {
  const c = customer.value
  if (c) return `${c.first_name} ${c.last_name}`.trim()
  return user.value?.email ?? ''
})
const initials = computed(() => (customer.value?.first_name || user.value?.email || '?').trim().charAt(0).toUpperCase())

async function logout() {
  await supabase.auth.signOut()
  clear()
  await navigateTo('/')
}
</script>

<template>
  <DropdownMenu v-if="!user">
    <DropdownMenuTrigger as-child>
      <button
        type="button"
        class="grid size-11 place-items-center rounded-full border border-border bg-card text-heading shadow-soft transition-colors hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
        aria-label="บัญชีผู้ใช้"
      >
        <UserRound class="size-5" :stroke-width="1.6" />
      </button>
    </DropdownMenuTrigger>
    <DropdownMenuContent align="end" class="w-52">
      <DropdownMenuItem as-child><NuxtLink to="/login" class="text-foreground no-underline"><LogIn /> เข้าสู่ระบบ</NuxtLink></DropdownMenuItem>
      <DropdownMenuItem as-child><NuxtLink to="/register" class="text-foreground no-underline"><UserPlus /> สมัครสมาชิก</NuxtLink></DropdownMenuItem>
      <DropdownMenuSeparator />
      <DropdownMenuItem as-child><NuxtLink to="/check-booking" class="text-foreground no-underline"><CalendarSearch /> ตรวจสอบการจอง</NuxtLink></DropdownMenuItem>
    </DropdownMenuContent>
  </DropdownMenu>
  <DropdownMenu v-else>
    <DropdownMenuTrigger as-child>
      <button
        type="button"
        class="flex h-11 items-center gap-2 rounded-full border border-border bg-card pr-3 pl-1 text-heading shadow-soft transition-colors hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none max-lg:pr-1"
        aria-label="เมนูบัญชี"
      >
        <span class="grid size-9 place-items-center rounded-full bg-secondary text-sm font-semibold text-heading">{{ initials }}</span>
        <span class="hidden max-w-36 truncate text-[15px] font-medium lg:block">{{ name }}</span>
        <ChevronDown class="hidden size-4 text-muted-foreground lg:block" />
      </button>
    </DropdownMenuTrigger>
    <DropdownMenuContent align="end" class="w-60">
      <DropdownMenuLabel class="font-normal">
        <span class="block truncate font-medium text-heading">{{ name }}</span>
        <span class="block truncate text-sm text-muted-foreground">{{ user.email }}</span>
      </DropdownMenuLabel>
      <DropdownMenuSeparator />
      <DropdownMenuItem as-child><NuxtLink to="/bookings" class="text-foreground no-underline"><CalendarCheck /> การจองของฉัน</NuxtLink></DropdownMenuItem>
      <DropdownMenuItem as-child><NuxtLink to="/history" class="text-foreground no-underline"><History /> ประวัติการนวด</NuxtLink></DropdownMenuItem>
      <DropdownMenuItem as-child><NuxtLink to="/profile" class="text-foreground no-underline"><UserRound /> โปรไฟล์</NuxtLink></DropdownMenuItem>
      <DropdownMenuSeparator />
      <DropdownMenuItem @select="logout"><LogOut /> ออกจากระบบ</DropdownMenuItem>
    </DropdownMenuContent>
  </DropdownMenu>
</template>
