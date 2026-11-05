<script setup lang="ts">
// บัญชีใน topbar: ยังไม่ login = ปุ่มเข้าสู่ระบบ/สมัคร · login แล้ว = avatar + dropdown
import { CalendarCheck, ChevronDown, History, LogOut, UserRound } from '@lucide/vue'

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
  <div v-if="!user" class="flex items-center gap-1">
    <Button as-child variant="ghost" size="sm" class="hidden sm:inline-flex"><NuxtLink to="/register">สมัครสมาชิก</NuxtLink></Button>
    <Button as-child variant="outline" size="sm"><NuxtLink to="/login">เข้าสู่ระบบ</NuxtLink></Button>
  </div>
  <DropdownMenu v-else>
    <DropdownMenuTrigger as-child>
      <button
        type="button"
        class="flex h-10 items-center gap-2 rounded-lg pr-2 pl-1 text-heading transition-colors hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
        aria-label="เมนูบัญชี"
      >
        <span class="grid size-8 place-items-center rounded-full bg-secondary text-sm font-semibold text-heading">{{ initials }}</span>
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
