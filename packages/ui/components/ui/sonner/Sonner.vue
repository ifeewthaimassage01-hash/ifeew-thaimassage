<script lang="ts" setup>
// Toaster (shadcn-vue Sonner) + สไตล์ร่วมของทั้ง 2 แอป (Warm Cream): พื้นการ์ด · ขอบมน · สีไอคอน/ขอบซ้ายตามประเภท
// วางครั้งเดียวใน layout: <Sonner />  (ค่าเริ่มต้น: บนกลางจอ · มีปุ่มปิด)
import type { ToasterProps } from "vue-sonner"
import { CircleCheckIcon, InfoIcon, Loader2Icon, OctagonXIcon, TriangleAlertIcon, XIcon } from "@lucide/vue"
import { cn } from "cn"
import { Toaster as Sonner } from "vue-sonner"

const props = withDefaults(defineProps<ToasterProps>(), {
  position: "top-center",
  closeButton: true,
  expand: false,
  visibleToasts: 3,
})

const toastOptions = computed<ToasterProps["toastOptions"]>(() => ({
  ...props.toastOptions,
  classes: {
    // แยกจากพื้นหลังครีมให้ชัด: พื้นสีอ่อนตามประเภท + ขอบหนาสีเข้ม + เงาลึก · ปุ่มปิดอยู่มุมขวาในกรอบ
    toast: "!rounded-xl !border-2 !shadow-[0_12px_32px_-10px_rgb(74_55_40/0.45)] !text-[15px] !gap-3 !py-3.5 !pl-4 !pr-11",
    title: "!font-semibold !leading-snug",
    description: "!opacity-80",
    success: "!bg-success-soft !border-success-ink/45 !text-success-ink [&_[data-icon]]:!text-success-ink",
    error: "!bg-danger-soft !border-danger-ink/45 !text-danger-ink [&_[data-icon]]:!text-danger-ink",
    warning: "!bg-pending-soft !border-pending-ink/45 !text-pending-ink [&_[data-icon]]:!text-pending-ink",
    info: "!bg-card !border-brand-accent/60 [&_[data-icon]]:!text-brand-accent",
    closeButton: "!transform-none !left-auto !right-2.5 !top-1/2 !-translate-y-1/2 !translate-x-0 !size-7 !border-0 !bg-transparent !text-current !opacity-60 hover:!opacity-100 hover:!bg-black/5",
    ...props.toastOptions?.classes,
  },
}))
</script>

<template>
  <Sonner
    :class="cn('toaster group', props.class)"
    :style="{
      '--normal-bg': 'var(--card)',
      '--normal-text': 'var(--heading)',
      '--normal-border': 'var(--input)',
      '--border-radius': 'var(--radius)',
    }"
    v-bind="{ ...props, toastOptions }"
  >
    <template #success-icon>
      <CircleCheckIcon class="size-5" />
    </template>
    <template #info-icon>
      <InfoIcon class="size-5" />
    </template>
    <template #warning-icon>
      <TriangleAlertIcon class="size-5" />
    </template>
    <template #error-icon>
      <OctagonXIcon class="size-5" />
    </template>
    <template #loading-icon>
      <div>
        <Loader2Icon class="size-5 animate-spin" />
      </div>
    </template>
    <template #close-icon>
      <XIcon class="size-3.5" />
    </template>
  </Sonner>
</template>
