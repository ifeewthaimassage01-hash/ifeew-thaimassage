import type { VariantProps } from "class-variance-authority"
import { cva } from "class-variance-authority"

export { default as Button } from "./Button.vue"

// ปุ่มแบน สีเดียว ไม่มีเงา รัศมี 10px สูง 44px (ใช้นิ้วกดได้) — กดแล้วยุบเล็กน้อย
export const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-lg text-[15px] font-medium transition-[background-color,color,transform] duration-150 active:scale-[0.98] disabled:pointer-events-none disabled:opacity-60 [&_svg]:pointer-events-none [&_svg:not([class*='size-'])]:size-4 shrink-0 [&_svg]:shrink-0 outline-none focus-visible:ring-ring/60 focus-visible:ring-3 aria-invalid:ring-destructive/20 aria-invalid:border-destructive no-underline",
  {
    variants: {
      variant: {
        default:
          "bg-primary text-primary-foreground hover:bg-primary/90",
        destructive:
          "bg-destructive text-white hover:bg-destructive/90 focus-visible:ring-destructive/30",
        outline:
          "border border-input bg-card text-foreground hover:bg-muted",
        secondary:
          "bg-secondary text-secondary-foreground hover:bg-secondary/75",
        ghost:
          "text-foreground hover:bg-muted",
        link: "text-link underline-offset-4 hover:underline",
      },
      size: {
        "default": "h-11 px-5 has-[>svg]:px-4",
        "xs": "h-7 gap-1 rounded-md px-2 text-sm has-[>svg]:px-1.5 [&_svg:not([class*='size-'])]:size-3",
        "sm": "h-9 gap-1.5 px-3 text-sm has-[>svg]:px-2.5",
        "lg": "h-12 px-6 text-base has-[>svg]:px-5",
        "icon": "size-11",
        "icon-xs": "size-7 rounded-md [&_svg:not([class*='size-'])]:size-3",
        "icon-sm": "size-9",
        "icon-lg": "size-12",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  },
)
export type ButtonVariants = VariantProps<typeof buttonVariants>
