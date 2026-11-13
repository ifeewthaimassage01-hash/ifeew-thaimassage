<script setup lang="ts">
import { CalendarDays, CalendarSearch, House, Info, MapPin, Menu, Phone, Sparkles } from '@lucide/vue'

// Shell ลูกค้า (ภาพอ้างอิง Warm Minimal): Top navigation แนวนอน · เนื้อหา · Footer
//   ≥1024 เมนูแนวนอน · <1024 โลโก้ + ปุ่มเมนู (drawer) · มือถือมีปุ่มจองค้างล่างจอ
const route = useRoute()
const drawer = ref(false)
watch(() => route.fullPath, () => (drawer.value = false))

const top = computed(() => [
  { to: '/', label: 'หน้าแรก', icon: House, exact: true },
  { to: '/services', label: 'บริการ', icon: Sparkles },
  { to: '/branches', label: 'สาขา', icon: MapPin },
  { to: '/#about', label: 'เกี่ยวกับเรา', icon: Info },
  { to: '/check-booking', label: 'ตรวจสอบการจอง', icon: CalendarSearch },
])
const isActive = (i: { to: string; exact?: boolean }) =>
  i.to.includes('#') ? false : i.exact ? route.path === i.to : route.path === i.to || route.path.startsWith(`${i.to}/`)

// หน้าแรกเป็น full-bleed (hero ลอดใต้ topbar) หน้าอื่นอยู่ในคอนเทนเนอร์
const home = computed(() => route.path === '/')
const { data: branches } = useBranches()
const tel = (p: string) => `tel:${p.replace(/\s|-/g, '')}`
</script>

<template>
  <TooltipProvider :delay-duration="200">
    <div class="flex min-h-dvh flex-col">
      <!-- Topbar -->
      <header class="sticky top-0 z-30 border-b border-transparent bg-background/80 backdrop-blur-md">
        <div class="mx-auto flex h-[76px] w-full max-w-[1200px] items-center gap-4 px-4 md:px-8">
          <NuxtLink to="/" class="flex shrink-0 items-center gap-2.5 text-heading no-underline" aria-label="Ifeew's Thaimassage หน้าแรก">
            <BrandMark class="size-10" />
            <span class="font-display text-[19px] leading-[1.05] font-semibold tracking-tight">Ifeew's<br>Thaimassage</span>
          </NuxtLink>

          <nav aria-label="เมนูหลัก" class="mx-auto hidden lg:block">
            <ul class="m-0 flex list-none items-center gap-1 p-0">
              <li v-for="i in top" :key="i.to">
                <NuxtLink
                  :to="i.to"
                  :aria-current="isActive(i) ? 'page' : undefined"
                  class="flex h-10 items-center gap-2 rounded-full px-4 text-[15px] no-underline transition-colors"
                  :class="isActive(i) ? 'bg-card font-medium text-heading shadow-soft' : 'text-foreground hover:bg-card/70 hover:text-heading'"
                >
                  <component :is="i.icon" v-if="isActive(i)" class="size-[18px] text-heading" :stroke-width="1.75" aria-hidden="true" />{{ i.label }}
                </NuxtLink>
              </li>
            </ul>
          </nav>
          <div class="flex-1 lg:hidden" />

          <Button v-if="route.path !== '/book'" as-child class="hidden h-11 rounded-full px-5 sm:inline-flex">
            <NuxtLink to="/book"><CalendarDays /> จองคิว</NuxtLink>
          </Button>

          <Sheet v-model:open="drawer">
            <SheetTrigger as-child>
              <Button variant="ghost" size="icon" class="-mr-2 lg:hidden" aria-label="เปิดเมนู"><Menu class="size-5" /></Button>
            </SheetTrigger>
            <SheetContent side="right" class="w-[85vw] max-w-xs gap-0 bg-background p-0">
              <SheetHeader class="h-[76px] flex-row items-center gap-2.5 px-5">
                <BrandMark class="size-9" />
                <SheetTitle class="font-display text-[18px] text-heading">Ifeew's Thaimassage</SheetTitle>
                <SheetDescription class="sr-only">เมนูหลัก</SheetDescription>
              </SheetHeader>
              <div class="overflow-y-auto px-3 py-2"><AppSidebarNav @navigate="drawer = false" /></div>
            </SheetContent>
          </Sheet>
        </div>
      </header>

      <!-- Main -->
      <main v-if="home" class="flex-1 -mt-[76px]"><slot /></main>
      <main v-else class="mx-auto w-full max-w-[1200px] flex-1 px-4 pt-4 pb-16 md:px-8 md:pt-8"><slot /></main>

      <!-- Footer -->
      <footer class="mt-10 border-t border-border bg-card/60">
        <div class="mx-auto grid w-full max-w-[1200px] gap-8 px-4 py-10 md:grid-cols-[1.3fr_1fr_1fr] md:px-8">
          <div class="grid content-start gap-3">
            <NuxtLink to="/" class="flex items-center gap-2.5 text-heading no-underline">
              <BrandMark class="size-9" />
              <span class="font-display text-[18px] leading-tight font-semibold">Ifeew's Thaimassage</span>
            </NuxtLink>
            <p class="m-0 max-w-sm text-[14px] text-muted-foreground">นวดไทย นวดน้ำมัน นวดประคบสมุนไพร ด้วยทีมงานมืออาชีพ จองออนไลน์ได้ทุกสาขา</p>
          </div>
          <nav aria-label="ลิงก์ส่วนท้าย" class="grid content-start gap-2 text-[14px]">
            <p class="m-0 font-medium text-heading">เมนู</p>
            <NuxtLink to="/services" class="text-muted-foreground no-underline hover:text-heading">บริการ</NuxtLink>
            <NuxtLink to="/branches" class="text-muted-foreground no-underline hover:text-heading">สาขา</NuxtLink>
            <NuxtLink to="/book" class="text-muted-foreground no-underline hover:text-heading">จองคิว</NuxtLink>
            <NuxtLink to="/check-booking" class="text-muted-foreground no-underline hover:text-heading">ตรวจสอบการจอง</NuxtLink>
          </nav>
          <div class="grid content-start gap-2 text-[14px]">
            <p class="m-0 font-medium text-heading">ติดต่อสาขา</p>
            <template v-for="b in branches ?? []" :key="b.id">
              <span class="text-foreground">{{ b.name }}</span>
              <a v-if="b.phone" :href="tel(b.phone)" class="flex w-fit items-center gap-1.5 text-muted-foreground no-underline hover:text-heading"><Phone class="size-4" aria-hidden="true" /><span class="num">{{ b.phone }}</span></a>
            </template>
          </div>
        </div>
        <div class="border-t border-border">
          <p class="mx-auto m-0 w-full max-w-[1200px] px-4 py-4 text-[13px] text-muted-foreground md:px-8">© Ifeew's Thaimassage</p>
        </div>
      </footer>

    </div>
    <ClientOnly><Sonner /></ClientOnly>
  </TooltipProvider>
</template>
