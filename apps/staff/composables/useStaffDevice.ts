import { staffLoginErrors } from '@ifeew/shared'

export interface DeviceInfo {
  device_id: string
  device_name: string
  company_id: string
  branch_id: string
  branch_name: string
  idle_lock_minutes: number
}

export interface DeviceStaff {
  user_id: string
  display_name: string
  photo_url: string | null
  locked: boolean
  is_owner?: boolean
}

export interface LoginBranch {
  branch_id: string
  name: string
}

export interface BranchStaffList {
  branches: LoginBranch[]
  branch?: { company_id: string; branch_id: string; branch_name: string; idle_lock_minutes: number }
  staff?: DeviceStaff[]
}

interface PinLoginResponse {
  session: { access_token: string; refresh_token: string; expires_at: number }
  user_id: string
  company_id: string
  branch_id: string
  idle_lock_minutes: number
}

const TOKEN_KEY = 'ifeew.device_token'

/**
 * เครื่องประจำสาขา: เก็บ device token (ได้จากการผูกเครื่องโดย OWNER) ใน localStorage
 * และเรียก Edge Functions device-staff-list / staff-pin-login
 */
export function useStaffDevice() {
  const config = useRuntimeConfig()
  const supabase = useSupabaseClient()
  const token = useLocalStorage<string | null>(TOKEN_KEY, null)

  const baseUrl = computed(
    () => config.public.functionsUrl || `${config.public.supabase.url}/functions/v1`,
  )

  async function call<T>(name: string, body: Record<string, unknown>): Promise<T> {
    return await $fetch<T>(`${baseUrl.value}/${name}`, {
      method: 'POST',
      body,
      headers: { apikey: config.public.supabase.key },
    })
  }

  function errorMessage(e: unknown): { code: string; message: string; attemptsLeft?: number | null } {
    const data = (e as { data?: { error_code?: string; attempts_left?: number | null } } | null)?.data
    const code = data?.error_code ?? 'INTERNAL_ERROR'
    return {
      code,
      message: staffLoginErrors[code] ?? staffLoginErrors.INTERNAL_ERROR!,
      attemptsLeft: data?.attempts_left ?? null,
    }
  }

  async function listStaff(): Promise<{ device: DeviceInfo; staff: DeviceStaff[] }> {
    if (!token.value) throw new Error('DEVICE_NOT_PAIRED')
    return await call('device-staff-list', { device_token: token.value })
  }

  async function pinLogin(userId: string, pin: string): Promise<PinLoginResponse> {
    if (!token.value) throw new Error('DEVICE_NOT_PAIRED')
    const res = await call<PinLoginResponse>('staff-pin-login', {
      device_token: token.value,
      user_id: userId,
      pin,
    })
    const { error } = await supabase.auth.setSession({
      access_token: res.session.access_token,
      refresh_token: res.session.refresh_token,
    })
    if (error) throw error
    return res
  }

  /** หน้า login: รายชื่อสาขา (+ พนักงานของสาขาที่เลือก) โดยไม่ต้องใช้เครื่องที่ผูก */
  async function listBranchStaff(branchId?: string | null): Promise<BranchStaffList> {
    return await call('branch-staff-list', { company_code: config.public.companyCode, branch_id: branchId ?? undefined })
  }

  /** พนักงาน: PIN ของสาขาที่เลือกจาก dropdown */
  async function branchPinLogin(branchId: string, userId: string, pin: string): Promise<PinLoginResponse> {
    const res = await call<PinLoginResponse>('staff-pin-login', {
      company_code: config.public.companyCode,
      branch_id: branchId,
      user_id: userId,
      pin,
    })
    const { error } = await supabase.auth.setSession({
      access_token: res.session.access_token,
      refresh_token: res.session.refresh_token,
    })
    if (error) throw error
    return res
  }

  /** เจ้าของร้าน: PIN อย่างเดียว (ไม่ต้องใช้เครื่องที่ผูก) */
  async function ownerPinLogin(pin: string): Promise<PinLoginResponse> {
    const res = await call<PinLoginResponse>('owner-pin-login', {
      company_code: config.public.companyCode,
      pin,
    })
    const { error } = await supabase.auth.setSession({
      access_token: res.session.access_token,
      refresh_token: res.session.refresh_token,
    })
    if (error) throw error
    return res
  }

  function savePairing(deviceToken: string) {
    token.value = deviceToken
  }

  function forget() {
    token.value = null
  }

  return { token, listStaff, pinLogin, listBranchStaff, branchPinLogin, ownerPinLogin, savePairing, forget, errorMessage }
}
