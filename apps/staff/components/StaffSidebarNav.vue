<script setup lang="ts">
// เมนูด้านข้างของ Staff: เต็ม (≥1280) / แบบย่อเหลือไอคอน (แท็บเล็ต) / ใน drawer (มือถือ)
const props = defineProps<{ compact?: boolean }>()
const emit = defineEmits<{ navigate: [] }>()
const { groups, isActive } = useStaffNav()
</script>

<template>
  <nav aria-label="เมนูหลัก" class="grid gap-5">
    <div v-for="g in groups" :key="g.label" class="grid gap-0.5">
      <p v-if="!props.compact" class="m-0 px-3 pb-1 text-[13px] font-medium text-muted-foreground">{{ g.label }}</p>
      <div v-else class="mx-auto mb-1 h-px w-6 bg-border" aria-hidden="true" />
      <template v-for="item in g.items" :key="item.to">
        <Tooltip v-if="props.compact">
          <TooltipTrigger as-child>
            <NuxtLink
              :to="item.to"
              :aria-label="item.label"
              :aria-current="isActive(item) ? 'page' : undefined"
              class="mx-auto flex size-10 items-center justify-center rounded-lg no-underline transition-colors"
              :class="isActive(item) ? 'bg-secondary text-primary' : 'text-muted-foreground hover:bg-muted hover:text-heading'"
              @click="emit('navigate')"
            ><component :is="item.icon" class="size-[18px]" :stroke-width="1.75" /></NuxtLink>
          </TooltipTrigger>
          <TooltipContent side="right">{{ item.label }}</TooltipContent>
        </Tooltip>
        <NuxtLink
          v-else
          :to="item.to"
          :aria-current="isActive(item) ? 'page' : undefined"
          class="flex h-9 items-center gap-3 rounded-lg px-3 text-[15px] no-underline transition-colors"
          :class="isActive(item) ? 'bg-secondary font-medium text-heading' : 'text-foreground hover:bg-muted hover:text-heading'"
          @click="emit('navigate')"
        >
          <component :is="item.icon" class="size-[18px] shrink-0" :class="isActive(item) ? 'text-primary' : 'text-muted-soft'" :stroke-width="1.75" />
          {{ item.label }}
        </NuxtLink>
      </template>
    </div>
  </nav>
</template>
