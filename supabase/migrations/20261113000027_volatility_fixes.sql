-- =============================================================================
-- Phase 9 / 027 — แก้ตามผล supabase db lint บน staging
--   get_available_slots / pos_available_starts ประกาศเป็น STABLE แต่เรียก private.has_capacity (VOLATILE)
--   → เปลี่ยนเป็น VOLATILE ให้ตรงกับพฤติกรรมจริง (supabase-js เรียก rpc ด้วย POST อยู่แล้ว)
-- =============================================================================
alter function public.get_available_slots(uuid, date, uuid[]) volatile;
alter function public.pos_available_starts(uuid, uuid[]) volatile;
