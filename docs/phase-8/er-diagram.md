# Phase 8 — การเงินส่วนกลาง

ขอบเขต: ประกันมือหมอประจำ + ลงเวลา, คอมมิชชันและรอบจ่าย, ปิดยอดรายวัน, งวดบัญชี, แดชบอร์ด OWNER, รายงาน

```mermaid
erDiagram
    EMPLOYEES ||--o{ EMPLOYEE_GUARANTEE_RATES : "1:N (มีผลไม่ทับกัน)"
    EMPLOYEES ||--o{ STAFF_ATTENDANCES : "1:N (1 ต่อวันทำการ)"
    EMPLOYEES ||--o{ GUARANTEE_OVERRIDES : "1:N (1 ต่อวัน)"
    SERVICE_ASSIGNMENTS ||--o| COMMISSIONS : "SERVICE 1:0..1"
    EMPLOYEES ||--o{ COMMISSIONS : "GUARANTEE 1 ต่อสาขาต่อวัน"
    COMMISSIONS ||--o{ COMMISSION_ADJUSTMENTS : "VOID_REVERSAL / GUARANTEE_RECALC"
    EMPLOYEES ||--o{ COMMISSION_ADJUSTMENTS : "MANUAL"
    COMMISSION_PAYOUTS ||--o{ COMMISSIONS : "1:N"
    COMMISSION_PAYOUTS ||--o{ COMMISSION_ADJUSTMENTS : "1:N"
    COMMISSION_PAYOUTS ||--o{ TIPS : "ทิปที่ไม่ใช่เงินสด"
    COMMISSION_PAYOUTS ||--|{ COMMISSION_PAYOUT_ITEMS : "1:N (ต่อหมอ)"
    BRANCHES ||--o{ BRANCH_DAILY_CLOSINGS : "1 ต่อวันทำการ"
    COMPANIES ||--o{ FINANCIAL_PERIODS : "1 ต่อเดือน"

    COMMISSIONS { uuid id PK
        text kind "SERVICE | GUARANTEE"
        date business_date
        numeric base_amount "ค่ามือ snapshot / ยอดประกัน"
        numeric share_ratio "สัดส่วนเมื่อส่งต่อหมอ"
        numeric amount
        text status "ACCRUED | PAID | VOID" }
    COMMISSION_ADJUSTMENTS { uuid id PK
        numeric amount "+/-"
        text source "MANUAL | VOID_REVERSAL | GUARANTEE_RECALC"
        text status "OPEN | PAID" }
    STAFF_ATTENDANCES { uuid id PK
        date business_date
        timestamptz clock_in_at
        timestamptz clock_out_at }
    BRANCH_DAILY_CLOSINGS { uuid id PK
        date business_date
        text status "SUBMITTED | APPROVED | REJECTED"
        jsonb figures "สรุปยอด ณ เวลาส่ง"
        numeric adjustment_amount "OWNER ปรับปรุง" }
    FINANCIAL_PERIODS { uuid id PK
        date period_start "วันที่ 1 ของเดือน"
        text status "LOCKED | OPEN" }
```

## กฎสำคัญ

| เรื่อง | บังคับที่ |
| --- | --- |
| ค่ามือเข้าเกณฑ์เมื่อบริการจบ + Invoice จ่ายครบ (ไม่คืนเงินเต็มจำนวน) | `private.sync_commissions` ขั้น 1 |
| Void/คืนเงินเต็ม: ยังไม่จ่าย = VOID, จ่ายแล้ว = รายการกลับ −ยอด (ครั้งเดียว) | ขั้น 2 + unique `commission_adjustments_reversal_key` |
| ประกันมือ = max(ยอดประกัน − ค่ามือของวัน, 0) เฉพาะหมอประจำที่มีกะ | `private.compute_guarantee` |
| ไม่ครบกะ (ลงเวลาเข้า/ออกไม่ครอบกะ ± grace) = ไม่ได้ประกัน เว้นแต่ OWNER ให้ | `staff_attendances`, `guarantee_overrides` |
| ประกันมือคำนวณอัตโนมัติ (ไม่ต้องอนุมัติ) จนกว่าจะจ่าย หลังจ่ายปรับรอบถัดไป | ขั้น 3 (`GUARANTEE_RECALC`) |
| ไม่นับทิปในประกันมือ/ค่ามือ, ทิปที่ไม่ใช่เงินสดจ่ายในรอบจ่าย | `tips.commission_payout_id` |
| รอบจ่าย: ร่าง → ยืนยัน (OWNER + TOTP) / ยกเลิก, ร่างได้ทีละ 1, ยอดติดลบยกไป | `create/confirm/cancel_commission_payout` |
| ปิดยอดรายวันได้เมื่อปิดกะครบ, OWNER อนุมัติ/ปฏิเสธ (+ ยอดปรับปรุงพร้อมเหตุผล) | `submit/review_daily_closing` |
| ล็อกงวด: เดือนที่จบแล้ว + ปิดยอดทุกวันได้รับอนุมัติ + TOTP | `lock_financial_period` |
| งวดที่ล็อกห้ามเขียนข้อมูลการเงินของเดือนนั้น (ทุกช่องทาง) | trigger `tg_period_lock` (hint `PERIOD_LOCKED`) |
| เปิดงวดต้องมีเหตุผล + TOTP | `reopen_financial_period` |
| รายรับ = รับจริง (รวมมัดจำที่หัก + มัดจำที่ริบ) − คืนเงิน, ไม่รวมทิป | `private.daily_finance` |
| กำไรเบื้องต้น = รายรับ − รายจ่าย − ค่ามือ (รวมประกันมือ/ปรับ) | `private.daily_finance` |
| STAFF ห้ามดูยอดรวมทุกสาขา, หมอเห็นค่ามือของตัวเองเท่านั้น | Function OWNER-only + RLS |
