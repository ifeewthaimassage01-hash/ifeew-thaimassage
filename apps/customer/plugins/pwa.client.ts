// ลงทะเบียน Service Worker (/sw.js) เพื่อให้ Chrome ติดตั้งเป็นแอปได้ — เฉพาะตอน build จริง
// (ตอน dev ไม่ลงทะเบียน กันแคชค้างระหว่างพัฒนา)
export default defineNuxtPlugin(() => {
  if (import.meta.dev || !('serviceWorker' in navigator)) return
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch((e) => console.warn('service worker', e))
  })
})
