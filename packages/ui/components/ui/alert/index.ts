import type { VariantProps } from "class-variance-authority"
import { cva } from "class-variance-authority"

export { default as Alert } from "./Alert.vue"
export { default as AlertDescription } from "./AlertDescription.vue"
export { default as AlertTitle } from "./AlertTitle.vue"

// ข้อความแจ้ง: พื้นสีอ่อนแบน ไม่มีเส้นขอบ ไม่มีเงา ตัวหนังสือสีเข้มเฉดเดียวกัน
export const alertVariants = cva(
  "relative w-full rounded-lg px-4 py-3 text-[15px] grid has-[>svg]:grid-cols-[calc(var(--spacing)*4)_1fr] grid-cols-[0_1fr] has-[>svg]:gap-x-3 gap-y-0.5 items-start [&>svg]:size-4 [&>svg]:translate-y-1 [&>svg]:text-current",
  {
    variants: {
      variant: {
        default: "bg-muted text-foreground",
        info: "bg-tint-beige text-tint-beige-ink",
        success: "bg-tint-green text-tint-green-ink",
        warning: "bg-tint-warn text-tint-warn-ink",
        destructive: "bg-tint-danger text-tint-danger-ink",
      },
    },
    defaultVariants: {
      variant: "default",
    },
  },
)

export type AlertVariants = VariantProps<typeof alertVariants>
