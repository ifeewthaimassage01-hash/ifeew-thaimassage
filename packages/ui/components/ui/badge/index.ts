import type { VariantProps } from "class-variance-authority"
import { cva } from "class-variance-authority"

export { default as Badge } from "./Badge.vue"

// สถานะ: พื้นสีอ่อน + ตัวหนังสือสีเข้มเฉดเดียวกัน (pastel-consumer) ไม่ใช้พื้นทึบตัวขาว
export const badgeVariants = cva(
  "inline-flex flex-none items-center justify-center rounded-full px-2.5 py-0.5 text-[13px] font-medium leading-5 w-fit whitespace-nowrap shrink-0 [&>svg]:size-3 gap-1 [&>svg]:pointer-events-none focus-visible:ring-ring/50 focus-visible:ring-3 overflow-hidden",
  {
    variants: {
      variant: {
        default: "bg-tint-beige text-tint-beige-ink",
        positive: "bg-tint-green text-tint-green-ink",
        warning: "bg-tint-warn text-tint-warn-ink",
        destructive: "bg-tint-danger text-tint-danger-ink",
        pink: "bg-tint-pink text-tint-pink-ink",
        neutral: "bg-muted text-muted-foreground",
        outline: "border border-input text-foreground",
      },
    },
    defaultVariants: {
      variant: "default",
    },
  },
)
export type BadgeVariants = VariantProps<typeof badgeVariants>
