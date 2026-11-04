import vuetify, { transformAssetUrls } from 'vite-plugin-vuetify'
import { fileURLToPath } from 'node:url'

// Customer App — Mobile first, SSR สำหรับหน้า public
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
        { rel: 'stylesheet', href: 'https://fonts.googleapis.com/css2?family=Noto+Sans+Thai:wght@400;500;600;700&display=swap' },
      ],
    },
  },

  modules: [
    '@nuxtjs/supabase',
    '@nuxtjs/tailwindcss',
    '@pinia/nuxt',
    '@vueuse/nuxt',
    (_options, nuxt) => {
      nuxt.hooks.hook('vite:extendConfig', (config) => {
        config.plugins?.push(vuetify({ autoImport: true }))
      })
    },
  ],

  build: { transpile: ['vuetify', '@ifeew/shared'] },

  vite: {
    vue: { template: { transformAssetUrls } },
  },

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
