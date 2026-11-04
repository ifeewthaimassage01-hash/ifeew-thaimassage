// SlipOK client — อ้างอิง SlipOK API Guide v1.13 (28 ก.พ. 2026)
//   POST https://api.slipok.com/api/line/apikey/<BRANCH_ID>
//   header: x-authorization: <API_KEY>, body (multipart): files, amount, log
//   สำเร็จ: { success: true, data: { success, transRef, amount, transTimestamp, sender, receiver, ... } }
//   ผิดพลาด: HTTP 4xx { code, message, data? }

export type SlipOutcome = 'VERIFIED' | 'REJECTED' | 'REVIEW'

export interface SlipCheckResult {
  outcome: SlipOutcome
  code: number | null
  message: string
  slip: {
    trans_ref?: string
    amount?: number
    trans_at?: string
    sender_name?: string
    receiver_name?: string
    receiver_account?: string
  }
}

// ปฏิเสธทันที: สลิปไม่ถูกต้อง/ซ้ำ/ยอดไม่ตรง/บัญชีผู้รับไม่ตรง/ไม่มีรายการจริง
const REJECT_CODES = new Set([1000, 1005, 1006, 1007, 1008, 1011, 1012, 1013, 1014])
// ส่งให้พนักงานตรวจ: ธนาคารขัดข้อง (1009), ต้องรอ (1010), ปัญหาแพ็กเกจ/ตั้งค่า (1001-1004, 1015)

const REJECT_MESSAGES: Record<number, string> = {
  1005: 'ไฟล์ไม่ใช่รูปภาพ',
  1006: 'รูปภาพไม่ถูกต้อง',
  1007: 'รูปภาพไม่มี QR Code ของสลิป',
  1008: 'QR ไม่ใช่สลิปการโอนเงิน',
  1011: 'ไม่พบรายการโอนเงินนี้ หรือ QR หมดอายุ',
  1012: 'สลิปนี้เคยถูกใช้แล้ว',
  1013: 'ยอดเงินในสลิปไม่ตรงกับยอดมัดจำ',
  1014: 'บัญชีผู้รับไม่ตรงกับบัญชีของร้าน',
}

interface SlipOkData {
  success?: boolean
  message?: string
  transRef?: string
  amount?: number
  transTimestamp?: string
  sender?: { displayName?: string; name?: string }
  receiver?: {
    displayName?: string
    name?: string
    account?: { value?: string }
    proxy?: { value?: string }
  }
}

export async function checkSlipWithSlipOk(params: {
  apiKey: string
  branchId: string
  file: Blob
  fileName: string
  amount: number
}): Promise<SlipCheckResult> {
  const form = new FormData()
  form.append('files', params.file, params.fileName)
  form.append('amount', String(params.amount))
  form.append('log', 'true') // ให้ SlipOK ตรวจบัญชีผู้รับที่ผูกกับสาขาและตรวจสลิปซ้ำ

  let res: Response
  try {
    res = await fetch(`https://api.slipok.com/api/line/apikey/${encodeURIComponent(params.branchId)}`, {
      method: 'POST',
      headers: { 'x-authorization': params.apiKey },
      body: form,
      signal: AbortSignal.timeout(20_000),
    })
  } catch (e) {
    return { outcome: 'REVIEW', code: null, message: `เชื่อมต่อระบบตรวจสลิปไม่ได้ (${(e as Error).name})`, slip: {} }
  }

  let body: { success?: boolean; code?: number; message?: string; data?: SlipOkData } = {}
  try {
    body = await res.json()
  } catch {
    return { outcome: 'REVIEW', code: null, message: `ระบบตรวจสลิปตอบกลับไม่ถูกต้อง (HTTP ${res.status})`, slip: {} }
  }

  if (res.ok && body.success === true && body.data?.success === true) {
    const d = body.data
    return {
      outcome: 'VERIFIED',
      code: null,
      message: d.message ?? '✅',
      slip: {
        trans_ref: d.transRef,
        amount: typeof d.amount === 'number' ? d.amount : Number(d.amount),
        trans_at: d.transTimestamp,
        sender_name: d.sender?.displayName ?? d.sender?.name,
        receiver_name: d.receiver?.displayName ?? d.receiver?.name,
        receiver_account: d.receiver?.account?.value ?? d.receiver?.proxy?.value,
      },
    }
  }

  const code = typeof body.code === 'number' ? body.code : null
  if (code !== null && REJECT_CODES.has(code)) {
    return { outcome: 'REJECTED', code, message: REJECT_MESSAGES[code] ?? body.message ?? 'สลิปไม่ถูกต้อง', slip: {} }
  }
  return {
    outcome: 'REVIEW',
    code,
    message: body.message ? `ตรวจอัตโนมัติไม่ได้: ${body.message}` : `ตรวจอัตโนมัติไม่ได้ (HTTP ${res.status})`,
    slip: {},
  }
}
