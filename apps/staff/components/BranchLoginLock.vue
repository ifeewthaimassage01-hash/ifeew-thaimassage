<script setup lang="ts">
// OWNER: ล็อกการเข้าระบบพนักงานตามพื้นที่ร้าน (ต่อสาขา) ด้วย GPS — ตรวจจริงใน Edge Function staff-pin-login
// เจ้าของร้านและเครื่องที่ผูกกับสาขาไม่ถูกล็อก
import { LocateFixed } from '@lucide/vue'

/** plain = ไม่มีกรอบ SectionCard (ใช้ใน popup ซึ่งมีหัวข้ออยู่แล้ว) */
const props = defineProps<{ branchId: string; companyId: string; plain?: boolean }>()
const emit = defineEmits<{ saved: [] }>()
const SectionCard = resolveComponent('SectionCard')

const supabase = useSupabaseClient()

const form = reactive({ enabled: false, lat: '' as string | number, lng: '' as string | number, radius: 150 as string | number })
const saving = ref(false)
const locating = ref(false)
const message = ref<{ type: 'success' | 'error'; text: string } | null>(null)

async function load() {
  const { data } = await supabase.from('branch_login_locks').select('*').eq('branch_id', props.branchId).maybeSingle()
  Object.assign(form, {
    enabled: data?.enabled ?? false,
    lat: data?.latitude ?? '',
    lng: data?.longitude ?? '',
    radius: data?.radius_m ?? 150,
  })
}
watch(() => props.branchId, load, { immediate: true })

const hasPoint = computed(() => form.lat !== '' && form.lng !== '')

function useCurrentLocation() {
  if (!('geolocation' in navigator)) {
    message.value = { type: 'error', text: 'เครื่องนี้ไม่รองรับการระบุตำแหน่ง' }
    return
  }
  locating.value = true
  navigator.geolocation.getCurrentPosition(
    (p) => {
      locating.value = false
      form.lat = Number(p.coords.latitude.toFixed(6))
      form.lng = Number(p.coords.longitude.toFixed(6))
      message.value = { type: 'success', text: `ได้ตำแหน่งแล้ว (คลาดเคลื่อนประมาณ ${Math.round(p.coords.accuracy)} ม.) · กดบันทึกเพื่อใช้งาน` }
    },
    () => {
      locating.value = false
      message.value = { type: 'error', text: 'อ่านตำแหน่งไม่ได้ · อนุญาตให้เบราว์เซอร์เข้าถึงตำแหน่ง แล้วลองใหม่' }
    },
    { enableHighAccuracy: true, timeout: 15_000, maximumAge: 0 },
  )
}

async function save() {
  const lat = form.lat === '' ? null : Number(form.lat)
  const lng = form.lng === '' ? null : Number(form.lng)
  if ((lat === null) !== (lng === null) || (lat !== null && (!Number.isFinite(lat) || !Number.isFinite(lng!) || Math.abs(lat) > 90 || Math.abs(lng!) > 180))) {
    message.value = { type: 'error', text: 'กรอกละติจูดและลองจิจูดให้ถูกต้อง หรือเว้นว่างทั้งสองช่อง' }
    return
  }
  if (form.enabled && lat === null) {
    message.value = { type: 'error', text: 'เปิดล็อกแล้วต้องตั้งตำแหน่งร้านก่อน' }
    return
  }
  saving.value = true
  try {
    await must(supabase.from('branch_login_locks').upsert({
      branch_id: props.branchId,
      company_id: props.companyId,
      enabled: form.enabled,
      latitude: lat,
      longitude: lng,
      radius_m: Math.min(2000, Math.max(30, Math.round(Number(form.radius) || 150))),
    }))
    message.value = { type: 'success', text: form.enabled ? 'บันทึกแล้ว · พนักงานเข้าระบบได้เฉพาะในร้าน' : 'บันทึกแล้ว · ยังไม่ได้เปิดล็อก' }
    await load()
    emit('saved')
  } catch (e) {
    message.value = { type: 'error', text: errorText(e, 'บันทึกไม่สำเร็จ') }
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <component
    :is="plain ? 'div' : SectionCard"
    v-bind="plain ? {} : { title: 'เข้าระบบได้เฉพาะในร้าน', description: 'พนักงานต้องอยู่ในรัศมีจากร้าน (ตรวจด้วย GPS ของเครื่อง) · เจ้าของร้านและเครื่องที่ผูกกับสาขาเข้าได้ทุกที่' }"
  >
    <form class="@container grid gap-5" @submit.prevent="save">
      <MessageAlert :message="message" @close="message = null" />
      <SwitchField v-model="form.enabled" label="เปิดล็อกพื้นที่" hint="มีผลตอนเข้าระบบครั้งถัดไป · คนที่เข้าอยู่แล้วใช้งานต่อได้จนออกจากระบบ (ตี 3)" />

      <div class="grid gap-2">
        <div class="grid gap-3 @lg:grid-cols-3">
          <TextField v-model="form.lat" label="ละติจูดร้าน" inputmode="decimal" placeholder="14.882900" />
          <TextField v-model="form.lng" label="ลองจิจูดร้าน" inputmode="decimal" placeholder="103.493700" />
          <TextField v-model="form.radius" label="รัศมี" inputmode="numeric" suffix="เมตร" hint="30–2000 ม." />
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <Button type="button" variant="outline" size="sm" :disabled="locating" @click="useCurrentLocation"><LocateFixed /> {{ locating ? 'กำลังหาตำแหน่ง…' : 'ใช้ตำแหน่งปัจจุบัน (ยืนอยู่ที่ร้าน)' }}</Button>
          <a v-if="hasPoint" :href="`https://www.google.com/maps?q=${form.lat},${form.lng}`" target="_blank" rel="noopener" class="text-sm text-primary underline">ดูบน Google Maps</a>
        </div>
        <p class="m-0 text-sm text-muted-foreground">พนักงานต้องอนุญาตให้เบราว์เซอร์เข้าถึงตำแหน่งตอนเข้าระบบ · GPS ในอาคารอาจคลาดเคลื่อน แนะนำรัศมี 150 ม. ขึ้นไป</p>
      </div>

      <div class="flex justify-end">
        <Button type="submit" :disabled="saving">{{ saving ? 'กำลังบันทึก…' : 'บันทึก' }}</Button>
      </div>
    </form>
  </component>
</template>
