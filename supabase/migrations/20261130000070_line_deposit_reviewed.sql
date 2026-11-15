-- แจ้งเตือนเรื่องสลิปมัดจำให้แยกชัด "ยังไม่ตรวจ" กับ "ตรวจแล้ว"
--   DEPOSIT_SLIP      ลูกค้าส่งสลิป ยังไม่มีใครตรวจ   → "จองใหม่ · สลิปรอตรวจ"
--   DEPOSIT_REVIEWED  (ใหม่) ตรวจสลิปแล้ว            → "สลิปผ่าน · ยืนยันการจองแล้ว" / "สลิปไม่ผ่าน · ยกเลิกการจองแล้ว"
--                     พนักงานกดตรวจ (บอกชื่อคนตรวจ กลุ่มจะได้ไม่ตรวจซ้ำ) หรือ SlipOK ตรวจผ่านอัตโนมัติ
--                     (สลิปที่ผ่านอัตโนมัติไม่เคยผ่านขั้น "รอตรวจ" — ก่อนหน้านี้กลุ่มไม่รู้เลยว่ามีการจองนี้)
--   เลิกผูก "มีการจองใหม่" กับสลิป (068) — ตัวเลือกแต่ละอันทำงานตามชื่อของมัน

alter table private.push_outbox drop constraint push_outbox_event_check;
alter table private.push_outbox add constraint push_outbox_event_check
  check (event in ('NEW_BOOKING', 'DEPOSIT_SLIP', 'DEPOSIT_REVIEWED', 'BOOKING_CANCELLED', 'WALK_IN', 'SERVICE_DONE', 'BOOKING_REMINDER'));

alter table private.line_settings drop constraint line_settings_group_events_check;
alter table private.line_settings add constraint line_settings_group_events_check
  check (group_events <@ array['NEW_BOOKING', 'DEPOSIT_SLIP', 'DEPOSIT_REVIEWED', 'BOOKING_CANCELLED', 'WALK_IN', 'SERVICE_DONE']);

-- ร้านที่เปิดแจ้งสลิปรอตรวจไว้ ให้ได้แจ้ง "ตรวจแล้ว" ด้วย (ปิดเองได้ในหน้า LINE OA)
update private.line_settings
   set group_events = group_events || array['DEPOSIT_REVIEWED']
 where 'DEPOSIT_SLIP' = any (group_events) and not ('DEPOSIT_REVIEWED' = any (group_events));

create or replace function private.tg_push_booking_deposits()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'PENDING_REVIEW' then
      perform private.push_enqueue('DEPOSIT_SLIP', new.company_id, new.branch_id, new.id, null);
    elsif new.status = 'VERIFIED' then
      -- SlipOK ตรวจผ่านทันทีตอนส่งสลิป
      perform private.push_enqueue('DEPOSIT_REVIEWED', new.company_id, new.branch_id, new.id, null);
    end if;
  elsif old.status = 'PENDING_REVIEW' and new.status in ('VERIFIED', 'REJECTED') then
    perform private.push_enqueue('DEPOSIT_REVIEWED', new.company_id, new.branch_id, new.id, new.reviewed_by);
  end if;
  return null;
end;
$$;

drop trigger if exists booking_deposits_push on public.booking_deposits;
create trigger booking_deposits_push
  after insert or update of status on public.booking_deposits
  for each row execute function private.tg_push_booking_deposits();

create or replace function private.push_enqueue(
  p_event text, p_company_id uuid, p_branch_id uuid, p_ref_id uuid, p_actor_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id  uuid;
  v_url text;
begin
  if p_event <> 'BOOKING_REMINDER'
     and not exists (
       select 1 from public.push_subscriptions s
        where s.company_id = p_company_id and (s.branch_id is null or s.branch_id = p_branch_id))
     and not exists (
       select 1 from private.line_settings ls
        where ls.company_id = p_company_id and ls.access_token_secret_id is not null
          and p_event = any (ls.group_events)
          and exists (
            select 1 from private.line_groups g
             where g.company_id = p_company_id and (g.branch_id is null or g.branch_id = p_branch_id)))
  then
    return;
  end if;
  select dispatch_url into v_url from private.push_config;
  insert into private.push_outbox (event, company_id, branch_id, ref_id, actor_id)
  values (p_event, p_company_id, p_branch_id, p_ref_id, p_actor_id)
  returning id into v_id;
  perform net.http_post(
    url := v_url,
    body := jsonb_build_object('id', v_id),
    headers := '{"Content-Type": "application/json"}'::jsonb,
    timeout_milliseconds := 10000
  );
exception when others then
  raise warning 'push_enqueue %: %', p_event, sqlerrm;
end;
$$;

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
  v_review    text;
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
    v_title := 'จองใหม่ · สลิปรอตรวจ';
    v_body := format('คุณ%s · %s น. · %s คน · ฿%s · มัดจำ ฿%s รอตรวจสลิป',
      r.first_name, to_char(r.starts_at at time zone 'Asia/Bangkok', 'DD/MM HH24:MI'),
      r.items_count, to_char(r.total_amount, 'FM999,999,990'), to_char(r.amount, 'FM999,999,990'));
    v_url := '/bookings';

  elsif o.event = 'DEPOSIT_REVIEWED' then
    select d.status, d.verification_source, d.amount, bk.starts_at, c.first_name,
           coalesce(nullif(trim(p.display_name), ''), 'พนักงาน') as reviewer
      into r
      from public.booking_deposits d
      join public.bookings bk on bk.id = d.booking_id
      join public.customers c on c.id = bk.customer_id
      left join public.profiles p on p.id = d.reviewed_by
     where d.id = o.ref_id;
    if r.status = 'VERIFIED' then
      v_title := 'สลิปผ่าน · ยืนยันการจองแล้ว';
      v_review := case when r.verification_source = 'AUTO' then 'ตรวจอัตโนมัติ' else 'ตรวจโดย ' || r.reviewer end;
    else
      v_title := 'สลิปไม่ผ่าน · ยกเลิกการจองแล้ว';
      v_review := 'ตรวจโดย ' || r.reviewer;
    end if;
    v_body := format('คุณ%s · นัด %s น. · มัดจำ ฿%s · %s',
      r.first_name, to_char(r.starts_at at time zone 'Asia/Bangkok', 'DD/MM HH24:MI'), to_char(r.amount, 'FM999,999,990'), v_review);
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
                         and o.event = any (coalesce(ls.group_events, array[]::text[]))
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
        when o.event in ('DEPOSIT_SLIP', 'DEPOSIT_REVIEWED') then private.line_booking_data((select d.booking_id from public.booking_deposits d where d.id = o.ref_id))
      end,
      'review', v_review,
      'review_ok', case when o.event = 'DEPOSIT_REVIEWED' then v_title like 'สลิปผ่าน%' end,
      'slip_amount', case when o.event in ('DEPOSIT_SLIP', 'DEPOSIT_REVIEWED') then (select d.amount from public.booking_deposits d where d.id = o.ref_id) end)
  );
end;
$$;
