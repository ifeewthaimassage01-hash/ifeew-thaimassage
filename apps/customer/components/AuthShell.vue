<script setup lang="ts">
// กรอบหน้าฟอร์มบัญชี: ฟอร์มด้านซ้าย + สิ่งที่สมาชิกทำได้จริงในแอปด้านขวา (มือถือเรียงลงมา)
defineProps<{ title: string; subtitle?: string; noAside?: boolean }>()

const perks = [
  { title: 'ดูการจองและสถานะมัดจำ', text: 'รู้ทันทีว่าร้านยืนยันแล้วหรือยัง และส่งสลิปมัดจำได้จากหน้าการจอง' },
  { title: 'ประวัติการนวด', text: 'ย้อนดูบริการ ระยะเวลา และหมอที่นวดให้ เพื่อจองคนเดิมครั้งหน้า' },
  { title: 'ยกเลิกได้เอง', text: 'ยกเลิกก่อนเวลานัดตามนโยบายร้านได้โดยไม่ต้องโทร ร้านโอนมัดจำคืนให้' },
  { title: 'ข้อมูลเป็นของคุณ', text: 'ดาวน์โหลดหรือขอลบข้อมูลส่วนตัวได้จากหน้าโปรไฟล์' },
]
</script>

<template>
  <div class="grid items-start gap-6 md:grid-cols-[minmax(0,440px)_minmax(0,1fr)] md:gap-10">
    <Card class="gap-5 py-6">
      <CardHeader class="px-6">
        <CardTitle as="h1" class="text-2xl">{{ title }}</CardTitle>
        <p v-if="subtitle" class="m-0 text-[15px] text-muted-foreground">{{ subtitle }}</p>
      </CardHeader>
      <CardContent class="px-6">
        <slot />
      </CardContent>
      <div v-if="$slots.footer" class="border-t border-border px-6 pt-4 text-center text-[15px]">
        <slot name="footer" />
      </div>
    </Card>

    <section v-if="!noAside" class="grid gap-4 rounded-xl bg-secondary p-6 md:mt-0" aria-labelledby="perks-h">
      <h2 id="perks-h" class="m-0 text-xl font-semibold">สมาชิกทำอะไรได้บ้าง</h2>
      <dl class="m-0 grid gap-4 sm:grid-cols-2 md:grid-cols-1 lg:grid-cols-2">
        <div v-for="p in perks" :key="p.title" class="grid gap-1">
          <dt class="font-semibold">{{ p.title }}</dt>
          <dd class="m-0 text-[15px] text-foreground">{{ p.text }}</dd>
        </div>
      </dl>
    </section>
  </div>
</template>
