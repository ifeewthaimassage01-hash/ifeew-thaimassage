<template>
  <!-- แถบโหลดบาง ๆ (แทน v-progress-linear indeterminate) -->
  <div class="relative h-1 w-full overflow-hidden rounded-full bg-secondary" role="progressbar" aria-label="กำลังโหลด" aria-busy="true">
    <div class="loading-bar absolute inset-y-0 w-1/3 rounded-full bg-primary" />
  </div>
</template>

<style scoped>
.loading-bar {
  animation: loading-slide 1.1s ease-in-out infinite;
}
@keyframes loading-slide {
  from { left: -33%; }
  to { left: 100%; }
}
@media (prefers-reduced-motion: reduce) {
  .loading-bar { animation: none; left: 0; width: 100%; opacity: 0.5; }
}
</style>
