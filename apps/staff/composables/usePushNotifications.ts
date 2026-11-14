/**
 * แจ้งเตือนเข้ามือถือ (Web Push) ของเครื่องนี้
 * - เปิด: ขออนุญาต → ลงทะเบียน /sw.js → pushManager.subscribe (VAPID) → public.push_subscribe
 * - ปิด: unsubscribe + public.push_unsubscribe
 * - เจ้าของร้านได้แจ้งเตือนทุกสาขา · พนักงานได้เฉพาะสาขาที่เลือกอยู่ (DB ตัดสิน)
 * iPhone/iPad: ต้อง "เพิ่มไปยังหน้าจอโฮม" แล้วเปิดจากไอคอนก่อน (iOS 16.4+) ถึงจะมี PushManager
 */
export type PushState = 'loading' | 'unsupported' | 'ios-install' | 'denied' | 'off' | 'on'

function base64UrlToBytes(b64: string): Uint8Array<ArrayBuffer> {
  const pad = '='.repeat((4 - (b64.length % 4)) % 4)
  const raw = atob((b64 + pad).replace(/-/g, '+').replace(/_/g, '/'))
  const out = new Uint8Array(new ArrayBuffer(raw.length))
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i)
  return out
}

export function usePushNotifications() {
  const supabase = useSupabaseClient()
  const config = useRuntimeConfig()
  const { company, activeBranchId } = useAccess()
  const state = useState<PushState>('push-state', () => 'loading')
  const busy = ref(false)

  const supported = () =>
    import.meta.client && 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window

  const isIos = () => import.meta.client && /iphone|ipad|ipod/i.test(navigator.userAgent)
  const isStandalone = () =>
    import.meta.client &&
    (window.matchMedia('(display-mode: standalone)').matches || (navigator as { standalone?: boolean }).standalone === true)

  async function registration() {
    return (await navigator.serviceWorker.getRegistration('/')) ?? (await navigator.serviceWorker.register('/sw.js'))
  }

  async function save(sub: PushSubscription) {
    if (!company.value) throw new Error('ยังโหลดข้อมูลร้านไม่เสร็จ')
    const json = sub.toJSON()
    const { error } = await supabase.rpc('push_subscribe', {
      p_company_id: company.value.company_id,
      p_branch_id: activeBranchId.value ?? null,
      p_endpoint: sub.endpoint,
      p_p256dh: json.keys?.p256dh ?? '',
      p_auth: json.keys?.auth ?? '',
    })
    if (error) throw error
  }

  /** อ่านสถานะของเครื่องนี้ (และอัปเดตสาขา/ผู้ใช้ให้ตรงกับที่ login อยู่) */
  async function sync() {
    if (!supported()) {
      state.value = isIos() && !isStandalone() ? 'ios-install' : 'unsupported'
      return
    }
    if (Notification.permission === 'denied') {
      state.value = 'denied'
      return
    }
    const reg = await navigator.serviceWorker.getRegistration('/')
    const sub = await reg?.pushManager.getSubscription()
    state.value = sub && Notification.permission === 'granted' ? 'on' : 'off'
    if (sub && state.value === 'on' && company.value) await save(sub).catch(() => {})
  }

  async function enable() {
    busy.value = true
    try {
      const perm = await Notification.requestPermission()
      if (perm !== 'granted') {
        state.value = perm === 'denied' ? 'denied' : 'off'
        return false
      }
      const reg = await registration()
      await navigator.serviceWorker.ready
      const sub =
        (await reg.pushManager.getSubscription()) ??
        (await reg.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: base64UrlToBytes(config.public.vapidPublicKey as string),
        }))
      await save(sub)
      state.value = 'on'
      return true
    } finally {
      busy.value = false
    }
  }

  async function disable() {
    busy.value = true
    try {
      const reg = await navigator.serviceWorker.getRegistration('/')
      const sub = await reg?.pushManager.getSubscription()
      if (sub) {
        await supabase.rpc('push_unsubscribe', { p_endpoint: sub.endpoint })
        await sub.unsubscribe()
      }
      state.value = 'off'
    } finally {
      busy.value = false
    }
  }

  return { state, busy, sync, enable, disable }
}
