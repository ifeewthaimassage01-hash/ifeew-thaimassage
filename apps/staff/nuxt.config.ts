import { fileURLToPath } from 'node:url'

// Staff App — Desktop first, ใช้บนเครื่องประจำสาขา (SPA: device token เก็บใน localStorage)
// UI/design tokens มาจาก layer ร่วม packages/ui (shadcn-vue + Tailwind v4 ตาม DESIGN.md)
export default defineNuxtConfig({
  extends: ['../../packages/ui'],

  compatibilityDate: '2026-11-01',
  ssr: false,
  devtools: { enabled: true },

  app: {
    head: {
      htmlAttrs: { lang: 'th' },
      title: "Ifeew's Thaimassage — Staff",
      meta: [{ name: 'viewport', content: 'width=device-width, initial-scale=1, viewport-fit=cover' }],
      link: [
        { rel: 'icon', type: 'image/png', sizes: '64x64', href: '/favicon.png' },
        { rel: 'apple-touch-icon', href: '/favicon.png' },
      ],
    },
  },

  modules: [
    '@nuxtjs/supabase',
    '@pinia/nuxt',
    '@vueuse/nuxt',
  ],

  build: { transpile: ['@ifeew/shared'] },

  supabase: {
    types: fileURLToPath(new URL('../../packages/shared/src/database.types.ts', import.meta.url)),
    useSsrCookies: false,
    redirect: true,
    redirectOptions: {
      login: '/login',
      callback: '/login',
      exclude: ['/set-password'],
      saveRedirectToCookie: false,
    },
  },

  runtimeConfig: {
    public: {
      // ติดตาม error (ว่าง = ปิด) และชื่อสภาพแวดล้อม (staging/production)
      // รหัสบริษัท (companies.code) ใช้ตอนเจ้าของร้าน login ด้วย PIN
      companyCode: 'IFEEW',
      sentryDsn: '',
      appEnv: '',
      // URL ของ Edge Functions (ปกติ = {SUPABASE_URL}/functions/v1)
      functionsUrl: '',
      // URL ของ Customer App (ใช้สร้างลิงก์ชำระมัดจำ/ติดตามการจอง)
      customerAppUrl: 'http://localhost:3000',
      // Cloudinary cloud name (NUXT_PUBLIC_CLOUDINARY_CLOUD_NAME) สำหรับรูปบริการ/รูปสาขา
      cloudinaryCloudName: '',
    },
  },

  typescript: { strict: true },
})
