/** สีของสถานะการจอง (DESIGN.md: Success = ยืนยัน/เสร็จ, Danger = ยกเลิก/ไม่มา) */
export type StatusVariant = 'success' | 'danger' | 'pending' | 'neutral' | 'default'

export function bookingStatusVariant(status: string): StatusVariant {
  return (
    ({
      CONFIRMED: 'success',
      COMPLETED: 'success',
      CHECKED_IN: 'default',
      PENDING: 'pending',
      CANCELLED: 'danger',
      NO_SHOW: 'danger',
      EXPIRED: 'neutral',
    }) as Record<string, StatusVariant>
  )[status] ?? 'neutral'
}
