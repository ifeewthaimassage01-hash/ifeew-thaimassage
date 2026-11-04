# Phase 3 — ER Diagram และ Cardinality

ขอบเขต: บริการและราคา (บริการกลาง + บริการรายสาขา + ประวัติราคา), ลูกค้า (สมาชิก/Guest), ความยินยอม PDPA, คำขอลบข้อมูล

```mermaid
erDiagram
    COMPANIES ||--o{ SERVICE_CATEGORIES : "1:N"
    SERVICE_CATEGORIES ||--o{ SERVICES : "1:N"
    SERVICES ||--o{ BRANCH_SERVICES : "1:N (1 แถวต่อสาขา)"
    BRANCHES ||--o{ BRANCH_SERVICES : "1:N"
    BRANCH_SERVICES ||--|{ BRANCH_SERVICE_OPTIONS : "1:N (ช่วงเวลาที่ขาย UK duration)"
    BRANCH_SERVICE_OPTIONS ||--|{ SERVICE_PRICE_HISTORIES : "1:N (ช่วงเวลามีผลไม่ซ้อน)"
    COMPANIES ||--o{ CUSTOMERS : "1:N (ข้อมูลระดับบริษัท)"
    PROFILES ||--o| CUSTOMERS : "0..1:0..1 ต่อบริษัท (สมาชิก)"
    CUSTOMERS ||--o| CUSTOMERS : "merged_into (Guest ที่รวมแล้ว)"
    COMPANIES ||--o{ PRIVACY_POLICY_VERSIONS : "1:N"
    CUSTOMERS ||--o{ CUSTOMER_CONSENTS : "1:N (append-only)"
    PRIVACY_POLICY_VERSIONS ||--o{ CUSTOMER_CONSENTS : "1:N"
    CUSTOMERS ||--o{ CUSTOMER_DATA_REQUESTS : "1:N (PENDING ได้ 1)"

    SERVICE_CATEGORIES {
        uuid id PK
        uuid company_id FK
        text name
        int sort_order
        bool is_active
    }
    SERVICES {
        uuid id PK
        uuid company_id FK
        uuid category_id FK
        text name "เช่น นวดไทย"
        text name_en "เช่น Thai Massage"
        text description
        text image_path "bucket service-images (public)"
        bool is_active
    }
    BRANCH_SERVICES {
        uuid id PK
        uuid company_id FK
        uuid branch_id FK
        uuid service_id FK "UK(branch_id, service_id)"
        bool is_active
        int sort_order
    }
    BRANCH_SERVICE_OPTIONS {
        uuid id PK
        uuid company_id FK
        uuid branch_service_id FK
        int duration_minutes "UK(branch_service_id, duration_minutes)"
        bool is_active
    }
    SERVICE_PRICE_HISTORIES {
        uuid id PK
        uuid company_id FK
        uuid branch_service_option_id FK
        numeric price "numeric(12,2) ราคารวม ไม่มี VAT"
        numeric therapist_fee "ค่าแรงหมอนวด (เห็นเฉพาะ OWNER)"
        timestamptz effective_from
        timestamptz effective_to
        text status "ACTIVE | CANCELLED"
        text reason
    }
    CUSTOMERS {
        uuid id PK
        uuid company_id FK
        uuid auth_user_id FK "NULL = Guest, UK(company_id, auth_user_id)"
        text first_name
        text last_name
        text phone "ไม่ UNIQUE, ตัวเลขล้วน"
        text email
        text staff_note
        text created_channel "ONLINE | STAFF"
        text status "ACTIVE | MERGED | ANONYMIZED"
        uuid merged_into_id FK
    }
    PRIVACY_POLICY_VERSIONS {
        uuid id PK
        uuid company_id FK
        text policy_type "PRIVACY_NOTICE | MARKETING"
        text version
        text title
        text content
        timestamptz published_at
    }
    CUSTOMER_CONSENTS {
        uuid id PK
        uuid company_id FK
        uuid customer_id FK
        uuid policy_version_id FK
        text consent_type
        bool granted
        text channel "ONLINE | STAFF"
    }
    CUSTOMER_DATA_REQUESTS {
        uuid id PK
        uuid company_id FK
        uuid customer_id FK
        text request_type "DELETE"
        text status "PENDING | COMPLETED | REJECTED"
        text reason
        uuid processed_by
        timestamptz processed_at
    }
```

## กฎสำคัญ

| เรื่อง | วิธีบังคับ |
|---|---|
| ช่วงเวลาบริการ | 1 บริการมีหลายช่วงเวลา (`branch_service_options`) ต่อสาขา แต่ละช่วงมีราคา + ค่าแรงของตัวเอง |
| ราคาปัจจุบัน | แถว `service_price_histories` ที่ ACTIVE และครอบเวลาปัจจุบัน ต่อช่วงเวลา (exclusion constraint ห้ามช่วงซ้อน) |
| ค่าแรงหมอนวด | ไม่ grant คอลัมน์ `therapist_fee` ให้ client — OWNER อ่านผ่าน `owner_service_pricing()` |
| บันทึกราคา | `save_branch_service_pricing()` บันทึกทุกช่วงเวลาของบริการพร้อมกัน (หลายสาขาได้ใน Transaction เดียว); แก้ของเดิมต้อง step-up TOTP + เหตุผล, มีผลทันที/ล่วงหน้า ห้ามย้อนหลัง |
| ลูกค้าเห็นราคา | view `v_public_branch_services` (security_invoker) เห็นเฉพาะราคาที่มีผลแล้ว ไม่เห็นราคาล่วงหน้า |
| ข้อมูลลูกค้า | ไม่มี SELECT ตรงสำหรับ STAFF/ลูกค้า — ใช้ Function: ค้นหาด้วยเบอร์เต็ม (ปิดบัง), ดูรายละเอียด (บันทึก audit) |
| จับคู่ Guest | `merge_customers()` พนักงานยืนยันเอง, ต้นทางต้องเป็น Guest, ไม่ลบแถว (status MERGED) |
| ความยินยอม | append-only แถวล่าสุดต่อประเภทคือสถานะปัจจุบัน |
| ลบข้อมูล (PDPA) | ลูกค้าส่งคำขอ → OWNER (step-up) อนุมัติ → anonymize customers/profiles + Edge Function เปลี่ยนอีเมลและ ban บัญชี Auth |
