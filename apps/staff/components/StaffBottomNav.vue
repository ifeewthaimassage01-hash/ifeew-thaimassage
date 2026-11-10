<script setup lang="ts">
import { CalendarCheck, ListOrdered, ReceiptText, Store, Wallet } from '@lucide/vue'

// แถบเมนูล่างสำหรับมือถือ (<768) — ทางลัดงานประจำวันที่ใช้บ่อย
const route = useRoute()

const items = [
  { to: '/pos', label: 'หน้าร้าน', icon: Store },
  { to: '/payments', label: 'ชำระเงิน', icon: Wallet, also: ['/checkout'] },
  { to: '/queue', label: 'คิว', icon: ListOrdered },
  { to: '/bookings', label: 'การจอง', icon: CalendarCheck },
  { to: '/expenses', label: 'รายจ่าย', icon: ReceiptText },
]

const isActive = (i: (typeof items)[number]) =>
  [i.to, ...(i.also ?? [])].some((p) => route.path === p || route.path.startsWith(`${p}/`))
</script>

<template>
  <!-- ตอน active: ไอคอนลอยขึ้นเหนือแถบเป็นวงกลมสีหลัก + เงาเรือง (ตามภาพอ้างอิง) -->
  <nav
    aria-label="เมนูลัด"
    class="fixed inset-x-0 bottom-0 z-40 rounded-t-3xl bg-card pb-[env(safe-area-inset-bottom)] shadow-[0_-6px_24px_-8px_rgb(74_55_40/0.18)] md:hidden"
  >
    <ul class="m-0 grid h-[68px] list-none grid-cols-5 p-0">
      <li v-for="item in items" :key="item.to" class="min-w-0">
        <NuxtLink
          :to="item.to"
          :aria-current="isActive(item) ? 'page' : undefined"
          class="group flex h-full flex-col items-center justify-end gap-1.5 px-1 pb-3 no-underline focus-visible:outline-none"
          :class="isActive(item) ? 'text-primary' : 'text-muted-foreground hover:text-heading'"
        >
          <span
            class="grid place-items-center rounded-full transition-all duration-300 ease-out group-focus-visible:ring-3 group-focus-visible:ring-ring/50"
            :class="
              isActive(item)
                ? 'size-12 -translate-y-3 bg-primary text-primary-foreground shadow-[0_4px_10px_-2px_rgb(147_112_79/0.4)] ring-4 ring-card'
                : 'size-7'
            "
          >
            <component :is="item.icon" :class="isActive(item) ? 'size-[22px]' : 'size-5'" :stroke-width="isActive(item) ? 2 : 1.75" />
          </span>
          <span
            class="max-w-full truncate text-[12px] leading-none transition-all duration-300"
            :class="isActive(item) ? '-mt-3 font-medium text-primary' : ''"
          >{{ item.label }}</span>
        </NuxtLink>
      </li>
    </ul>
  </nav>
</template>
