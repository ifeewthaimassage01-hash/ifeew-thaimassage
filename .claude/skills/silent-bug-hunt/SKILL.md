---
name: silent-bug-hunt
description: ตรวจหา "บัคเงียบ" ในโปรเจกต์ ifeew-thaimassage — โค้ดที่ทำงานไม่ได้แต่ไม่แจ้ง error (error ถูกกลืน, ผล supabase ไม่เช็ก error, RLS บล็อกแล้วได้ผลว่าง, state ที่เขียนแต่ไม่เคยแสดง, function/RPC ที่เรียกแต่ไม่มีจริงหรือไม่ได้ deploy) และไฟล์/โค้ดที่ไม่ได้ใช้งาน (component, composable, export, edge function, SQL function, หน้าที่ไม่มีลิงก์) แล้วรายงานพร้อมหลักฐาน ก่อนถามว่าจะแก้ข้อไหน ใช้ทุกครั้งที่ผู้ใช้ขอให้หาบัคที่ไม่ขึ้น error, กดแล้วไม่เกิดอะไร, ข้อมูลไม่ขึ้นแต่ไม่มี error, บันทึกแล้วไม่เข้า, ตรวจโค้ดตาย/ไฟล์ขยะ/ไฟล์ที่ไม่ได้ใช้, ทำความสะอาดโค้ด, audit ก่อนขึ้น production หรือถามว่า "มีอะไรพังเงียบ ๆ อยู่ไหม" แม้จะไม่ได้พูดคำว่า silent bug ตรง ๆ
---

# Silent Bug Hunt (ifeew-thaimassage)

บัคเงียบอันตรายกว่าบัคที่ crash เพราะผู้ใช้เห็นแค่ "ไม่มีข้อมูล" หรือ "กดแล้วไม่มีอะไรเกิดขึ้น" แล้วเข้าใจว่าระบบปกติ
เป้าหมายคือหาจุดที่ **ความล้มเหลวถูกแปลงเป็นความเงียบ** และโค้ด/ไฟล์ที่ไม่มีใครใช้ แล้วรายงานให้ผู้ใช้เลือกว่าจะแก้อะไร

สแต็ก: Nuxt 4 (2 แอป `apps/customer`, `apps/staff` + layer `packages/ui`, ชนิดร่วม `packages/shared`) ·
Supabase (Postgres + RLS, migrations ใน `supabase/migrations`) · Edge Functions (Deno, `supabase/functions`, helper `_shared/http.ts`)

## ขั้นตอน

### 1. สแกนอัตโนมัติ (ได้ "ผู้ต้องสงสัย" ไม่ใช่ข้อสรุป)

```bash
node .claude/skills/silent-bug-hunt/scripts/scan.mjs            # ทั้งหมด
node .claude/skills/silent-bug-hunt/scripts/scan.mjs --only rpc,edge-function   # เฉพาะบางเช็ก
node .claude/skills/silent-bug-hunt/scripts/scan.mjs --json     # ไว้กรองต่อ
```

เช็กที่มี: `swallowed-error` · `unchecked-supabase` · `write-only-state` · `storage-key` · `rpc` · `table` ·
`edge-function` · `deno-env` · `unused-component` · `unused-export` · `unlinked-page`

ถ้าผู้ใช้ระบุขอบเขต (เช่น "เฉพาะหน้า checkout" หรือ "ไฟล์ที่เพิ่งแก้") ให้กรองผลให้เหลือเฉพาะส่วนนั้น แล้วไปอ่านไฟล์ในขอบเขตแบบละเอียดในขั้นที่ 3

### 2. ยืนยันทีละข้อ — ห้ามรายงานผลสแกนดิบ

สคริปต์ใช้ regex จึงมีทั้ง false positive และสิ่งที่ตั้งใจทำ ต้องเปิดไฟล์ดูบริบททุกข้อระดับ high/medium แล้วจัดเข้า 1 ใน 3 กลุ่ม:
**ยืนยันแล้ว** (อธิบายได้ว่าผู้ใช้จะเจออะไร) / **ตั้งใจไว้** (มีคอมเมนต์อธิบาย และ fallback ถูกต้อง) / **ไม่ใช่ปัญหา**

แนวทางตัดสินแต่ละเช็ก:

- **unchecked-supabase** — supabase-js ไม่ throw แต่คืน `{ data, error }` ถ้าดึงแค่ `data` เมื่อ RLS/RPC พัง `data` จะเป็น `null`
  แล้วหน้าแสดง "ยังไม่มีข้อมูล" แทนข้อความผิดพลาด → ยืนยันเมื่อ null ถูกตีความเป็น "ว่าง" (เช่น `data ?? []`) โดยไม่มีที่อื่นเช็ก error
  วิธีแก้ในโปรเจกต์นี้: ห่อด้วย `must()` (staff: `apps/staff/composables/useStepUp.ts`) หรือเช็ก `error` แล้วตั้ง state ที่ template แสดงจริง
- **swallowed-error** — `catch {}` / `.catch(() => {})` ถือว่า "ตั้งใจไว้" ได้ถ้ามีคอมเมนต์บอกเหตุผล และการไม่ทำอะไรไม่ทำให้ผู้ใช้เข้าใจผิด
  (เช่น middleware ที่ไม่ควรบล็อกหน้าสาธารณะเพราะเน็ตหลุด) แต่ถ้าเงียบแล้วหน้าค้าง/ข้อมูลผิด → ยืนยัน
- **write-only-state** — `error.value = ...` หรือ `failed.value = ...` ที่ template ไม่เคยแสดง = ผู้ใช้ไม่เคยเห็นข้อความผิดพลาด
- **storage-key** — key ที่เขียนแต่ไม่มีที่อ่าน หรืออ่านแค่เพื่อเขียนทับตัวเอง = ฟีเจอร์ครึ่งเดียว (เช่น `ifeew.guest_bookings`)
- **rpc / table** — เรียกชื่อที่ไม่มีใน migrations = พังตอนรันจริงแน่นอน (เว้นแต่ชื่อถูกสร้างนอก migrations) ตรวจด้วยว่าไม่ได้ถูก
  `alter function ... set schema private` ไปแล้ว · public function ที่ไม่มีใครเรียก ให้ grep ใน `supabase/` และ `tools/` ก่อน
  (อาจเป็น cron, pg_net, ใช้ตอน bootstrap หรือเรียกจาก SQL editor)
- **edge-function** — โฟลเดอร์ที่ไม่มีใน `config.toml` ใช้ `verify_jwt = true` โดยอัตโนมัติ ถ้า function ตั้งใจให้คนไม่ login เรียก
  gateway จะตอบ 401 ก่อนถึงโค้ด → browser แจ้งเป็น **CORS error** (เคยเกิดจริงในโปรเจกต์นี้) · function ที่เรียกจาก app แต่ยังไม่ deploy ก็ให้อาการเดียวกัน
- **deno-env** — secret ที่โค้ดอ่านแต่ไม่อยู่ใน `.env.example` มักลืมตั้งตอน deploy → `Deno.env.get` ได้ `undefined`
- **unused-component / unused-export / unlinked-page** — ดูกฎในหัวข้อ "ไฟล์ไม่ได้ใช้งาน" ด้านล่าง

### 3. ตรวจด้วยตา — สิ่งที่สคริปต์จับไม่ได้

อ่านโค้ดส่วนที่เกี่ยวข้อง (หน้า/flow ที่ผู้ใช้กังวล หรือหน้าที่สำคัญเรื่องเงิน: `checkout`, `pos`, `expenses`, `daily-closings`,
`commissions`) แล้วมองหารูปแบบเหล่านี้ ซึ่งเป็นสาเหตุหลักของบัคเงียบในสแต็กนี้:

1. **RLS บล็อก update/delete แบบเงียบ** — `supabase.from(t).update(...)` ที่ RLS ไม่อนุญาตจะได้ 0 แถว *ไม่มี error*
   ถ้าโค้ดไม่ `.select()` แล้วเช็กว่ามีแถวกลับมา ผู้ใช้จะเห็น "บันทึกแล้ว" ทั้งที่ไม่มีอะไรเปลี่ยน (เช็ก policy ใน migrations ประกอบ)
2. **loading ค้าง** — async handler ที่ตั้ง `loading = true` แต่ไม่ได้คืนค่าใน `finally` เมื่อ throw ปุ่มจะ disabled ตลอดไป
3. **Promise ที่ไม่ได้ await/ไม่มี catch** ใน event handler — error หายไปใน console เท่านั้น
4. **Edge Function ตอบ 200 พร้อม error ใน body** หรือ app เช็ก `error_code` ผิดชื่อจาก `_shared/http.ts`
5. **SQL ที่กลืน error** — `exception when others then null/return`, `on conflict do nothing` ที่ทำให้ insert หายเงียบ,
   `perform` ที่ทิ้งผลที่ควรตรวจ, trigger ที่ `return null` ใน BEFORE trigger (ยกเลิกแถวเงียบ ๆ)
6. **watch/computed ที่ไม่ reactive** — watch ค่าดิบ (`watch(props.x, ...)` แทน `() => props.x`), destructure จาก reactive แล้วเสีย reactivity
7. **v-if ซ่อนข้อผิดพลาด** — เงื่อนไขแสดง error ผิด หรือ empty state แสดงก่อน error state
8. **ค่าที่ถูกตัด/แปลงเงียบ** — `Number('')` = 0, `parseInt` ตัดทศนิยม, timezone (ทุกอย่างควรเป็น Asia/Bangkok ผ่าน helper ใน `@ifeew/shared`)
9. **สถานะที่ deploy จริงไม่ตรงกับโค้ด** — ใช้คำสั่งอ่านอย่างเดียวได้ เช่น `npx supabase functions list`, `npx supabase migration list`
   หรือ `curl -X OPTIONS` ไปที่ function URL (ดู `apps/*/.env` สำหรับ URL) — **ห้าม deploy/push/reset เอง**

### 4. ไฟล์ไม่ได้ใช้งาน — ระวังก่อนตัดสินว่า "ลบได้"

- Nuxt auto-import: component ใช้ชื่อไฟล์ (`packages/ui/components/ui/**` ไม่มี prefix, ที่อื่นมี prefix ตามโฟลเดอร์)
  composable/utils ถูกเรียกโดยไม่ต้อง import → ค้นด้วยชื่อ ไม่ใช่ด้วย import path
- ชิ้นส่วน shadcn-vue ใน `packages/ui/components/ui/` ที่ไม่ได้ใช้ (เช่น `SelectScrollUpButton`) ติดมากับชุด — รายงานรวมเป็นบรรทัดเดียว ไม่ต้องแนะนำให้ลบ
- หน้า (pages) ที่ไม่มีลิงก์อาจตั้งใจให้เข้าจากลิงก์ภายนอก (เช่น `/t/[token]` ลิงก์ที่ส่งทาง LINE) — ตรวจคอมเมนต์และ edge function ที่สร้าง URL
- migrations เก่าห้ามลบเด็ดขาด (ประวัติฐานข้อมูล) · `database.types.ts` เป็นไฟล์ generate
- ไฟล์ที่ไม่มีใครใช้แต่ "ควรถูกใช้" (เช่น component ใหม่ที่ลืมใส่ในหน้า) เป็นบัค ไม่ใช่ขยะ — แยกให้ชัดในรายงาน

## รายงาน

เขียนเป็นภาษาไทย กระชับ อ้างอิงไฟล์เป็นลิงก์ markdown `[file.vue:42](apps/.../file.vue#L42)` ใช้โครงนี้:

```markdown
## สรุป
สแกน N จุด → ยืนยันเป็นบัคเงียบ X ข้อ, ไฟล์/โค้ดไม่ได้ใช้ Y รายการ, ตั้งใจไว้/ไม่ใช่ปัญหา Z ข้อ

## บัคเงียบที่ยืนยันแล้ว (เรียงจากร้ายแรงสุด)
### 1. <ผู้ใช้เจออะไร — เขียนเป็นอาการ ไม่ใช่ชื่อเช็ก>
- **ที่:** [file:line](...)
- **เกิดอะไรขึ้น:** <กลไก 1–2 ประโยค>
- **หลักฐาน:** <โค้ดสั้น ๆ หรือผลคำสั่งที่ยืนยัน>
- **แก้:** <แนวทางที่เข้ากับ pattern ของโปรเจกต์>

## น่าสงสัย (ยืนยันไม่ได้จากโค้ดอย่างเดียว)
<สิ่งที่ต้องทดสอบจริงหรือดูฐานข้อมูล/สถานะ deploy — บอกวิธีตรวจ>

## ไฟล์/โค้ดที่ไม่ได้ใช้
| รายการ | ประเภท | แนะนำ |
<ลบได้ / ควรถูกใช้ (บัค) / เก็บไว้ (เหตุผล)> · ชิ้นส่วน shadcn รวมเป็น 1 แถว

## ตั้งใจไว้ / ไม่ใช่ปัญหา
<รายการสั้น ๆ พร้อมเหตุผลบรรทัดเดียว เพื่อให้ผู้ใช้รู้ว่าดูแล้ว>
```

ความร้ายแรง: **สูง** = ข้อมูลเงิน/การจองผิดหรือหาย, ผู้ใช้เข้าใจว่าสำเร็จทั้งที่ล้มเหลว · **กลาง** = ผู้ใช้เห็นหน้าว่าง/ค้างโดยไม่รู้สาเหตุ ·
**ต่ำ** = โค้ดตาย, debug ยาก

## หลังรายงาน — ถามก่อนแก้

อย่าแก้โค้ดหรือลบไฟล์ในรอบเดียวกับที่รายงาน ให้ปิดท้ายด้วยการถามว่าจะแก้ข้อไหน (ใช้ AskUserQuestion แบบ multiSelect
ถ้ามี โดยเสนอกลุ่มที่แนะนำเป็นตัวเลือกแรก) เพราะบางข้ออาจตั้งใจไว้ด้วยเหตุผลที่โค้ดไม่ได้บอก และการลบไฟล์ย้อนกลับยาก
เมื่อผู้ใช้เลือกแล้ว แก้ตาม pattern เดิมของโปรเจกต์ แล้วรัน `pnpm typecheck` ยืนยัน
