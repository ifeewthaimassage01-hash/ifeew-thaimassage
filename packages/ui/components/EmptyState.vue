<script setup lang="ts">
// สถานะว่าง: ภาพเส้นเรียบ ๆ (หินนวดซ้อน + ใบไม้) + หัวข้อ + คำอธิบาย + ปุ่ม (DESIGN.md §3)
defineProps<{ title: string; description?: string; compact?: boolean }>()
</script>

<template>
  <div class="flex flex-col items-center rounded-xl border border-dashed border-input bg-card text-center" :class="compact ? 'gap-2 px-5 py-6' : 'gap-3 px-6 py-10'">
    <svg v-if="!compact" viewBox="0 0 120 88" class="h-20 w-28" fill="none" aria-hidden="true">
      <ellipse cx="60" cy="80" rx="44" ry="5" fill="var(--secondary)" />
      <rect x="30" y="58" width="60" height="18" rx="9" stroke="var(--muted-soft)" stroke-width="2" fill="var(--card)" />
      <rect x="38" y="42" width="44" height="16" rx="8" stroke="var(--muted-soft)" stroke-width="2" fill="var(--card)" />
      <rect x="46" y="28" width="28" height="14" rx="7" stroke="var(--muted-soft)" stroke-width="2" fill="var(--card)" />
      <path d="M74 26c4-12 14-17 26-16-1 12-9 20-22 20" stroke="var(--brand-accent)" stroke-width="2" stroke-linecap="round" />
      <path d="M78 28c5-5 10-9 16-12" stroke="var(--brand-accent)" stroke-width="2" stroke-linecap="round" />
    </svg>
    <p class="m-0 font-medium text-heading">{{ title }}</p>
    <p v-if="description" class="m-0 max-w-[44ch] text-[15px] text-muted-foreground">{{ description }}</p>
    <div v-if="$slots.default" class="mt-1 flex flex-wrap justify-center gap-2"><slot /></div>
  </div>
</template>
