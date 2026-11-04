import tailwindcss from '@tailwindcss/vite'
import { fileURLToPath } from 'node:url'

// Customer App — Mobile first, SSR สำหรับหน้า public
// UI: shadcn-vue (reka-ui) + Tailwind v4 — คอมโพเนนต์อยู่ใน components/ui
export default defineNuxtConfig({
  compatibilityDate: '2026-11-01',
  ssr: true,
  devtools: { enabled: true },

  app: {
    head: {
      htmlAttrs: { lang: 'th' },
      title: "Ifeew's Thaimassage",
      meta: [
        { name: 'viewport', content: 'width=device-width, initial-scale=1' },
        { name: 'description', content: 'จองบริการนวดไทย Ifeew\'s Thaimassage ทุกสาขา' },
      ],
      link: [
        { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
        { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' },
        { rel: 'stylesheet', href: 'https://fonts.googleapis.com/css2?family=Noto+Sans+Thai:wght@400;500;600;700&display=swap' },
      ],
    },
  },

  css: ['~/assets/css/main.css'],

  modules: ['@nuxtjs/supabase', '@pinia/nuxt', '@vueuse/nuxt', 'shadcn-nuxt'],

  // คอมโพเนนต์ของแอปลงทะเบียนอัตโนมัติ ยกเว้น components/ui ที่ shadcn-nuxt ลงทะเบียนเอง (ไม่มี prefix)
  components: [{ path: '~/components', ignore: ['ui/**'] }],

  shadcn: { prefix: '', componentDir: './components/ui' },

  build: { transpile: ['@ifeew/shared'] },

  vite: { plugins: [tailwindcss()] },

  supabase: {
    types: fileURLToPath(new URL('../../packages/shared/src/database.types.ts', import.meta.url)),
    // หน้าส่วนใหญ่เป็น public — ป้องกันเฉพาะหน้าที่ต้อง login ด้วย middleware "auth"
    redirect: false,
  },

  runtimeConfig: {
    public: {
      // ติดตาม error (ว่าง = ปิด) และชื่อสภาพแวดล้อม (staging/production)
      sentryDsn: '',
      appEnv: '',
      // รหัสบริษัทที่แอปลูกค้านี้ให้บริการ (NUXT_PUBLIC_COMPANY_CODE)
      companyCode: 'IFEEW',
      // URL ของ Edge Functions (ว่าง = {SUPABASE_URL}/functions/v1)
      functionsUrl: '',
      // Cloudflare Turnstile site key (ค่าเริ่มต้นคือ test key ของ Cloudflare ที่ผ่านเสมอ)
      turnstileSiteKey: '1x00000000000000000000AA',
    },
  },

  typescript: { strict: true },
})
