import type { VariantProps } from "class-variance-authority"
import { cva } from "class-variance-authority"

export { default as Badge } from "./Badge.vue"

// สถานะ (DESIGN.md: Success/Danger เฉพาะสถานะที่มีความหมาย) — พื้นอ่อน + จุดสี + ตัวหนังสือเข้มที่อ่านได้
export const badgeVariants = cva(
  "inline-flex flex-none items-center justify-center gap-1.5 rounded-md px-2 py-0.5 text-[13px] font-medium leading-5 w-fit whitespace-nowrap shrink-0 [&>svg]:size-3 [&>svg]:pointer-events-none focus-visible:ring-ring/50 focus-visible:ring-3",
  {
    variants: {
      variant: {
        default: "bg-secondary text-heading",
        success: "bg-success-soft text-success-ink",
        danger: "bg-danger-soft text-danger-ink",
        pending: "bg-pending-soft text-pending-ink",
        neutral: "bg-muted text-foreground",
        outline: "border border-border bg-card text-heading",
      },
      dot: {
        true: "before:size-1.5 before:rounded-full before:bg-current before:content-['']",
        false: "",
      },
    },
    defaultVariants: {
      variant: "default",
      dot: false,
    },
  },
)
export type BadgeVariants = VariantProps<typeof badgeVariants>
