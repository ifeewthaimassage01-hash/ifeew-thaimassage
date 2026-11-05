<script setup lang="ts">
import { ChevronRight, Menu } from '@lucide/vue'

// Shell ตาม DESIGN.md: Sidebar + Topbar + Main
//   เดสก์ท็อป (≥1024) sidebar เต็ม 248px · แท็บเล็ต (768–1023) sidebar แบบย่อเหลือไอคอน · มือถือ: drawer
const route = useRoute()
const { crumbs } = useAppNav()
const drawer = ref(false)
watch(() => route.fullPath, () => (drawer.value = false))
</script>

<template>
  <TooltipProvider :delay-duration="200">
    <div class="min-h-dvh md:grid md:grid-cols-[76px_minmax(0,1fr)] lg:grid-cols-[var(--sidebar-width)_minmax(0,1fr)]">
      <!-- Sidebar -->
      <aside class="sticky top-0 hidden h-dvh flex-col border-r border-border bg-background md:flex">
        <NuxtLink to="/" class="flex h-16 items-center gap-2.5 px-5 text-heading no-underline max-lg:justify-center max-lg:px-0" aria-label="Ifeew's Thaimassage หน้าแรก">
          <BrandMark class="size-8" />
          <span class="hidden text-[17px] font-semibold tracking-tight lg:inline">Ifeew's Thaimassage</span>
        </NuxtLink>
        <div class="flex-1 overflow-y-auto px-3 pt-4 pb-6">
          <AppSidebarNav class="hidden lg:grid" />
          <AppSidebarNav compact class="lg:hidden" />
        </div>
        <div class="hidden border-t border-border px-5 py-4 lg:block">
          <p class="m-0 text-sm font-medium text-heading">ต้องการความช่วยเหลือ?</p>
          <p class="m-0 text-sm text-muted-foreground">โทรหาสาขาได้จาก<NuxtLink to="/branches" class="ml-1">หน้าสาขา</NuxtLink></p>
        </div>
      </aside>

      <div class="flex min-w-0 flex-col">
        <!-- Topbar -->
        <header class="sticky top-0 z-30 border-b border-border bg-background">
          <div class="flex h-16 items-center gap-3 px-4 md:px-8">
            <Sheet v-model:open="drawer">
              <SheetTrigger as-child>
                <Button variant="ghost" size="icon" class="-ml-2 md:hidden" aria-label="เปิดเมนู"><Menu class="size-5" /></Button>
              </SheetTrigger>
              <SheetContent side="left" class="w-[85vw] max-w-xs gap-0 bg-background p-0">
                <SheetHeader class="h-16 flex-row items-center gap-2.5 border-b border-border px-5">
                  <BrandMark class="size-8" />
                  <SheetTitle class="text-[17px] text-heading">Ifeew's Thaimassage</SheetTitle>
                  <SheetDescription class="sr-only">เมนูหลัก</SheetDescription>
                </SheetHeader>
                <div class="overflow-y-auto px-3 py-4"><AppSidebarNav @navigate="drawer = false" /></div>
              </SheetContent>
            </Sheet>

            <NuxtLink to="/" class="flex items-center gap-2 text-heading no-underline md:hidden" aria-label="หน้าแรก">
              <BrandMark class="size-7" />
            </NuxtLink>

            <nav aria-label="ตำแหน่งปัจจุบัน" class="min-w-0 flex-1">
              <ol class="m-0 flex list-none items-center gap-1.5 p-0 text-[15px]">
                <li v-for="(c, i) in crumbs" :key="i" class="flex min-w-0 items-center gap-1.5">
                  <ChevronRight v-if="i > 0" class="size-4 shrink-0 text-muted-soft" aria-hidden="true" />
                  <NuxtLink v-if="c.to" :to="c.to" class="truncate text-muted-foreground no-underline hover:text-heading">{{ c.label }}</NuxtLink>
                  <span v-else class="truncate font-medium text-heading" aria-current="page">{{ c.label }}</span>
                </li>
              </ol>
            </nav>

            <Button v-if="route.path !== '/book'" as-child size="sm" class="hidden sm:inline-flex"><NuxtLink to="/book">จองคิว</NuxtLink></Button>
            <AppAccountMenu />
          </div>
        </header>

        <!-- Main -->
        <main class="mx-auto w-full max-w-6xl flex-1 px-4 pt-6 pb-16 md:px-8 md:pt-8">
          <slot />
        </main>

        <footer class="mx-auto w-full max-w-6xl px-4 pb-8 md:px-8">
          <div class="flex flex-wrap items-center justify-between gap-2 border-t border-border pt-5 text-sm text-muted-foreground">
            <span>© Ifeew's Thaimassage</span>
            <span>นวดไทย จองออนไลน์ทุกสาขา</span>
          </div>
        </footer>

        <!-- มือถือ: ปุ่มจองหลักอยู่ใกล้นิ้วเสมอ (DESIGN.md: Keep important actions easily accessible) -->
        <div v-if="route.path !== '/book'" class="sticky bottom-0 z-20 border-t border-border bg-background p-3 sm:hidden">
          <Button as-child size="lg" class="w-full"><NuxtLink to="/book">จองคิว</NuxtLink></Button>
        </div>
      </div>
    </div>
    <ClientOnly><Toaster position="top-center" :toast-options="{ classes: { toast: '!rounded-xl !border-border !bg-card !text-heading !shadow-sm', description: '!text-muted-foreground', success: '[&_[data-icon]]:!text-success-ink', error: '[&_[data-icon]]:!text-danger-ink' } }" /></ClientOnly>
  </TooltipProvider>
</template>
