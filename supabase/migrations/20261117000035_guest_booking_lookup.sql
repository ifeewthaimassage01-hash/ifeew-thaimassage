-- =============================================================================
-- 035 — ตรวจสอบการจองด้วยเบอร์โทร (Guest ที่ไม่ได้ login)
--   - Edge Function guest-booking-lookup (Turnstile + rate limit) เรียก guest_bookings_by_phone
--   - คืนรายการการจองของ Guest (ไม่รวมสมาชิก — สมาชิกให้ login ดู) พร้อม token ชั่วคราว (LOOKUP)
--     ให้เปิดหน้า /t/<token> ได้ โดยไม่ยกเลิกลิงก์ติดตามเดิม (TRACKING) ที่ลูกค้า/ร้านถืออยู่
-- =============================================================================

alter table public.booking_tracking_tokens
  add column purpose text not null default 'TRACKING' check (purpose in ('TRACKING', 'LOOKUP'));

-- ลิงก์ติดตามหลักยังมีได้ครั้งละ 1 ต่อการจอง; token LOOKUP มีหลายอันได้ (อายุสั้น)
drop index public.booking_tracking_tokens_one_active;
create unique index booking_tracking_tokens_one_active
  on public.booking_tracking_tokens (booking_id) where revoked_at is null and purpose = 'TRACKING';
create index booking_tracking_tokens_lookup_expiry_idx
  on public.booking_tracking_tokens (token_expires_at) where purpose = 'LOOKUP';

-- ออกลิงก์ติดตามใหม่: ยกเลิกเฉพาะ TRACKING เดิม (LOOKUP หมดอายุเอง)
create or replace function private.issue_tracking_token(p_booking_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  b       public.bookings;
  v_days  integer;
  v_token text := 'trk_' || encode(extensions.gen_random_bytes(32), 'hex');
begin
  select * into b from public.bookings where id = p_booking_id;
  select tracking_token_days_after into v_days from public.company_settings where company_id = b.company_id;

  update public.booking_tracking_tokens set revoked_at = now()
   where booking_id = b.id and revoked_at is null and purpose = 'TRACKING';

  insert into public.booking_tracking_tokens (company_id, booking_id, token_hash, token_expires_at)
  values (b.company_id, b.id, encode(extensions.digest(v_token, 'sha256'), 'hex'),
          greatest(b.ends_at, now()) + make_interval(days => v_days));
  return v_token;
end;
$$;

-- -----------------------------------------------------------------------------
-- รายการการจองตามเบอร์โทร (เรียกผ่าน Edge Function เท่านั้น)
--   ขอบเขต: Guest ที่ ACTIVE ของบริษัทนี้, นัดตั้งแต่ 90 วันก่อนเป็นต้นไป, ไม่เกิน 20 รายการ
--   token LOOKUP อายุ 30 นาที
-- -----------------------------------------------------------------------------
create or replace function public.guest_bookings_by_phone(p_company_code text, p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid := private.company_id_by_code(p_company_code);
  v_phone   text := private.normalize_phone(p_phone);
  v_result  jsonb := '[]'::jsonb;
  v_token   text;
  r         record;
begin
  if v_company is null or v_phone is null then
    return v_result;
  end if;

  -- เก็บกวาด token LOOKUP ที่หมดอายุแล้ว
  delete from public.booking_tracking_tokens
   where purpose = 'LOOKUP' and token_expires_at < now() - interval '1 day';

  perform private.expire_stale_bookings();

  for r in
    select b.id, b.company_id
      from public.bookings b
      join public.customers c on c.id = b.customer_id
     where c.company_id = v_company
       and c.phone = v_phone
       and c.status = 'ACTIVE'
       and c.auth_user_id is null
       and b.starts_at > now() - interval '90 days'
     order by b.starts_at desc
     limit 20
  loop
    v_token := 'trk_' || encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.booking_tracking_tokens (company_id, booking_id, token_hash, token_expires_at, purpose)
    values (r.company_id, r.id, encode(extensions.digest(v_token, 'sha256'), 'hex'), now() + interval '30 minutes', 'LOOKUP');
    v_result := v_result || jsonb_build_array(
      private.booking_customer_view(r.id) || jsonb_build_object('tracking_token', v_token));
  end loop;

  return v_result;
end;
$$;

revoke all on function public.guest_bookings_by_phone(text, text) from public, anon, authenticated;
grant execute on function public.guest_bookings_by_phone(text, text) to service_role;
