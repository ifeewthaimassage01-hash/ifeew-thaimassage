# เช็ก Edge Functions และ RPC ก่อนขึ้น production

ขอบเขตที่เช็ก: Edge Functions 13 ตัว, RPC ที่แอปและ Edge Functions เรียก 108 ตัว และ public functions ทั้งหมด 120 ตัวใน migrations 001–035 รวมถึงงานที่ยังไม่ได้ commit (check-booking, guest-booking-lookup, migration 035) ส่วนฝั่ง production ดูได้อย่างเดียว ผ่าน `supabase functions list`, `migration list` และ `secrets list` ไม่ได้แก้หรือ deploy อะไร

## สรุปสั้นๆ

- **ต้องแก้ก่อนขึ้น 1 จุด:** ฟีเจอร์ "ตรวจสอบการจอง" พังทุกครั้งที่ใช้บน production เพราะ deploy function แล้ว แต่ยังไม่ได้รัน migration 035
- **มีที่พังเงียบๆ 9 จุด:** หน้าจอไม่เช็ก error จาก RPC ถ้า RPC ล้มเหลว หน้าจอจะแสดงเป็นค่าว่างเหมือนไม่มีข้อมูล ไม่มีข้อความ error ขึ้น
- **มีของที่ไม่ได้ใช้แล้ว:** Edge Function 1 ตัว และ RPC อีกราว 10 ตัว ในจำนวนนี้มีกลุ่ม RPC ลิ้นชัก/กะที่ยังเรียกได้จริง
- **ส่วนที่ปกติ:** ชื่อ RPC, ชื่อพารามิเตอร์, สิทธิ์ execute และ verify_jwt ไม่มีจุดผิด (รายละเอียดอยู่ท้ายรายงาน)

---

## 1. ต้องแก้ก่อนขึ้น production

### guest-booking-lookup อยู่บน production แล้ว แต่ไม่มี RPC ให้เรียก
- `supabase functions list` แสดงว่า `guest-booking-lookup` v1 ACTIVE แล้ว (deploy เมื่อ 2026-11-10)
- `supabase migration list` แสดงว่า `20261117000035_guest_booking_lookup.sql` **ยังไม่ได้รันบน production** ฟังก์ชัน `public.guest_bookings_by_phone` จึงยังไม่มีบน production
- ผลคือทุกครั้งที่มีคนค้นหา function จะเจอ error แล้ว `throw` ออกเป็น 500 `INTERNAL_ERROR` ลูกค้าเห็นแค่ "ค้นหาไม่สำเร็จ กรุณาลองใหม่" ส่วนสาเหตุจริงอยู่ใน function logs ที่เดียว
- งานที่ยังไม่ commit ใน `useAppNav.ts` และ `t/[token].vue` เพิ่มลิงก์ "ตรวจสอบการจอง" ให้ Guest ทุกคนแล้ว ถ้า deploy customer app ก่อนรัน migration ลูกค้าจะเจอปุ่มที่กดแล้วใช้ไม่ได้ทันที
- **ลำดับที่ถูกต้อง:** `supabase db push` (รัน 035) → ทดสอบ `/check-booking` → deploy customer app
- หลังรันแล้วให้ regenerate `packages/shared/src/database.types.ts` ด้วย ตอนนี้ไฟล์นี้ยังไม่มีคอลัมน์ `booking_tracking_tokens.purpose`

---

## 2. จุดที่พังเงียบๆ (error ถูกทิ้ง หน้าจอเห็นเป็นค่าว่าง)

ทุกจุดในตารางเขียนแบบ `const { data } = await supabase.rpc(...)` โดยไม่ดู `error` ถ้า RPC ล้ม (สิทธิ์ไม่พอ, เน็ตหลุด, session หมด, ส่งพารามิเตอร์ผิดเงื่อนไข) หน้าจอจะเหมือนไม่มีข้อมูล ผู้ใช้ไม่รู้เลยว่ามีอะไรผิด

| ความเสี่ยง | ไฟล์ | RPC | ผลที่ผู้ใช้เห็น |
|---|---|---|---|
| สูง | `apps/staff/pages/pos.vue:37` | `pos_finance_board` | รายการ "ค้างชำระ" ว่าง และ `invoiceOf()` คืนค่า undefined ทำให้หน้า POS ดูเหมือนไม่มีบิลค้าง ทั้งที่จริงคือโหลดไม่ได้ |
| สูง | `apps/staff/pages/checkout/[orderId].vue:47` | `pos_board` | dropdown "ทิปให้หมอ" ว่าง แคชเชียร์บันทึกทิปไม่ได้และไม่รู้สาเหตุ |
| กลาง | `apps/staff/pages/queue.vue:372` | `branch_attendance_today` | กล่องลงเวลาไม่มีรายชื่อพนักงาน |
| กลาง | `apps/staff/pages/queue.vue` (`loadFuelSetting`) | select `company_settings` | ค่าน้ำมันกลายเป็น 0 ติ๊กค่าน้ำมันหมอวิ่งไม่ได้ ดูเหมือนเจ้าของยังไม่ได้ตั้งค่า |
| กลาง | `apps/staff/pages/my-work.vue:37` | `my_earnings` | การ์ดรายได้หายไปเฉยๆ ตัวอย่างที่เกิดได้จริง: เลือกช่วงเกิน 62 วัน DB จะ raise error แต่หน้าจอไม่แสดงอะไร |
| กลาง | `apps/staff/pages/index.vue:29` | `staff_dashboard_finance` | ตัวเลขยอดขาย/ค้างชำระบนแดชบอร์ดหายไปโดยไม่มีข้อความ |
| ต่ำ | `apps/staff/pages/settings/devices.vue:94` | `my_owner_pin_status` | สถานะ PIN เจ้าของไม่แสดง |
| ต่ำ | `apps/customer/pages/index.vue:35` | `my_bookings` | ไม่แสดงนัดถัดไปหรือจำนวนที่ต้องโอนมัดจำ |
| ต่ำ | `apps/customer/pages/bookings/[id].vue:21` | `my_booking` | ขึ้นว่า "ไม่พบการจอง" แทนที่จะบอกว่าโหลดไม่สำเร็จ |

วิธีแก้: ห่อด้วย `must(...)` ที่มีอยู่แล้วใน `useStepUp.ts` แล้วแสดง error เหมือนหน้าอื่น หรืออย่างน้อยเช็ก `error` แล้วแสดงข้อความ

**จุดเงียบฝั่ง Edge Function / DB**
- `booking-deposit-slip` (บรรทัด 75): query `branch_payment_accounts` ไม่เช็ก error ถ้า query ล้ม สลิปจะไปอยู่ในสถานะ REVIEW ให้พนักงานตรวจเอง ไม่มีข้อมูลหาย แต่ไม่มี log บอกสาเหตุ
- **ฝั่ง production ยังไม่ได้ตั้ง `SLIPOK_API_KEY`** (เช็กจาก `supabase secrets list`) สลิปทุกใบ ทั้งมัดจำและ POS จะไปอยู่ใน REVIEW ให้พนักงานตรวจเองทั้งหมด ถ้าตั้งใจให้ตรวจอัตโนมัติต้องตั้งค่านี้ก่อน
- `customer-erasure` คืน 207 `auth_synced:false` ได้ (หน้าจอแสดงคำเตือน) แต่ตอนนั้นคำขอถูกเปลี่ยนเป็น COMPLETED ไปแล้ว **จึงกดทำซ้ำไม่ได้** และข้อมูลส่วนบุคคลยังค้างอยู่ใน Auth ต้องเข้าไปล้างเอง ควรมีทางให้ sync ซ้ำ
- `staff-create`, `staff-set-status`, `customer-erasure` ไม่มี try/catch ครอบส่วนนอก ถ้าเกิด exception (เช่น env ขาด) response จะไม่มี CORS header เบราว์เซอร์จะแสดงเป็น network error แทนข้อความที่อ่านเข้าใจได้
- `queue_undo_start` แล้วเรียกหมอวิ่งพร้อมค่าน้ำมันอีกรอบ จะบันทึกรายจ่ายค่าน้ำมัน (`FREELANCE_FUEL`) **ซ้ำ 2 รายการ** เพราะตอนย้อน รายจ่ายเดิมไม่ถูก void

---

## 3. ของที่ไม่ได้ใช้แล้ว

**Edge Function**
- `device-staff-list`: ไม่มีหน้าไหนเรียก `listStaff()` แล้ว เพราะ login เปลี่ยนไปใช้ branch mode (`branch-staff-list`) ตั้งแต่ migration 030 ตัว function ยัง deploy อยู่และเปิด `verify_jwt=false` (ใช้ได้ต้องมี device token)
- ใน `staff-pin-login` โหมด device_token (`pinLogin()`) ก็ไม่มีหน้าไหนเรียกแล้วเหมือนกัน
- RPC `device_list_staff` ถูกเรียกจาก function นี้ที่เดียว จึงไม่ได้ใช้ไปด้วย

**RPC ที่ไม่มีโค้ดไหนเรียก แต่ยังเรียกได้**
- `pos_open_session`, `pos_close_session`, `pos_cash_adjustment`, `pos_review_session`, `pos_sessions_list`: ระบบลิ้นชัก/กะถูกเลิกใช้ใน migration 034 **แต่สิทธิ์ execute ของ authenticated ยังอยู่** พนักงานที่มีสิทธิ์สาขาเรียกตรงผ่าน API ได้ เช่น บันทึกเงินเข้า/ออกลิ้นชัก หรือปิดกะเองพร้อมยอดนับ ซึ่งกระทบยอดปิดรายวัน **แนะนำ revoke หรือ drop**
- `pos_invoice`: ไม่มีที่เรียก (แอปใช้ `pos_create_invoice` / `pos_issue_invoice` แทน)
- `change_my_pin`: ไม่มีหน้าให้พนักงานเปลี่ยน PIN เอง
- `queue_call`: โค้ดใน `queue.vue` `pick()` ไปไม่ถึงแล้ว เพราะคิวที่ไม่ใช่ IN_SERVICE จะไปเข้า `callStart()` (`queue_call_start`) ทั้งหมด
- `queue_accept`, `queue_start`: ถูกเรียกเฉพาะใน `device_queue_action` ตอน action ACCEPT/START แต่ปุ่ม PIN ในหน้าคิวแสดงเฉพาะคิว IN_SERVICE จึงส่งได้แค่ COMPLETE ทั้งสอง path นี้จึงไม่ถูกใช้แล้ว
- `bootstrap_company`: ไม่ใช่ของค้าง สคริปต์ `tools/bootstrap/create-company.mjs` ยังใช้อยู่ (สิทธิ์ service_role) ควรเก็บไว้

---

## 4. ส่วนที่ผ่าน

- RPC ที่แอปและ Edge Functions เรียกทั้ง 108 ชื่อมีอยู่ใน migrations ทุกตัว ชื่อพารามิเตอร์ตรงกับ signature ล่าสุด และไม่มี overload ที่ทำให้เรียกกำกวม (`queue_call_start` เวอร์ชันเก่าถูก drop ไปแล้ว)
- สิทธิ์ execute (ไล่จาก `alter default privileges` ใน 010 และ grant/revoke ที่ตามมา รวมถึงตอน rename เป็น `_core`):
  - RPC ที่แอปเรียกด้วย JWT ผู้ใช้ grant ให้ authenticated ทุกตัว
  - ที่เปิดให้ anon มีแค่ `get_public_company`, `get_current_policies`, `get_available_slots` ซึ่งตรงกับหน้าที่ลูกค้ายังไม่ login
  - RPC ที่ให้เฉพาะ service_role ถูกเรียกผ่าน `adminClient()` ใน Edge Function เท่านั้น
- Edge Function ทั้ง 13 ตัวที่แอปเรียกมีอยู่บน production ทุกตัว และค่า verify_jwt ตรงกับ `config.toml`
- migration 001–034 รันบน production ครบแล้ว

## สิ่งที่ยังไม่ได้เช็ก
- เนื้อโค้ดของ function ที่ deploy อยู่ตรงกับไฟล์ใน repo หรือไม่ (ไม่ได้ download มาเทียบ) ที่ควรระวังคือ `owner-pin-login` ซึ่ง deploy ก่อนเวลาที่ commit ไฟล์
- ค่าจริงของ `ALLOWED_ORIGINS` บน production เห็นแค่ digest ถ้าไม่มีโดเมนจริงของทั้งสองแอป (เช่น `https://ifeew.vercel.app`, `https://ifeew-staff.vercel.app` ตาม `docs/deploy.md`) การเรียก Edge Function จากเบราว์เซอร์จะติด CORS ทุกตัว
- `TURNSTILE_SECRET_KEY` มีตั้งไว้แล้ว แต่ดูไม่ได้ว่าเป็น test key (`1x000…AA` ที่ผ่านเสมอ) หรือ key จริง

## คำถาม
1. ตั้งใจให้สลิปทุกใบตรวจเอง (ยังไม่ใช้ SlipOK) ตอนเปิดตัวใช่ไหม หรือต้องตั้ง `SLIPOK_API_KEY` ก่อน
2. ให้ revoke/drop RPC ลิ้นชัก/กะ และลบ `device-staff-list` ที่ไม่ได้ใช้เลยไหม หรือจะเก็บไว้ก่อน
3. ให้แก้ 9 จุดในข้อ 2 ให้แสดง error เลยไหม (เริ่มจาก `pos.vue` และ `checkout` ก่อน)
