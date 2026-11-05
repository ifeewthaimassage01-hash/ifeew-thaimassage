<script setup lang="ts">
// แสดงกล่องจาก useDialog() — วางใน layout ครั้งเดียว
const { current } = useDialog()

const open = ref(false)
const text = ref('')
const touched = ref(false)

watch(current, (req) => {
  if (!req) return
  text.value = req.options.defaultValue ?? ''
  touched.value = false
  open.value = true
})

const opts = computed(() => current.value?.options)
const isPrompt = computed(() => current.value?.kind === 'prompt')
const minLength = computed(() => opts.value?.minLength ?? 0)
const tooShort = computed(() => isPrompt.value && text.value.trim().length < minLength.value)
const error = computed(() =>
  touched.value && tooShort.value
    ? minLength.value <= 1 ? 'กรุณากรอกข้อมูล' : `กรอกอย่างน้อย ${minLength.value} ตัวอักษร`
    : null,
)

function finish(value: boolean | string | null) {
  const req = current.value
  current.value = null
  open.value = false
  req?.resolve(value)
}

function submit() {
  if (!isPrompt.value) return finish(true)
  touched.value = true
  if (tooShort.value) return
  finish(text.value)
}

function onOpenChange(v: boolean) {
  if (!v && current.value) finish(isPrompt.value ? null : false)
}
</script>

<template>
  <Dialog :open="open" @update:open="onOpenChange">
    <DialogContent v-if="opts" class="sm:max-w-md">
      <form class="grid gap-5" novalidate @submit.prevent="submit">
        <DialogHeader>
          <DialogTitle>{{ opts.title }}</DialogTitle>
          <DialogDescription :class="opts.description ? '' : 'sr-only'">
            {{ opts.description ?? (isPrompt ? 'กรอกข้อมูลแล้วกดยืนยัน' : 'ยืนยันการดำเนินการ') }}
          </DialogDescription>
        </DialogHeader>

        <template v-if="isPrompt">
          <TextareaField
            v-if="opts.multiline"
            v-model="text"
            :label="opts.label"
            :aria-label="opts.label ? undefined : opts.title"
            :placeholder="opts.placeholder"
            :maxlength="opts.maxLength"
            :error="error"
            rows="3"
            autofocus
          />
          <TextField
            v-else
            v-model="text"
            :label="opts.label"
            :aria-label="opts.label ? undefined : opts.title"
            :placeholder="opts.placeholder"
            :maxlength="opts.maxLength"
            :error="error"
            autofocus
          />
        </template>

        <DialogFooter class="gap-2">
          <Button type="button" variant="outline" @click="onOpenChange(false)">{{ opts.cancelText ?? 'ยกเลิก' }}</Button>
          <Button type="submit" :variant="opts.destructive ? 'destructive' : 'default'">{{ opts.confirmText ?? 'ยืนยัน' }}</Button>
        </DialogFooter>
      </form>
    </DialogContent>
  </Dialog>
</template>
