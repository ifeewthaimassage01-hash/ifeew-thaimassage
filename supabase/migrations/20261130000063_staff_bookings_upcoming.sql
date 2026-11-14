-- หน้าการจอง (แอปพนักงาน) ดู "ทั้งหมด" ได้: การจองตั้งแต่วันนี้เป็นต้นไป + สลิปที่ยังรอตรวจทุกวัน
-- (ก่อนหน้านี้ดูได้ทีละวัน สลิปของวันอื่นจึงหลุดสายตา ทำให้ตรวจสลิปให้ลูกค้าช้า)
-- ข้อมูลแต่ละแถวเหมือน staff_bookings ทุกประการ (ใช้ private.staff_booking_json ร่วมกัน)

create or replace function private.staff_booking_json(p_booking_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'booking_id', b.id, 'booking_code', b.booking_code, 'status', b.status, 'channel', b.channel,
    'starts_at', b.starts_at, 'ends_at', b.ends_at,
    'customer_id', c.id, 'customer_name', trim(c.first_name || ' ' || c.last_name),
    'phone_masked', private.mask_phone(c.phone), 'is_member', c.auth_user_id is not null,
    'items', (select jsonb_agg(jsonb_build_object('service_name', i.service_name, 'duration_minutes', i.duration_minutes,
                                                  'unit_price', i.unit_price) order by i.created_at, i.id)
                from public.booking_items i where i.booking_id = b.id),
    'total_amount', b.total_amount, 'deposit_required', b.deposit_required, 'deposit_status', b.deposit_status,
    'hold_expires_at', b.hold_expires_at, 'customer_note', b.customer_note, 'staff_note', b.staff_note,
    'cancel_reason', b.cancel_reason,
    'deposits', (select jsonb_agg(jsonb_build_object(
                    'deposit_id', d.id, 'status', d.status, 'amount', d.amount, 'slip_path', d.slip_path,
                    'provider_code', d.provider_code, 'provider_message', d.provider_message,
                    'slip_amount', d.slip_amount, 'slip_trans_ref', d.slip_trans_ref, 'slip_trans_at', d.slip_trans_at,
                    'slip_sender_name', d.slip_sender_name, 'slip_receiver_name', d.slip_receiver_name,
                    'refund_status', d.refund_status, 'refund_reference', d.refund_reference, 'created_at', d.created_at)
                    order by d.created_at)
                   from public.booking_deposits d where d.booking_id = b.id)
  )
    from public.bookings b
    join public.customers c on c.id = b.customer_id
   where b.id = p_booking_id;
$$;

revoke all on function private.staff_booking_json(uuid) from public;

-- การจองตั้งแต่ต้นวันนี้ (เวลาของบริษัท) + ทุกการจองที่สลิปรอตรวจ ไม่ว่าวันไหน · เรียงตามเวลานัด · สูงสุด 300 รายการ
create or replace function public.staff_bookings_upcoming(p_branch_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tz    text;
  v_start timestamptz;
begin
  perform private.require_branch_access(p_branch_id);
  select s.timezone into v_tz from public.branches b join public.company_settings s on s.company_id = b.company_id
   where b.id = p_branch_id;
  v_start := (now() at time zone v_tz)::date::timestamp at time zone v_tz;

  return coalesce((
    select jsonb_agg(private.staff_booking_json(x.id) order by x.starts_at, x.created_at)
      from (
        select b.id, b.starts_at, b.created_at
          from public.bookings b
         where b.branch_id = p_branch_id
           and (b.starts_at >= v_start or b.deposit_status = 'PENDING_REVIEW')
         order by b.starts_at, b.created_at
         limit 300
      ) x
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.staff_bookings_upcoming(uuid) from public, anon;
grant execute on function public.staff_bookings_upcoming(uuid) to authenticated;
