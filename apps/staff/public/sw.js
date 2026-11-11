// Service Worker — ทำให้ติดตั้งเป็นแอปได้ (Chrome "ติดตั้งแอป") + หน้าออฟไลน์
// ไม่แคชหน้า/ข้อมูลของแอป (ข้อมูลต้องสดจาก Supabase เสมอ) — แคชแค่หน้าออฟไลน์และไอคอน
// เปลี่ยน VERSION เมื่อแก้ไฟล์นี้ เพื่อล้างแคชเก่า
const VERSION = 'ifeew-v1'
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
