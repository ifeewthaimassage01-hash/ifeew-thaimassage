# Phase 4 — ER Diagram และ Cardinality

ขอบเขต: ทรัพยากร (เตียง/อุปกรณ์), การจัดสรรตามเวลา, การจอง (สมาชิก/Guest/พนักงาน), มัดจำผ่านสลิป (SlipOK + พนักงานตรวจ), Tracking Token, ยกเลิก/No-show/คืนมัดจำ

```mermaid
erDiagram
    COMPANIES ||--o{ RESOURCE_TYPES : "1:N"
    BRANCHES ||--o{ BRANCH_RESOURCES : "1:N (UK branch+type)"
    RESOURCE_TYPES ||--o{ BRANCH_RESOURCES : "1:N"
    SERVICES ||--o{ SERVICE_RESOURCES : "1:N (ระดับบริการ)"
    RESOURCE_TYPES ||--o{ SERVICE_RESOURCES : "1:N"
    BRANCHES ||--o| BRANCH_PAYMENT_ACCOUNTS : "1:0..1 (PromptPay + SlipOK branch)"
    CUSTOMERS ||--o{ BOOKINGS : "1:N"
    BRANCHES ||--o{ BOOKINGS : "1:N"
    BOOKINGS ||--|{ BOOKING_ITEMS : "1:1..4 (คนละ 1 รายการ)"
    BRANCH_SERVICE_OPTIONS ||--o{ BOOKING_ITEMS : "1:N (+Snapshot)"
    BOOKING_ITEMS ||--|{ RESOURCE_ALLOCATIONS : "1:N (ต่อประเภททรัพยากร)"
    BOOKINGS ||--o{ BOOKING_TRACKING_TOKENS : "1:N (ACTIVE ได้ 1)"
    BOOKINGS ||--o{ BOOKING_DEPOSITS : "1:N (ส่งสลิปได้หลายครั้ง, ผ่านได้ 1)"

    RESOURCE_TYPES { uuid id PK
        uuid company_id FK
        text name
        bool is_active }
    BRANCH_RESOURCES { uuid id PK
        uuid branch_id FK
        uuid resource_type_id FK
        int total_quantity
        text status "ACTIVE | MAINTENANCE | DISABLED" }
    SERVICE_RESOURCES { uuid id PK
        uuid service_id FK
        uuid resource_type_id FK
        int quantity }
    RESOURCE_ALLOCATIONS { uuid id PK
        uuid branch_id FK
        uuid resource_type_id FK
        uuid booking_item_id FK
        int quantity
        timestamptz starts_at
        timestamptz ends_at "รวมเวลาเผื่อทำความสะอาด"
        text status "HELD | RESERVED | IN_USE | RELEASED"
        timestamptz expires_at "เฉพาะ HELD" }
    BOOKINGS { uuid id PK
        uuid branch_id FK
        uuid customer_id FK
        text booking_code "BKG-{branch}-{YYYYMMDD}-{NNNN} ออกเมื่อ CONFIRMED"
        text channel "ONLINE | STAFF"
        text status "PENDING CONFIRMED CHECKED_IN COMPLETED CANCELLED NO_SHOW EXPIRED"
        timestamptz starts_at
        numeric deposit_required
        text deposit_status
        timestamptz hold_expires_at }
    BOOKING_ITEMS { uuid id PK
        uuid booking_id FK
        uuid branch_service_option_id FK
        text service_name "Snapshot"
        int duration_minutes "Snapshot"
        numeric unit_price "Snapshot"
        numeric therapist_fee "Snapshot (OWNER)"
        numeric discount_amount
        numeric line_total }
    BOOKING_DEPOSITS { uuid id PK
        uuid booking_id FK
        numeric amount
        text status "PENDING_REVIEW | VERIFIED | REJECTED"
        text slip_path
        text slip_trans_ref "UK เมื่อไม่ REJECTED"
        text verification_source "AUTO | STAFF"
        text refund_status "NONE | PENDING | REFUNDED | FORFEITED" }
    BOOKING_TRACKING_TOKENS { uuid id PK
        uuid booking_id FK
        text token_hash "sha256"
        timestamptz token_expires_at
        timestamptz revoked_at }
```

## กฎสำคัญ

| เรื่อง | วิธีบังคับ |
|---|---|
| Capacity | `private.assert_capacity()` ล็อก `branch_resources` (FOR UPDATE) แล้วคำนวณยอดใช้สูงสุดในช่วงเวลา (HELD ที่ยังไม่หมดอายุ + RESERVED + IN_USE) ต้องไม่เกิน `total_quantity`; เรียกจาก trigger ทุกครั้งที่ allocation กลายเป็น active |
| เวลาเผื่อ | allocation ยาว = ระยะบริการ + `booking_buffer_minutes` |
| State Booking | `private.transition_booking()` ตามตารางในสเปก สถานะสุดท้ายเปลี่ยนไม่ได้ |
| มัดจำออนไลน์ | ยอดคงที่ต่อคน × จำนวนรายการ; จองแล้ว = PENDING + HELD (`booking_hold_minutes`); สลิปผ่าน SlipOK = CONFIRMED + RESERVED; ตรวจไม่ได้ = PENDING_REVIEW (ขยายเวลากันที่) ให้พนักงานตัดสิน |
| สลิปซ้ำ | SlipOK `log: true` + unique `slip_trans_ref` ใน DB |
| ยกเลิก | สมาชิกยกเลิกเองก่อนนัด ≥ `cancellation_cutoff_hours`; Guest ยกเลิกเองไม่ได้; ทันเวลา = คืนมัดจำ (REFUND PENDING → พนักงานบันทึกการโอนคืน), ช้า/No-show = ริบ |
| Token | สุ่ม 256 บิต เก็บ sha256, หมดอายุ 7 วันหลังนัด, ใช้ดูสถานะ/ส่งสลิปเท่านั้น |
| Guest | สร้างลูกค้า Guest ใหม่ทุกครั้ง (ไม่รวมอัตโนมัติ) — พนักงานจับคู่ภายหลัง |
