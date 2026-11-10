-- =============================================================================
-- 042 — เวลาเริ่มของ walk-in หน้าร้าน (pos_available_starts) ใช้ช่วงเวลาจากการตั้งค่า
--   เดิม: ทุก 5 นาที (เขียนตายตัว) → ใหม่: ทุก company_settings.booking_slot_minutes (เช่น 30 นาที)
--   เวลาเริ่มชนขอบช่วงเสมอ (เช่น :00 / :30) — ปัดขึ้นจากเวลาปัจจุบัน
--   คง volatile ไว้ตาม migration 027
-- =============================================================================

create or replace function public.pos_available_starts(p_branch_id uuid, p_option_ids uuid[])
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  w          record;
  v_tz       text;
  v_buffer   integer;
  v_step     integer;
  v_max_dur  integer;
  v_t        timestamptz;
  v_demands  jsonb;
  v_opt      uuid;
  v_result   jsonb := '[]'::jsonb;
begin
  perform private.require_branch_access(p_branch_id);
  perform private.assert_branch_options(p_branch_id, p_option_ids);
  select * into w from private.branch_window_at(p_branch_id, now());
  if w.opens_at is null then
    return v_result;
  end if;
  select s.timezone, s.booking_buffer_minutes, greatest(5, coalesce(s.booking_slot_minutes, 30))
    into v_tz, v_buffer, v_step
    from public.branches b join public.company_settings s on s.company_id = b.company_id where b.id = p_branch_id;
  select max(duration_minutes) into v_max_dur from public.branch_service_options where id = any (p_option_ids);

  -- ปัดขึ้นให้ชนขอบช่วง (epoch หารลงตัว — เขตเวลาไทยเป็นชั่วโมงเต็ม จึงได้ :00/:30 ตามเวลาท้องถิ่น)
  v_t := to_timestamp(ceil(extract(epoch from greatest(w.opens_at, now())) / (v_step * 60)) * (v_step * 60));
  while v_t + make_interval(mins => v_max_dur) <= w.closes_at and jsonb_array_length(v_result) < 60 loop
    v_demands := '[]'::jsonb;
    foreach v_opt in array p_option_ids loop
      v_demands := v_demands || private.option_demands(v_opt, v_t, v_buffer);
    end loop;
    if private.has_capacity(p_branch_id, v_demands, false) then
      v_result := v_result || jsonb_build_object('starts_at', v_t, 'time', to_char(v_t at time zone v_tz, 'HH24:MI'));
    end if;
    v_t := v_t + make_interval(mins => v_step);
  end loop;
  return v_result;
end;
$$;
