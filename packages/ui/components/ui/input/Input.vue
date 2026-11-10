<script setup lang="ts">
import type { HTMLAttributes } from "vue"
import { useVModel } from "@vueuse/core"
import { cn } from "cn"

/**
 * จำกัดให้พิมพ์ได้เฉพาะตัวเลข (ตัดตัวอักษรอื่นทิ้งทันที รวมถึงตอนวาง และแปลงเลขไทย ๐-๙ เป็น 0-9)
 * - digits  : สตริงตัวเลขล้วน เช่น เบอร์โทร PIN รหัส OTP เลขผู้เสียภาษี (ค่าเป็น string คงเลข 0 นำหน้า)
 * - integer : จำนวนเต็มไม่ติดลบ (ค่าเป็น number)
 * - decimal : จำนวนเงิน ทศนิยมไม่เกิน 2 ตำแหน่ง ไม่ติดลบ (ค่าเป็น number)
 * - signed  : แบบ decimal แต่ใส่ค่าลบได้ (ค่าเป็น number)
 * type="number" ที่ไม่ระบุ numeric จะใช้ decimal (แสดงเป็นช่องข้อความ ไม่มีปุ่มเลื่อนค่า และพิมพ์ e/+/- ไม่ได้)
 */
export type NumericMode = "digits" | "integer" | "decimal" | "signed"

defineOptions({ inheritAttrs: false })

const props = defineProps<{
  defaultValue?: string | number
  modelValue?: string | number
  class?: HTMLAttributes["class"]
  numeric?: NumericMode
}>()

const emits = defineEmits<{
  (e: "update:modelValue", payload: string | number): void
}>()

const modelValue = useVModel(props, "modelValue", emits, {
  passive: true,
  defaultValue: props.defaultValue,
})

const attrs = useAttrs()
const mode = computed<NumericMode | undefined>(() => props.numeric ?? (attrs.type === "number" ? "decimal" : undefined))
// attrs ที่ส่งต่อให้ <input> (โหมดตัวเลขกำหนด type/inputmode เอง)
const passAttrs = computed(() => {
  if (!mode.value) return attrs
  const { type: _type, inputmode: _inputmode, min: _min, max: _max, step: _step, ...rest } = attrs
  return rest
})
const numericType = computed(() => (attrs.type === "password" ? "password" : "text"))
const numericInputmode = computed<"numeric" | "decimal" | "tel" | undefined>(() => {
  if (mode.value === "signed") return undefined // แป้นตัวเลขบน iOS ไม่มีเครื่องหมายลบ
  if (mode.value === "decimal") return "decimal"
  return attrs.inputmode === "tel" ? "tel" : "numeric"
})

const THAI_DIGITS = /[๐-๙]/g
function sanitize(raw: string, m: NumericMode): string {
  const v = raw.replace(THAI_DIGITS, (d) => String(d.charCodeAt(0) - 0x0e50))
  if (m === "digits" || m === "integer") return v.replace(/\D/g, "")
  const negative = m === "signed" && v.trimStart().startsWith("-")
  const [int = "", ...rest] = v.replace(/[^0-9.]/g, "").split(".")
  const dec = rest.length ? `.${rest.join("").slice(0, 2)}` : ""
  return `${negative ? "-" : ""}${int}${dec}`
}
function toValue(text: string, m: NumericMode): string | number {
  if (m === "digits") return text
  return text === "" || text === "-" || text === "." || text === "-." ? "" : Number(text)
}

// ข้อความที่แสดงในช่อง (เก็บแยกจากค่า เพื่อให้พิมพ์ "12." หรือ "-" ระหว่างทางได้)
const text = ref("")
watch(
  [() => props.modelValue, mode],
  ([v, m]) => {
    if (!m) return
    const next = v === undefined || v === null ? "" : String(v)
    if (m === "digits" ? text.value !== next : toValue(text.value, m) !== v) text.value = sanitize(next, m)
  },
  { immediate: true },
)

function onNumericInput(e: Event) {
  const m = mode.value!
  const el = e.target as HTMLInputElement
  const raw = el.value
  const clean = sanitize(raw, m)
  if (clean !== raw) {
    const caret = sanitize(raw.slice(0, el.selectionStart ?? raw.length), m).length
    el.value = clean
    el.setSelectionRange(caret, caret)
  }
  text.value = clean
  emits("update:modelValue", toValue(clean, m))
}

const inputClass = computed(() => cn(
  'file:text-foreground placeholder:text-muted-foreground selection:bg-primary selection:text-primary-foreground border-input h-11 md:h-10 w-full min-w-0 rounded-lg border bg-card px-3.5 py-1 text-base text-heading transition-[color,box-shadow] outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/40 file:inline-flex file:h-7 file:border-0 file:bg-transparent file:text-sm file:font-medium disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50',
  'focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-3',
  'aria-invalid:ring-destructive/20 dark:aria-invalid:ring-destructive/40 aria-invalid:border-destructive',
  props.class,
))
</script>

<template>
  <input
    v-if="mode"
    v-bind="passAttrs"
    :value="text"
    :type="numericType"
    :inputmode="numericInputmode"
    data-slot="input"
    :class="inputClass"
    @input="onNumericInput"
  >
  <input
    v-else
    v-bind="passAttrs"
    v-model="modelValue"
    data-slot="input"
    :class="inputClass"
  >
</template>
