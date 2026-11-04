# คู่มือขึ้นระบบ (Staging → Production)

ทำ Staging ให้ผ่านรายการตรวจด้านล่างทั้งหมดก่อน แล้วจึงทำ Production ด้วยขั้นตอนเดียวกัน
ตามที่ตกลง: ใช้โดเมนของ Vercel, Supabase แพ็กเกจ Free (ยังไม่มี PITR), อีเมลในตัวของ Supabase

> ข้อจำกัดของแพ็กเกจที่เลือก
> - Supabase Free: โปรเจกต์ที่ไม่มีการใช้งาน 7 วันจะถูกหยุด (ต้องกด Restore) และไม่มี PITR — สำรองข้อมูลเองด้วย `supabase db dump` อย่างน้อยวันละครั้ง จนกว่าจะอัปเกรดเป็น Pro
> - อีเมลในตัวของ Supabase ส่งได้ไม่กี่ฉบับต่อชั่วโมง พอสำหรับเชิญ OWNER / รีเซ็ตรหัสผ่าน แต่ไม่พอถ้าลูกค้าสมัครสมาชิกจำนวนมาก (ตอนนั้นให้ตั้ง SMTP)

## สิ่งที่ต้องทำเอง (สร้างบัญชี / ใส่ key)

| รายการ | ที่ไหน |
| --- | --- |
| Supabase 2 โปรเจกต์: `ifeew-staging`, `ifeew-production` (Region: Southeast Asia - Singapore) | supabase.com |
| Vercel 2 โปรเจกต์ต่อสภาพแวดล้อม: Customer App, Staff App | vercel.com |
| Cloudflare Turnstile: site key + secret key (ใส่โดเมน `*.vercel.app` ของ Customer App) | dash.cloudflare.com |
| SlipOK: API Key + Branch ID ของบัญชีรับเงินแต่ละสาขา | slipok.com |
| (ไม่บังคับ) Sentry: DSN ของ 2 แอป | sentry.io |

**ห้าม** ส่ง key ในแชท / commit ลง Git — ใส่ใน Dashboard ของแต่ละบริการ หรือไฟล์ `.env` ในเครื่องเท่านั้น

## 1. Supabase

```bash
pnpm exec supabase login
```

```bash
pnpm exec supabase link --project-ref <project-ref>
```

```bash
pnpm exec supabase db push
```

- `db push` รัน migrations ทั้งหมด (ไม่รัน `seed.sql`)
- Dashboard → Database → Extensions: ตรวจว่า `pg_cron` เปิดอยู่ แล้วใน SQL Editor: `select jobname, schedule from cron.job;`
  ต้องมี `expire-stale-bookings` (ทุกนาที) และ `sync-commissions` (ทุกชั่วโมง) — ถ้าไม่มี (เปิด pg_cron หลัง push) ให้รัน
  `select cron.schedule('expire-stale-bookings', '* * * * *', 'select private.expire_stale_bookings()');` และ
  `select cron.schedule('sync-commissions', '7 * * * *', 'select private.sync_all_commissions()');`
- Database → Publications → `supabase_realtime`: ตรวจว่ามี `queue_items`, `service_orders`, `invoices`
  (ถ้าไม่มี: `alter publication supabase_realtime add table public.queue_items, public.service_orders, public.invoices;`)
- Advisors → Security / Performance: ต้องไม่มีรายการระดับ ERROR

### Auth (Dashboard → Authentication)

| ตั้งค่า | ค่า |
| --- | --- |
| Site URL | URL ของ Customer App เช่น `https://ifeew.vercel.app` |
| Redirect URLs | `https://ifeew.vercel.app/**`, `https://ifeew-staff.vercel.app/set-password`, `https://ifeew-staff.vercel.app/**` |
| Multi-Factor → TOTP | เปิดไว้ได้ (ตั้งแต่ migration 028 เจ้าของร้านไม่บังคับ MFA — login ด้วย PIN บนเครื่องสาขา) |
| Password | ขั้นต่ำ 10 ตัว, ต้องมีตัวพิมพ์เล็ก/ใหญ่/ตัวเลข, เปิด "Prevent leaked passwords" (ถ้ามีในแพ็กเกจ) |
| Email confirmations | เปิด |
| Secure password change | เปิด |

### Edge Functions

```bash
pnpm exec supabase functions deploy device-staff-list staff-pin-login staff-create staff-set-status customer-erasure guest-booking booking-tracking booking-deposit-slip queue-pin-action pos-payment-slip
```

```bash
pnpm exec supabase secrets set ALLOWED_ORIGINS=https://ifeew.vercel.app,https://ifeew-staff.vercel.app TURNSTILE_SECRET_KEY=<secret> SLIPOK_API_KEY=<key>
```

`device-staff-list`, `staff-pin-login`, `guest-booking`, `booking-tracking`, `booking-deposit-slip` ปิด verify JWT ไว้ใน `supabase/config.toml` แล้ว (deploy จะใช้ค่านี้)

### สร้างบริษัทและ OWNER คนแรก

```bash
cd tools/bootstrap && npm install && cp company.example.json company.json
```

แก้ `company.json` (อีเมล OWNER, สาขา, นโยบายความเป็นส่วนตัวฉบับจริง) แล้วรัน (key อ่านจาก environment ไม่ต้องเขียนลงไฟล์):

```bash
SUPABASE_URL=https://<ref>.supabase.co SUPABASE_SECRET_KEY=<secret key> STAFF_APP_URL=https://ifeew-staff.vercel.app node create-company.mjs company.json
```

OWNER จะได้อีเมลเชิญ → ตั้งรหัสผ่าน (`/set-password`) → เข้าระบบ → ผูกแท็บเล็ตหน้าร้าน → ตั้ง “PIN เจ้าของร้าน” ที่หน้าตั้งค่าเครื่อง

## 2. Vercel (ทำ 2 โปรเจกต์จาก repo เดียว)

| | Customer App | Staff App |
| --- | --- | --- |
| Root Directory | `apps/customer` | `apps/staff` |
| Framework | Nuxt | Nuxt |
| Install Command | `cd ../.. && npx pnpm@10.34.9 install --frozen-lockfile` | เหมือนกัน |
| Build Command | `npx nuxt build` | `npx nuxt build` |

Environment Variables

| ตัวแปร | Customer App | Staff App |
| --- | --- | --- |
| `NUXT_PUBLIC_SUPABASE_URL` | `https://<ref>.supabase.co` | เหมือนกัน |
| `NUXT_PUBLIC_SUPABASE_KEY` | Publishable key | เหมือนกัน |
| `NUXT_PUBLIC_COMPANY_CODE` | รหัสบริษัท | - |
| `NUXT_PUBLIC_TURNSTILE_SITE_KEY` | site key จริง | - |
| `NUXT_PUBLIC_CUSTOMER_APP_URL` | - | URL ของ Customer App |
| `NUXT_PUBLIC_SENTRY_DSN` | (ไม่บังคับ) | (ไม่บังคับ) |
| `NUXT_PUBLIC_APP_ENV` | `staging` / `production` | เหมือนกัน |

ห้ามใส่ Secret / Service Role Key ใน Vercel ของทั้ง 2 แอป

## 3. รายการตรวจก่อนเปิดใช้ (ทำบน Staging ก่อน)

- [ ] `pnpm db:test` ผ่าน (ต่อ staging ด้วย `supabase test db --linked`) และ `tools/dbtest` ผ่านในเครื่อง
- [ ] OWNER: รับอีเมลเชิญ → ตั้งรหัสผ่าน → เข้าระบบได้, ลืมรหัสผ่านได้, ตั้ง PIN เจ้าของร้าน → login ด้วย PIN บนเครื่องสาขาได้
- [ ] ตั้งเวลาทำการ, บริการ/ราคา, เตียงและอุปกรณ์, บัญชี PromptPay + SlipOK Branch ID, พนักงาน + PIN
- [ ] ผูกแท็บเล็ตหน้าร้าน → พนักงาน login ด้วยชื่อ + PIN → ลงเวลาเข้างาน
- [ ] ลูกค้า: สมัครสมาชิก (ได้อีเมลยืนยัน), จองแบบ Guest (Turnstile จริง) → สแกน QR โอนมัดจำจริง 1 รายการ → SlipOK ตรวจผ่าน
- [ ] หน้าร้าน: Walk-in → เรียกคิว → หมอกด PIN → จบ → ชำระ (เงินสด + QR จริง) → ปิดกะ → ปิดยอดรายวัน → OWNER อนุมัติ
- [ ] เปิดหน้า “คิว” 2 เครื่อง: อัปเดต Realtime
- [ ] OWNER: แดชบอร์ด, รายงาน + CSV, รอบจ่ายค่ามือ, ประกันมือ
- [ ] มือถือ (Customer App) / แท็บเล็ต (หน้าร้าน) / คอมพิวเตอร์ (OWNER) แสดงผลถูกต้อง, ถ่ายรูปสลิปได้
- [ ] ลบข้อมูลทดสอบออกจาก Production (ไม่รัน seed บน Production)

## 4. สำรองข้อมูล (แพ็กเกจ Free ไม่มี PITR)

```bash
pnpm exec supabase db dump --linked -f backup-$(date +%F).sql
```

```bash
pnpm exec supabase db dump --linked --data-only -f backup-data-$(date +%F).sql
```

เก็บไฟล์ไว้นอกเครื่อง (เข้ารหัส) และทดสอบ restore ลงโปรเจกต์ staging อย่างน้อยปีละครั้ง (สเปกข้อ 22)
เมื่อธุรกิจใช้งานจริงเต็มรูปแบบ แนะนำอัปเกรด Production เป็น Pro + PITR
