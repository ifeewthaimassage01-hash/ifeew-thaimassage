<script setup lang="ts">
// ช่องยอมรับนโยบายความเป็นส่วนตัว (บังคับ) และรับข่าวสาร (ไม่บังคับ) พร้อมเปิดอ่านฉบับเต็ม
import type { CurrentPolicy } from '@ifeew/shared'

const privacyAccepted = defineModel<boolean>('privacy', { default: false })
const marketing = defineModel<boolean>('marketing', { default: false })
defineProps<{ policies: Partial<Record<'PRIVACY_NOTICE' | 'MARKETING', CurrentPolicy>> | null }>()

const showing = ref<CurrentPolicy | null>(null)
</script>

<template>
  <div class="mb-4">
    <v-checkbox v-model="privacyAccepted" color="primary" hide-details density="compact">
      <template #label>
        <span>
          ข้าพเจ้ารับทราบ
          <a href="#" class="text-light-brown" @click.prevent.stop="showing = policies?.PRIVACY_NOTICE ?? null">นโยบายความเป็นส่วนตัว</a>
          <span v-if="policies?.PRIVACY_NOTICE" class="text-xs text-light-brown"> (ฉบับ {{ policies.PRIVACY_NOTICE.version }})</span>
        </span>
      </template>
    </v-checkbox>
    <v-checkbox v-if="policies?.MARKETING" v-model="marketing" color="primary" hide-details density="compact">
      <template #label>
        <span>
          ยินยอมรับข่าวสารและโปรโมชัน (ไม่บังคับ)
          <a href="#" class="text-light-brown" @click.prevent.stop="showing = policies?.MARKETING ?? null">รายละเอียด</a>
        </span>
      </template>
    </v-checkbox>

    <v-dialog :model-value="!!showing" max-width="640" scrollable @update:model-value="showing = null">
      <v-card v-if="showing" class="p-6">
        <p class="m-0 mb-1 text-lg font-medium">{{ showing.title }}</p>
        <p class="m-0 mb-4 text-xs text-light-brown">ฉบับ {{ showing.version }}</p>
        <div class="max-h-[60vh] overflow-y-auto whitespace-pre-line text-sm">{{ showing.content }}</div>
        <div class="mt-4 flex justify-end"><v-btn variant="text" @click="showing = null">ปิด</v-btn></div>
      </v-card>
    </v-dialog>
  </div>
</template>
