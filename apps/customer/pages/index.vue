<script setup lang="ts">
import { formatBaht, formatDuration } from '@ifeew/shared'

// หน้าแรก — คำถามของหน้า: "สาขาไหนเปิดอยู่ จองได้เลยไหม ราคาเท่าไร"
const { data: branches, pending, error } = await useBranches()
const branchIds = computed(() => (branches.value ?? []).map((b) => b.id))
const { data: hours } = await useOpenToday(branchIds)
const { data: catalog } = await useCatalog()

// ราคาเริ่มต้นของแต่ละบริการ (รวมทุกสาขา) — แสดง 6 รายการแรกตามลำดับเมนูของร้าน
const services = computed(() => {
  const map = new Map<string, { id: string; name: string; category: string; from: number; minutes: number }>()
  for (const s of catalog.value ?? []) {
    const cheapest = s.options[0]
    if (!cheapest) continue
    const cur = map.get(s.service_id)
    if (!cur || cheapest.price < cur.from)
      map.set(s.service_id, { id: s.branch_service_id, name: s.name, category: s.category_name, from: cheapest.price, minutes: cheapest.duration_minutes })
  }
  return [...map.values()]
})
</script>

<template>
  <div class="grid gap-8">
    <section class="grid gap-3">
      <h1 class="m-0 text-[28px] font-semibold leading-tight tracking-tight">นวดไทย จองคิวออนไลน์ได้ทุกสาขา</h1>
      <p class="m-0 max-w-[46ch] text-[17px] text-foreground">เลือกสาขา บริการ และเวลาที่ว่าง แล้วจ่ายมัดจำผ่าน PromptPay ก็ได้คิวทันที</p>
      <div class="mt-1 flex flex-wrap gap-2">
        <Button as-child size="lg"><NuxtLink to="/book">จองคิว</NuxtLink></Button>
        <Button as-child size="lg" variant="outline"><NuxtLink to="/services">ดูราคาบริการ</NuxtLink></Button>
      </div>
    </section>

    <!-- ถ้ายังไม่มีบริการเปิดจอง ไม่แสดงคอลัมน์ราคา ให้สาขาใช้เต็มความกว้าง -->
    <div class="grid items-start gap-6" :class="services.length ? 'lg:grid-cols-[minmax(0,1fr)_340px]' : ''">
      <section class="grid gap-3" aria-labelledby="branches-h">
        <div class="flex items-baseline justify-between gap-3">
          <h2 id="branches-h" class="m-0 text-xl font-semibold">สาขาวันนี้</h2>
          <NuxtLink to="/branches" class="text-[15px]">สาขาทั้งหมด</NuxtLink>
        </div>
        <div v-if="pending" class="grid gap-3"><Skeleton v-for="n in 2" :key="n" class="h-44 rounded-xl" /></div>
        <Alert v-else-if="error" variant="destructive"><AlertDescription>โหลดข้อมูลสาขาไม่สำเร็จ กรุณาลองใหม่</AlertDescription></Alert>
        <p v-else-if="!branches?.length" class="m-0 rounded-lg border border-dashed px-4 py-3 text-muted-foreground">ยังไม่มีสาขาที่เปิดให้บริการ</p>
        <div v-else class="grid items-start gap-3" :class="!services.length && branches.length > 1 ? 'md:grid-cols-2' : ''">
          <BranchCard v-for="b in branches" :key="b.id" :branch="b" :hours="hours?.[b.id] ?? null" />
        </div>
      </section>

      <section v-if="services.length" class="grid gap-3" aria-labelledby="prices-h">
        <div class="flex items-baseline justify-between gap-3">
          <h2 id="prices-h" class="m-0 text-xl font-semibold">ราคาเริ่มต้น</h2>
          <NuxtLink to="/services" class="text-[15px]">ทุกบริการ</NuxtLink>
        </div>
        <Card class="gap-0 py-2">
          <NuxtLink
            v-for="s in services.slice(0, 6)"
            :key="s.id"
            :to="`/services/${s.id}`"
            class="flex items-center gap-3 px-5 py-3 text-foreground no-underline transition-colors hover:bg-muted/60"
          >
            <span class="size-2.5 shrink-0 rounded-full" :class="categoryTint(s.category)" aria-hidden="true" />
            <span class="min-w-0 flex-1">
              <span class="block truncate font-medium">{{ s.name }}</span>
              <span class="block text-sm text-muted-foreground">{{ s.category }} · {{ formatDuration(s.minutes) }}</span>
            </span>
            <span class="num shrink-0 text-right font-semibold">{{ formatBaht(s.from) }}</span>
          </NuxtLink>
          <p v-if="services.length > 6" class="m-0 px-5 pt-1 pb-3 text-sm text-muted-foreground">และอีก {{ services.length - 6 }} บริการ</p>
        </Card>
      </section>
    </div>
  </div>
</template>
