// Service Worker — ทำให้ติดตั้งเป็นแอปได้ (Chrome "ติดตั้งแอป") + หน้าออฟไลน์ + แจ้งเตือน (Web Push)
// ไม่แคชหน้า/ข้อมูลของแอป (ข้อมูลต้องสดจาก Supabase เสมอ) — แคชแค่หน้าออฟไลน์และไอคอน
// เปลี่ยน VERSION เมื่อแก้ไฟล์นี้ เพื่อล้างแคชเก่า
const VERSION = 'ifeew-v2'
const OFFLINE_URL = '/offline.html'

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(VERSION).then((cache) => cache.addAll([OFFLINE_URL, '/icons/icon-192.png'])).then(() => self.skipWaiting()),
  )
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  )
})

// เปิดหน้าใหม่ (navigation) ไม่ได้เพราะไม่มีเน็ต → แสดงหน้าออฟไลน์ · คำขออื่นปล่อยผ่านตามปกติ
self.addEventListener('fetch', (event) => {
  if (event.request.mode !== 'navigate') return
  event.respondWith(fetch(event.request).catch(() => caches.match(OFFLINE_URL)))
})

// แจ้งเตือนจากร้าน (Edge Function push-dispatch): { title, body, url, tag }
self.addEventListener('push', (event) => {
  let d = {}
  try {
    d = event.data ? event.data.json() : {}
  } catch {
    d = { body: event.data ? event.data.text() : '' }
  }
  event.waitUntil(
    self.registration.showNotification(d.title || "Ifeew's Thaimassage", {
      body: d.body || '',
      icon: '/icons/icon-192.png',
      tag: d.tag,
      data: { url: d.url || '/' },
    }),
  )
})

// กดแจ้งเตือน → เปิดหน้าที่เกี่ยวข้อง (ใช้หน้าต่างแอปที่เปิดอยู่ถ้ามี)
self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const url = new URL((event.notification.data && event.notification.data.url) || '/', self.location.origin).href
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      const win = list.find((c) => c.url.startsWith(self.location.origin))
      if (win) return win.focus().then((c) => (c && 'navigate' in c ? c.navigate(url) : undefined))
      return self.clients.openWindow(url)
    }),
  )
})
