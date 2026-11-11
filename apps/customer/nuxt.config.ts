import { fileURLToPath } from 'node:url'

// Customer App — Mobile first, SSR สำหรับหน้า public
// UI/design tokens มาจาก layer ร่วม packages/ui (shadcn-vue + Tailwind v4 ตาม DESIGN.md)
export default defineNuxtConfig({
  extends: ['../../packages/ui'],

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
        { name: 'theme-color', content: '#f8f3ed' },
      ],
      link: [
        { rel: 'icon', type: 'image/png', sizes: '64x64', href: '/favicon.png' },
        { rel: 'apple-touch-icon', href: '/icons/icon-192.png' },
        { rel: 'manifest', href: '/manifest.webmanifest' },
      ],
    },
  },

  modules: ['@nuxtjs/supabase', '@pinia/nuxt', '@vueuse/nuxt'],

  build: { transpile: ['@ifeew/shared'] },

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
      // รูปหน้าแรก (URL หรือ path ใน public/ เช่น /images/hero.jpg) — ว่าง = ใช้รูปบริการจากระบบแทน
      heroImage: '/images/hero-massage.png',
      // รูปหน้าร้านในส่วน "สาขาของเรา" — ว่าง = ใช้รูปบริการจากระบบแทน
      branchImage: '',
      // Cloudinary cloud name (NUXT_PUBLIC_CLOUDINARY_CLOUD_NAME) สำหรับรูปบริการ/รูปสาขา
      cloudinaryCloudName: '',
    },
  },

  typescript: { strict: true },
})
