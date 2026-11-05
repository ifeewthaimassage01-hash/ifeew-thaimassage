<script setup lang="ts">
import type { HTMLAttributes } from "vue"
import { cn } from "cn"

const props = defineProps<{
  class?: HTMLAttributes["class"]
}>()
</script>

<template>
  <th
    data-slot="table-head"
    :class="cn('text-muted-foreground h-11 px-4 text-left align-middle text-[13px] font-medium whitespace-nowrap [&:has([role=checkbox])]:pr-0 *:[[role=checkbox]]:translate-y-0.5', props.class)"
  >
    <slot />
  </th>
</template>
