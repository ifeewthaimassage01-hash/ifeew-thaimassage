// สร้างข้อความ QR PromptPay (มาตรฐาน EMVCo / Thai QR Payment) พร้อมยอดเงิน
// รองรับ: เบอร์มือถือ 10 หลัก, เลขประจำตัว 13 หลัก, e-Wallet 15 หลัก

function tlv(id: string, value: string): string {
  return `${id}${value.length.toString().padStart(2, '0')}${value}`
}

/** CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF) ตามที่ EMVCo กำหนด */
export function crc16(input: string): string {
  let crc = 0xffff
  const bytes = new TextEncoder().encode(input)
  for (const b of bytes) {
    crc ^= b << 8
    for (let i = 0; i < 8; i++) {
      crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff
    }
  }
  return crc.toString(16).toUpperCase().padStart(4, '0')
}

export function promptPayPayload(promptPayId: string, amount?: number): string {
  const id = promptPayId.replace(/[^0-9]/g, '')
  let target: string
  if (/^0[0-9]{9}$/.test(id)) target = tlv('01', `0066${id.slice(1)}`.padStart(13, '0'))
  else if (/^[0-9]{13}$/.test(id)) target = tlv('02', id)
  else if (/^[0-9]{15}$/.test(id)) target = tlv('03', id)
  else throw new Error('PromptPay ID ไม่ถูกต้อง')

  const hasAmount = typeof amount === 'number' && amount > 0
  const body =
    tlv('00', '01') +
    tlv('01', hasAmount ? '12' : '11') +
    tlv('29', tlv('00', 'A000000677010111') + target) +
    tlv('58', 'TH') +
    tlv('53', '764') +
    (hasAmount ? tlv('54', amount!.toFixed(2)) : '') +
    '6304'
  return body + crc16(body)
}
