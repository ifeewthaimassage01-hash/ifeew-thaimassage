/**
 * เข้าสู่ระบบด้วย LINE (LIFF) — ไม่ใช่ระบบสมาชิก ใช้เพื่อส่งยืนยันการจอง/เตือนนัดเข้า LINE ของลูกค้า
 * - ค่า LIFF ID / ลิงก์เพิ่มเพื่อน ตั้งในแอปพนักงาน /settings/line → public.line_public_config
 * - Endpoint URL ของ LIFF = หน้าแรกของเว็บ (Rich Menu ใช้ https://liff.line.me/<LIFF ID>/book)
 * - โหลด SDK ทางการจาก CDN ของ LINE เฉพาะเมื่อ: เปิดในแอป LINE · เคยเข้าสู่ระบบในเครื่องนี้ · กดเข้าสู่ระบบ
 * - ID token ส่งไปกับการจอง → server ยืนยันกับ LINE แล้วผูกการจองกับ LINE ของลูกค้า
 */
interface LiffSdk {
  init(o: { liffId: string }): Promise<void>
  isLoggedIn(): boolean
  isInClient(): boolean
  login(o?: { redirectUri?: string }): void
  logout(): void
  getIDToken(): string | null
  getDecodedIDToken(): { name?: string; picture?: string; exp?: number } | null
  getFriendship(): Promise<{ friendFlag: boolean }>
}

interface LinePublicConfig {
  liff_id: string | null
  add_friend_url: string | null
}

export interface LineUser {
  name: string
  picture: string | null
}

/** token การจองที่กำลังเชื่อม LINE (เก็บก่อนไปหน้าเข้าสู่ระบบ LINE) */
export const LINE_LINK_KEY = 'ifeew.line-link-token'
/** เครื่องนี้เคยเข้าสู่ระบบด้วย LINE → โหลด SDK ตอนเปิดเว็บเพื่อคืนสถานะ */
const REMEMBER_KEY = 'ifeew.line-login'

const SDK_URL = 'https://static.line-scdn.net/liff/edge/2/sdk.js'
let configP: Promise<LinePublicConfig | null> | null = null
let sdkP: Promise<LiffSdk | null> | null = null
/** เหตุผลที่เริ่ม LIFF ไม่สำเร็จครั้งล่าสุด (แสดงให้ผู้ใช้/ร้านรู้ว่าติดตรงไหน) */
let lastInitError = ''

function describeInitError(e: unknown): string {
  const err = e as { code?: string; message?: string } | null
  const where = typeof location !== 'undefined' ? location.origin : ''
  if (where.includes('localhost') || where.includes('127.0.0.1')) return `ทดสอบบน ${where} ไม่ได้ ต้องเปิดจากโดเมนที่ตั้งเป็น Endpoint URL ของ LIFF`
  return [err?.code, err?.message].filter(Boolean).join(': ') || 'ไม่ทราบสาเหตุ'
}

function loadSdk(): Promise<LiffSdk | null> {
  const w = window as unknown as { liff?: LiffSdk }
  if (w.liff) return Promise.resolve(w.liff)
  return new Promise((resolve) => {
    const s = document.createElement('script')
    s.src = SDK_URL
    s.async = true
    s.onload = () => resolve(w.liff ?? null)
    s.onerror = () => resolve(null)
    document.head.appendChild(s)
  })
}

function remember(on: boolean) {
  try {
    if (on) localStorage.setItem(REMEMBER_KEY, '1')
    else localStorage.removeItem(REMEMBER_KEY)
  } catch {}
}
function remembered(): boolean {
  try {
    return localStorage.getItem(REMEMBER_KEY) === '1'
  } catch {
    return false
  }
}

export function useLiff() {
  const supabase = useSupabaseClient()
  const { code: companyCode } = useCompany()
  /** ร้านเปิดใช้ LINE แล้ว (มี LIFF ID) — null = ยังไม่รู้ */
  const available = useState<boolean | null>('liff-available', () => null)
  const addFriendUrl = useState<string | null>('liff-add-friend', () => null)
  /** ผู้ใช้ที่เข้าสู่ระบบด้วย LINE อยู่ (null = ยังไม่ได้เข้าสู่ระบบ) */
  const user = useState<LineUser | null>('liff-user', () => null)
  /** กำลังคืนสถานะการเข้าสู่ระบบตอนเปิดเว็บ */
  const restoring = useState('liff-restoring', () => false)
  /** null = ไม่รู้ · false = ยังไม่ได้เพิ่มเพื่อน OA (จะไม่ได้รับข้อความ) */
  const isFriend = useState<boolean | null>('liff-friend', () => null)
  const connected = computed(() => !!user.value)

  const inLineApp = () => import.meta.client && /\bLine\//i.test(navigator.userAgent)

  function config(): Promise<LinePublicConfig | null> {
    configP ??= (async () => {
      try {
        const { data } = await supabase.rpc('line_public_config', { p_company_code: companyCode })
        const cfg = (data as LinePublicConfig | null) ?? null
        available.value = !!cfg?.liff_id
        addFriendUrl.value = cfg?.add_friend_url ?? null
        return cfg
      } catch {
        available.value = false
        return null
      }
    })()
    return configP
  }

  /** โหลด SDK + liff.init (ใช้ได้ทั้งในแอป LINE และเบราว์เซอร์ทั่วไป) */
  function sdk(): Promise<LiffSdk | null> {
    if (!import.meta.client) return Promise.resolve(null)
    sdkP ??= (async () => {
      try {
        const cfg = await config()
        if (!cfg?.liff_id) return null
        const liff = await loadSdk()
        if (!liff) {
          lastInitError = 'โหลด LINE SDK ไม่สำเร็จ (เครือข่ายหรือตัวบล็อกโฆษณา)'
          sdkP = null // ให้ลองใหม่ได้ตอนกดอีกครั้ง
          return null
        }
        await liff.init({ liffId: cfg.liff_id })
        lastInitError = ''
        return liff
      } catch (e) {
        console.warn('LIFF init failed', e)
        lastInitError = describeInitError(e)
        sdkP = null // ให้ลองใหม่ได้ตอนกดอีกครั้ง
        return null
      }
    })()
    return sdkP
  }

  /** ID token ที่ยังไม่หมดอายุ (เหลืออย่างน้อย 2 นาที) */
  function freshToken(liff: LiffSdk): string | null {
    if (!liff.isLoggedIn()) return null
    const token = liff.getIDToken()
    const exp = liff.getDecodedIDToken()?.exp ?? 0
    return token && exp * 1000 > Date.now() + 120_000 ? token : null
  }

  async function refreshState(liff: LiffSdk) {
    if (!freshToken(liff)) {
      // หมดอายุ: ในแอป LINE เข้าใหม่อัตโนมัติไม่ได้กลางหน้า → ถือว่ายังไม่ได้เข้าสู่ระบบ ให้กดใหม่
      if (liff.isLoggedIn() && !liff.isInClient()) liff.logout()
      user.value = null
      return
    }
    const d = liff.getDecodedIDToken()
    user.value = { name: d?.name ?? 'ผู้ใช้ LINE', picture: d?.picture ?? null }
    remember(true)
    isFriend.value = await liff.getFriendship().then((f) => f.friendFlag).catch(() => null)
  }

  /** ตอนเปิดเว็บ: คืนสถานะถ้าอยู่ในแอป LINE / เคยเข้าสู่ระบบ / เพิ่งกลับจากหน้า LINE */
  async function restore() {
    if (!import.meta.client) return
    const params = new URLSearchParams(location.search)
    const shouldLoad = inLineApp() || remembered() || params.has('liff.state') || params.has('liffClientId')
    if (!shouldLoad) {
      config() // แค่รู้ว่าร้านเปิดใช้ LINE ไหม (แสดงปุ่มเข้าสู่ระบบ)
      return
    }
    restoring.value = true
    try {
      const liff = await sdk()
      if (liff) await refreshState(liff)
    } finally {
      restoring.value = false
    }
  }

  /** ไปหน้าเข้าสู่ระบบ LINE แล้วกลับมาที่ redirectPath (ค่าเริ่มต้น = หน้าปัจจุบัน) */
  async function login(redirectPath?: string) {
    const liff = await sdk()
    if (!liff) throw new Error(`เข้าสู่ระบบด้วย LINE ไม่สำเร็จ${lastInitError ? ` (${lastInitError})` : ''}`)
    if (freshToken(liff)) {
      await refreshState(liff)
      return
    }
    remember(true)
    const path = redirectPath ?? `${location.pathname}${location.search}`
    liff.login({ redirectUri: `${location.origin}${path}` })
  }

  async function logout() {
    const liff = sdkP ? await sdkP : null
    if (liff?.isLoggedIn()) liff.logout()
    user.value = null
    isFriend.value = null
    remember(false)
  }

  /** ID token สำหรับส่งไปกับคำขอ (null = ยังไม่ได้เข้าสู่ระบบ หรือหมดอายุ) */
  async function idToken(): Promise<string | null> {
    const liff = sdkP ? await sdkP : null
    if (!liff) return null
    const token = freshToken(liff)
    if (!token) await refreshState(liff)
    return token
  }

  /** ปุ่ม "เชื่อม LINE" ของการจองหนึ่งรายการ: ได้ token ทันทีถ้าเข้าสู่ระบบอยู่ ไม่งั้นพาไปเข้าสู่ระบบ */
  async function loginOrToken(redirectPath: string): Promise<string | null> {
    const liff = await sdk()
    if (!liff) throw new Error(`เชื่อม LINE ไม่สำเร็จ${lastInitError ? ` (${lastInitError})` : ''}`)
    const token = freshToken(liff)
    if (token) {
      await refreshState(liff)
      return token
    }
    await login(redirectPath)
    return null
  }

  return {
    available,
    addFriendUrl,
    user,
    connected,
    restoring,
    isFriend,
    config,
    sdk,
    restore,
    login,
    logout,
    idToken,
    loginOrToken,
    inLineApp,
  }
}
