# Phase 2 — ER Diagram และ Cardinality

ขอบเขต: เวลาทำการและวันหยุดสาขา, พนักงาน, ประวัติย้ายสาขา, ตารางงาน, การยืนยันตัวตนซ้ำ (step-up TOTP), รูปพนักงาน (Storage)

```mermaid
erDiagram
    BRANCHES ||--|{ BRANCH_OPENING_HOURS : "1:7 (trigger สร้างให้ครบ 7 วัน)"
    BRANCHES ||--o{ BRANCH_HOLIDAYS : "1:N (ACTIVE ได้ 1 แถวต่อวันที่)"
    COMPANY_MEMBERSHIPS ||--o| EMPLOYEES : "1:0..1 (เฉพาะ role STAFF)"
    EMPLOYEES ||--o{ EMPLOYEE_TRANSFERS : "1:N"
    BRANCH_MEMBERSHIPS ||--o| EMPLOYEE_TRANSFERS : "to_membership 1:1"
    EMPLOYEES ||--o{ EMPLOYEE_SCHEDULES : "1:N (ห้ามเวลาซ้อน)"
    BRANCHES ||--o{ EMPLOYEE_SCHEDULES : "1:N"

    BRANCH_OPENING_HOURS {
        uuid id PK
        uuid company_id FK
        uuid branch_id FK
        smallint iso_dow "1=จันทร์ .. 7=อาทิตย์ UK(branch_id, iso_dow)"
        bool is_closed
        time opens_at
        time closes_at "น้อยกว่า opens_at = ปิดหลังเที่ยงคืน"
    }
    BRANCH_HOLIDAYS {
        uuid id PK
        uuid company_id FK
        uuid branch_id FK
        date holiday_date
        text name
        bool is_closed "false = เปิดเวลาพิเศษ"
        time opens_at
        time closes_at
        bool is_active "soft delete"
    }
    EMPLOYEES {
        uuid id PK
        uuid company_id FK
        uuid user_id FK "UK(company_id, user_id) -> company_memberships"
        text employee_code "OWNER กรอกเอง UK(company_id, upper(code))"
        text nickname "แสดงในหน้า PIN/คิว ซิงก์ไป profiles.display_name"
        text photo_path "employee-photos/{company_id}/{employee_id}/..."
        date start_date
        text status "ACTIVE | INACTIVE | RESIGNED"
        timestamptz resigned_at
    }
    EMPLOYEE_TRANSFERS {
        uuid id PK
        uuid company_id FK
        uuid employee_id FK
        uuid from_branch_id FK "NULL = เริ่มงาน"
        uuid to_branch_id FK
        uuid from_membership_id FK
        uuid to_membership_id FK
        timestamptz effective_from "ทันทีหรือล่วงหน้า"
        text reason
        text status "ACTIVE | CANCELLED"
    }
    EMPLOYEE_SCHEDULES {
        uuid id PK
        uuid company_id FK
        uuid branch_id FK
        uuid employee_id FK
        timestamptz starts_at
        timestamptz ends_at "ข้ามเที่ยงคืนได้ ไม่เกิน 16 ชม."
        text status "SCHEDULED | LEAVE | CANCELLED"
        text note
    }
```

## กฎสำคัญ

| เรื่อง | วิธีบังคับ |
|---|---|
| พนักงาน 1:1 membership และต้องเป็น STAFF | composite FK `(company_id, user_id)` + UNIQUE + trigger ตรวจ role |
| OWNER ได้คนเดียวต่อบริษัท | partial unique index `company_memberships (company_id) WHERE role='OWNER' AND status='ACTIVE'` |
| ย้ายสาขา | `transfer_employee()` ปิด branch_membership เดิม (effective_to) + สร้างใหม่ + บันทึก transfer ใน Transaction เดียว; ห้ามถ้ามีกะที่สาขาเดิมหลังวันมีผล หรือมีการย้ายที่รอมีผลอยู่ |
| กะงาน | exclusion constraint ห้ามซ้อนต่อพนักงาน (ยกเว้น CANCELLED); trigger ตรวจว่าพนักงานสังกัดสาขานั้นตลอดช่วงกะ; CANCELLED เป็นสถานะสุดท้าย |
| ระงับ (INACTIVE) | membership = SUSPENDED, ลบ PIN, ban บัญชี (Edge Function) — สิทธิ์สาขาเดิมคงไว้เพื่อเปิดใช้ใหม่ |
| ลาออก (RESIGNED) | membership = REVOKED, ปิดสิทธิ์สาขา, ยกเลิกการย้ายที่รอมีผลและกะในอนาคต, ลบ PIN, ban บัญชี — สถานะสุดท้าย |
| การกระทำเสี่ยงสูง | `private.require_owner_step_up()` ต้องเป็น OWNER aal2 และ JWT `amr` มี `totp` ภายใน 5 นาที |
