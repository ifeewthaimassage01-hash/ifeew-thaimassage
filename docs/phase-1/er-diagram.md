# Phase 1 — ER Diagram และ Cardinality

ขอบเขต: Foundation (บริษัท สาขา โปรไฟล์ สมาชิก/สิทธิ์ Audit Log เลขรันเอกสาร Idempotency Rate Limit เครื่องประจำสาขาและ PIN พนักงาน)

```mermaid
erDiagram
    AUTH_USERS ||--|| PROFILES : "1:1 (trigger สร้างให้)"
    COMPANIES ||--|| COMPANY_SETTINGS : "1:1 (trigger สร้างให้)"
    COMPANIES ||--o{ BRANCHES : "1:N"
    COMPANIES ||--o{ COMPANY_MEMBERSHIPS : "1:N"
    PROFILES ||--o{ COMPANY_MEMBERSHIPS : "1:N (1 แถวต่อบริษัท)"
    COMPANY_MEMBERSHIPS ||--o{ BRANCH_MEMBERSHIPS : "1:N (ช่วงเวลาไม่ซ้อนกัน)"
    BRANCHES ||--o{ BRANCH_MEMBERSHIPS : "1:N"
    COMPANY_MEMBERSHIPS ||--o| STAFF_PINS : "1:0..1"
    BRANCHES ||--o{ BRANCH_DEVICES : "1:N"
    BRANCHES ||--o{ DOCUMENT_SEQUENCES : "1:N (ต่อ doc_type + period_key)"
    COMPANIES ||--o{ AUDIT_LOGS : "1:N"
    PROFILES ||--o{ AUDIT_LOGS : "actor 1:N"
    PROFILES ||--o{ IDEMPOTENCY_KEYS : "1:N"

    COMPANIES {
        uuid id PK
        text code UK "A-Z0-9 2-10"
        text name
        text legal_name
        text tax_id
        bool is_active
    }
    COMPANY_SETTINGS {
        uuid company_id PK,FK
        text timezone "Asia/Bangkok"
        int cancellation_cutoff_hours "default 3"
        numeric large_expense_threshold
        int staff_pin_max_attempts
        int staff_pin_lockout_minutes
        int staff_idle_lock_minutes
    }
    BRANCHES {
        uuid id PK
        uuid company_id FK
        text code "UK(company_id, code) แก้ไม่ได้หลังออกเอกสาร"
        text name
        text address
        text phone
        text map_url
        bool is_active
        int sort_order
    }
    PROFILES {
        uuid id PK,FK "auth.users.id"
        text display_name
        text phone
        text avatar_path
    }
    COMPANY_MEMBERSHIPS {
        uuid id PK
        uuid company_id FK
        uuid user_id FK
        text role "OWNER | STAFF"
        text status "ACTIVE | SUSPENDED | REVOKED"
        timestamptz effective_from
        timestamptz effective_to
    }
    BRANCH_MEMBERSHIPS {
        uuid id PK
        uuid company_id FK
        uuid branch_id FK "composite (company_id, branch_id)"
        uuid user_id FK "composite (company_id, user_id)"
        text status "ACTIVE | REVOKED"
        timestamptz effective_from
        timestamptz effective_to
    }
    STAFF_PINS {
        uuid company_id PK,FK
        uuid user_id PK,FK
        text pin_hash "bcrypt"
        int failed_attempts
        timestamptz locked_until
    }
    BRANCH_DEVICES {
        uuid id PK
        uuid company_id FK
        uuid branch_id FK
        text name
        text token_hash UK "sha256 ของ device secret"
        text status "ACTIVE | REVOKED"
        timestamptz last_seen_at
    }
    DOCUMENT_SEQUENCES {
        uuid id PK
        uuid company_id FK
        uuid branch_id FK
        text doc_type "INV RCP BKG QUE ..."
        text period_key "YYYY หรือ YYYYMMDD"
        bigint last_number
    }
    AUDIT_LOGS {
        uuid id PK
        uuid company_id
        uuid branch_id
        uuid actor_user_id
        text action
        text table_name
        uuid record_id
        jsonb old_values
        jsonb new_values
        text reason
        timestamptz occurred_at
    }
    IDEMPOTENCY_KEYS {
        uuid id PK
        uuid user_id
        text endpoint
        text key "UK(user_id, endpoint, key) NULLS NOT DISTINCT"
        text request_hash
        text status
        jsonb response
        timestamptz expires_at
    }
    RATE_LIMIT_BUCKETS {
        text bucket_key PK
        timestamptz window_start
        int hit_count
    }
```

## Cardinality และกฎสำคัญ

| ความสัมพันธ์ | Cardinality | วิธีบังคับ |
|---|---|---|
| auth.users → profiles | 1:1 | FK `profiles.id → auth.users.id` + trigger `on_auth_user_created` |
| companies → company_settings | 1:1 | PK = FK + trigger สร้างแถวอัตโนมัติ |
| companies → branches | 1:N | FK + `UNIQUE (company_id, code)` + `UNIQUE (company_id, id)` สำหรับ composite FK |
| profiles ↔ companies | M:N ผ่าน company_memberships | `UNIQUE (company_id, user_id)` 1 แถวต่อคนต่อบริษัท ประวัติการเปลี่ยน role อยู่ใน audit_logs |
| company_memberships → branch_memberships | 1:N | composite FK `(company_id, user_id)` และ `(company_id, branch_id)` กันข้ามบริษัท; exclusion constraint กันไม่ให้ 1 คนมีสาขา ACTIVE ซ้อนเวลากัน (พนักงานประจำสาขาเดียวในช่วงเวลาหนึ่ง) |
| company_memberships → staff_pins | 1:0..1 | PK `(company_id, user_id)` + composite FK |
| branches → branch_devices | 1:N | composite FK `(company_id, branch_id)` |
| branches → document_sequences | 1:N | `UNIQUE (company_id, branch_id, doc_type, period_key)` |

## หมายเหตุการออกแบบ

- **Role** มาจาก `company_memberships.role` เท่านั้น ไม่อ่านจาก JWT claim หรือ user_metadata
- **OWNER** ได้สิทธิ์เจ้าของเฉพาะเมื่อ session เป็น `aal2` (ผ่าน TOTP แล้ว) ตรวจใน `private.is_company_owner()`
- **CUSTOMER** ไม่มี membership จะผูกกับ `customers.auth_user_id` ใน Phase 3
- **audit_logs** ไม่มี `updated_at` เพราะเป็น append-only (มี trigger ห้าม UPDATE/DELETE/TRUNCATE)
- **idempotency_keys / rate_limit_buckets** เป็นตารางควบคุมระบบ ไม่มี company_id เพราะใช้ข้ามบริษัทได้ (เช่น Public Endpoint ของ Guest) และไม่มี Policy ให้ client เข้าถึงเลย
- **document_sequences** ใช้ `period_key` แทน `fiscal_year` (ตามข้อตกลงข้อ 6) รอบปี/วันคำนวณตาม `company_settings.timezone`
