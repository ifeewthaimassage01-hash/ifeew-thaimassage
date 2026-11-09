<script setup lang="ts">
import { ChevronDown, ChevronRight, LogOut, Menu } from '@lucide/vue'

// Shell ตาม DESIGN.md: Sidebar + Topbar + Main
//   ≥1280 sidebar เต็ม · 768–1279 sidebar ย่อเหลือไอคอน · <768 drawer
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
</script>

<template>
  <TooltipProvider :delay-duration="200">
    <div class="min-h-dvh md:grid md:grid-cols-[68px_minmax(0,1fr)] xl:grid-cols-[var(--sidebar-width)_minmax(0,1fr)]">
      <!-- Sidebar -->
      <aside class="sticky top-0 hidden h-dvh flex-col border-r border-border bg-background md:flex">
        <NuxtLink to="/" class="flex h-16 shrink-0 items-center gap-2.5 px-5 text-heading no-underline max-xl:justify-center max-xl:px-0" aria-label="แดชบอร์ด">
          <BrandMark class="size-8" />
          <span class="hidden min-w-0 xl:block">
            <span class="block truncate text-[15px] leading-tight font-semibold">Ifeew's Thaimassage</span>
            <span class="block truncate text-[13px] text-muted-foreground">{{ company?.company_name ?? 'ระบบร้าน' }}</span>
          </span>
        </NuxtLink>
        <div class="scrollbar-hidden flex-1 overflow-y-auto px-3 pt-3 pb-6">
          <StaffSidebarNav class="hidden xl:grid" />
          <StaffSidebarNav compact class="xl:hidden" />
        </div>
      </aside>

      <div class="flex min-w-0 flex-col">
        <!-- Topbar -->
        <header class="sticky top-0 z-30 border-b border-border bg-background">
          <div class="flex h-16 items-center gap-3 px-4 md:px-6 xl:px-8">
            <Sheet v-model:open="drawer">
              <SheetTrigger as-child>
                <Button variant="ghost" size="icon" class="-ml-2 md:hidden" aria-label="เปิดเมนู"><Menu class="size-5" /></Button>
              </SheetTrigger>
              <SheetContent side="left" class="w-[85vw] max-w-xs gap-0 bg-background p-0">
                <SheetHeader class="h-16 flex-row items-center gap-2.5 border-b border-border px-5">
                  <BrandMark class="size-8" />
                  <SheetTitle class="text-[15px] text-heading">{{ company?.company_name ?? "Ifeew's Thaimassage" }}</SheetTitle>
                  <SheetDescription class="sr-only">เมนูหลัก</SheetDescription>
                </SheetHeader>
                <div class="scrollbar-hidden overflow-y-auto px-3 py-4"><StaffSidebarNav @navigate="drawer = false" /></div>
              </SheetContent>
            </Sheet>

            <nav aria-label="ตำแหน่งปัจจุบัน" class="hidden min-w-0 flex-1 sm:block">
              <ol class="m-0 flex list-none items-center gap-1.5 p-0 text-[15px]">
                <li v-for="(c, i) in crumbs" :key="i" class="flex min-w-0 items-center gap-1.5" :class="i === 0 && crumbs.length > 1 ? 'max-lg:hidden' : ''">
                  <ChevronRight v-if="i > 0" class="size-4 shrink-0 text-muted-soft" :class="i === 1 ? 'max-lg:hidden' : ''" aria-hidden="true" />
                  <NuxtLink v-if="c.to" :to="c.to" class="truncate text-muted-foreground no-underline hover:text-heading">{{ c.label }}</NuxtLink>
                  <span v-else class="truncate" :class="i === crumbs.length - 1 ? 'font-medium text-heading' : 'text-muted-foreground'" :aria-current="i === crumbs.length - 1 ? 'page' : undefined">{{ c.label }}</span>
                </li>
              </ol>
            </nav>
            <div class="flex-1 sm:hidden" />

            <!-- สาขาที่กำลังทำงาน -->
            <SelectField
              v-if="branches.length > 1"
              v-model="activeBranchId"
              :items="branches"
              item-title="name"
              item-value="branch_id"
              placeholder="เลือกสาขา"
              class="w-44 sm:w-56"
              aria-label="สาขา"
            />
            <span v-else-if="branches[0]" class="hidden truncate text-[15px] font-medium text-heading md:block">{{ branches[0].name }}</span>

            <DropdownMenu>
              <DropdownMenuTrigger as-child>
                <button
                  type="button"
                  class="flex h-10 items-center gap-2 rounded-lg pr-2 pl-1 text-heading transition-colors hover:bg-muted focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
                  aria-label="เมนูบัญชี"
                >
                  <span class="grid size-8 place-items-center rounded-full bg-secondary text-sm font-semibold">{{ initials }}</span>
                  <span class="hidden text-left lg:block">
                    <span class="block max-w-40 truncate text-sm leading-tight font-medium">{{ displayName }}</span>
                    <span class="block text-[13px] leading-tight text-muted-foreground">{{ isOwner ? 'เจ้าของร้าน' : 'พนักงาน' }}</span>
                  </span>
                  <ChevronDown class="hidden size-4 text-muted-foreground lg:block" />
                </button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" class="w-60">
                <DropdownMenuLabel class="font-normal">
                  <span class="block truncate font-medium text-heading">{{ displayName }}</span>
                  <span class="block truncate text-sm text-muted-foreground">{{ isOwner ? 'เจ้าของร้าน' : 'พนักงาน' }} · {{ company?.company_name }}</span>
                </DropdownMenuLabel>
                <DropdownMenuSeparator />
                <DropdownMenuItem @select="logout()"><LogOut /> ออกจากระบบ</DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </header>

        <main class="mx-auto w-full max-w-[1400px] flex-1 px-4 pt-6 pb-12 md:px-6 md:pt-8 xl:px-8">
          <slot />
        </main>
      </div>
    </div>

    <StepUpDialog />
    <AppDialogHost />
    <Toaster position="top-center" :toast-options="{ classes: { toast: '!rounded-xl !border-border !bg-card !text-heading !shadow-sm', description: '!text-muted-foreground' } }" />
  </TooltipProvider>
</template>
