<script setup lang="ts">
import type { HTMLAttributes } from "vue"
import { cn } from "cn"

// stack: จอแคบ (<640px) แสดงแต่ละแถวเป็นการ์ดซ้อนลงมา แทนการเลื่อนตารางไปด้านข้าง
//   - หัวคอลัมน์ถูกคัดลอกเป็น data-label ของแต่ละช่องให้อัตโนมัติ (CSS แสดงเป็นป้ายด้านซ้าย)
//   - ช่องแรกของแถว = หัวการ์ด · คอลัมน์ที่หัวเป็น sr-only (เช่น ปุ่มการทำงาน) ไม่มีป้าย
//   - ช่อง colspan (เช่น "ยังไม่มีข้อมูล") แสดงเต็มแถว
//   ใส่ data-label เองที่ TableCell ได้ ถ้าต้องการป้ายต่างจากหัวคอลัมน์
const props = defineProps<{
  class?: HTMLAttributes["class"]
  stack?: boolean
}>()

const table = ref<HTMLTableElement | null>(null)
let observer: MutationObserver | null = null

function visibleText(el: Element): string {
  const clone = el.cloneNode(true) as Element
  clone.querySelectorAll(".sr-only").forEach((n) => n.remove())
  return clone.textContent?.trim() ?? ""
}

function applyLabels() {
  const t = table.value
  if (!t) return
  const heads = [...t.querySelectorAll(":scope > thead > tr:last-child > th")].map(visibleText)
  t.querySelectorAll(":scope > tbody > tr, :scope > tfoot > tr").forEach((tr) => {
    let col = 0
    for (const cell of tr.children) {
      const span = (cell as HTMLTableCellElement).colSpan || 1
      if (span > 1 && span >= heads.length) cell.setAttribute("data-full", "")
      else if (!cell.hasAttribute("data-label") || cell.hasAttribute("data-auto-label")) {
        cell.setAttribute("data-label", heads[col] ?? "")
        cell.setAttribute("data-auto-label", "")
      }
      col += span
    }
  })
}

onMounted(() => {
  if (!props.stack || !table.value) return
  applyLabels()
  observer = new MutationObserver(applyLabels)
  observer.observe(table.value, { childList: true, subtree: true })
})
onBeforeUnmount(() => observer?.disconnect())
</script>

<template>
  <div data-slot="table-container" class="relative w-full overflow-auto">
    <table ref="table" data-slot="table" :data-stack="stack ? '' : undefined" :class="cn('w-full caption-bottom text-[15px]', props.class)">
      <slot />
    </table>
  </div>
</template>
