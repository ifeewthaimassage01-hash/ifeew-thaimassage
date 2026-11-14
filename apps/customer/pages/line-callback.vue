<script setup lang="ts">
// กลับจากหน้าเข้าสู่ระบบ LINE (ปุ่ม "เชื่อม LINE" หน้าสถานะการจอง)
// token ของการจองเก็บใน sessionStorage ก่อนออกไป — ไม่ส่ง tracking token ไปใน URL ของ LINE
import { LoaderCircle } from '@lucide/vue'
import { toast } from 'vue-sonner'

useHead({ title: "เชื่อม LINE — Ifeew's Thaimassage", meta: [{ name: 'robots', content: 'noindex' }] })


const { sdk } = useLiff()
const { call } = useEdgeFunction()
const error = ref<string | null>(null)
const token = ref<string | null>(null)

onMounted(async () => {
  try {
    token.value = sessionStorage.getItem(LINE_LINK_KEY)
  } catch {
    token.value = null
  }
  if (!token.value) {
    error.value = 'ไม่พบการจองที่จะเชื่อม กรุณากลับไปที่หน้าสถานะการจองแล้วกดเชื่อม LINE อีกครั้ง'
    return
  }
  try {
    const liff = await sdk()
    const idToken = liff?.isLoggedIn() ? liff.getIDToken() : null
    if (!idToken) throw new Error('เข้าสู่ระบบ LINE ไม่สำเร็จ กรุณาลองอีกครั้ง')
    await call('booking-tracking', { token: token.value, action: 'line_link', id_token: idToken })
    try {
      sessionStorage.removeItem(LINE_LINK_KEY)
    } catch {}
    toast.success('เชื่อม LINE แล้ว')
    await navigateTo(`/t/${token.value}`, { replace: true })
  } catch (e) {
    error.value = (e as { data?: unknown }).data ? edgeErrorText(e, 'เชื่อม LINE ไม่สำเร็จ') : e instanceof Error ? e.message : 'เชื่อม LINE ไม่สำเร็จ'
  }
})
</script>

<template>
  <div class="mx-auto grid max-w-md gap-4 py-16 text-center">
    <template v-if="!error">
      <LoaderCircle class="mx-auto size-8 animate-spin text-primary motion-reduce:animate-none" aria-hidden="true" />
      <p class="m-0 text-lg font-medium text-heading" role="status">กำลังเชื่อม LINE กับการจองของคุณ</p>
    </template>
    <template v-else>
      <p class="m-0 text-lg font-medium text-heading">เชื่อม LINE ไม่สำเร็จ</p>
      <p class="m-0 text-[15px] text-muted-foreground">{{ error }}</p>
      <div class="flex justify-center gap-2">
        <Button v-if="token" as-child><NuxtLink :to="`/t/${token}`">กลับไปหน้าสถานะการจอง</NuxtLink></Button>
        <Button v-else as-child variant="outline"><NuxtLink to="/check-booking">ตรวจสอบการจอง</NuxtLink></Button>
      </div>
    </template>
  </div>
</template>
