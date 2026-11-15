-- ข้อความ LINE เป็น Flex Message (การ์ด) — ยืนยันการจอง / เตือนนัด / แจ้งเตือนกลุ่มพนักงาน
--   SQL ส่งข้อมูลเป็นโครงสร้าง (line_flex / flex) ให้ Edge Function สร้างการ์ด
--   ข้อความธรรมดา (line_text / text) ยังส่งคู่กัน ใช้เป็น altText (ข้อความที่ขึ้นในรายการแชท/แจ้งเตือนบนมือถือ)

-- วันที่แบบไทยไม่มีเวลา เช่น "วันจันทร์ที่ 16 พ.ย."
create or replace function private.th_date(p timestamptz)
returns text
language sql
stable
set search_path = ''
as $$
  select 'วัน' || (array['อาทิตย์','จันทร์','อังคาร','พุธ','พฤหัสบดี','ศุกร์','เสาร์'])[extract(dow from p at time zone 'Asia/Bangkok')::int + 1]
      || 'ที่ ' || extract(day from p at time zone 'Asia/Bangkok')::int || ' '
      || (array['ม.ค.','ก.พ.','มี.ค.','เม.ย.','พ.ค.','มิ.ย.','ก.ค.','ส.ค.','ก.ย.','ต.ค.','พ.ย.','ธ.ค.'])[extract(month from p at time zone 'Asia/Bangkok')::int];
$$;
revoke all on function private.th_date(timestamptz) from public;

-- ข้อมูลการจองสำหรับการ์ด LINE
create or replace function private.line_booking_data(p_booking_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'customer_name', c.first_name,
    'branch_name', br.name,
    'branch_phone', br.phone,
    'map_url', br.map_url,
    'booking_code', b.booking_code,
    'date_label', private.th_date(b.starts_at),
    'time_label', to_char(b.starts_at at time zone 'Asia/Bangkok', 'HH24:MI') || '–' || to_char(b.ends_at at time zone 'Asia/Bangkok', 'HH24:MI') || ' น.',
    'short_label', to_char(b.starts_at at time zone 'Asia/Bangkok', 'DD/MM HH24:MI') || ' น.',
    'people', b.items_count,
    'total', b.total_amount,
    'deposit_required', b.deposit_required,
    'deposit_status', b.deposit_status,
    'hold_until', to_char(b.hold_expires_at at time zone 'Asia/Bangkok', 'HH24:MI'),
    'items', coalesce((select jsonb_agg(jsonb_build_object('name', i.service_name, 'minutes', i.duration_minutes) order by i.starts_at, i.created_at)
                         from public.booking_items i where i.booking_id = b.id), '[]'::jsonb)
  )
    from public.bookings b
    join public.customers c on c.id = b.customer_id
    join public.branches br on br.id = b.branch_id
   where b.id = p_booking_id;
$$;
revoke all on function private.line_booking_data(uuid) from public;

create or replace function public.push_claim(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  o         private.push_outbox;
  ls        private.line_settings;
  v_title   text;
  v_body    text;
  v_url     text;
  v_branch  text;
  r         record;
  -- การจองที่ต้องมัดจำ: ยังไม่ส่งเข้ากลุ่ม LINE ตอนจอง (รอส่งพร้อมสลิป)
  v_line_skip boolean := false;
begin
  update private.push_outbox
     set claimed_at = now()
   where id = p_id and claimed_at is null and created_at > now() - interval '15 minutes'
  returning * into o;
  if o.id is null then
    return null;
  end if;
  select * into ls from private.line_settings where company_id = o.company_id;

  -- เตือนลูกค้าก่อนถึงนัด: ส่ง LINE หาลูกค้าคนเดียว ไม่มี Web Push
  if o.event = 'BOOKING_REMINDER' then
    select rcp.line_user_id into r from private.booking_line_recipients rcp where rcp.booking_id = o.ref_id;
    if r.line_user_id is null then
      return null;
    end if;
    return jsonb_build_object(
      'company_id', o.company_id,
      'title', 'แจ้งเตือนนัดหมาย', 'body', '', 'url', '', 'tag', 'reminder-' || o.ref_id,
      'subscriptions', '[]'::jsonb,
      'line_to', jsonb_build_array(r.line_user_id),
      'line_text', private.line_booking_text(o.ref_id, 'REMINDER')
                   || coalesce(E'\n\nตรวจสอบการจอง ' || ls.customer_url || '/check-booking', ''),
      'line_flex', jsonb_build_object(
        'kind', 'reminder',
        'booking', private.line_booking_data(o.ref_id),
        'link', ls.customer_url || '/check-booking')
    );
  end if;

  select b.name into v_branch from public.branches b where b.id = o.branch_id;

  if o.event in ('NEW_BOOKING', 'BOOKING_CANCELLED') then
    select bk.starts_at, bk.items_count, bk.total_amount, bk.deposit_required, c.first_name
      into r
      from public.bookings bk join public.customers c on c.id = bk.customer_id
     where bk.id = o.ref_id;
    v_line_skip := o.event = 'NEW_BOOKING' and coalesce(r.deposit_required, 0) > 0;
    if o.event = 'NEW_BOOKING' then
      v_title := 'การจองใหม่';
      v_body := format('คุณ%s · %s น. · %s คน · ฿%s',
        r.first_name, to_char(r.starts_at at time zone 'Asia/Bangkok', 'DD/MM HH24:MI'),
        r.items_count, to_char(r.total_amount, 'FM999,999,990'));
    else
      v_title := 'ลูกค้ายกเลิกการจอง';
      v_body := format('คุณ%s · นัด %s น.', r.first_name, to_char(r.starts_at at time zone 'Asia/Bangkok', 'DD/MM HH24:MI'));
    end if;
    v_url := '/bookings';

  elsif o.event = 'DEPOSIT_SLIP' then
    select d.amount, bk.starts_at, bk.items_count, bk.total_amount, c.first_name
      into r
      from public.booking_deposits d
      join public.bookings bk on bk.id = d.booking_id
      join public.customers c on c.id = bk.customer_id
     where d.id = o.ref_id;
    -- การจองที่ต้องมัดจำส่งเข้ากลุ่มครั้งเดียวตอนนี้: รายละเอียดการจอง + สลิป
    v_title := 'จองใหม่ + สลิปมัดจำ';
    v_body := format('คุณ%s · %s น. · %s คน · ฿%s · มัดจำ ฿%s รอตรวจสลิป',
      r.first_name, to_char(r.starts_at at time zone 'Asia/Bangkok', 'DD/MM HH24:MI'),
      r.items_count, to_char(r.total_amount, 'FM999,999,990'), to_char(r.amount, 'FM999,999,990'));
    v_url := '/bookings';

  elsif o.event = 'WALK_IN' then
    select count(*) as n, string_agg(i.service_name || ' ' || i.duration_minutes || ' นาที', ', ' order by i.created_at) as items
      into r
      from public.service_order_items i
     where i.service_order_id = o.ref_id and i.status = 'ACTIVE';
    v_title := 'รับลูกค้าหน้าร้าน';
    v_body := case when r.n > 0 then format('%s คน · %s', r.n, r.items) else 'มีลูกค้าหน้าร้านเข้ามาใหม่' end;
    v_url := '/queue';

  elsif o.event = 'SERVICE_DONE' then
    select q.queue_number, i.service_name, i.duration_minutes,
           (select e.nickname from public.service_assignments a join public.employees e on e.id = a.employee_id
             where a.queue_item_id = q.id and a.status <> 'CANCELLED' order by a.assigned_at desc limit 1) as therapist
      into r
      from public.queue_items q join public.service_order_items i on i.id = q.service_order_item_id
     where q.id = o.ref_id;
    v_title := 'บริการเสร็จแล้ว';
    v_body := format('คิว %s · %s %s นาที%s · รอชำระเงิน',
      lpad(r.queue_number::text, 3, '0'), r.service_name, r.duration_minutes,
      coalesce(' · หมอ' || r.therapist, ''));
    v_url := '/payments';
  end if;

  if v_branch is not null then
    v_title := v_title || ' · ' || v_branch;
  end if;

  return jsonb_build_object(
    'company_id', o.company_id,
    'title', v_title,
    'body', v_body,
    'url', v_url,
    'tag', lower(o.event) || '-' || o.ref_id,
    'subscriptions', coalesce((
      select jsonb_agg(jsonb_build_object('endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth))
        from public.push_subscriptions s
       where s.company_id = o.company_id
         and (s.branch_id is null or s.branch_id = o.branch_id)
         and (o.actor_id is null or s.user_id <> o.actor_id) -- คนที่ทำรายการเองไม่ต้องได้แจ้งเตือน
    ), '[]'::jsonb),
    'line_to', case when not v_line_skip
                         and (o.event = any (coalesce(ls.group_events, array[]::text[]))
                              or (o.event = 'DEPOSIT_SLIP' and 'NEW_BOOKING' = any (coalesce(ls.group_events, array[]::text[]))))
                    then coalesce((
      select jsonb_agg(g.group_id)
        from private.line_groups g
       where g.company_id = o.company_id and (g.branch_id is null or g.branch_id = o.branch_id)
    ), '[]'::jsonb) else '[]'::jsonb end,
    'line_text', '🔔 ' || v_title || E'\n' || v_body || coalesce(E'\n' || ls.staff_url || v_url, ''),
    'line_flex', jsonb_build_object(
      'kind', 'staff',
      'event', o.event,
      'title', v_title,
      'body', v_body,
      'link', ls.staff_url || v_url,
      'booking', case
        when o.event in ('NEW_BOOKING', 'BOOKING_CANCELLED') then private.line_booking_data(o.ref_id)
        when o.event = 'DEPOSIT_SLIP' then private.line_booking_data((select d.booking_id from public.booking_deposits d where d.id = o.ref_id))
      end,
      'slip_amount', case when o.event = 'DEPOSIT_SLIP' then (select d.amount from public.booking_deposits d where d.id = o.ref_id) end)
  );
end;
$$;

-- ผูกการจองกับ LINE ของลูกค้า → { text, flex } (เดิมคืน text อย่างเดียว)
drop function public.line_attach_booking(text, text, text);
create or replace function public.line_attach_booking(p_token text, p_line_user_id text, p_site_url text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id  uuid := private.booking_id_by_token(p_token);
  s     private.line_settings;
  b     public.bookings;
  v_url text;
begin
  if v_id is null or p_line_user_id !~ '^U[0-9a-f]{32}$' then
    return null;
  end if;
  select * into b from public.bookings where id = v_id;
  select * into s from private.line_settings where company_id = b.company_id;

  insert into private.booking_line_recipients (booking_id, line_user_id, reminded_at)
  values (v_id, p_line_user_id,
          -- จองกระชั้นกว่าช่วงเตือน / ปิดการเตือน → ไม่ต้องเตือน
          case when not coalesce(s.reminder_enabled, true)
                 or b.starts_at - now() <= make_interval(mins => coalesce(s.reminder_minutes, 120)) then now() end)
  on conflict (booking_id) do update set line_user_id = excluded.line_user_id;

  if not coalesce(s.confirm_enabled, true) then
    return null;
  end if;
  v_url := coalesce(s.customer_url, nullif(p_site_url, ''));
  return jsonb_build_object(
    'text', private.line_booking_text(v_id, 'CONFIRM')
      || coalesce(E'\n\nดูสถานะ · ชำระมัดจำ · ยกเลิก\n' || v_url || '/t/' || p_token, ''),
    'flex', jsonb_build_object(
      'kind', 'confirm',
      'booking', private.line_booking_data(v_id),
      'link', v_url || '/t/' || p_token));
end;
$$;

revoke all on function public.line_attach_booking(text, text, text) from public, anon, authenticated;
grant execute on function public.line_attach_booking(text, text, text) to service_role;
