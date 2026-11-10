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
})

const toastOptions = computed<ToasterProps["toastOptions"]>(() => ({
  ...props.toastOptions,
  classes: {
    toast: "!rounded-xl !border !border-border !bg-card !text-heading !shadow-soft !text-[15px] !gap-3 !py-3.5 !pl-4",
    title: "!font-medium !leading-snug",
    description: "!text-muted-foreground",
    success: "!border-l-4 !border-l-success [&_[data-icon]]:!text-success-ink",
    error: "!border-l-4 !border-l-danger [&_[data-icon]]:!text-danger-ink",
    warning: "!border-l-4 !border-l-pending-ink [&_[data-icon]]:!text-pending-ink",
    info: "!border-l-4 !border-l-brand-accent [&_[data-icon]]:!text-brand-accent",
    closeButton: "!bg-card !border-border !text-muted-foreground hover:!text-heading",
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
      '--normal-border': 'var(--border)',
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
