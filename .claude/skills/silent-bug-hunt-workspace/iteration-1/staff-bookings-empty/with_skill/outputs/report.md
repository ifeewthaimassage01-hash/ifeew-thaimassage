## สรุป
ตรวจหน้า `apps/staff/pages/bookings.vue` และ RPC `staff_bookings` (สแกนอัตโนมัติเจอ 2 จุดในไฟล์นี้ แล้วอ่านทั้ง flow การโหลดรายการเอง)
→ สาเหตุที่เป็นไปได้ของ "รายการไม่ขึ้น ไม่มี error" **4 ข้อ**, บัคเงียบอื่นในหน้าเดียวกัน 3 ข้อ, ตรวจแล้วไม่ใช่ปัญหา 5 ข้อ

ข้อสังเกตก่อน: ตัวโหลดหลัก `load()` **ไม่ได้กลืน error** เพราะใช้ `must()` กับ `fail()` และแสดงผ่าน `MessageAlert` ถูกต้องแล้ว
ถ้า RPC พังจริงจะมีข้อความแดงขึ้น อาการ "ว่างเปล่าแต่ไม่มี error" จึงน่าจะเกิดในกรณีที่ RPC **สำเร็จ** (หรือไม่ถูกเรียกเลย) แต่หน้าแสดงผลว่าง

## สาเหตุที่เป็นไปได้ (เรียงจากน่าจะเป็นมากสุด)

### 1. ตัวกรองเริ่มต้น "กำลังดำเนินการ" ซ่อนการจองที่จบแล้ว แต่หน้าขึ้นว่า "ไม่มีการจองในวันนี้"
- **ที่:** [bookings.vue:34](apps/staff/pages/bookings.vue#L34), [bookings.vue:39-45](apps/staff/pages/bookings.vue#L39-L45), [bookings.vue:323](apps/staff/pages/bookings.vue#L323)
- **เกิดอะไรขึ้น:** `statusFilter` เริ่มที่ `'ACTIVE'` ซึ่งแสดงเฉพาะ `PENDING / CONFIRMED / CHECKED_IN` ส่วนการจองที่เป็น `COMPLETED`, `CANCELLED`, `NO_SHOW`, `EXPIRED` ถูกซ่อนหมด พอปิดบิลลูกค้าของวันนั้นครบแล้ว (เช่น ช่วงเย็น) หรือเปิดดูวันที่ผ่านมา รายการจะหายทั้งหมด แล้ว empty state ขึ้นว่า **"ไม่มีการจองในวันนี้"** ทั้งที่มีการจองอยู่จริง (และยังเขียนว่า "วันนี้" แม้กำลังดูวันอื่น)
- **หลักฐาน:**
  ```ts
  const statusFilter = ref<'ALL' | 'ACTIVE' | 'REVIEW'>('ACTIVE')
  : ['PENDING', 'CONFIRMED', 'CHECKED_IN'].includes(r.status)
  <EmptyState v-else-if="!visible.length" :title="statusFilter === 'REVIEW' ? 'ไม่มีสลิปรอตรวจ' : 'ไม่มีการจองในวันนี้'">
  ```
- **แก้:** แยกกรณี `rows.length === 0` (ไม่มีการจองจริง) ออกจากกรณี `rows.length > 0 && visible.length === 0` (มีการจองแต่ถูกกรองออก) กรณีหลังให้ขึ้นว่า "ไม่มีการจองที่กำลังดำเนินการ · มีอีก N รายการ" พร้อมปุ่มสลับไป "ทั้งหมด" และให้ข้อความใช้วันที่ที่เลือกแทนคำว่า "วันนี้"
- **ความร้ายแรง:** กลาง (พนักงานเข้าใจว่าวันนั้นไม่มีการจอง)

### 2. กดเปลี่ยนวันเร็ว ๆ แล้วผลของวันก่อนหน้ามาทับวันที่เลือกอยู่ (race condition)
- **ที่:** [bookings.vue:48-62](apps/staff/pages/bookings.vue#L48-L62)
- **เกิดอะไรขึ้น:** `watch([date, branch], load)` ยิง RPC ทุกครั้งที่เปลี่ยนวันหรือสาขา แต่ไม่ทิ้งผลของคำขอที่ล้าสมัย ถ้ากด ‹ › หลายครั้งหรือสลับสาขาเร็ว ๆ คำตอบที่มาถึงทีหลังจะเขียนทับ `rows` หน้าจึงอาจแสดงรายการของวันหรือสาขาอื่น (ซึ่งอาจว่าง) ในขณะที่ช่องวันที่แสดงอีกวัน และไม่มี error ใด ๆ ขึ้น นอกจากนี้ `loading` ถูกปิดโดยคำขอที่เสร็จก่อน ไม่ใช่คำขอล่าสุด ส่วน `submitCreate` ([bookings.vue:289-290](apps/staff/pages/bookings.vue#L289-L290)) เปลี่ยน `date` (ซึ่งไปเรียก watch อยู่แล้ว) แล้วยัง `await load()` ซ้ำอีกครั้ง กลายเป็น 2 คำขอซ้อนกัน
- **หลักฐาน:**
  ```ts
  rows.value = (await must(supabase.rpc('staff_bookings', { ... p_date: date.value }))) as ...
  watch([date, () => activeBranch.value?.branch_id], load, { immediate: true })
  ```
- **แก้:** ใช้ตัวนับคำขอ (`const seq = ++loadSeq; ... if (seq !== loadSeq) return`) ก่อนเขียน `rows` และ `loading` หรือใช้ `onCleanup` ของ watch แล้วลบ `await load()` ที่ซ้ำใน `submitCreate` (หรือเรียกเฉพาะตอนที่วันไม่เปลี่ยน)
- **ความร้ายแรง:** กลาง (เกิดแค่ "บางที" ตรงกับอาการที่เล่ามา)

### 3. ไม่มีสาขาที่เลือกอยู่ → `load()` จบเงียบ ๆ แล้วหน้าขึ้นว่า "ไม่มีการจองในวันนี้"
- **ที่:** [bookings.vue:49](apps/staff/pages/bookings.vue#L49), [useAccess.ts:18-26](apps/staff/composables/useAccess.ts#L18-L26)
- **เกิดอะไรขึ้น:** `activeBranch` เป็น `null` ได้เมื่อ `my_access()` ส่งรายการสาขากลับมาว่าง ใน [20261114000028_owner_pin_login.sql](supabase/migrations/20261114000028_owner_pin_login.sql) สาขาถูกกรองด้วย `b.is_active and private.has_branch_access(b.id)` ดังนั้นพนักงานที่ยังไม่ถูกผูกกับสาขา หรือสาขาที่ถูกปิด (`is_active = false`) ยังผ่าน middleware ได้ (middleware เช็กแค่ว่ามี `company`) แต่หน้า bookings ไม่โหลดอะไรเลยและไม่บอกเหตุผล ปุ่ม "สร้างการจอง" ใน empty state ก็จะพังที่ `activeBranch.value!.branch_id` ([bookings.vue:233](apps/staff/pages/bookings.vue#L233)) ด้วย TypeError ที่ขึ้นแค่ใน console ผู้ใช้กดแล้วไม่มีอะไรเกิดขึ้น
- **หลักฐาน:** `if (!activeBranch.value) return` (ไม่มี state ไหนบอกผู้ใช้) · `activeBranchId.value = branches.value[0]?.branch_id ?? null`
- **แก้:** แสดง EmptyState แยกว่า "ยังไม่ได้เลือกสาขา / บัญชีนี้ยังไม่มีสาขาที่ใช้งานได้" เมื่อ `!activeBranch` และใส่ guard ใน `openCreate` แทนการใช้ `!`
- **ความร้ายแรง:** กลาง

### 4. ล้างช่องวันที่ (ปุ่ม clear ของ `<input type="date">`) → หน้าค้างอยู่กับข้อมูลเก่าและปุ่ม ‹ › ใช้ไม่ได้
- **ที่:** [bookings.vue:307-309](apps/staff/pages/bookings.vue#L307-L309), [packages/shared/src/index.ts:171](packages/shared/src/index.ts#L171)
- **เกิดอะไรขึ้น:** `date` กลายเป็น `''` แล้ว RPC คืน error ภาษาอังกฤษ (`invalid input syntax for type date`) ซึ่งยังแสดงให้เห็นอยู่ แต่ `rows` เดิมไม่ถูกล้าง และเมื่อกด ‹ › ฟังก์ชัน `addDays('')` จะ throw `RangeError: Invalid time value` ใน click handler แบบเงียบ ๆ (ขึ้นแค่ใน console) ผู้ใช้ต้องกด "วันนี้" ถึงจะกลับมาใช้ได้
- **แก้:** ไม่เรียก `load()` เมื่อ `date` ว่าง (หรือใช้ `bangkokToday()` แทน) และใส่ guard ใน `addDays`
- **ความร้ายแรง:** ต่ำ

## บัคเงียบอื่นในหน้าเดียวกัน (ไม่ใช่รายการหลัก แต่อาการคล้ายกัน)

### 5. โหลดเวลาว่างไม่สำเร็จแต่หน้าขึ้นว่า "ไม่มีเวลาว่างในวันนี้"
- **ที่:** [bookings.vue:257-260](apps/staff/pages/bookings.vue#L257-L260), [bookings.vue:485](apps/staff/pages/bookings.vue#L485)
- **เกิดอะไรขึ้น:** `slots.value = error ? [] : ...` ถ้า `get_available_slots` พัง (เรื่องสิทธิ์หรือเน็ต) พนักงานจะเห็นว่า "ไม่มีเวลาว่าง" แล้วอาจบอกลูกค้าว่าคิวเต็มทั้งที่ยังว่างอยู่ watch ตัวนี้ยังมี race แบบเดียวกับข้อ 2 ด้วย (เมื่อเปลี่ยนบริการหรือวันเร็ว ๆ)
- **แก้:** เมื่อมี `error` ให้เรียก `fail(error, 'โหลดเวลาว่างไม่สำเร็จ')` แทนการตั้งค่าเป็น `[]`

### 6. รายการบริการในหน้าสร้างการจองว่างเปล่าเงียบ ๆ
- **ที่:** [bookings.vue:230-235](apps/staff/pages/bookings.vue#L230-L235) (สแกนจับได้: `unchecked-supabase`)
- **เกิดอะไรขึ้น:** โค้ดดึงแค่ `{ data }` แล้วใช้ `data ?? []` ถ้า query view `v_public_branch_services` พัง dropdown บริการจะว่างโดยไม่มีข้อความบอก
- **แก้:** ห่อด้วย `must()` แล้วใส่ `fail(e, 'โหลดรายการบริการไม่สำเร็จ')`

### 7. รูปสลิปไม่ขึ้นและไม่มีข้อความเตือน
- **ที่:** [bookings.vue:86-87](apps/staff/pages/bookings.vue#L86-L87) (สแกนจับได้: `unchecked-supabase`)
- **เกิดอะไรขึ้น:** ถ้า `createSignedUrl` ล้มเหลว (storage policy หรือไฟล์หาย) `slipUrl` จะเป็น `null` dialog จึงไม่มีรูปและไม่มีคำเตือน พนักงานอาจอนุมัติโดยดูแค่ตัวเลข
- **แก้:** เช็ก `error` แล้วแสดงใน dialog ว่า "โหลดรูปสลิปไม่สำเร็จ"
- **ความร้ายแรง:** กลางถึงสูง (เกี่ยวกับการอนุมัติเงินมัดจำ)

## น่าสงสัย (ยืนยันไม่ได้จากโค้ดอย่างเดียว)
- **ฐานข้อมูลที่ deploy อยู่ไม่ตรงกับ migration:** ถ้า production ไม่มี `staff_bookings` จะได้ error (ไม่เงียบ) แต่ถ้าเป็นเวอร์ชันเก่าที่กรองต่างออกไปอาจได้ `[]` ตรวจได้ด้วย `npx supabase migration list` (อ่านอย่างเดียว) ว่า apply `20261107000019` แล้ว
- **ขอบเขตของวัน:** RPC ตัดช่วงด้วย `p_date::timestamp at time zone v_tz` (Asia/Bangkok) ซึ่งถูกต้องตามโค้ด แต่ถ้ามีการจองที่ถูกสร้างจากที่อื่น (เช่น seed หรือสคริปต์ใน `tools/`) ด้วย `starts_at` ผิด timezone มันจะไปโผล่อีกวัน ตรวจด้วย SQL: `select starts_at at time zone 'Asia/Bangkok' from bookings where branch_id = '...' order by starts_at desc limit 20`
- **วิธีเช็กเร็วว่าเป็นข้อ 1 หรือไม่:** วันที่เจออาการ ให้กดตัวกรอง "ทั้งหมด" ถ้ารายการโผล่ขึ้นมาก็คือข้อ 1

## ไฟล์/โค้ดที่ไม่ได้ใช้
ไม่พบในหน้านี้ (คำขอนี้เจาะจงหน้า bookings จึงไม่ได้ไล่หา dead code ทั้งโปรเจกต์)

## ตั้งใจไว้ / ไม่ใช่ปัญหา
- `load()` ใช้ `must()` + `fail()` + `finally { loading = false }` จึงแสดง error จริงและไม่ค้าง
- เมื่อไม่มีสิทธิ์ในสาขา `staff_bookings` จะ **raise** `ไม่มีสิทธิ์ในสาขานี้` (ไม่คืน `[]` แบบเงียบ) เพราะ `require_branch_access` ทำงานถูกต้อง
- `v_tz` เป็น null ไม่ได้ เพราะ `company_settings.timezone` เป็น `not null default 'Asia/Bangkok'` และถูก insert ตอนสร้างบริษัท
- inner join กับ `public.customers` ไม่ตัดแถวทิ้ง เพราะ `bookings.customer_id` เป็น `not null` และ function เป็น `security definer` (RLS ไม่กรอง)
- `r.items.map(...)` ไม่ crash เพราะ `create_booking_core` บังคับให้มีรายการอย่างน้อย 1 รายการเสมอ

---

ยังไม่ได้แก้ไฟล์ใดในโปรเจกต์

**จะให้แก้ข้อไหนครับ?** (แนะนำให้ทำ 1, 2, 3, 5, 7 ก่อน เพราะตรงกับอาการและกระทบงานจริง)
- [ ] 1. แยกข้อความ "ไม่มีการจอง" กับ "ถูกตัวกรองซ่อน" และแสดงวันที่ที่เลือก
- [ ] 2. กัน race ของ `load()` และลบการโหลดซ้ำใน `submitCreate`
- [ ] 3. Empty state เมื่อไม่มีสาขา และ guard ปุ่มสร้างการจอง
- [ ] 4. กันช่องวันที่ว่าง
- [ ] 5. แสดง error เมื่อโหลดเวลาว่างไม่สำเร็จ (และกัน race)
- [ ] 6. แสดง error เมื่อโหลดรายการบริการไม่สำเร็จ
- [ ] 7. แสดงคำเตือนเมื่อโหลดรูปสลิปไม่สำเร็จ
