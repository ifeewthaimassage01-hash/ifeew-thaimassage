<script setup lang="ts">
// แป้นกด PIN 6 หลัก (ปุ่มใหญ่สำหรับหน้าจอสัมผัส)
const props = defineProps<{ loading?: boolean; error?: string | null }>()
const emit = defineEmits<{ submit: [pin: string] }>()

const pin = ref('')
const LENGTH = 6

function press(d: string) {
  if (props.loading || pin.value.length >= LENGTH) return
  pin.value += d
  if (pin.value.length === LENGTH) emit('submit', pin.value)
}
function backspace() {
  pin.value = pin.value.slice(0, -1)
}
function reset() {
  pin.value = ''
}

defineExpose({ reset })

onKeyStroke((e) => {
  if (/^[0-9]$/.test(e.key)) press(e.key)
  else if (e.key === 'Backspace') backspace()
})
</script>

<template>
  <div class="flex flex-col items-center gap-5">
    <div class="flex gap-3" aria-label="PIN">
      <span
        v-for="i in LENGTH"
        :key="i"
        class="block h-4 w-4 rounded-full border-2 border-light-brown"
        :class="i <= pin.length ? 'bg-light-brown' : 'bg-transparent'"
      />
    </div>

    <p v-if="error" class="m-0 text-center text-sm text-red-700" role="alert">{{ error }}</p>

    <div class="grid grid-cols-3 gap-3">
      <v-btn
        v-for="d in ['1', '2', '3', '4', '5', '6', '7', '8', '9']"
        :key="d"
        variant="tonal"
        color="primary"
        class="!h-16 !w-20 text-xl"
        :disabled="loading"
        @click="press(d)"
      >
        {{ d }}
      </v-btn>
      <span />
      <v-btn variant="tonal" color="primary" class="!h-16 !w-20 text-xl" :disabled="loading" @click="press('0')">
        0
      </v-btn>
      <v-btn variant="text" class="!h-16 !w-20" :disabled="loading" aria-label="ลบ" @click="backspace">
        <v-icon icon="mdi-backspace-outline" />
      </v-btn>
    </div>

    <v-progress-linear v-if="loading" indeterminate color="primary" class="max-w-xs" />
  </div>
</template>
