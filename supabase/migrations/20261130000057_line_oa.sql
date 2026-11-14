-- เชื่อม LINE OA (Messaging API)
--
-- 1) กลุ่ม LINE ของร้านรับแจ้งเตือน (NEW_BOOKING · DEPOSIT_SLIP · BOOKING_CANCELLED)
--    เจ้าของร้านสร้างรหัสในแอปพนักงาน → เชิญบอทเข้ากลุ่ม → พิมพ์ "เชื่อมร้าน <รหัส>" ในกลุ่ม
--    (Edge Function line-webhook ตรวจลายเซ็น LINE แล้วเรียก line_link_group)
-- 2) ลูกค้าที่จองผ่าน LIFF: guest-booking ตรวจ ID token → line_attach_booking → ส่งยืนยันการจอง
--    + pg_cron ส่งเตือนก่อนถึงนัด (BOOKING_REMINDER) ผ่านคิวเดิมของ push-dispatch
--
-- ใช้ pipeline เดิม: trigger → private.push_outbox → pg_net → push-dispatch → push_claim(id)
--   push_claim คืน line_to (group/user id) + line_text เพิ่ม · push-dispatch ส่ง LINE push message
-- ข้อความ push ของ LINE นับโควตาต่อผู้รับ (กลุ่ม 5 คน = 5 ข้อความ) → กลุ่มรับเฉพาะ 3 เหตุการณ์ข้างบน

-- -----------------------------------------------------------------------------
-- ตาราง (private: เข้าถึงผ่าน RPC เท่านั้น)
-- -----------------------------------------------------------------------------
alter table private.push_config
  add column customer_url text not null default 'https://ifeew.vercel.app' check (customer_url ~ '^https?://'),
  add column staff_url text not null default 'https://ifeew-staff.vercel.app' check (staff_url ~ '^https?://'),
  add column line_reminder_minutes integer not null default 120 check (line_reminder_minutes between 15 and 1440);

create table private.line_groups (
  group_id    text primary key check (group_id ~ '^C[0-9a-f]{32}$'),
  company_id  uuid not null references public.companies (id) on delete cascade,
  branch_id   uuid references public.branches (id) on delete cascade, -- NULL = ทุกสาขา
  group_name  text check (group_name is null or char_length(group_name) <= 200),
  linked_at   timestamptz not null default now(),
  linked_by   uuid references auth.users (id) on delete set null
);
create index line_groups_company_idx on private.line_groups (company_id, branch_id);

create table private.line_link_codes (
  code        text primary key check (code ~ '^[A-Z2-9]{6}$'),
  company_id  uuid not null references public.companies (id) on delete cascade,
  branch_id   uuid references public.branches (id) on delete cascade,
  created_by  uuid not null references auth.users (id) on delete cascade,
  expires_at  timestamptz not null
);

create table private.booking_line_recipients (
  booking_id    uuid primary key references public.bookings (id) on delete cascade,
  line_user_id  text not null check (line_user_id ~ '^U[0-9a-f]{32}$'),
  created_at    timestamptz not null default now(),
  reminded_at   timestamptz
);
create index booking_line_recipients_pending_idx on private.booking_line_recipients (booking_id) where reminded_at is null;

alter table private.push_outbox drop constraint push_outbox_event_check;
alter table private.push_outbox add constraint push_outbox_event_check
  check (event in ('NEW_BOOKING', 'DEPOSIT_SLIP', 'BOOKING_CANCELLED', 'WALK_IN', 'SERVICE_DONE', 'BOOKING_REMINDER'));

-- -----------------------------------------------------------------------------
-- ข้อความสำหรับลูกค้า
-- -----------------------------------------------------------------------------
create or replace function private.th_datetime(p timestamptz)
returns text
language sql
stable
set search_path = ''
as $$
  select 'วัน' || (array['อาทิตย์','จันทร์','อังคาร','พุธ','พฤหัสบดี','ศุกร์','เสาร์'])[extract(dow from p at time zone 'Asia/Bangkok')::int + 1]
      || 'ที่ ' || extract(day from p at time zone 'Asia/Bangkok')::int || ' '
      || (array['ม.ค.','ก.พ.','มี.ค.','เม.ย.','พ.ค.','มิ.ย.','ก.ค.','ส.ค.','ก.ย.','ต.ค.','พ.ย.','ธ.ค.'])[extract(month from p at time zone 'Asia/Bangkok')::int]
      || ' เวลา ' || to_char(p at time zone 'Asia/Bangkok', 'HH24:MI') || ' น.';
$$;

-- p_kind: CONFIRM (ตอนจอง) | REMINDER (ก่อนถึงนัด)
create or replace function private.line_booking_text(p_booking_id uuid, p_kind text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  b       record;
  v_items text;
  v_text  text;
begin
  select bk.*, c.first_name, br.name as branch_name, br.phone as branch_phone, br.map_url
    into b
    from public.bookings bk
    join public.customers c on c.id = bk.customer_id
    join public.branches br on br.id = bk.branch_id
   where bk.id = p_booking_id;
  if b.id is null then
    return null;
  end if;

  select string_agg('• ' || i.service_name || ' ' || i.duration_minutes || ' นาที', E'\n' order by i.starts_at, i.created_at)
    into v_items
    from public.booking_items i where i.booking_id = b.id;

  if p_kind = 'REMINDER' then
    v_text := format(E'⏰ แจ้งเตือนนัดหมาย\nคุณ%s มีนัดนวดกับเรา%s\n\n📍 %s\n🗓 %s\n%s',
      b.first_name,
      case when b.starts_at - now() < interval '1 day' then 'เร็ว ๆ นี้' else '' end,
      b.branch_name, private.th_datetime(b.starts_at), coalesce(v_items, ''));
    v_text := v_text || E'\n\nกรุณามาก่อนเวลาประมาณ 10 นาที ถ้ามาไม่ได้รบกวนแจ้งร้านล่วงหน้า';
  else
    v_text := format(E'✅ ได้รับการจองแล้ว\nคุณ%s ขอบคุณที่จองกับเรา\n\n📍 %s\n🗓 %s\n%s\n\nรวม %s คน · ฿%s',
      b.first_name, b.branch_name, private.th_datetime(b.starts_at), coalesce(v_items, ''),
      b.items_count, to_char(b.total_amount, 'FM999,999,990'));
    if b.booking_code is not null then
      v_text := v_text || E'\nรหัสการจอง ' || b.booking_code;
    end if;
    if b.deposit_status = 'AWAITING_PAYMENT' then
      v_text := v_text || format(E'\n\n💳 กรุณาชำระมัดจำ ฿%s%s ไม่เช่นนั้นการจองจะถูกยกเลิกอัตโนมัติ',
        to_char(b.deposit_required, 'FM999,999,990'),
        coalesce(' ภายใน ' || to_char(b.hold_expires_at at time zone 'Asia/Bangkok', 'HH24:MI') || ' น.', ''));
    end if;
  end if;

  if b.branch_phone is not null then
    v_text := v_text || E'\n📞 ' || b.branch_phone;
  end if;
  if b.map_url is not null then
    v_text := v_text || E'\n🗺 ' || b.map_url;
  end if;
  return v_text;
end;
$$;

revoke all on function private.th_datetime(timestamptz) from public;
revoke all on function private.line_booking_text(uuid, text) from public;

-- -----------------------------------------------------------------------------
-- เจ้าของร้าน: จัดการกลุ่ม LINE (แอปพนักงาน /settings/line)
-- -----------------------------------------------------------------------------
create or replace function public.line_create_link_code(p_company_id uuid, p_branch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_alpha constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- 32 ตัว ไม่มี I O 0 1
  v_bytes bytea;
  v_code  text;
  v_exp   timestamptz := now() + interval '30 minutes';
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'เฉพาะเจ้าของร้าน' using errcode = 'insufficient_privilege';
  end if;
  if p_branch_id is not null and not exists (
    select 1 from public.branches where id = p_branch_id and company_id = p_company_id
  ) then
    raise exception 'ไม่พบสาขา' using errcode = 'invalid_parameter_value';
  end if;

  delete from private.line_link_codes where expires_at < now() or (company_id = p_company_id and created_by = auth.uid());
  loop
    v_bytes := extensions.gen_random_bytes(6);
    v_code := '';
    for i in 0..5 loop
      v_code := v_code || substr(v_alpha, (get_byte(v_bytes, i) % 32) + 1, 1);
    end loop;
    begin
      insert into private.line_link_codes (code, company_id, branch_id, created_by, expires_at)
      values (v_code, p_company_id, p_branch_id, auth.uid(), v_exp);
      exit;
    exception when unique_violation then
      -- ชนกัน (แทบไม่เกิด) → สุ่มใหม่
    end;
  end loop;
  return jsonb_build_object('code', v_code, 'expires_at', v_exp);
end;
$$;

create or replace function public.line_groups_list(p_company_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'เฉพาะเจ้าของร้าน' using errcode = 'insufficient_privilege';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'group_id', g.group_id, 'group_name', g.group_name, 'branch_id', g.branch_id,
             'branch_name', br.name, 'linked_at', g.linked_at) order by g.linked_at)
      from private.line_groups g left join public.branches br on br.id = g.branch_id
     where g.company_id = p_company_id
  ), '[]'::jsonb);
end;
$$;

create or replace function public.line_unlink_group(p_company_id uuid, p_group_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'เฉพาะเจ้าของร้าน' using errcode = 'insufficient_privilege';
  end if;
  delete from private.line_groups where company_id = p_company_id and group_id = p_group_id;
end;
$$;

revoke all on function public.line_create_link_code(uuid, uuid) from public, anon;
revoke all on function public.line_groups_list(uuid) from public, anon;
revoke all on function public.line_unlink_group(uuid, text) from public, anon;
grant execute on function public.line_create_link_code(uuid, uuid) to authenticated;
grant execute on function public.line_groups_list(uuid) to authenticated;
grant execute on function public.line_unlink_group(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Edge Functions (service_role)
-- -----------------------------------------------------------------------------
-- line-webhook: ในกลุ่มพิมพ์ "เชื่อมร้าน <รหัส>" → ผูกกลุ่ม (รหัสใช้ได้ครั้งเดียว)
create or replace function public.line_link_group(p_code text, p_group_id text, p_group_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c private.line_link_codes;
begin
  delete from private.line_link_codes
   where code = upper(trim(p_code)) and expires_at > now()
  returning * into c;
  if c.code is null then
    return null;
  end if;

  insert into private.line_groups (group_id, company_id, branch_id, group_name, linked_by)
  values (p_group_id, c.company_id, c.branch_id, left(p_group_name, 200), c.created_by)
  on conflict (group_id) do update
    set company_id = excluded.company_id, branch_id = excluded.branch_id, group_name = excluded.group_name,
        linked_by = excluded.linked_by, linked_at = now();

  return jsonb_build_object(
    'company_name', (select co.name from public.companies co where co.id = c.company_id),
    'branch_name', (select br.name from public.branches br where br.id = c.branch_id)
  );
end;
$$;

-- line-webhook: บอทถูกเตะออก/กลุ่มถูกลบ
create or replace function public.line_group_left(p_group_id text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from private.line_groups where group_id = p_group_id;
$$;

-- guest-booking: ผูกการจองกับ LINE ของลูกค้า (ยืนยัน ID token แล้ว) → ข้อความยืนยันพร้อมลิงก์ติดตาม
create or replace function public.line_attach_booking(p_token text, p_line_user_id text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id   uuid := private.booking_id_by_token(p_token);
  v_cfg  private.push_config;
  b      public.bookings;
begin
  if v_id is null or p_line_user_id !~ '^U[0-9a-f]{32}$' then
    return null;
  end if;
  select * into v_cfg from private.push_config;
  select * into b from public.bookings where id = v_id;

  insert into private.booking_line_recipients (booking_id, line_user_id, reminded_at)
  values (v_id, p_line_user_id,
          -- จองกระชั้นกว่าช่วงเตือน → ไม่ต้องเตือนซ้ำ (ข้อความยืนยันพอแล้ว)
          case when b.starts_at - now() <= make_interval(mins => v_cfg.line_reminder_minutes) then now() end)
  on conflict (booking_id) do update set line_user_id = excluded.line_user_id;

  return private.line_booking_text(v_id, 'CONFIRM')
      || E'\n\nดูสถานะ · ชำระมัดจำ · ยกเลิก\n' || v_cfg.customer_url || '/t/' || p_token;
end;
$$;

revoke all on function public.line_link_group(text, text, text) from public, anon, authenticated;
revoke all on function public.line_group_left(text) from public, anon, authenticated;
revoke all on function public.line_attach_booking(text, text) from public, anon, authenticated;
grant execute on function public.line_link_group(text, text, text) to service_role;
grant execute on function public.line_group_left(text) to service_role;
grant execute on function public.line_attach_booking(text, text) to service_role;

-- -----------------------------------------------------------------------------
-- คิวแจ้งเตือน: ส่งต่อเมื่อมีเครื่อง Web Push หรือกลุ่ม LINE ที่ต้องได้รับ
-- -----------------------------------------------------------------------------
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
     and not (
       p_event in ('NEW_BOOKING', 'DEPOSIT_SLIP', 'BOOKING_CANCELLED')
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
  v_cfg     private.push_config;
  v_title   text;
  v_body    text;
  v_url     text;
  v_branch  text;
  r         record;
begin
  update private.push_outbox
     set claimed_at = now()
   where id = p_id and claimed_at is null and created_at > now() - interval '15 minutes'
  returning * into o;
  if o.id is null then
    return null;
  end if;
  select * into v_cfg from private.push_config;

  -- เตือนลูกค้าก่อนถึงนัด: ส่ง LINE หาลูกค้าคนเดียว ไม่มี Web Push
  if o.event = 'BOOKING_REMINDER' then
    select rcp.line_user_id into r from private.booking_line_recipients rcp where rcp.booking_id = o.ref_id;
    if r.line_user_id is null then
      return null;
    end if;
    return jsonb_build_object(
      'title', 'แจ้งเตือนนัดหมาย', 'body', '', 'url', '', 'tag', 'reminder-' || o.ref_id,
      'subscriptions', '[]'::jsonb,
      'line_to', jsonb_build_array(r.line_user_id),
      'line_text', private.line_booking_text(o.ref_id, 'REMINDER')
                   || E'\n\nตรวจสอบการจอง ' || v_cfg.customer_url || '/check-booking'
    );
  end if;

  select b.name into v_branch from public.branches b where b.id = o.branch_id;

  if o.event in ('NEW_BOOKING', 'BOOKING_CANCELLED') then
    select bk.starts_at, bk.items_count, bk.total_amount, c.first_name
      into r
      from public.bookings bk join public.customers c on c.id = bk.customer_id
     where bk.id = o.ref_id;
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
    select d.amount, bk.starts_at, c.first_name
      into r
      from public.booking_deposits d
      join public.bookings bk on bk.id = d.booking_id
      join public.customers c on c.id = bk.customer_id
     where d.id = o.ref_id;
    v_title := 'ลูกค้าส่งสลิปมัดจำ';
    v_body := format('คุณ%s โอน ฿%s · นัด %s น. · รอตรวจสลิป',
      r.first_name, to_char(r.amount, 'FM999,999,990'), to_char(r.starts_at at time zone 'Asia/Bangkok', 'DD/MM HH24:MI'));
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
    'line_to', case when o.event in ('NEW_BOOKING', 'DEPOSIT_SLIP', 'BOOKING_CANCELLED') then coalesce((
      select jsonb_agg(g.group_id)
        from private.line_groups g
       where g.company_id = o.company_id and (g.branch_id is null or g.branch_id = o.branch_id)
    ), '[]'::jsonb) else '[]'::jsonb end,
    'line_text', '🔔 ' || v_title || E'\n' || v_body || E'\n' || v_cfg.staff_url || v_url
  );
end;
$$;

-- push-dispatch: LINE ตอบว่าผู้รับไม่มีอยู่/บอทไม่ได้อยู่ในกลุ่มแล้ว → เลิกส่งไปที่นั่น
create or replace function public.line_remove_targets(p_ids text[])
returns void
language sql
security definer
set search_path = ''
as $$
  delete from private.line_groups where group_id = any (p_ids);
$$;

revoke all on function public.line_remove_targets(text[]) from public, anon, authenticated;
grant execute on function public.line_remove_targets(text[]) to service_role;

-- -----------------------------------------------------------------------------
-- เตือนก่อนถึงนัด (pg_cron ทุก 5 นาที)
-- -----------------------------------------------------------------------------
create or replace function private.line_send_reminders()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mins integer;
  r      record;
begin
  select line_reminder_minutes into v_mins from private.push_config;
  for r in
    select rcp.booking_id, b.company_id, b.branch_id
      from private.booking_line_recipients rcp
      join public.bookings b on b.id = rcp.booking_id
     where rcp.reminded_at is null
       and b.status in ('PENDING', 'CONFIRMED')
       and b.deposit_status <> 'AWAITING_PAYMENT'
       and b.starts_at > now()
       and b.starts_at <= now() + make_interval(mins => v_mins)
     for update of rcp skip locked
  loop
    update private.booking_line_recipients set reminded_at = now() where booking_id = r.booking_id;
    perform private.push_enqueue('BOOKING_REMINDER', r.company_id, r.branch_id, r.booking_id, null);
  end loop;
end;
$$;

revoke all on function private.line_send_reminders() from public;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('line-booking-reminders', '*/5 * * * *', 'select private.line_send_reminders()');
  else
    raise warning 'pg_cron ไม่ได้เปิด — ยังไม่มีการเตือนก่อนถึงนัดทาง LINE';
  end if;
end;
$$;
