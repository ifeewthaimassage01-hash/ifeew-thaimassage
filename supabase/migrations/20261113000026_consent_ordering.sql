-- =============================================================================
-- Phase 9 / 026 — ความยินยอม "ล่าสุด" ต้องแน่นอน
--   พบบน Supabase จริง: บันทึกความยินยอม 2 ครั้งใน Transaction เดียวกันได้ recorded_at เท่ากัน (now())
--   ทำให้การเลือก "ล่าสุด" (order by recorded_at desc) สุ่มได้ทั้งสองแถว
--   → ใช้เวลาจริงขณะบันทึก (clock_timestamp) เมื่อไม่ได้ระบุเวลาเอง
-- =============================================================================

create or replace function private.tg_customer_consents_clock()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.recorded_at = now() then
    new.recorded_at := clock_timestamp();
  end if;
  return new;
end;
$$;

create trigger customer_consents_clock before insert on public.customer_consents
  for each row execute function private.tg_customer_consents_clock();
