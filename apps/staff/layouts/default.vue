<script setup lang="ts">
import { CalendarPlus, ChevronDown, LogOut, Menu, Plus, ReceiptText, Store } from '@lucide/vue'

// Shell (ภาพอ้างอิง Warm Cream): พื้นครีมต่อเนื่อง ไม่มีเส้นคั่น sidebar/topbar · การ์ดลอยด้วยเงานุ่ม
//   ≥1280 sidebar เต็ม · 768–1279 sidebar ย่อเหลือไอคอน · <768 drawer + bottom nav
const supabase = useSupabaseClient()
const user = useSupabaseUser()
const route = useRoute()
const { company, branches, activeBranchId, isOwner, clear } = useAccess()
const { crumbs } = useStaffNav()

const drawer = ref(false)
watch(() => route.fullPath, () => (drawer.value = false))

async function logout(reason?: string) {
  await supabase.auth.signOut()
  clear()
  clearLoginMark()
  await navigateTo(reason ? `/login?error=${reason}` : '/login')
}

// ออกจากระบบอัตโนมัติเมื่อขึ้นวันทำงานใหม่ (ตี 3 เวลาไทย) — ตรวจทุก 30 วินาที และตอนกลับมาที่แท็บ
function checkWorkDay() {
  if (user.value && loginExpired()) logout('day_end')
}
useIntervalFn(checkWorkDay, 30_000)
useEventListener(document, 'visibilitychange', () => {
  if (document.visibilityState === 'visible') checkWorkDay()
})

const displayName = computed(() => user.value?.user_metadata?.display_name || user.value?.email || 'ผู้ใช้')
const initials = computed(() => String(displayName.value).trim().charAt(0).toUpperCase())
const roleLabel = computed(() => (isOwner.value ? 'เจ้าของร้าน' : 'พนักงาน'))
</script>

<template>
  <TooltipProvider :delay-duration="200">
    <div class="min-h-dvh md:pl-[76px] xl:pl-[var(--sidebar-width)]">
      <!-- Sidebar: ตรึงกับจอ (fixed) — เมนูยาวเลื่อนในตัวเอง ไม่เลื่อนหายไปกับหน้า -->
      <aside class="fixed inset-y-0 left-0 z-20 hidden w-[76px] flex-col bg-background md:flex xl:w-[var(--sidebar-width)]">
        <NuxtLink to="/" class="flex shrink-0 flex-col gap-2 px-6 pt-7 pb-5 text-heading no-underline max-xl:items-center max-xl:px-0" aria-label="แดชบอร์ด">
          <BrandMark class="size-11" />
          <span class="hidden min-w-0 xl:block">
            <span class="block truncate text-[15px] leading-tight font-semibold">Ifeew's Thaimassage</span>
          </span>
        </NuxtLink>
        <div class="scrollbar-hidden flex-1 overflow-y-auto px-4 pb-4">
          <StaffSidebarNav class="hidden xl:grid" />
          <StaffSidebarNav compact class="xl:hidden" />
        </div>
      </aside>

      <div class="flex min-h-dvh min-w-0 flex-col">
        <!-- Topbar -->
        <header class="sticky top-0 z-30 bg-background/95 backdrop-blur-sm">
          <div class="flex h-[72px] items-center gap-3 px-4 md:px-6 xl:pr-8 xl:pl-2">
            <Sheet v-model:open="drawer">
              <SheetTrigger as-child>
                <Button variant="ghost" size="icon" class="-ml-2 md:hidden" aria-label="เปิดเมนู"><Menu class="size-5" /></Button>
              </SheetTrigger>
              <SheetContent side="left" class="w-[85vw] max-w-xs gap-0 bg-background p-0">
                <SheetHeader class="h-16 flex-row items-center gap-2.5 px-5">
                  <BrandMark class="size-8" />
                  <SheetTitle class="text-[15px] text-heading">{{ company?.company_name ?? "Ifeew's Thaimassage" }}</SheetTitle>
                  <SheetDescription class="sr-only">เมนูหลัก</SheetDescription>
                </SheetHeader>
                <div class="scrollbar-hidden overflow-y-auto px-3 py-2"><StaffSidebarNav @navigate="drawer = false" /></div>
              </SheetContent>
            </Sheet>

            <span class="min-w-0 flex-1 truncate font-medium text-heading sm:hidden">{{ crumbs[crumbs.length - 1]?.label }}</span>
            <div class="hidden flex-1 sm:block" />

            <!-- สาขาที่กำลังทำงาน -->
            <SelectField
              v-if="branches.length > 1"
              v-model="activeBranchId"
              :items="branches"
              item-title="name"
              item-value="branch_id"
              placeholder="เลือกสาขา"
              class="w-40 sm:w-52"
              aria-label="สาขา"
            />
            <span v-else-if="branches[0]" class="hidden truncate text-[15px] text-muted-foreground lg:block">{{ branches[0].name }}</span>

            <!-- สร้างรายการใหม่ -->
            <DropdownMenu>
              <DropdownMenuTrigger as-child>
                <Button variant="ghost" size="icon" class="size-10 rounded-full text-heading" aria-label="สร้างรายการใหม่"><Plus class="size-5" /></Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" class="w-56">
                <DropdownMenuItem as-child><NuxtLink to="/pos" class="no-underline"><Store /> รับลูกค้า Walk-in</NuxtLink></DropdownMenuItem>
                <DropdownMenuItem as-child><NuxtLink to="/bookings" class="no-underline"><CalendarPlus /> จองให้ลูกค้า</NuxtLink></DropdownMenuItem>
                <DropdownMenuItem as-child><NuxtLink to="/expenses" class="no-underline"><ReceiptText /> บันทึกรายจ่าย</NuxtLink></DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>

            <DropdownMenu>
              <DropdownMenuTrigger as-child>
                <button
                  type="button"
                  class="flex h-11 items-center gap-2 rounded-full border border-border bg-card pr-3 pl-1 text-heading shadow-soft transition-colors hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none max-lg:pr-1"
                  aria-label="เมนูบัญชี"
                >
                  <span class="grid size-9 place-items-center rounded-full bg-secondary text-sm font-semibold">{{ initials }}</span>
                  <span class="hidden text-left lg:block">
                    <span class="block max-w-36 truncate text-sm leading-tight font-medium">{{ displayName }}</span>
                    <span class="block text-[12px] leading-tight text-muted-foreground">{{ roleLabel }}</span>
                  </span>
                  <ChevronDown class="hidden size-4 text-muted-foreground lg:block" />
                </button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" class="w-60">
                <DropdownMenuLabel class="font-normal">
                  <span class="block truncate font-medium text-heading">{{ displayName }}</span>
                  <span class="block truncate text-sm text-muted-foreground">{{ roleLabel }} · {{ company?.company_name }}</span>
                </DropdownMenuLabel>
                <DropdownMenuSeparator />
                <DropdownMenuItem @select="logout()"><LogOut /> ออกจากระบบ</DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </header>

        <!-- มือถือ: เว้นที่ด้านล่างให้แถบเมนูล่าง (h-16 + safe area) -->
        <main class="mx-auto w-full max-w-[1480px] flex-1 px-4 pt-4 pb-[calc(7rem+env(safe-area-inset-bottom))] md:px-6 md:pt-5 md:pb-12 xl:pr-8 xl:pl-2">
          <slot />
        </main>
      </div>
    </div>

    <StaffBottomNav />
    <StepUpDialog />
    <AppDialogHost />
    <Sonner position="top-center" :toast-options="{ classes: { toast: '!rounded-xl !border-border !bg-card !text-heading !shadow-sm', description: '!text-muted-foreground' } }" />
  </TooltipProvider>
</template>
