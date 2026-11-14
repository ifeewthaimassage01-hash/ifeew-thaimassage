-- ลูกค้าที่จองผ่านเว็บกด "เชื่อม LINE" ในหน้าสถานะการจอง (booking-tracking action=line_link)
-- คืนบริษัท/สถานะ/ผูก LINE แล้วหรือยัง ของการจองตาม tracking token (service_role เท่านั้น)
create or replace function public.line_booking_status(p_token text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'company_id', b.company_id,
    'status', b.status,
    'linked', exists (select 1 from private.booking_line_recipients r where r.booking_id = b.id)
  )
    from public.bookings b
   where b.id = private.booking_id_by_token(p_token);
$$;

revoke all on function public.line_booking_status(text) from public, anon, authenticated;
grant execute on function public.line_booking_status(text) to service_role;
