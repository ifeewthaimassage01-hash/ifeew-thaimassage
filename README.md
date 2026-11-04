# Ifeew's Thaimassage — ระบบบริหารร้านนวดหลายสาขา

Monorepo (pnpm workspaces) สำหรับ Customer App, Staff App และ Supabase ชุดเดียว

```
apps/
  customer/        Nuxt 3 — ลูกค้า (SSR, mobile first)        port 3000
  staff/           Nuxt 3 — พนักงาน/เจ้าของ (SPA, desktop first) port 3001
packages/
  shared/          Database types, Zod schema, ค่าคงที่ร่วม
supabase/
  migrations/      Schema ทั้งหมด (แก้ผ่าน migration เท่านั้น)
  functions/       Edge Functions (device-staff-list, staff-pin-login, staff-create, staff-set-status, customer-erasure, guest-booking, booking-tracking, booking-deposit-slip, queue-pin-action, pos-payment-slip)
  tests/database/  pgTAP tests
  seed.sql         ข้อมูลทดสอบ (local/dev เท่านั้น)
docs/phase-*/      ER Diagram และเอกสารออกแบบแต่ละ Phase
```

## สิ่งที่ต้องมี

- Node.js 22+ และ pnpm 10 (`corepack enable` หรือ `npx pnpm@10`)
- Docker Desktop (สำหรับ Supabase local: `supabase start`)
- Supabase CLI 3.x (ติดตั้งเป็น devDependency แล้ว เรียกผ่าน `pnpm exec supabase`)

## ติดตั้ง

```bash
pnpm install
```

## รัน Supabase local

```bash
pnpm db:start
```

```bash
pnpm db:reset
```

`db:reset` จะรัน migrations ทั้งหมดและ `seed.sql` จากนั้น `supabase status` จะแสดง URL และ Publishable/Secret key

## ตั้งค่า Environment

| ไฟล์ | ตัวแปร | หมายเหตุ |
|---|---|---|
| `apps/customer/.env` | `NUXT_PUBLIC_SUPABASE_URL`, `NUXT_PUBLIC_SUPABASE_KEY`, `NUXT_PUBLIC_COMPANY_CODE` | Publishable key เท่านั้น, company code = `companies.code` |
| `apps/staff/.env` | `NUXT_PUBLIC_SUPABASE_URL`, `NUXT_PUBLIC_SUPABASE_KEY`, `NUXT_PUBLIC_FUNCTIONS_URL` (ไม่บังคับ) | Publishable key เท่านั้น |
| `supabase/functions/.env` | `ALLOWED_ORIGINS`, `TURNSTILE_SECRET_KEY`, `SLIPOK_API_KEY` | origin ของทั้งสองแอป, Turnstile secret, SlipOK API key (ว่าง = พนักงานตรวจสลิปเอง) |

คัดลอกจากไฟล์ `.env.example` ในแต่ละโฟลเดอร์ **ห้ามใส่ Secret/Service Role Key ในแอป Nuxt**

## รันแอป

```bash
pnpm functions:serve
```

```bash
pnpm dev:staff
```

```bash
pnpm dev:customer
```

## บัญชีทดสอบ (local)

ดูหัวไฟล์ [supabase/seed.sql](supabase/seed.sql) — OWNER ใช้อีเมล/รหัสผ่าน + TOTP, STAFF ใช้เลือกชื่อ + PIN

ขั้นตอนทดสอบ Staff Login:
1. เปิด Staff App → แท็บ “เจ้าของร้าน” → login → สแกน QR ด้วยแอป Authenticator → ยืนยันรหัส
2. เมนู “ตั้งค่าเครื่อง” → เลือกสาขา → “ผูกเครื่องนี้”
3. ออกจากระบบ → แท็บ “พนักงาน” → แตะชื่อ → กด PIN

ขั้นตอนทดสอบ Phase 2 (OWNER):
- เมนู “พนักงาน” → เพิ่มพนักงาน / ตั้ง PIN / ย้ายสาขา / เปลี่ยนสถานะ — ระบบจะขอรหัส Authenticator ซ้ำถ้ายืนยันครั้งล่าสุดเกิน 5 นาที
- เมนู “ตารางงาน” → กด + ในช่องวัน เพื่อเพิ่มกะ, “คัดลอกสัปดาห์ก่อน”
- เมนู “สาขา” → เวลาทำการและวันหยุด

ขั้นตอนทดสอบ Phase 3:
- Customer App: สมัครสมาชิก (ต้องยอมรับนโยบาย) → โปรไฟล์ → ดาวน์โหลดข้อมูล / ขอลบข้อมูล; ดูบริการและราคาที่หน้า “บริการ” และหน้าสาขา
- Staff App เมนู “ลูกค้า”: ค้นหาเบอร์ `0812345678` (มีสมาชิก + Guest) → จับคู่ Guest; แท็บ “คำขอลบข้อมูล” (OWNER)
- Staff App เมนู “บริการและราคา” (OWNER): เปลี่ยนราคาทันที/ล่วงหน้า (ขอ TOTP ซ้ำ), ประวัติราคา

ขั้นตอนทดสอบ Phase 4:
- Customer App “จอง”: เลือกสาขา/บริการ/วันเวลา → จองแบบ Guest (Turnstile test key ผ่านอัตโนมัติ) → หน้า `/t/<token>` แสดง QR PromptPay → อัปโหลดสลิป
- ถ้ายังไม่ตั้ง `SLIPOK_API_KEY` หรือ SlipOK Branch ID ของสาขา สลิปจะไปที่ Staff App เมนู “การจอง” → แท็บ “รอตรวจสลิป”
- Staff App เมนู “เตียงและอุปกรณ์” (OWNER): จำนวนต่อสาขา, บริการใช้อะไร, บัญชีรับมัดจำ + SlipOK Branch ID

ขั้นตอนทดสอบ Phase 5 (สาขา SKV มีหมอ 2 คน: นภา PIN 246810, ดาว PIN 482916):
- เมนู “หน้าร้าน (POS)” → “เปิดกะ” → “รับลูกค้า Walk-in” → เลือกบริการ (ระบบเลือกเวลาว่างเร็วสุดให้) → จอแสดงเลขคิวให้แจ้งลูกค้า
- ลูกค้าที่จองไว้วันนี้ → “เช็กอิน”
- เมนู “คิว” → “เรียกคิว” เลือกหมอ → ออกจากระบบแล้ว login เป็นหมอ (PIN) → แท็บ “คิวของฉัน” → รับคิว → เริ่มบริการ → จบบริการ
- เปิดเมนู “คิว” ไว้สองเครื่อง/สองแท็บ เพื่อดูการอัปเดตแบบ Realtime

ขั้นตอนทดสอบ Phase 6:
- เมนู “คิว” บนเครื่องที่ผูกสาขาแล้ว: ปุ่ม “หมอกด PIN” ให้หมอรับ/เริ่ม/จบคิวของตัวเองโดยไม่ต้องออกจากระบบหน้าร้าน (ต้อง `pnpm functions:serve`)
- คิวที่กำลังให้บริการ: “ต่อเวลา” (หมอคนเดิมทำต่อทันทีเมื่อจบรายการเดิม), “เปลี่ยนหมอ” (ค่ามือแบ่งตามเวลา), “ย้อนเริ่ม”; คิวที่เพิ่งจบ: “ย้อนจบบริการ” (ภายใน 15 นาที)
- เมนู “งานของฉัน” (หมอ) และ “สรุปงานหมอ” (OWNER); แดชบอร์ดหน้าแรก
- Customer App: ไอคอนประวัติ → ประวัติการใช้บริการ

ขั้นตอนทดสอบ Phase 7:
- เมนู “หน้าร้าน (POS)” → เปิดกะ → การ์ดลูกค้า “ชำระเงิน” → ส่วนลด (ไม่เกิน 20% สำหรับพนักงาน) → “ออก Invoice” → รับเงินสด/QR/โอน (+ทิป)
- QR/โอน: “ถ่ายรูปสลิป” → ถ้ายังไม่ตั้ง SlipOK ระบบให้พนักงานยืนยันเองพร้อมเหตุผล (ต้อง `pnpm functions:serve`)
- ลูกค้าที่จองและจ่ายมัดจำแล้ว: ออก Invoice แล้วระบบหักมัดจำให้อัตโนมัติ
- “เงินเข้า/ออกลิ้นชัก”, “จ่ายทิป”, “ปิดกะ” (กรอกเงินที่นับได้ก่อน แล้วจึงเห็นยอดที่ควรมี) → เมนู “กะและเงินสด” (OWNER อนุมัติ)
- เมนู “รายจ่าย”: จำนวนเงิน + หมายเหตุ + รูป; ยกเลิกในกะเดียวกันได้ทันที นอกนั้นส่งคำขอให้ OWNER
- OWNER: Void Invoice ที่รับเงินแล้ว / คืนเงิน (ต้องยืนยันรหัส Authenticator ซ้ำ)

## ทดสอบ

```bash
pnpm db:test
```

```bash
pnpm typecheck
```

## สร้าง Database types ใหม่

หลังแก้ migration ทุกครั้ง (ต้องมี local stack ทำงานอยู่):

```bash
pnpm db:types
```

## Deploy (สรุป)

1. สร้าง Supabase project แยก dev / staging / production (Region Singapore)
2. `supabase link --project-ref <ref>` แล้ว `supabase db push` (ไม่ push `seed.sql` ไป staging/production)
3. `supabase functions deploy device-staff-list staff-pin-login staff-create staff-set-status customer-erasure guest-booking booking-tracking booking-deposit-slip queue-pin-action pos-payment-slip` และ `supabase secrets set ALLOWED_ORIGINS=...`
4. `pg_cron`: migration 019 จะ schedule งานปล่อยการจองที่หมดเวลาชำระให้อัตโนมัติถ้าฐานข้อมูลมี pg_cron (Supabase มีให้) — ตรวจใน SQL Editor ด้วย `select * from cron.job;` ถ้าไม่มี ให้เปิด extension `pg_cron` แล้วรัน `select cron.schedule('expire-stale-bookings', '* * * * *', 'select private.expire_stale_bookings()');`
5. Dashboard → Auth: เปิด TOTP MFA, ปิด/เปิด signup ตามต้องการ, ตั้ง password policy ให้ตรงกับ `config.toml`
6. Vercel: สร้าง 2 project (root = `apps/customer`, `apps/staff`) ตั้ง env ตามตารางด้านบน
7. สร้างบริษัท/OWNER คนแรกของ staging/production — ยังไม่มีสคริปต์ (ต้องทำก่อนขึ้น Production)
