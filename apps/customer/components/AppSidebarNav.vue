<script setup lang="ts">
// เมนูด้านข้าง ใช้ทั้งใน sidebar (เต็ม/แบบย่อ) และ drawer บนมือถือ
const props = defineProps<{ compact?: boolean }>()
const emit = defineEmits<{ navigate: [] }>()
const { groups, isActive } = useAppNav()
</script>

<template>
  <nav aria-label="เมนูหลัก" class="grid gap-6">
    <div v-for="g in groups" :key="g.label" class="grid gap-1">
      <p v-if="!props.compact" class="m-0 px-3 pb-1 text-[13px] font-medium text-muted-foreground">{{ g.label }}</p>
      <div v-else class="mx-auto mb-1 h-px w-6 bg-border" aria-hidden="true" />
      <template v-for="item in g.items" :key="item.to">
        <Tooltip v-if="props.compact">
          <TooltipTrigger as-child>
            <NuxtLink
              :to="item.to"
              :aria-label="item.label"
              :aria-current="isActive(item.to) ? 'page' : undefined"
              class="mx-auto flex size-11 items-center justify-center rounded-xl no-underline transition-colors"
              :class="isActive(item.to) ? 'bg-secondary text-primary' : 'text-muted-foreground hover:bg-muted hover:text-heading'"
              @click="emit('navigate')"
            ><component :is="item.icon" class="size-5" :stroke-width="1.75" /></NuxtLink>
          </TooltipTrigger>
          <TooltipContent side="right">{{ item.label }}</TooltipContent>
        </Tooltip>
        <NuxtLink
          v-else
          :to="item.to"
          :aria-current="isActive(item.to) ? 'page' : undefined"
          class="flex h-10 items-center gap-3 rounded-xl px-3 text-[15px] no-underline transition-colors"
          :class="isActive(item.to) ? 'bg-secondary font-medium text-heading' : 'text-foreground hover:bg-muted hover:text-heading'"
          @click="emit('navigate')"
        >
          <component :is="item.icon" class="size-[18px] shrink-0" :class="isActive(item.to) ? 'text-primary' : 'text-muted-soft'" :stroke-width="1.75" />
          {{ item.label }}
        </NuxtLink>
      </template>
    </div>
  </nav>
</template>
