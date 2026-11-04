<script setup lang="ts">
import { Menu } from '@lucide/vue'

// Shell: แถบบน 56px บนพื้นเดียวกับหน้า + คอลัมน์กลาง (ไม่มี sidebar — มีปลายทางไม่กี่หน้า)
// มือถือ: โลโก้ + ปุ่มจอง + ปุ่มเมนูเปิด sheet ที่มีลิงก์ทั้งหมด
const user = useSupabaseUser()
const supabase = useSupabaseClient()
const { clear } = useCustomer()
const route = useRoute()
const menuOpen = ref(false)

const links = computed(() => [
  { to: '/services', label: 'บริการ' },
  { to: '/branches', label: 'สาขา' },
  ...(user.value
    ? [
        { to: '/bookings', label: 'การจองของฉัน' },
        { to: '/history', label: 'ประวัติ' },
        { to: '/profile', label: 'โปรไฟล์' },
      ]
    : []),
])

watch(() => route.fullPath, () => (menuOpen.value = false))

async function logout() {
  menuOpen.value = false
  await supabase.auth.signOut()
  clear()
  await navigateTo('/')
}
</script>

<template>
  <div class="min-h-dvh">
    <header class="sticky top-0 z-40 border-b border-border/70 bg-background">
      <div class="mx-auto flex h-14 max-w-5xl items-center gap-2 px-4 md:px-6">
        <NuxtLink to="/" class="mr-auto flex items-center gap-2.5 text-foreground no-underline">
          <BrandMark class="size-8" />
          <span class="text-[17px] font-semibold tracking-tight">Ifeew's Thaimassage</span>
        </NuxtLink>

        <nav class="hidden items-center gap-1 md:flex" aria-label="เมนูหลัก">
          <NuxtLink
            v-for="l in links"
            :key="l.to"
            :to="l.to"
            class="rounded-lg px-3 py-2 text-[15px] font-medium text-muted-foreground no-underline transition-colors hover:bg-muted hover:text-foreground"
            active-class="!bg-muted !text-foreground"
          >{{ l.label }}</NuxtLink>
          <Button v-if="user" variant="ghost" class="text-muted-foreground" @click="logout">ออกจากระบบ</Button>
          <NuxtLink v-else to="/login" class="rounded-lg px-3 py-2 text-[15px] font-medium text-muted-foreground no-underline hover:bg-muted hover:text-foreground">เข้าสู่ระบบ</NuxtLink>
        </nav>

        <Button as-child class="ml-1"><NuxtLink to="/book">จองคิว</NuxtLink></Button>

        <Sheet v-model:open="menuOpen">
          <SheetTrigger as-child>
            <Button variant="ghost" size="icon" class="md:hidden" aria-label="เปิดเมนู"><Menu class="size-5" /></Button>
          </SheetTrigger>
          <SheetContent side="right" class="w-full bg-background sm:max-w-sm">
            <SheetHeader class="px-5 pt-5">
              <SheetTitle class="flex items-center gap-2.5 text-lg"><BrandMark class="size-8" />Ifeew's Thaimassage</SheetTitle>
              <SheetDescription class="sr-only">เมนูหลัก</SheetDescription>
            </SheetHeader>
            <nav class="grid px-3" aria-label="เมนูหลัก">
              <NuxtLink
                v-for="l in links"
                :key="l.to"
                :to="l.to"
                class="rounded-lg px-3 py-3 text-lg font-medium text-foreground no-underline hover:bg-muted"
                active-class="!bg-muted"
              >{{ l.label }}</NuxtLink>
            </nav>
            <div class="mt-auto grid gap-2 p-5">
              <Button v-if="user" variant="outline" @click="logout">ออกจากระบบ</Button>
              <Button v-else as-child variant="outline"><NuxtLink to="/login">เข้าสู่ระบบ</NuxtLink></Button>
              <Button as-child size="lg"><NuxtLink to="/book">จองคิว</NuxtLink></Button>
            </div>
          </SheetContent>
        </Sheet>
      </div>
    </header>

    <main class="mx-auto max-w-5xl px-4 pt-6 pb-16 md:px-6 md:pt-9">
      <slot />
    </main>

    <footer class="border-t border-border/70">
      <div class="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-2 px-4 py-6 text-sm text-muted-foreground md:px-6">
        <span>Ifeew's Thaimassage · นวดไทย จองออนไลน์ทุกสาขา</span>
        <NuxtLink to="/branches" class="text-link">ติดต่อสาขา</NuxtLink>
      </div>
    </footer>
  </div>
</template>
