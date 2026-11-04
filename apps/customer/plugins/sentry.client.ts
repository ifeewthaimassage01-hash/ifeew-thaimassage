import * as Sentry from '@sentry/vue'

/**
 * ติดตาม error (สเปกข้อ 22) — ทำงานเฉพาะเมื่อตั้ง NUXT_PUBLIC_SENTRY_DSN
 * ไม่ส่งข้อมูลส่วนตัว: ตัดข้อมูลผู้ใช้/คำขอ, ลบ token/อีเมล/เบอร์โทรออกจากข้อความ
 */
const SCRUB = [
  /(trk|dvc)_[0-9a-f]{64}/gi,
  /eyJ[\w-]+\.[\w-]+\.[\w-]+/g,
  /[^\s@]+@[^\s@]+\.[^\s@]+/g,
  /0[0-9]{8,9}/g,
]
const scrub = (s: string) => SCRUB.reduce((t, re) => t.replace(re, '[ซ่อน]'), s)

export default defineNuxtPlugin((nuxtApp) => {
  const config = useRuntimeConfig()
  const dsn = config.public.sentryDsn as string
  if (!dsn) return

  Sentry.init({
    app: nuxtApp.vueApp,
    dsn,
    environment: (config.public.appEnv as string) || 'production',
    tracesSampleRate: 0,
    beforeSend(event) {
      delete event.user
      delete event.request
      if (event.message) event.message = scrub(event.message)
      for (const ex of event.exception?.values ?? []) {
        if (ex.value) ex.value = scrub(ex.value)
      }
      return event
    },
    beforeBreadcrumb(crumb) {
      if (crumb.message) crumb.message = scrub(crumb.message)
      if (crumb.data?.url) crumb.data.url = scrub(String(crumb.data.url).split('#')[0]!.split('?')[0]!)
      return crumb
    },
  })
})
