import type { VariantProps } from "class-variance-authority"
import { cva } from "class-variance-authority"

export { default as Alert } from "./Alert.vue"
export { default as AlertDescription } from "./AlertDescription.vue"
export { default as AlertTitle } from "./AlertTitle.vue"

// ข้อความแจ้งในหน้า: พื้นอ่อน เส้นขอบบาง ไม่มีเงา
export const alertVariants = cva(
  "relative w-full rounded-lg border px-4 py-3 text-[15px] grid has-[>svg]:grid-cols-[calc(var(--spacing)*4)_1fr] grid-cols-[0_1fr] has-[>svg]:gap-x-3 gap-y-0.5 items-start [&>svg]:size-4 [&>svg]:translate-y-1 [&>svg]:text-current",
  {
    variants: {
      variant: {
        default: "border-border bg-card text-foreground",
        info: "border-secondary bg-muted text-heading",
        success: "border-success/30 bg-success-soft text-success-ink",
        warning: "border-brand-accent/30 bg-pending-soft text-pending-ink",
        destructive: "border-danger/30 bg-danger-soft text-danger-ink",
      },
    },
    defaultVariants: {
      variant: "default",
    },
  },
)

export type AlertVariants = VariantProps<typeof alertVariants>
