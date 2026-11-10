# ผลตรวจบัคที่พังเงียบๆ และไฟล์ที่ไม่ได้ใช้ — ifeew-thaimassage

ผมตรวจทั้ง 2 แอป (customer, staff), `packages/ui`, `packages/shared`, Edge Functions และ migrations ทั้งหมด รวมถึงงานที่ยังไม่ commit (check-booking, guest-booking-lookup, migration 035, Input แบบตัวเลข) และรัน `vue-tsc --noEmit` ทั้ง 2 แอปแล้ว ไม่มี type error ผมไม่ได้แก้ไฟล์ใดในโปรเจกต์ และไม่ได้เปิดแอปหรือรันเทสต์ DB

เรียงจากเรื่องที่ควรแก้ก่อน

## ระดับสูง: ผู้ใช้ไม่รู้ว่าทำงานไม่สำเร็จ หรือข้อมูลออกมาผิด

### 1. `<Toaster>` น่าจะไม่ถูก render เลย ทำให้ toast ทุกอันในแอปลูกค้าไม่ขึ้น
- `packages/ui/components/ui/sonner/index.ts` export ชื่อ `Toaster` แต่ Nuxt ลงทะเบียนคอมโพเนนต์จากชื่อไฟล์ (`Sonner.vue` จึงได้ชื่อ `Sonner`) และไม่สแกน `index.ts` เลย
- ใน `.nuxt/components.d.ts` ของทั้ง 2 แอปมีแค่ `Sonner` ไม่มี `Toaster` และ build เดิมใน `.output` ก็เรียก `resolveComponent("Toaster")` ตอน runtime ซึ่งจะได้แค่ warning และไม่แสดงอะไร
- ผลที่ตามมา: `apps/customer/pages/profile.vue` (บันทึกโปรไฟล์, เปิด/ปิดรับข่าว, ขอลบข้อมูล) และการยกเลิกการจองใน `apps/customer/pages/bookings/[id].vue:38,42` บอกผลทั้งสำเร็จและผิดพลาดผ่าน toast อย่างเดียว ถ้าเรียก RPC ไม่สำเร็จ ลูกค้าจะไม่เห็นอะไรเลย
- วิธีเช็ก: เปิดหน้า /profile แล้วกดบันทึก ดูใน console ว่ามี `Failed to resolve component: Toaster` หรือเปล่า
- วิธีแก้: ใช้ `<Sonner>` ในทั้ง 3 layout (`apps/customer/layouts/default.vue:86`, `apps/staff/layouts/default.vue:133`, `apps/staff/layouts/blank.vue:5`) หรือ import `Toaster` ตรงๆ

### 2. หน้าตั้งค่าบริษัทอาจเขียนค่า default ทับค่าจริง
`apps/staff/pages/settings/index.vue:35-53` ฟังก์ชัน `load()` ไม่ตรวจ `error` เลย ถ้าโหลด `company_settings` ไม่สำเร็จ (เช่น เน็ตหลุด) ฟอร์มจะแสดงค่า default ที่เขียนไว้ในโค้ด (มัดจำ 100, ยกเลิกก่อน 3 ชม. ฯลฯ) โดยไม่มีข้อความเตือน ถ้าเจ้าของร้านกด "บันทึก" ค่าจริงจะถูกเขียนทับเงียบๆ
- วิธีแก้: ถ้าโหลดไม่สำเร็จให้แสดง error และปิดปุ่มบันทึก

### 3. หน้าจอง: ถ้าเปลี่ยนวันเร็วๆ อาจได้ช่องเวลาของอีกวัน และจองผิดวันได้
`apps/customer/pages/book.vue:94-117` watch ที่เรียก `get_available_slots` ไม่ได้กันผลตอบกลับที่มาช้า ถ้าลูกค้ากดเปลี่ยนวันหรือบริการเร็วๆ ผลของคำขอเก่าที่ตอบกลับทีหลังจะทับ `slots` ของวันใหม่ หัวข้อบนจอจะเป็นวันใหม่ แต่ `slot.starts_at` ที่ส่งไปจองเป็นเวลาของวันเก่า ระบบจองให้สำเร็จโดยไม่มี error
- วิธีแก้: เก็บเลขลำดับคำขอ (request id) แล้วทิ้งผลที่ไม่ใช่คำขอล่าสุด

### 4. หน้าจองใช้ค่าคงที่ในโค้ด ไม่ได้อ่านจากการตั้งค่าบริษัท
- `book.vue:19` ใช้ `MAX_PEOPLE = 4` ตายตัว แต่เจ้าของร้านตั้ง `booking_max_items` ได้ 1–10 ถ้าตั้งเป็น 6 ลูกค้าก็เลือกได้แค่ 4 ถ้าตั้งเป็น 2 จะเลือกได้ 4 แล้วไปเจอ error ตอนกดจอง
- `book.vue:178` แถบวันที่มี 14 วันตายตัว ถ้าตั้ง `booking_max_advance_days` เป็น 7 วันที่ 8–14 จะขึ้นว่า "ไม่มีเวลาว่าง" (DB กรองทิ้งเงียบๆ ที่ `20261107000018_resources_capacity.sql:510`) และถ้าตั้งเกิน 14 ลูกค้าก็จองเกิน 14 วันไม่ได้

### 5. เงินที่รับหลังส่งปิดยอดรายวันจะไม่อยู่ในยอดที่ส่งไปแล้ว
หลัง migration 034 ฟังก์ชัน `submit_daily_closing` จะปิดกะอัตโนมัติ แล้วเก็บ `figures` เป็น snapshot ณ ตอนกดส่ง ถ้ามีการรับเงิน, ค่าน้ำมันหมอวิ่ง หรือทิปของวันเดียวกันเกิดขึ้นหลังจากนั้น `private.require_open_session` (034:77) จะเปิดกะใหม่ของวันเดิมให้เอง เพราะไม่มีจุดไหนเช็กว่าวันนั้นส่งปิดยอดไปแล้ว ยอดที่เจ้าของร้านอนุมัติจึงไม่ตรงกับเงินจริง และไม่มีคำเตือนใดๆ ส่วน `lock_financial_period` ก็ผ่านได้ เพราะวันนั้นมี closing อยู่แล้ว
- วิธีแก้ (เลือกอย่างใดอย่างหนึ่ง): ห้ามรับเงินในวันที่มี closing สถานะ SUBMITTED/APPROVED หรือทำให้ closing กลับมาเป็นสถานะ "ต้องส่งใหม่" เมื่อมีรายการเงินเพิ่ม

### 6. เมื่อโหลดข้อมูลไม่สำเร็จ หลายหน้าแสดงเป็น "ไม่มีข้อมูล" แทนที่จะแสดง error
โค้ดอ่านแค่ `{ data }` แล้วไม่สนใจ `error` ผู้ใช้จึงเห็นข้อมูลที่ผิด

| ที่ | สิ่งที่ผู้ใช้เห็นเมื่อพัง |
|---|---|
| `apps/customer/pages/bookings/[id].vue:21` | "ไม่พบการจองนี้" (ทั้งที่การจองมีอยู่) |
| `apps/customer/pages/services/[id].vue:12` | ไม่พบบริการ |
| `apps/customer/composables/useOpenToday.ts:51-68` | **ทุกสาขาขึ้นว่า "ปิดวันนี้"** |
| `apps/customer/pages/index.vue:35` | ไม่แสดงนัดถัดไป |
| `apps/staff/pages/pos.vue:37` | ไม่เห็น Invoice ค้างชำระและทิปที่ยังไม่จ่าย |
| `apps/staff/pages/pos.vue:74` (`catch { bookings = [] }`) | "ไม่มีการจองรอเช็กอิน" |
| `apps/staff/pages/index.vue:29` | ยอดขาย/ค้างชำระบนแดชบอร์ดหายไป |
| `apps/staff/pages/my-work.vue:37` | รายได้ของหมอว่าง |
| `apps/staff/pages/queue.vue:137` | ค่าน้ำมันเป็น 0 ทำให้ติ๊กค่าน้ำมันหมอวิ่งไม่ได้ โดยไม่บอกเหตุผล |
| `apps/staff/pages/expenses.vue:43` | ใช้เกณฑ์รายจ่ายใหญ่ 5000 ที่เขียนไว้ในโค้ดแทนค่าจริง |
| `apps/staff/pages/branches/[id].vue:27`, `resources.vue:39`, `services.vue:44`, `guarantees.vue:32`, `commissions.vue:112`, `checkout/[orderId].vue:47`, `bookings.vue:230`, `employees.vue:269` | รายการว่าง หรือเลือกหมอ/บริการไม่ได้ |

ในโปรเจกต์มี helper `must()` อยู่แล้ว (`apps/staff/composables/useStepUp.ts`) ใช้ตัวนี้ห่อทุกจุดที่ระบุไว้ แล้วแสดงผ่าน `MessageAlert` ได้เลย

## ระดับกลาง

### 7. ฟีเจอร์ใหม่ "ตรวจสอบการจองด้วยเบอร์โทร" (ยังไม่ commit)
- **ใครที่รู้เบอร์โทรก็ได้ token สำหรับเปิดหน้า `/t/<token>`** ของการจองทุกรายการของเบอร์นั้น (ย้อนหลัง 90 วัน) และเห็นวัน-เวลา สาขา บริการ และชื่อแบบปิดบังบางส่วน มีแค่ Turnstile กับ rate limit 10 ครั้งต่อชั่วโมงกันไว้ ควรตัดสินใจว่ายอมรับระดับความเป็นส่วนตัวนี้ได้ไหม หรือจะเพิ่ม OTP หรือให้กรอกรหัสการจองด้วย
- `packages/shared/src/database.types.ts` ยังไม่ได้ regenerate หลัง migration 035 (ไม่มีคอลัมน์ `purpose` และไม่มี `guest_bookings_by_phone`) ควรรัน `pnpm db:types`
- ตอน deploy ต้องตั้ง `ALLOWED_ORIGINS` ให้มี origin ของแอปลูกค้าบน production ไม่อย่างนั้น CORS จะตอบ `Access-Control-Allow-Origin: ''` และฝั่งลูกค้าจะเห็นแค่ข้อความ "ค้นหาไม่สำเร็จ"

### 8. ค่า Turnstile ตั้งต้นเป็น test key ที่ผ่านเสมอ
`apps/customer/nuxt.config.ts` ตั้ง `turnstileSiteKey` เป็น test key ของ Cloudflare และ `supabase/functions/.env.example` ก็ใช้ test secret ถ้าลืมตั้งทั้ง 2 ค่าตอนขึ้น production CAPTCHA จะถูกปิดไปเงียบๆ ควรให้ build หรือ function fail ถ้ายังใช้ test key ใน `appEnv=production`

### 9. `localStorage['ifeew.guest_bookings']` มีแต่เขียน ไม่มีที่อ่าน
`book.vue:159-160` คอมเมนต์บอกว่าเก็บไว้ "ให้ Guest กลับมาดูได้" แต่ทั้งโปรเจกต์ไม่มีโค้ดไหนอ่านค่านี้ ฟีเจอร์นี้จึงไม่ได้ทำงานจริง ถ้าจะใช้หน้า /check-booking แทน ก็ลบโค้ดส่วนนี้ทิ้งได้ (ข้อมูลที่เก็บเป็น token จริง การเก็บไว้ในเครื่องโดยไม่ได้ใช้ถือเป็นความเสี่ยงที่ไม่จำเป็น)

### 10. การ `update().eq()` ที่ RLS กรองทิ้งจะขึ้นว่า "สำเร็จ"
หน้า owner หลายหน้า (`branches`, `branches/[id]`, `services`, `resources`, `schedules`, `settings`) ใช้ `.update(...).eq('id', ...)` ตรงๆ ถ้า RLS ไม่ผ่าน (เช่น membership หมดอายุระหว่างใช้งาน) PostgREST จะตอบกลับสำเร็จโดยมี 0 แถว แล้วหน้าจอก็แจ้งว่า "บันทึกแล้ว" ตอนนี้ยังไม่เจอเคสที่พังจริง เพราะ policy ทุกอันใช้ `is_company_owner` และหน้าเหล่านี้เป็น `ownerOnly` อยู่แล้ว แต่ถ้าเติม `.select('id')` แล้วเช็กว่าได้ 1 แถว จะปลอดภัยกว่า

### 11. รูปพนักงานเก่าค้างใน storage
`apps/staff/pages/employees.vue:160-173` อัปโหลดรูปใหม่ไปที่ path ใหม่ทุกครั้ง แต่ไม่ลบรูปเก่า storage จะโตขึ้นเรื่อยๆ (และเป็นข้อมูลส่วนบุคคลที่ค้างอยู่)

## โค้ดและไฟล์ที่ไม่ได้ใช้งาน

**Database RPC ที่ยังเปิดให้เรียกได้ แต่ไม่มีแอปไหนเรียกแล้ว** (ส่วนใหญ่เหลือจากการเอาระบบลิ้นชักออกใน migration 034)
- `pos_open_session`, `pos_close_session`, `pos_cash_adjustment`, `pos_review_session`, `pos_sessions_list` ยัง `grant execute to authenticated` อยู่ พนักงานจึงยังเรียกผ่าน API ตรงๆ ได้ เช่น ปิดกะด้วยยอดเงินสดที่กรอกเอง ควร revoke หรือ drop
- `pos_invoice`, `change_my_pin` ไม่มีหน้าไหนเรียกใช้
- (`queue_accept`/`queue_start` ยังใช้ภายใน `device_queue_action` อยู่ อย่าลบ)

**โค้ดที่ไม่มีวันถูกเรียก**
- `apps/staff/pages/queue.vue:205` สาขา `queue_call` ใน `pick()` ทำงานไม่ถึง เพราะกรณีที่ไม่ใช่ `IN_SERVICE` ถูก `return callStart(...)` ไปก่อนแล้ว
- `packages/shared/src/index.ts` มี export ที่ไม่มีใครใช้: `SessionRow` (เหลือจากระบบกะ), `normalizeThaiPhone`, `phoneSchema`, `displayNameSchema`, `PricingSnapshot`, `BANGKOK_OFFSET`, `WorkHistoryRow`, `PaymentMethod`, `MembershipRole` (ส่วน type `BookingStatus`/`DepositStatus`/`OrderStatus`/`OrderChannel` น่าจะถูกใช้ภายใน shared เอง ควรเช็กก่อนลบ)
- `packages/ui/components/ui/sonner/Sonner.vue` ไม่ถูกใช้ (ดูข้อ 1 ซึ่งควรเปลี่ยนมาใช้ไฟล์นี้)

**ไฟล์และโฟลเดอร์**
- `.taste-skill/` มีภาพ screenshot 288 ไฟล์ (~9.7 MB) ถูก commit อยู่ใน git และไม่มีโค้ดไหนอ้างถึง ควรย้ายออกหรือใส่ไว้ใน `.gitignore`
- `apps/customer/server/`, `apps/staff/server/`, `apps/*/public/` เป็นโฟลเดอร์ว่าง
- `apps/customer/.output`, `apps/staff/.output` เป็น build เก่า (5 พ.ย.) ไม่อยู่ใน git อยู่แล้ว แต่ลบทิ้งได้ จะได้ไม่สับสน
- shadcn ที่ไม่ได้ใช้ใน `packages/ui/components/ui/` เช่น `avatar/*`, `separator`, `DropdownMenuSub*`, `DropdownMenuRadio*`, `DropdownMenuCheckboxItem`, `DropdownMenuShortcut`, `SelectGroup/Label/Separator`, `CardAction/Description/Footer`, `DialogScrollContent`, `SheetClose/Footer`, `TableCaption/Empty`, `AlertTitle` เป็นเรื่องปกติของ shadcn จะเก็บไว้ก็ได้

## สิ่งที่ตรวจแล้วไม่เจอปัญหา
- ชื่อ RPC ทุกตัวที่แอปและ Edge Function เรียกมีอยู่ใน migrations ทั้งหมด
- Edge Function ทั้ง 13 ตัวมีหน้าที่เรียกใช้ครบ และ `config.toml` ตั้ง `verify_jwt` ให้ตัวใหม่แล้ว
- ทางเดินของหมอวิ่ง (employee_id เป็น NULL) ใน `sync_commissions` และ `pos_order_view` จัดการไว้ถูกต้อง
- `vue-tsc --noEmit` ผ่านทั้ง 2 แอป (ใช้ `.nuxt` เดิมที่ generate ไว้แล้ว)

## คำถาม
1. ข้อ 7: ยอมรับได้ไหมที่ใครก็ตามที่รู้เบอร์โทรจะเห็นรายการจองของเบอร์นั้น หรืออยากให้เพิ่ม OTP หรือให้กรอกรหัสการจองด้วย
2. ข้อ 5: อยากให้ระบบ "ห้ามรับเงินหลังส่งปิดยอดแล้ว" หรือ "เปิด closing ให้ส่งใหม่อัตโนมัติ" ดี
3. ให้ผมลงมือแก้ข้อ 1–4 และข้อ 6 เลยไหม (ข้อเหล่านี้แก้ฝั่ง frontend อย่างเดียว ไม่ต้องทำ migration)
