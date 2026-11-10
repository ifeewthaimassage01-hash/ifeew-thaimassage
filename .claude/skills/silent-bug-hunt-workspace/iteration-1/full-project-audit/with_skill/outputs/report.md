## สรุป
สแกนเจอ 95 จุดที่ต้องสงสัย แล้วเปิดดูโค้ดทุกข้อที่ระดับ high/medium พร้อมเช็กสถานะ production แบบอ่านอย่างเดียว (`supabase functions list`, `supabase migration list --remote`, `curl -X OPTIONS`) ผลคือ
- **บัคเงียบที่ยืนยันแล้ว 11 ข้อ** (บางข้อรวมหลายจุดที่เป็นแบบเดียวกัน)
- **ไฟล์/โค้ดที่ไม่ได้ใช้ 7 รายการ** (รวมชิ้นส่วน shadcn 29 ไฟล์ไว้ 1 แถว)
- **ตั้งใจไว้หรือไม่ใช่ปัญหา 12 ข้อ**

ต้นเหตุที่เจอบ่อยที่สุดคือโค้ดดึงแค่ `{ data }` จาก supabase แล้วใช้ `data ?? []` หรือ `data ?? null` ต่อเลย ถ้า RPC หรือ RLS พัง หน้าจอจะขึ้นว่า "ว่าง" หรือซ่อนส่วนนั้นไป แทนที่จะแจ้งว่าโหลดไม่สำเร็จ

---

## บัคเงียบที่ยืนยันแล้ว (เรียงจากร้ายแรงสุด)

### 1. [สูง] หน้า "ตรวจสอบการจอง" ด้วยเบอร์โทรใช้ไม่ได้บน production ลูกค้าเห็นแค่ "ค้นหาไม่สำเร็จ กรุณาลองใหม่"
- **ที่:** [check-booking.vue:39](apps/customer/pages/check-booking.vue#L39) → [guest-booking-lookup/index.ts:38](supabase/functions/guest-booking-lookup/index.ts#L38) → [20261117000035_guest_booking_lookup.sql](supabase/migrations/20261117000035_guest_booking_lookup.sql)
- **เกิดอะไรขึ้น:** Edge Function `guest-booking-lookup` ถูก deploy แล้ว (ACTIVE, `verify_jwt=false` ตรงกับ config.toml) แต่ migration 035 ที่สร้าง `guest_bookings_by_phone` และคอลัมน์ `purpose` **ยังไม่ได้ push ขึ้น production** ทุกครั้งที่ค้นหา RPC จึงพัง function ตอบ 500 `INTERNAL_ERROR` ลูกค้าเห็นข้อความกลาง ๆ ส่วนสาเหตุจริงอยู่แค่ใน log ของ function ตอนนี้ลิงก์ไปหน้านี้มีอยู่แล้วทั้งในเมนู ([useAppNav.ts:22](apps/customer/composables/useAppNav.ts#L22)) และในข้อความ error ของ [t/[token].vue:44](apps/customer/pages/t/[token].vue#L44)
- **หลักฐาน:** `npx supabase migration list --remote` ได้ `{ local: '20261117000035', remote: '' }` เป็นรายการเดียวที่ไม่ตรง ส่วน `functions list` มี `guest-booking-lookup` version 1 สถานะ ACTIVE
- **แก้:** push migration 035 ก่อน deploy แอป customer ที่มีเมนูนี้ (ผมไม่ได้ push ให้) หรือถ้ายังไม่พร้อมก็ซ่อนเมนูไว้ก่อน เพิ่มเติมได้อีกอย่างคือให้ function log `error.code` และให้ `edgeErrorText` แยกกรณี `INTERNAL_ERROR` ออกจาก "ลองใหม่"

### 2. [สูง] หน้าชำระเงิน: ถ้าโหลดรายชื่อหมอไม่ได้ จะจ่ายเงินพร้อมทิปไม่ได้ ปุ่มชำระเงินกดไม่ได้โดยไม่มีคำอธิบาย
- **ที่:** [checkout/[orderId].vue:47](apps/staff/pages/checkout/[orderId].vue#L47)
- **เกิดอะไรขึ้น:** `pos_board` ถูกเรียกแบบไม่เช็ก error พอพังจะได้ `therapists = []` ช่อง "ทิปให้หมอ" ไม่มีตัวเลือกเลย ขณะที่ `canPay` บังคับให้ต้องเลือกหมอเมื่อ `tip > 0` แคชเชียร์เลยเก็บเงินไม่ได้และไม่รู้สาเหตุ
- **หลักฐาน:** `therapists.value = ((data ?? null) as ...)?.therapists ?? []` และ `if (tip.value > 0 && !tipEmployee.value) return false`
- **แก้:** ห่อด้วย `must()` แล้วส่ง error เข้า `fail(e, 'โหลดรายชื่อหมอไม่สำเร็จ')` แบบเดียวกับ `load()` ด้านบน

### 3. [สูง] หน้า POS: ถ้า `pos_finance_board` พัง กล่อง "ต้องจัดการ" (บิลค้างชำระ, ทิปเงินสดค้างจ่าย) จะหายไปทั้งกล่อง
- **ที่:** [pos.vue:37](apps/staff/pages/pos.vue#L37)
- **เกิดอะไรขึ้น:** ถ้า `finance` เป็น `null` เงื่อนไข `v-if="finance && ..."` จะซ่อนกล่องทั้งหมด badge สถานะบิลในแต่ละ order ก็หายด้วย และปุ่มจะขึ้น "ชำระเงิน" แม้ order นั้นจ่ายครบแล้ว พนักงานจะเข้าใจว่าไม่มียอดค้าง
- **แก้:** ใช้ `must()` แล้วตั้งข้อความ error ที่ template แสดงจริง (แบบ `MessageAlert`)

### 4. [กลาง] แดชบอร์ดพนักงาน: การ์ด "ยอดรับวันนี้ / ยอดค้างชำระ / คำขอยกเลิกรายจ่าย" หายไปเฉย ๆ
- **ที่:** [index.vue:29](apps/staff/pages/index.vue#L29)
- **เกิดอะไรขึ้น:** `staff_dashboard` ถูกห่อด้วย `must()` แล้ว แต่ `staff_dashboard_finance` ที่อยู่บรรทัดถัดไปยังไม่ได้ห่อ ถ้าพังจะได้ `money = null` แล้ว `v-if="money"` ซ่อนการ์ดเงินทั้งหมด (RPC นี้ใช้สิทธิ์ระดับสาขาเหมือนกัน การซ่อนไว้จึงไม่ใช่เรื่องสิทธิ์ที่ตั้งใจ)
- **แก้:** เปลี่ยนเป็น `money.value = await must(...)` ซึ่งจะเข้า `catch` ที่ตั้ง `error.value` ไว้อยู่แล้ว

### 5. [กลาง] เปิดหน้าต่าง "จองให้ลูกค้า / Walk-in / ต่อเวลา" แล้วรายการบริการว่าง
- **ที่:** [bookings.vue:230](apps/staff/pages/bookings.vue#L230), [pos.vue:122](apps/staff/pages/pos.vue#L122), [queue.vue:294](apps/staff/pages/queue.vue#L294)
- **เกิดอะไรขึ้น:** ทั้งสามที่โหลด `v_public_branch_services` ด้วย `catalog.value = (data ?? [])` ถ้า query พัง พนักงานจะเห็นว่าไม่มีบริการให้เลือก ทำรายการต่อไม่ได้ และไม่มีข้อความบอก
- **แก้:** ทำเป็น helper ตัวเดียว `loadBranchCatalog(branchId)` ที่ใช้ `must()` ซึ่งจะลดโค้ดซ้ำ 3 จุดไปด้วย

### 6. [กลาง] เรียกหมอฟรีแลนซ์: ช่อง "มีค่าน้ำมัน" ถูกปิดไว้เงียบ ๆ ทำให้ค่าน้ำมันไม่ถูกบันทึกเป็นรายจ่าย
- **ที่:** [queue.vue:137](apps/staff/pages/queue.vue#L137)
- **เกิดอะไรขึ้น:** ถ้าอ่าน `company_settings` ไม่ได้ จะได้ `fuelSetting = 0` แล้ว checkbox ค่าน้ำมันจะถูก disable ([queue.vue:558](apps/staff/pages/queue.vue#L558)) พนักงานจะเห็นเหมือนร้านยังไม่ได้ตั้งค่าน้ำมัน รายจ่ายจริงจึงไม่ถูกบันทึก
- **แก้:** เช็ก `error` แล้วแสดงข้อความ ไม่ควรถือว่าเป็น 0

### 7. [กลาง] ตรวจสลิปมัดจำ / ดูสลิปชำระเงิน / ดูรูปใบเสร็จรายจ่าย: รูปไม่ขึ้น หรือกดแล้วไม่มีอะไรเกิดขึ้น
- **ที่:** [bookings.vue:86](apps/staff/pages/bookings.vue#L86), [checkout/[orderId].vue:184](apps/staff/pages/checkout/[orderId].vue#L184), [expenses.vue:104](apps/staff/pages/expenses.vue#L104)
- **เกิดอะไรขึ้น:** `createSignedUrl` ไม่ได้เช็ก error ในหน้าต่างอนุมัติหรือปฏิเสธมัดจำ รูปสลิปจะไม่แสดง (`v-if="slipUrl"`) แต่ปุ่มอนุมัติยังกดได้ ส่วนอีกสองที่ `window.open` จะไม่ทำงานเลย
- **แก้:** ถ้าไม่ได้ `signedUrl` ให้แสดงข้อความ "เปิดรูปสลิปไม่สำเร็จ" และในหน้าต่างมัดจำควร disable ปุ่มอนุมัติไว้จนกว่ารูปจะโหลดได้

### 8. [กลาง] สมาชิกที่ login อยู่อาจถูกพาไปจองแบบ Guest ทำให้การจองไม่ขึ้นใน "การจองของฉัน"
- **ที่:** [book.vue:51](apps/customer/pages/book.vue#L51) ร่วมกับ [customer.global.ts:13](apps/customer/middleware/customer.global.ts#L13)
- **เกิดอะไรขึ้น:** `ensure().catch(() => {})` กลืน error ของ `my_customer` ไว้ ทำให้ `customer` ยังเป็น `undefined` และ `isMember` เป็น false หน้าจองจึงแสดงฟอร์ม Guest (ชื่อ เบอร์ Turnstile) ทั้งที่ผู้ใช้ login อยู่ แล้วส่งผ่าน `guest-booking`
- **แก้:** ถ้า `user` มีค่าแต่ `ensure()` ล้มเหลว ให้แสดง error พร้อมปุ่มลองใหม่ ไม่ควรตกไปเป็นฟอร์ม Guest

### 9. [กลาง] ฝั่งลูกค้า: ถ้าโหลดพลาดจะเห็นข้อความ "ไม่พบการจองนี้" หรือ "ไม่พบบริการนี้" แทนที่จะบอกว่าโหลดไม่สำเร็จ
- **ที่:** [bookings/[id].vue:21](apps/customer/pages/bookings/[id].vue#L21), [services/[id].vue:12](apps/customer/pages/services/[id].vue#L12), [index.vue:35](apps/customer/pages/index.vue#L35) (นัดครั้งถัดไปหายไป)
- **แก้:** เช็ก `error` แล้วแสดง Alert ข้อผิดพลาดก่อน EmptyState ส่วนใน `useAsyncData` ให้ `throw error` เพื่อให้ได้ `error` ของ Nuxt

### 10. [กลาง] กดปุ่ม "เพิ่มวันหยุด" แล้วไม่มีอะไรเกิดขึ้น
- **ที่:** [branches/[id].vue:75](apps/staff/pages/branches/[id].vue#L75)
- **เกิดอะไรขึ้น:** `const { data: b } = ...single(); if (!b) return` คือถ้าอ่านสาขาไม่ได้ ฟังก์ชันจะ return ทันทีโดยไม่ตั้ง `message`
- **แก้:** ตั้ง `message.value = { type: 'error', ... }` ก่อน return หรือใช้ `company_id` จากข้อมูลสาขาที่โหลดไว้แล้วในหน้า

### 11. [ต่ำ] รายการหรือสถานะรองที่ว่างหรือผิดแบบเงียบ ๆ (แบบเดียวกันทั้งหมด)
- [settings/devices.vue:94](apps/staff/pages/settings/devices.vue#L94): ถ้าโหลดไม่ได้จะขึ้น badge "ยังไม่ได้ตั้ง" PIN ทั้งที่อาจตั้งไว้แล้ว
- [queue.vue:372](apps/staff/pages/queue.vue#L372): รายชื่อลงเวลาเข้า-ออกว่าง
- [schedules.vue:68](apps/staff/pages/schedules.vue#L68) / [:76](apps/staff/pages/schedules.vue#L76): แถวพนักงานในตารางกะหาย
- [commissions.vue:112](apps/staff/pages/commissions.vue#L112): dropdown หมอในหน้าต่างปรับค่ามือว่าง
- [employees.vue:74](apps/staff/pages/employees.vue#L74) (รูปพนักงาน), [:269](apps/staff/pages/employees.vue#L269) (ประวัติย้ายสาขาว่าง)
- [expenses.vue:43](apps/staff/pages/expenses.vue#L43): ใช้เกณฑ์ "รายจ่ายก้อนใหญ่" ค่าเริ่มต้นแทนค่าที่ตั้งไว้
- [my-work.vue:37](apps/staff/pages/my-work.vue#L37): กล่องรายได้หายไป (ถ้าช่วงวันที่ผิด จะมี error จาก `my_work_history` แสดงอยู่แล้ว จึงเงียบเฉพาะกรณีอื่น)
- [index.vue:15](apps/staff/pages/index.vue#L15): ชื่อทักทายว่าง
- **แก้:** ใช้ `must()` แล้วส่งเข้า `fail()` หรือ `message` ของแต่ละหน้า

---

## น่าสงสัย (ยืนยันไม่ได้จากโค้ดอย่างเดียว)
- **เก็บลิงก์การจองของ Guest ไว้ในเครื่อง แต่ไม่เคยนำมาใช้:** [book.vue:159-160](apps/customer/pages/book.vue#L159) เขียน `ifeew.guest_bookings` (tracking token สูงสุด 10 อัน) แต่ไม่มีที่ไหนอ่านค่านี้ไปใช้ รวมถึงหน้า `check-booking` ที่เพิ่งเพิ่มมาด้วย ผลคือเป็นฟีเจอร์ครึ่งเดียว และมีลิงก์ที่เปิดดูการจองได้ค้างอยู่ใน localStorage ของเครื่องที่อาจใช้ร่วมกัน ต้องตัดสินใจว่าจะให้ `check-booking` แสดง "การจองล่าสุดในเครื่องนี้" หรือเลิกเขียนค่านี้
- **การ update ตรงตาราง (settings, branches, services, resources, schedules, employees) ไม่มี `.select()` ต่อท้าย:** RLS ของตารางเหล่านี้ (`is_company_owner`) ตรงกับ middleware `ownerOnly` อยู่แล้ว จึงไม่น่าโดนบล็อกในการใช้งานปกติ แต่ถ้า session หมดหรือ membership หมดอายุระหว่างใช้งาน การ update จะได้ 0 แถวแล้วขึ้นว่า "บันทึกแล้ว" วิธีตรวจคือลองตั้ง `effective_to` ของ membership ให้หมดอายุใน local แล้วกดบันทึก
- **ถ้าเรียก `pos_finance_board` แล้ว error ตลอด:** ข้อ 2–4 จะเกิดพร้อมกันทั้งหมด ลองเปิด POS ด้วยบัญชี STAFF ของสาขาแล้วดู Network tab ว่า `pos_finance_board` และ `staff_dashboard_finance` ตอบ 200 หรือไม่

---

## ไฟล์/โค้ดที่ไม่ได้ใช้
| รายการ | ประเภท | แนะนำ |
|---|---|---|
| `public.change_my_pin` ([20261104000009_devices_and_staff_pins.sql:276](supabase/migrations/20261104000009_devices_and_staff_pins.sql#L276)) | SQL function | **ควรถูกใช้ (บัค?)** เพราะยังไม่มีหน้าจอให้ STAFF เปลี่ยน PIN ตัวเอง มีแค่ OWNER ตั้งให้ผ่าน `set_staff_pin` ถ้าไม่ได้ตั้งใจจะทำฟีเจอร์นี้ ให้ drop ด้วย migration ใหม่ ห้ามแก้ migration เก่า |
| `phoneSchema` ([index.ts:48](packages/shared/src/index.ts#L48)) | export | ลบได้ (โปรเจกต์ใช้ `thaiPhoneSchema` แทน) |
| `displayNameSchema` ([index.ts:53](packages/shared/src/index.ts#L53)) | export | ลบได้ |
| `SessionRow` ([index.ts:580](packages/shared/src/index.ts#L580)) | type | ลบได้ |
| type/const ที่ export เกินจำเป็น 23 ตัว (เช่น `NavItem`, `BookingStatus`, `crc16`, `ConfirmOptions`) | export | เก็บไว้ ถูกใช้ภายในไฟล์และเป็น public type ของ package |
| `public.bootstrap_company` | SQL function | เก็บไว้ ถูกเรียกจาก `tools/bootstrap/create-company.mjs` และมีเทสต์ 16 |
| ชิ้นส่วน shadcn-vue ที่ไม่ได้ใช้ 29 ไฟล์ใน `packages/ui/components/ui/` (Avatar*, DropdownMenuSub*, Select{Group,Label,Scroll*,Separator}, Sheet{Close,Footer,Overlay}, Sonner ฯลฯ) | component | เก็บไว้ ติดมากับชุด ไม่ต้องลบ |

ไม่มี component นอก `packages/ui` และไม่มีหน้า (pages) ที่ไม่ได้ใช้ ส่วนไฟล์ใหม่ที่ยังไม่ commit คือ `StaffBottomNav.vue` ถูกใช้ใน [layouts/default.vue:129](apps/staff/layouts/default.vue#L129) และ `check-booking.vue` มีลิงก์จากเมนูแล้ว

---

## ตั้งใจไว้ / ไม่ใช่ปัญหา
- [customer.global.ts:13](apps/customer/middleware/customer.global.ts#L13) `catch {}`: มีคอมเมนต์บอกว่าไม่บล็อกหน้าสาธารณะเมื่อเน็ตหลุด ถือว่าถูกต้อง (แต่ดูผลกระทบในข้อ 8)
- [useWorkDay.ts:27,35](apps/staff/composables/useWorkDay.ts#L27) `catch {}` รอบ localStorage: เบราว์เซอร์ที่ไม่มี storage ต้องไม่ทำให้ login พัง
- [AppAccountMenu.vue:9-10](apps/customer/components/AppAccountMenu.vue#L9): ถ้าโหลดไม่ได้จะ fallback ไปแสดงอีเมล ไม่ทำให้ผู้ใช้เข้าใจผิด
- [profile.vue:32](apps/customer/pages/profile.vue#L32) `refresh().catch`: ข้อมูลยังมาจาก middleware และ `saveProfile` validate ซ้ำอยู่แล้ว ความเสี่ยงต่ำ
- Edge function ที่ไม่มีใน config.toml 5 ตัว (`customer-erasure`, `pos-payment-slip`, `queue-pin-action`, `staff-create`, `staff-set-status`): ทั้งหมดต้อง login อยู่แล้ว และบน production ก็เป็น `verify_jwt: true` ตรงกัน
- Edge function ทุกตัวในโฟลเดอร์ deploy แล้ว และ `OPTIONS` ตอบ 204 ทุกตัว จึงไม่มีความเสี่ยงแบบ "CORS error เพราะยังไม่ deploy"
- Secret ที่ function อ่าน (`ALLOWED_ORIGINS`, `TURNSTILE_SECRET_KEY`, `SLIPOK_API_KEY`) มีครบใน `.env.example`
- error_code ที่ function ส่งกลับมาตรงกับที่ `edgeErrorText` ทั้งสองแอปจัดการไว้
- `on conflict do nothing` ใน migrations: เป็น seed หรือ storage bucket และใน `idempotency_begin` มีเช็ก `if found` ต่อ ถือว่าถูกต้อง
- ไม่พบ `exception when others` หรือ BEFORE trigger ที่ `return null` แบบกลืนข้อมูล
- handler ที่ตั้ง loading/saving ในหน้าการเงิน (checkout, commissions, bookings, expenses) มี `finally` คืนค่าครบ ไม่มีจุดที่ปุ่มจะค้าง
- `my-work.vue` ถ้าเลือกช่วงวันที่เกิน 62 วัน: `my_work_history` แสดง error อยู่แล้ว

---

**จะให้แก้ข้อไหนครับ?** (ผมยังไม่ได้แก้ ลบ หรือ push อะไรทั้งนั้น)
1. **แนะนำ:** ข้อ 2–7 และ 10 ฝั่ง Staff ที่เกี่ยวกับเงินและหน้าร้าน แก้ด้วย `must()` + `fail()` ตาม pattern เดิม แล้วรัน `pnpm typecheck`
2. ข้อ 1: คุณจะ push migration 035 ขึ้น production เอง หรือให้ผมซ่อนเมนู "ตรวจสอบการจอง" ไว้ก่อน?
3. ข้อ 8–9 ฝั่ง Customer (แสดง error แทน "ไม่พบ" และไม่ให้สมาชิกตกไปเป็นฟอร์ม Guest)
4. ข้อ 11 รายการรองทั้งหมด
5. `ifeew.guest_bookings`: จะให้ `check-booking` แสดงการจองล่าสุดในเครื่องนี้ หรือเลิกเก็บค่านี้?
6. `change_my_pin`: จะทำหน้าให้หมอเปลี่ยน PIN เอง หรือ drop function นี้?
7. ลบ export ที่ไม่ได้ใช้ (`phoneSchema`, `displayNameSchema`, `SessionRow`)
