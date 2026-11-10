## สรุป
ตรวจ Edge Functions 13 ตัว กับ RPC 108 ชื่อ (แอปเรียก 96 จุด รวมที่ Edge Functions เรียกต่อ) ใช้ทั้งสแกนอัตโนมัติ ตรวจลายเซ็นพารามิเตอร์/สิทธิ์ `grant` กับ migrations และเช็กสถานะบน production แบบอ่านอย่างเดียว (`supabase functions list`, `supabase migration list --remote`)
→ **ยืนยันเป็นบัค 4 ข้อ** (ข้อที่ 1 พังแน่นอนบน production ตอนนี้) · **ไม่ได้ใช้ 2 รายการ** · **ตั้งใจไว้/ไม่ใช่ปัญหา 9 ข้อ**

เรื่องที่ไม่พบปัญหา:
- ทุก RPC ที่แอปเรียกมีอยู่จริงใน migrations ทั้งชื่อและพารามิเตอร์ และ `grant execute` ให้ role ที่ถูกต้องแล้ว
- ฟังก์ชันที่ถูก rename หรือย้ายไป schema `private` (มี `create_guest_booking` และ `pos_record_payment` เป็นต้น) มี wrapper ใน `public` พร้อม grant ใหม่ครบ
- Edge Function ทั้ง 13 ตัวมีโค้ดในแอปเรียกใช้ และ deploy บน production แล้วทั้งหมด

## บัคเงียบที่ยืนยันแล้ว (เรียงจากร้ายแรงสุด)

### 1. หน้า "ตรวจสอบการจอง" ของ Guest ค้นหาไม่ได้เลยบน production (ความร้ายแรง: สูง)
- **ที่:** [guest-booking-lookup/index.ts:38](supabase/functions/guest-booking-lookup/index.ts#L38) เรียก `guest_bookings_by_phone` ซึ่งสร้างใน [20261117000035_guest_booking_lookup.sql:48](supabase/migrations/20261117000035_guest_booking_lookup.sql#L48) · หน้าเรียกใช้คือ [check-booking.vue:39](apps/customer/pages/check-booking.vue#L39)
- **เกิดอะไรขึ้น:** Edge Function `guest-booking-lookup` deploy ขึ้น production แล้ว (v1 เมื่อ 2026-11-10) แต่ **migration 035 ยังไม่ได้ push** ฟังก์ชัน SQL ที่มันเรียกจึงยังไม่มี ทุกคำขอจะได้ 500 `INTERNAL_ERROR` ส่วน `edgeErrorText` ฝั่งลูกค้าไม่มีข้อความสำหรับรหัสนี้ ลูกค้าจึงเห็นแค่ "ค้นหาไม่สำเร็จ กรุณาลองใหม่" ซึ่งลองกี่ครั้งก็ไม่ผ่าน
  ถ้า deploy หน้าเว็บลูกค้าไปก่อน migration ปัญหาจะกระจายไปด้วย เพราะเมนู ([useAppNav.ts:22](apps/customer/composables/useAppNav.ts#L22)) และหน้า [t/[token].vue:44](apps/customer/pages/t/[token].vue#L44) ลิงก์มาหน้านี้
- **หลักฐาน:** `supabase migration list --remote` → `{"local":"20261117000035","remote":""}` · `supabase functions list` → `guest-booking-lookup ACTIVE version 1 verify_jwt false`
- **แก้:** push migration 035 ก่อนหรือพร้อมกับ deploy แอป customer (migration นี้ยังเปลี่ยน index `booking_tracking_tokens_one_active` และ `private.issue_tracking_token` ด้วย) และควรเพิ่ม `INTERNAL_ERROR` ใน map ของ `edgeErrorText` ฝั่งลูกค้า ให้ข้อความไม่ชวนลองซ้ำ

### 2. พนักงานเห็น "ไม่มีเวลาว่าง" ทั้งที่จริงคือโหลดคิวว่างไม่สำเร็จ ทำให้อาจปฏิเสธลูกค้า (ความร้ายแรง: สูง)
- **ที่:** [pos.vue:176-181](apps/staff/pages/pos.vue#L176) (`pos_available_starts`) และ [bookings.vue:257-261](apps/staff/pages/bookings.vue#L257) (`get_available_slots`)
- **เกิดอะไรขึ้น:** ถ้า RPC error (หมดสิทธิ์สาขา, session หมด, เน็ตหลุด หรือ exception ใน SQL) โค้ดตั้ง `starts`/`slots` เป็น `[]` แล้ว template แสดงข้อความ "วันนี้ไม่มีเวลาว่างสำหรับบริการนี้" หรือ "ไม่มีเวลาว่างในวันนี้" ทั้ง walk-in และการจองแทนลูกค้าจะถูกบอกว่าคิวเต็ม
- **หลักฐาน:** `starts.value = err ? [] : (...)` และ `slots.value = error ? [] : (...)` · ฝั่งลูกค้า [book.vue:107](apps/customer/pages/book.vue#L107) ทำถูกแล้ว คือเก็บ `slotError` แยกไว้แสดง
- **แก้:** เก็บ error ไว้ใน state แยก (เช่น `startsError`) แล้วแสดงใน template ก่อน empty state แบบเดียวกับ `book.vue`

### 3. บิลค้างชำระและทิปเงินสดที่ยังไม่จ่ายหายไปจากหน้า POS และแดชบอร์ด โดยไม่มีข้อความเตือน (ความร้ายแรง: กลาง)
- **ที่:** [pos.vue:37](apps/staff/pages/pos.vue#L37) (`pos_finance_board`) · [index.vue:29](apps/staff/pages/index.vue#L29) (`staff_dashboard_finance`) · [checkout/[orderId].vue:47](apps/staff/pages/checkout/[orderId].vue#L47) (`pos_board`)
- **เกิดอะไรขึ้น:** โค้ดอ่านแค่ `{ data }` ถ้า RPC พัง `data` จะเป็น `null` แล้วการ์ด "ต้องจัดการ" (ยอดค้างชำระและปุ่มจ่ายทิป) กับการ์ดยอดเงินบนแดชบอร์ดจะหายไปเลย ดูเหมือน "ไม่มียอดค้าง" ส่วนหน้า checkout ถ้า `pos_board` พัง dropdown "ทิปให้หมอ" จะว่าง ทำให้เลือกหมอที่จะรับทิปไม่ได้
- **หลักฐาน:** `const { data } = await supabase.rpc('pos_finance_board', ...)` ตามด้วย `finance.value = (data ?? null)` · หน้า [payments.vue:24](apps/staff/pages/payments.vue#L24) เรียก RPC เดียวกันแต่เช็ก error และแสดง `financeError` ถูกต้องแล้ว
- **แก้:** ห่อด้วย `must()` ใน try/catch ที่มีอยู่ (index.vue) หรือเก็บ error ไว้แสดงแบบ payments.vue

### 4. ข้อมูลลูกค้าที่โหลดไม่สำเร็จแสดงเป็น "ไม่พบ" หรือ "ไม่มี" (ความร้ายแรง: กลาง/ต่ำ)
- [customer bookings/[id].vue:21](apps/customer/pages/bookings/[id].vue#L21) (`my_booking`): ถ้า error จะขึ้น "ไม่พบการจองนี้ การจองอาจถูกลบหรือเป็นของบัญชีอื่น" ทำให้ลูกค้าตกใจว่าการจองหาย
- [customer index.vue:35](apps/customer/pages/index.vue#L35) (`my_bookings`): ถ้า error การ์ดนัดครั้งถัดไปจะหายไปเฉย ๆ
- [staff my-work.vue:37](apps/staff/pages/my-work.vue#L37) (`my_earnings`): ถ้า error (เช่นเลือกช่วงเกิน 62 วัน) ส่วน "รายได้ที่ร้านจะจ่าย" จะหายไปโดยไม่บอกเหตุผล
- [staff queue.vue:372](apps/staff/pages/queue.vue#L372) (`branch_attendance_today`): ถ้า error รายชื่อในหน้าลงเวลาจะว่าง
- **แก้:** เช็ก `error` แล้วตั้ง state error ที่ template แสดงจริง (สำหรับ my_booking ให้แยก "error" ออกจาก "ไม่พบ")

## น่าสงสัย (ยืนยันไม่ได้จากโค้ดอย่างเดียว)
- **โค้ด Edge Function ที่ deploy อยู่อาจไม่ตรงกับโค้ดในเครื่อง:** ส่วนใหญ่ deploy ครั้งล่าสุดวันที่ 4–5 พ.ย. (v1–v5) แต่ hash ของ bundle เทียบกับไฟล์ในเครื่องโดยตรงไม่ได้ ถ้าหลังจากนั้นมีแก้ `_shared/http.ts` หรือ function ใด ควร deploy ใหม่ทั้งชุดก่อนขึ้นจริง วิธีตรวจคือดูว่า `git log -- supabase/functions` มี commit หลังวันที่ deploy (`updated_at` ใน `supabase functions list`) หรือไม่
- **Function ที่ต้อง login (`verify_jwt = true`):** `customer-erasure`, `pos-payment-slip`, `staff-create`, `staff-set-status` และ `queue-pin-action` ไม่อยู่ใน config.toml และบน production ก็เป็น `verify_jwt: true` ตรงกัน ทั้งหมดเรียกผ่าน `useEdgeFunction` ของแอป staff ซึ่งแนบ JWT เสมอ จึงไม่มีปัญหา **ยกเว้น** `queue-pin-action` ที่ใช้ device token + PIN ถ้าเครื่องประจำสาขาเคยถูกใช้โดยไม่มี session (ล็อกเอาต์ไปแล้ว แต่ยังเปิดหน้าคิวอยู่) gateway จะตอบ 401 ซึ่งเบราว์เซอร์แสดงเป็น CORS error ควรทดสอบบนเครื่องสาขาจริงหลัง session หมดอายุ

## ไฟล์/โค้ดที่ไม่ได้ใช้
| รายการ | ประเภท | แนะนำ |
|---|---|---|
| `public.change_my_pin` ([20261104000009_devices_and_staff_pins.sql:276](supabase/migrations/20261104000009_devices_and_staff_pins.sql#L276)) | SQL function (grant ให้ authenticated) | **ฟีเจอร์ครึ่งเดียว** ยังไม่มีหน้าให้พนักงานเปลี่ยน PIN เอง (ตอนนี้มีแค่ผู้จัดการตั้ง PIN ผ่าน `set_staff_pin`) ให้เลือกว่าจะทำหน้าเปลี่ยน PIN หรือปล่อยไว้ ไม่ควรลบเพราะอยู่ใน migration เก่า |
| `public.bootstrap_company` | SQL function (service_role) | **เก็บไว้** ใช้จาก [tools/bootstrap/create-company.mjs:66](tools/bootstrap/create-company.mjs#L66) ตอนสร้างบริษัทแรก และมี test 16 |

ไม่พบ Edge Function ที่ไม่มีใครเรียก

## ตั้งใจไว้ / ไม่ใช่ปัญหา
- `queue_call_start` ถูก drop แล้วสร้างใหม่ใน migration 033 พร้อม grant ครบ และพารามิเตอร์ตรงกับ [queue.vue:160](apps/staff/pages/queue.vue#L160)
- ตัวตรวจพารามิเตอร์แจ้ง `save_branch_service_pricing`, `set_employee_guarantee` และ `set_guarantee_override` ไม่ตรง แต่ดูแล้วเป็น false positive จากคอมเมนต์และวงเล็บซ้อนในโค้ด พารามิเตอร์ตรงจริง
- `customer-erasure` / `staff-set-status` ตอบ 207 พร้อม `auth_synced: false` และแอปแสดงข้อความแยกกรณีนี้ถูกต้อง
- [login.vue:94](apps/staff/pages/login.vue#L94) `attendance_clock` ข้าม error เฉพาะ code `23514`/`42501` โดยตั้งใจ (ลงเวลาไปแล้ว หรือไม่ใช่พนักงานสาขา) และมีคอมเมนต์อธิบาย
- `queue.vue` ใช้ `act()` ที่ห่อ `must()` ส่วน `queue_call` และ `queue_handover` เช็ก error เองพร้อมจัดการ hint `OFF_SHIFT`
- `guest_bookings_by_phone` revoke จาก anon/authenticated แล้ว grant ให้ service_role เท่านั้น ถูกต้องสำหรับการเรียกผ่าน Edge Function
- Edge Function ทุกตัวตอบ error ด้วย status 4xx/5xx และ `error_code` ไม่พบตัวที่ตอบ 200 พร้อม error ใน body
- ไม่พบ secret (`Deno.env.get`) ที่ขาดใน `.env.example`
- `useCustomer.ts` (`my_customer`) และ `usePolicies` / `useCompany` เช็ก error แล้ว

---

**จะให้แก้ข้อไหนบ้าง?** (เลือกได้หลายข้อ)
1. **แนะนำ:** ข้อ 2 + 3: แสดง error แทน "ไม่มีเวลาว่าง" หรือ "ไม่มียอดค้าง" ในหน้า POS, การจอง, แดชบอร์ด และ checkout
2. ข้อ 4: แยก error ออกจาก empty state ในหน้าลูกค้าและหน้างานของฉัน
3. ข้อ 1 (ส่วนโค้ด): เพิ่มข้อความสำหรับ `INTERNAL_ERROR` ใน `edgeErrorText` ฝั่งลูกค้า ส่วนการ push migration 035 ขึ้น production ผมไม่ได้ทำให้ ต้องสั่งเองหรือยืนยันให้ผมรันครับ
4. `change_my_pin`: ทำหน้าให้พนักงานเปลี่ยน PIN เอง หรือปล่อยไว้ก่อน
