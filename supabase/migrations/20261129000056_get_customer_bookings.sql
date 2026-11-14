-- หน้า "ลูกค้า" (Staff): รายละเอียดลูกค้าแสดงประวัติการจองด้วย (ล่าสุด 50 รายการ)
--   วันเวลานัด · สาขา · สถานะ · จำนวนคน · บริการแต่ละคน · ยอดรวม · มัดจำ · หมายเหตุลูกค้า
create or replace function public.get_customer(p_customer_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.customers;
begin
  select * into c from public.customers where id = p_customer_id;
  if c.id is null or not private.is_company_member(c.company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;

  perform private.write_audit(p_action => 'CUSTOMER_VIEWED', p_company_id => c.company_id,
                              p_table_name => 'customers', p_record_id => c.id);

  return jsonb_build_object(
    'customer_id', c.id, 'first_name', c.first_name, 'last_name', c.last_name,
    'phone', c.phone, 'email', c.email, 'staff_note', c.staff_note,
    'is_member', c.auth_user_id is not null, 'created_channel', c.created_channel,
    'status', c.status, 'merged_into_id', c.merged_into_id, 'created_at', c.created_at,
    'marketing_consent', (
      select cc.granted from public.customer_consents cc
       where cc.customer_id = c.id and cc.consent_type = 'MARKETING'
       order by cc.recorded_at desc, cc.created_at desc limit 1),
    'bookings', coalesce((
      select jsonb_agg(x.v order by x.starts_at desc)
        from (
          select b.starts_at, jsonb_build_object(
                   'booking_id', b.id, 'booking_code', b.booking_code, 'channel', b.channel,
                   'status', b.status, 'starts_at', b.starts_at, 'ends_at', b.ends_at,
                   'items_count', b.items_count, 'total_amount', b.total_amount,
                   'deposit_required', b.deposit_required, 'deposit_status', b.deposit_status,
                   'customer_note', b.customer_note, 'created_at', b.created_at,
                   'branch_name', br.name,
                   'items', coalesce((
                     select jsonb_agg(jsonb_build_object(
                              'service_name', i.service_name, 'duration_minutes', i.duration_minutes,
                              'price', i.line_total) order by i.created_at, i.id)
                       from public.booking_items i where i.booking_id = b.id), '[]'::jsonb)
                 ) as v
            from public.bookings b
            join public.branches br on br.id = b.branch_id
           where b.customer_id = c.id
             and (private.is_company_owner(b.company_id) or private.has_branch_access(b.branch_id))
           order by b.starts_at desc
           limit 50
        ) x), '[]'::jsonb)
  );
end;
$$;
