import tailwindcss from '@tailwindcss/vite'
import { fileURLToPath } from 'node:url'

/**
 * @ifeew/ui — Nuxt layer ที่ Customer App และ Staff App ใช้ร่วมกัน (DESIGN.md §9: design token เดียว ไม่ซ้ำ styling)
 *   - assets/css/main.css: Tailwind v4 + design tokens ตาม DESIGN.md
 *   - components/ui: shadcn-vue (reka-ui) ที่ปรับตาม token แล้ว — ลงทะเบียนชื่อเดิม (Button, Card, ...)
 *   - components: BrandMark, PageHeader, StatCard, EmptyState
 * เพิ่มคอมโพเนนต์ shadcn-vue ใหม่: รัน CLI ในแอปใดแอปหนึ่ง (ใช้ components.json ในโฟลเดอร์นี้) แล้วย้ายมาไว้ที่ components/ui
 */
const here = (p: string) => fileURLToPath(new URL(p, import.meta.url))

export default defineNuxtConfig({
  css: ['vue-sonner/style.css', here('./assets/css/main.css')],

  components: [
    { path: here('./components/ui'), pathPrefix: false, extensions: ['vue'] },
    { path: here('./components'), ignore: ['ui/**'] },
  ],

  app: {
    head: {
      link: [
        { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
        { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' },
        { rel: 'stylesheet', href: 'https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@600;700&family=DM+Sans:opsz,wght@9..40,400;9..40,500;9..40,600&family=Noto+Serif+Thai:wght@500;600&family=Noto+Sans+Thai:wght@400;500;600;700&display=swap' },
      ],
    },
  },

  vite: { plugins: [tailwindcss()] },
})
