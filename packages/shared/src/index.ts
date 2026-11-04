import { z } from 'zod'

export type { Database, Json, Tables } from './database.types'
export { promptPayPayload } from './promptpay'

// -----------------------------------------------------------------------------
// สิทธิ์ (ใช้แสดงผลเท่านั้น — การบังคับจริงอยู่ที่ RLS)
// -----------------------------------------------------------------------------
export type MembershipRole = 'OWNER' | 'STAFF'

export interface AccessBranch {
  branch_id: string
  code: string
  name: string
}

export interface AccessCompany {
  company_id: string
  company_code: string
  company_name: string
  role: MembershipRole
  owner_mfa_required: boolean
  branches: AccessBranch[]
}

export interface MyAccess {
  user_id: string | null
  aal: 'aal1' | 'aal2'
  companies: AccessCompany[]
}

// -----------------------------------------------------------------------------
// Validation (ตรวจซ้ำฝั่ง DB เสมอ)
// -----------------------------------------------------------------------------
export const pinSchema = z
  .string()
  .regex(/^[0-9]{6}$/, 'PIN ต้องเป็นตัวเลข 6 หลัก')

export const emailSchema = z.string().trim().toLowerCase().email('อีเมลไม่ถูกต้อง')

export const passwordSchema = z
  .string()
  .min(10, 'รหัสผ่านอย่างน้อย 10 ตัวอักษร')
  .regex(/[a-z]/, 'ต้องมีตัวพิมพ์เล็ก')
  .regex(/[A-Z]/, 'ต้องมีตัวพิมพ์ใหญ่')
  .regex(/[0-9]/, 'ต้องมีตัวเลข')

export const phoneSchema = z
  .string()
  .trim()
  .regex(/^[0-9+\-\s]{6,20}$/, 'เบอร์โทรไม่ถูกต้อง')

export const displayNameSchema = z.string().trim().min(1, 'กรุณากรอกชื่อ').max(120)

/** เบอร์โทรไทย (รับ +66 / ขีด / ช่องว่าง) — DB normalize ซ้ำเสมอ */
export function normalizeThaiPhone(input: string): string | null {
  let v = input.replace(/[^0-9]/g, '')
  if (v.startsWith('66') && (v.length === 11 || v.length === 12)) v = `0${v.slice(2)}`
  return /^0[0-9]{8,9}$/.test(v) ? v : null
}

export const thaiPhoneSchema = z
  .string()
  .refine((v) => normalizeThaiPhone(v) !== null, 'เบอร์โทรไม่ถูกต้อง (เช่น 0812345678)')
  .transform((v) => normalizeThaiPhone(v)!)

export const personNameSchema = z.string().trim().min(1, 'กรุณากรอกชื่อ').max(100)

/** 60 -> "1 ชม", 90 -> "1.5 ชม", 45 -> "45 นาที", 75 -> "1 ชม 15 นาที" */
export function formatDuration(minutes: number): string {
  if (minutes < 60) return `${minutes} นาที`
  if (minutes % 30 === 0) return `${minutes / 60} ชม`
  return `${Math.floor(minutes / 60)} ชม ${minutes % 60} นาที`
}

export interface PricingSnapshot {
  id: string
  price: number
  therapist_fee: number
  effective_from: string
}

export interface PricingOption {
  option_id: string
  duration_minutes: number
  is_active: boolean
  current: PricingSnapshot | null
  scheduled: PricingSnapshot | null
  history: Array<PricingSnapshot & { effective_to: string | null; status: 'ACTIVE' | 'CANCELLED'; reason: string }> | null
}

export interface BranchServicePricing {
  branch_service_id: string
  service_id: string
  is_active: boolean
  options: PricingOption[]
}

export function formatBaht(value: number): string {
  return new Intl.NumberFormat('th-TH', { style: 'currency', currency: 'THB', maximumFractionDigits: 0 }).format(value)
}

export interface CurrentPolicy {
  id: string
  version: string
  title: string
  content: string
  published_at: string
}

export interface MyCustomer {
  customer_id: string
  first_name: string
  last_name: string
  phone: string
  email: string | null
  created_at: string
  consents: Partial<Record<'PRIVACY_NOTICE' | 'MARKETING', { granted: boolean; recorded_at: string; version: string }>>
  pending_deletion: boolean
}

export interface CustomerDetail {
  customer_id: string
  first_name: string
  last_name: string
  phone: string | null
  email: string | null
  staff_note: string | null
  is_member: boolean
  created_channel: 'ONLINE' | 'STAFF'
  status: 'ACTIVE' | 'MERGED' | 'ANONYMIZED'
  merged_into_id: string | null
  created_at: string
  marketing_consent: boolean | null
}

export const employeeCodeSchema = z
  .string()
  .trim()
  .regex(/^[A-Za-z0-9][A-Za-z0-9_-]{0,19}$/, 'รหัสพนักงานใช้ A-Z 0-9 - _ ไม่เกิน 20 ตัว')

export const nicknameSchema = z.string().trim().min(1, 'กรุณากรอกชื่อเล่น').max(60)

export const reasonSchema = z.string().trim().min(3, 'กรุณาระบุเหตุผลอย่างน้อย 3 ตัวอักษร').max(500)

export const employeeStatusLabels: Record<'ACTIVE' | 'INACTIVE' | 'RESIGNED', string> = {
  ACTIVE: 'ทำงาน',
  INACTIVE: 'ระงับ',
  RESIGNED: 'ลาออก',
}

export const scheduleStatusLabels: Record<'SCHEDULED' | 'LEAVE' | 'CANCELLED', string> = {
  SCHEDULED: 'เข้างาน',
  LEAVE: 'ลา',
  CANCELLED: 'ยกเลิก',
}

export const isoDowLabels = ['', 'จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์', 'อาทิตย์'] as const

// -----------------------------------------------------------------------------
// วันเวลา Asia/Bangkok (UTC+7 ไม่มี DST) — ใช้กับ input วันที่/เวลาในหน้าจอ
// -----------------------------------------------------------------------------
export const BANGKOK_OFFSET = '+07:00'

/** 'YYYY-MM-DD' + 'HH:mm' (เวลาไทย) -> ISO timestamptz */
export function bangkokIso(date: string, time: string): string {
  return `${date}T${time}:00${BANGKOK_OFFSET}`
}

/** บวกวันให้ 'YYYY-MM-DD' */
export function addDays(date: string, days: number): string {
  const d = new Date(`${date}T00:00:00Z`)
  d.setUTCDate(d.getUTCDate() + days)
  return d.toISOString().slice(0, 10)
}

/** วันที่ปัจจุบันตามเวลาไทย 'YYYY-MM-DD' */
export function bangkokToday(now: Date = new Date()): string {
  return new Date(now.getTime() + 7 * 3600_000).toISOString().slice(0, 10)
}

/** วันจันทร์ของสัปดาห์ที่มี date */
export function mondayOf(date: string): string {
  const dow = new Date(`${date}T00:00:00Z`).getUTCDay() // 0=อาทิตย์
  return addDays(date, dow === 0 ? -6 : 1 - dow)
}

/** timestamptz -> { date: 'YYYY-MM-DD', time: 'HH:mm' } ตามเวลาไทย */
export function toBangkokParts(iso: string): { date: string; time: string } {
  const s = new Date(new Date(iso).getTime() + 7 * 3600_000).toISOString()
  return { date: s.slice(0, 10), time: s.slice(11, 16) }
}

/** ช่วงกะจากวันที่ + เวลาเริ่ม/จบ (จบ <= เริ่ม = ข้ามเที่ยงคืน) */
export function shiftRange(date: string, start: string, end: string): { starts_at: string; ends_at: string } {
  return {
    starts_at: bangkokIso(date, start),
    ends_at: bangkokIso(end <= start ? addDays(date, 1) : date, end),
  }
}

// -----------------------------------------------------------------------------
// Error code จาก Edge Function → ข้อความภาษาไทย
// -----------------------------------------------------------------------------
export const staffLoginErrors: Record<string, string> = {
  DEVICE_INVALID: 'เครื่องนี้ยังไม่ได้ผูกกับสาขา หรือถูกยกเลิกแล้ว',
  INVALID_CREDENTIALS: 'PIN ไม่ถูกต้อง',
  PIN_LOCKED: 'PIN ถูกล็อกชั่วคราว กรุณารอแล้วลองใหม่ หรือติดต่อเจ้าของร้าน',
  RATE_LIMITED: 'ลองหลายครั้งเกินไป กรุณารอสักครู่',
  INVALID_BODY: 'ข้อมูลไม่ถูกต้อง',
  INTERNAL_ERROR: 'ระบบขัดข้อง กรุณาลองใหม่',
}

// -----------------------------------------------------------------------------
// การจอง (Phase 4)
// -----------------------------------------------------------------------------
export type BookingStatus = 'PENDING' | 'CONFIRMED' | 'CHECKED_IN' | 'COMPLETED' | 'CANCELLED' | 'NO_SHOW' | 'EXPIRED'
export type DepositStatus =
  | 'NOT_REQUIRED' | 'AWAITING_PAYMENT' | 'PENDING_REVIEW' | 'PAID' | 'REFUND_PENDING' | 'REFUNDED' | 'FORFEITED'

export const bookingStatusLabels: Record<BookingStatus, string> = {
  PENDING: 'รอยืนยัน',
  CONFIRMED: 'ยืนยันแล้ว',
  CHECKED_IN: 'เช็กอินแล้ว',
  COMPLETED: 'เสร็จสิ้น',
  CANCELLED: 'ยกเลิก',
  NO_SHOW: 'ไม่มาตามนัด',
  EXPIRED: 'หมดเวลา',
}

export const depositStatusLabels: Record<DepositStatus, string> = {
  NOT_REQUIRED: 'ไม่มีมัดจำ',
  AWAITING_PAYMENT: 'รอชำระมัดจำ',
  PENDING_REVIEW: 'รอตรวจสลิป',
  PAID: 'ชำระมัดจำแล้ว',
  REFUND_PENDING: 'รอคืนมัดจำ',
  REFUNDED: 'คืนมัดจำแล้ว',
  FORFEITED: 'ริบมัดจำ',
}

export interface BookingView {
  booking_id: string
  booking_code: string | null
  status: BookingStatus
  channel: 'ONLINE' | 'STAFF'
  starts_at: string
  ends_at: string
  branch: { id: string; name: string; phone: string | null; address: string | null }
  customer_name: string
  customer_note: string | null
  items: Array<{ service_name: string; service_name_en: string | null; duration_minutes: number; unit_price: number; line_total: number }>
  total_amount: number
  deposit_required: number
  deposit_status: DepositStatus
  hold_expires_at: string | null
  can_upload_slip: boolean
  payment: { promptpay_id: string; account_name: string; bank_name: string | null; amount: number } | null
  last_slip: { status: 'PENDING_REVIEW' | 'VERIFIED' | 'REJECTED'; message: string | null; created_at: string } | null
  cancel_reason: string | null
  cancelled_at: string | null
  created_at: string
  tracking_token?: string
  slip_outcome?: 'VERIFIED' | 'REJECTED' | 'REVIEW'
  slip_message?: string
}

export interface AvailableSlot {
  starts_at: string
  time: string
}

export interface StaffBookingDeposit {
  deposit_id: string
  status: 'PENDING_REVIEW' | 'VERIFIED' | 'REJECTED'
  amount: number
  slip_path: string | null
  provider_code: number | null
  provider_message: string | null
  slip_amount: number | null
  slip_trans_ref: string | null
  slip_trans_at: string | null
  slip_sender_name: string | null
  slip_receiver_name: string | null
  refund_status: 'NONE' | 'PENDING' | 'REFUNDED' | 'FORFEITED'
  refund_reference: string | null
  created_at: string
}

export interface StaffBookingRow {
  booking_id: string
  booking_code: string | null
  status: BookingStatus
  channel: 'ONLINE' | 'STAFF'
  starts_at: string
  ends_at: string
  customer_id: string
  customer_name: string
  phone_masked: string | null
  is_member: boolean
  items: Array<{ service_name: string; duration_minutes: number; unit_price: number }>
  total_amount: number
  deposit_required: number
  deposit_status: DepositStatus
  hold_expires_at: string | null
  customer_note: string | null
  staff_note: string | null
  cancel_reason: string | null
  deposits: StaffBookingDeposit[] | null
}

export function bangkokTime(iso: string): string {
  return new Date(iso).toLocaleTimeString('th-TH', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Bangkok' })
}

export function bangkokDateLong(iso: string): string {
  return new Date(iso).toLocaleDateString('th-TH', { dateStyle: 'full', timeZone: 'Asia/Bangkok' })
}

/** UUID สำหรับ Idempotency-Key */
export function newIdempotencyKey(): string {
  return crypto.randomUUID()
}
