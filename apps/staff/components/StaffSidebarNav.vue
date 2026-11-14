<script setup lang="ts">
// เมนูด้านข้างของ Staff: เต็ม (≥1280) / แบบย่อเหลือไอคอน (แท็บเล็ต) / ใน drawer (มือถือ)
// เมนูที่เลือก = แผ่นขาวนวลยกขึ้นจากพื้นครีม (เหมือนเมนูของเว็บลูกค้า) · หัวกลุ่มเว้นด้านบนมากกว่าด้านล่าง
const props = defineProps<{ compact?: boolean }>()
const emit = defineEmits<{ navigate: [] }>()
const { groups, isActive } = useStaffNav()
</script>

<template>
  <nav aria-label="เมนูหลัก" class="grid gap-6">
    <div v-for="g in groups" :key="g.label" class="grid gap-1">
      <p v-if="!props.compact" class="m-0 px-3 pb-1.5 text-[13px] font-medium text-muted-foreground">{{ g.label }}</p>
      <div v-else class="mx-auto mb-1.5 h-px w-6 bg-border" aria-hidden="true" />
      <template v-for="item in g.items" :key="item.to">
        <Tooltip v-if="props.compact">
          <TooltipTrigger as-child>
            <NuxtLink
              :to="item.to"
              :aria-label="item.label"
              :aria-current="isActive(item) ? 'page' : undefined"
              class="mx-auto flex size-11 items-center justify-center rounded-xl no-underline transition-[background-color,color,box-shadow] duration-150 focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
              :class="isActive(item) ? 'bg-card text-primary shadow-soft ring-1 ring-border' : 'text-muted-foreground hover:bg-muted hover:text-heading'"
              @click="emit('navigate')"
            ><component :is="item.icon" class="size-[18px]" :stroke-width="1.75" /></NuxtLink>
          </TooltipTrigger>
          <TooltipContent side="right">{{ item.label }}</TooltipContent>
        </Tooltip>
        <NuxtLink
          v-else
          :to="item.to"
          :aria-current="isActive(item) ? 'page' : undefined"
          class="flex h-10 items-center gap-3 rounded-xl px-3 text-[15px] no-underline transition-[background-color,color,box-shadow] duration-150 focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
          :class="isActive(item) ? 'bg-card font-medium text-heading shadow-soft ring-1 ring-border' : 'text-foreground hover:bg-muted hover:text-heading'"
          @click="emit('navigate')"
        >
          <component :is="item.icon" class="size-[18px] shrink-0" :class="isActive(item) ? 'text-primary' : 'text-muted-foreground'" :stroke-width="1.75" />
          {{ item.label }}
        </NuxtLink>
      </template>
    </div>
  </nav>
</template>
