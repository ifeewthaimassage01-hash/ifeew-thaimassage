-- =============================================================================
-- 051 — ชื่อร้าน "Ifeew's Thaimassage (staging)" → "Ifeew's Thaimassage" (ตามที่ผู้ใช้ขอ)
--   แก้เฉพาะแถวที่ยังเป็นชื่อเดิมจาก tools/bootstrap (รันซ้ำได้)
-- =============================================================================

update public.companies set name = 'Ifeew''s Thaimassage' where name = 'Ifeew''s Thaimassage (staging)';
