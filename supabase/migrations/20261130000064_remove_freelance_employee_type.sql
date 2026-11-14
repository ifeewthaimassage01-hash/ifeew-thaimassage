-- เลิกใช้ประเภทพนักงาน "หมอฟรีแลนซ์" (FREELANCE) — ร้านไม่ได้ใช้ (ตอนนี้ 0 คน)
--   พนักงานที่มีบัญชีทุกคนเป็นหมอประจำ (REGULAR) · หมอที่ไม่มีบัญชีใช้ "หมอวิ่ง" (กรอกชื่อตอนเริ่มนวด) ตามเดิม
--   คงคอลัมน์ employment_type ไว้ (ฟังก์ชันประกันมือ/สรุปเงินยังอ่านอยู่) แต่รับได้ค่าเดียว
update public.employees set employment_type = 'REGULAR' where employment_type <> 'REGULAR';

alter table public.employees drop constraint if exists employees_employment_type_check;
alter table public.employees add constraint employees_employment_type_check check (employment_type = 'REGULAR');

comment on column public.employees.employment_type is 'REGULAR เท่านั้น (เลิกใช้ FREELANCE ใน migration 064 — หมอนอกใช้ "หมอวิ่ง" กรอกชื่อ)';
