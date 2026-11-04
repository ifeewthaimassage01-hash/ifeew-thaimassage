<script setup lang="ts">
import type { HTMLAttributes } from "vue"
import { cn } from "cn"

// as: ระดับหัวข้อให้ตรงโครงหน้า (ค่าเริ่มต้น h3)
const props = withDefaults(defineProps<{
  as?: "h1" | "h2" | "h3" | "h4" | "p"
  class?: HTMLAttributes["class"]
}>(), { as: "h3" })
</script>

<template>
  <component
    :is="props.as"
    data-slot="card-title"
    :class="cn('m-0 text-lg leading-snug font-semibold', props.class)"
  >
    <slot />
  </component>
</template>
