-- ลูกค้าเป็น Guest อย่างเดียว: เลิกระบบสมาชิก (สมัคร/เข้าสู่ระบบ) ของแอปลูกค้า
-- 1) ปิด RPC ฝั่งสมาชิกทั้งหมด (สมัคร, ดู/แก้ข้อมูลตัวเอง, จองแบบสมาชิก, ดู/ยกเลิกการจองของตัวเอง, PDPA self-service)
--    ไม่ลบ function ทิ้ง (เก็บประวัติ/ย้อนกลับได้) แค่ถอนสิทธิ์เรียกจาก anon/authenticated
-- 2) พนักงานแก้ชื่อ/เบอร์/อีเมลของลูกค้าได้ทุกคน (รวมลูกค้าที่เคยสมัครสมาชิกไว้) และจับคู่ลูกค้าได้ทุกคน

revoke execute on function public.register_customer(text, text, text, text, uuid, boolean) from anon, authenticated;
revoke execute on function public.my_customer(text) from anon, authenticated;
revoke execute on function public.update_my_customer(text, text, text, text) from anon, authenticated;
revoke execute on function public.set_my_marketing_consent(text, boolean) from anon, authenticated;
revoke execute on function public.export_my_data(text) from anon, authenticated;
revoke execute on function public.request_my_data_deletion(text, text) from anon, authenticated;
revoke execute on function public.create_member_booking(text, uuid, timestamptz, uuid[], text, text) from anon, authenticated;
revoke execute on function public.my_bookings(text) from anon, authenticated;
revoke execute on function public.my_booking(text, uuid) from anon, authenticated;
revoke execute on function public.my_booking_payment_context(text, uuid) from anon, authenticated;
revoke execute on function public.cancel_my_booking(text, uuid, text) from anon, authenticated;
revoke execute on function public.my_service_history(text) from anon, authenticated;

-- แก้ข้อมูลลูกค้า (พนักงาน): ไม่แยกสมาชิก/Guest แล้ว
create or replace function public.update_customer(
  p_customer_id uuid, p_first_name text, p_last_name text, p_phone text, p_email text, p_staff_note text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c       public.customers;
  v_phone text := private.normalize_phone(p_phone);
begin
  select * into c from public.customers where id = p_customer_id for update;
  if c.id is null or not private.is_company_member(c.company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if v_phone is null then
    raise exception 'เบอร์โทรไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  update public.customers
     set first_name = p_first_name, last_name = coalesce(p_last_name, ''), phone = v_phone,
         email = p_email, staff_note = nullif(trim(p_staff_note), '')
   where id = c.id;
end;
$$;

-- จับคู่ลูกค้า (พนักงานยืนยัน): ต้นทางเป็นใครก็ได้ (ไม่มีสมาชิกแล้ว)
create or replace function public.merge_customers(p_source_id uuid, p_target_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.customers;
  t public.customers;
begin
  if p_source_id = p_target_id then
    raise exception 'เลือกลูกค้าคนเดียวกัน' using errcode = 'invalid_parameter_value';
  end if;
  -- ล็อกตามลำดับ id กัน deadlock
  perform 1 from public.customers where id in (p_source_id, p_target_id) order by id for update;
  select * into s from public.customers where id = p_source_id;
  select * into t from public.customers where id = p_target_id;

  if s.id is null or t.id is null or s.company_id <> t.company_id or not private.is_company_member(s.company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if s.status <> 'ACTIVE' or t.status <> 'ACTIVE' then
    raise exception 'ลูกค้าต้องอยู่ในสถานะใช้งานทั้งคู่' using errcode = 'check_violation';
  end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาระบุเหตุผล' using errcode = 'invalid_parameter_value';
  end if;

  perform set_config('app.audit_reason', trim(p_reason), true);

  update public.customers
     set status = 'MERGED', merged_into_id = t.id, merged_at = now()
   where id = s.id;

  -- ย้ายหมายเหตุของร้านไปไว้ที่ปลายทาง
  if s.staff_note is not null then
    update public.customers
       set staff_note = left(concat_ws(E'\n', t.staff_note, '[รวมจากลูกค้าอื่น] ' || s.staff_note), 1000)
     where id = t.id;
  end if;
end;
$$;
