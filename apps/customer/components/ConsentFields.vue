<script setup lang="ts">
// ช่องยอมรับนโยบายความเป็นส่วนตัว (บังคับ) และรับข่าวสาร (ไม่บังคับ) พร้อมเปิดอ่านฉบับเต็ม
import type { CurrentPolicy } from '@ifeew/shared'

const privacyAccepted = defineModel<boolean>('privacy', { default: false })
const marketing = defineModel<boolean>('marketing', { default: false })
defineProps<{ policies: Partial<Record<'PRIVACY_NOTICE' | 'MARKETING', CurrentPolicy>> | null }>()

const showing = ref<CurrentPolicy | null>(null)
const uid = useId()
</script>

<template>
  <div class="grid gap-3">
    <div class="flex items-start gap-3">
      <Checkbox :id="`${uid}-privacy`" v-model="privacyAccepted" class="mt-0.5" />
      <Label :for="`${uid}-privacy`" class="block text-[15px] leading-6 font-normal">
        ข้าพเจ้ารับทราบ
        <button type="button" class="cursor-pointer text-link underline underline-offset-2" @click.prevent="showing = policies?.PRIVACY_NOTICE ?? null">นโยบายความเป็นส่วนตัว</button>
        <span v-if="policies?.PRIVACY_NOTICE" class="text-muted-foreground"> (ฉบับ {{ policies.PRIVACY_NOTICE.version }})</span>
      </Label>
    </div>
    <div v-if="policies?.MARKETING" class="flex items-start gap-3">
      <Checkbox :id="`${uid}-marketing`" v-model="marketing" class="mt-0.5" />
      <Label :for="`${uid}-marketing`" class="block text-[15px] leading-6 font-normal">
        รับข่าวสารและโปรโมชัน <span class="text-muted-foreground">(ไม่บังคับ)</span>{{ ' ' }}
        <button type="button" class="cursor-pointer text-link underline underline-offset-2" @click.prevent="showing = policies?.MARKETING ?? null">รายละเอียด</button>
      </Label>
    </div>

    <Dialog :open="!!showing" @update:open="(v) => !v && (showing = null)">
      <DialogContent class="max-h-[85dvh] grid-rows-[auto_minmax(0,1fr)_auto] sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle>{{ showing?.title }}</DialogTitle>
          <DialogDescription>ฉบับ {{ showing?.version }}</DialogDescription>
        </DialogHeader>
        <div class="overflow-y-auto whitespace-pre-line text-[15px] leading-relaxed">{{ showing?.content }}</div>
        <DialogFooter><Button variant="outline" @click="showing = null">ปิด</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
