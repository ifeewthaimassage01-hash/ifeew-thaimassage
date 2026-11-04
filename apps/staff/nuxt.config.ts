import vuetify, { transformAssetUrls } from 'vite-plugin-vuetify'
import { fileURLToPath } from 'node:url'

// Staff App — Desktop first, ใช้บนเครื่องประจำสาขา (SPA: device token เก็บใน localStorage)
export default defineNuxtConfig({
  compatibilityDate: '2026-11-01',
  ssr: false,
  devtools: { enabled: true },

  app: {
    head: {
      htmlAttrs: { lang: 'th' },
      title: "Ifeew's Thaimassage — Staff",
      meta: [{ name: 'viewport', content: 'width=device-width, initial-scale=1' }],
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
      sentryDsn: '',
      appEnv: '',
      // URL ของ Edge Functions (ปกติ = {SUPABASE_URL}/functions/v1)
      functionsUrl: '',
      // URL ของ Customer App (ใช้สร้างลิงก์ชำระมัดจำ/ติดตามการจอง)
      customerAppUrl: 'http://localhost:3000',
    },
  },

  typescript: { strict: true },
})
