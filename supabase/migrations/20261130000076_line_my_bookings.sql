-- =============================================================================
-- 076 — "การจองของฉัน" สำหรับลูกค้าที่เข้าสู่ระบบด้วย LINE (LIFF)
--   - Edge Function line-my-bookings ยืนยัน ID token กับ LINE แล้วเรียก line_my_bookings (service_role เท่านั้น)
--   - แสดงเฉพาะการจองที่ผูกกับ LINE คนนี้แล้ว (private.booking_line_recipients — จองตอนเข้าสู่ระบบด้วย LINE
--     หรือกด "เชื่อม LINE" ในหน้าติดตาม) ไม่ดึงการจองอื่นจากเบอร์โทร
--   - แต่ละรายการมี token LOOKUP อายุ 30 นาที ไว้เปิด /t/<token> (แบบเดียวกับค้นหาด้วยเบอร์ — migration 035)
--   - profile = ชื่อ/เบอร์จากการจองล่าสุด ใช้เติมฟอร์มจองครั้งถัดไป (เป็นข้อมูลของเจ้าของ LINE เอง)
-- =============================================================================

create index if not exists booking_line_recipients_user_idx
  on private.booking_line_recipients (line_user_id);

create or replace function public.line_my_bookings(p_company_code text, p_line_user_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company  uuid := private.company_id_by_code(p_company_code);
  v_bookings jsonb := '[]'::jsonb;
  v_profile  jsonb;
  v_token    text;
  r          record;
begin
  if v_company is null or p_line_user_id !~ '^U[0-9a-f]{32}$' then
    return jsonb_build_object('bookings', v_bookings, 'profile', null);
  end if;

  -- เก็บกวาด token LOOKUP ที่หมดอายุแล้ว
  delete from public.booking_tracking_tokens
   where purpose = 'LOOKUP' and token_expires_at < now() - interval '1 day';

  perform private.expire_stale_bookings();

  -- นัดที่ยังไม่ถึงทั้งหมด + นัดที่ผ่านมาไม่เกิน 180 วัน (สูงสุด 30 รายการ)
  for r in
    select b.id, b.company_id
      from private.booking_line_recipients rcp
      join public.bookings b on b.id = rcp.booking_id
     where rcp.line_user_id = p_line_user_id
       and b.company_id = v_company
       and b.starts_at > now() - interval '180 days'
     order by b.starts_at desc
     limit 30
  loop
    v_token := 'trk_' || encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.booking_tracking_tokens (company_id, booking_id, token_hash, token_expires_at, purpose)
    values (r.company_id, r.id, encode(extensions.digest(v_token, 'sha256'), 'hex'), now() + interval '30 minutes', 'LOOKUP');
    v_bookings := v_bookings || jsonb_build_array(
      private.booking_customer_view(r.id) || jsonb_build_object('tracking_token', v_token));
  end loop;

  -- ชื่อ/เบอร์จากการจองล่าสุดที่ผูกกับ LINE นี้ (ลูกค้าที่ยังใช้งาน ไม่ถูกลบข้อมูล)
  select jsonb_build_object('first_name', c.first_name, 'last_name', c.last_name, 'phone', c.phone)
    into v_profile
    from private.booking_line_recipients rcp
    join public.bookings b on b.id = rcp.booking_id
    join public.customers c on c.id = b.customer_id
   where rcp.line_user_id = p_line_user_id
     and b.company_id = v_company
     and c.status = 'ACTIVE' and c.anonymized_at is null
   order by b.created_at desc
   limit 1;

  return jsonb_build_object('bookings', v_bookings, 'profile', v_profile);
end;
$$;

revoke all on function public.line_my_bookings(text, text) from public, anon, authenticated;
grant execute on function public.line_my_bookings(text, text) to service_role;
