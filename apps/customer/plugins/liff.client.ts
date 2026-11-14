// เข้าสู่ระบบด้วย LINE: คืนสถานะตอนเปิดเว็บ (ในแอป LINE · เคยเข้าสู่ระบบในเครื่องนี้ · เพิ่งกลับจากหน้า LINE)
// และให้ LIFF ที่ Endpoint เป็นหน้าแรกพาไปหน้าปลายทาง (/?liff.state=/book → /book)
// เครื่องที่ไม่เคยใช้ LINE โหลดแค่ค่าตั้งของร้าน ไม่โหลด SDK
export default defineNuxtPlugin((nuxtApp) => {
  const { restore } = useLiff()
  nuxtApp.hook('app:mounted', () => {
    restore()
  })
})
