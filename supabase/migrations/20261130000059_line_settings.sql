-- ตั้งค่า LINE OA ทั้งหมดจากหน้าเว็บ (แอปพนักงาน /settings/line) แทน Supabase secrets / Vercel env
--   - Channel access token + Channel secret เก็บเข้ารหัสใน Supabase Vault (เขียนได้ อ่านกลับจากเว็บไม่ได้)
--   - ค่าอื่น (LINE Login channel ID, LIFF ID, ลิงก์เพิ่มเพื่อน, URL เว็บ, การเตือนนัด, เหตุการณ์ที่ส่งเข้ากลุ่ม)
--     เก็บใน private.line_settings ต่อบริษัท
--   - Webhook URL ต่อบริษัท: /functions/v1/line-webhook?c=<company_id>

create table private.line_settings (
  company_id               uuid primary key references public.companies (id) on delete cascade,
  access_token_secret_id   uuid,
  channel_secret_secret_id uuid,
  access_token_hint        text,
  login_channel_id         text check (login_channel_id is null or login_channel_id ~ '^[0-9]{6,20}$'),
  liff_id                  text check (liff_id is null or liff_id ~ '^[0-9]{6,20}-[A-Za-z0-9]{4,20}$'),
  add_friend_url           text check (add_friend_url is null or add_friend_url ~ '^https://[^\s]{4,300}$'),
  bot_name                 text,
  bot_basic_id             text,
  customer_url             text check (customer_url is null or customer_url ~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?$'),
  staff_url                text check (staff_url is null or staff_url ~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?$'),
  confirm_enabled          boolean not null default true,
  reminder_enabled         boolean not null default true,
  reminder_minutes         integer not null default 120 check (reminder_minutes between 15 and 1440),
  group_events             text[] not null default array['NEW_BOOKING', 'DEPOSIT_SLIP', 'BOOKING_CANCELLED']
                             check (group_events <@ array['NEW_BOOKING', 'DEPOSIT_SLIP', 'BOOKING_CANCELLED', 'WALK_IN', 'SERVICE_DONE']),
  updated_at               timestamptz not null default now(),
  updated_by               uuid references auth.users (id) on delete set null
);

-- บริษัทที่มีอยู่: เริ่มด้วย URL แอปพนักงานที่ใช้จริง
insert into private.line_settings (company_id, staff_url)
select id, 'https://staffifeew.vercel.app' from public.companies
on conflict do nothing;

-- ย้ายค่าที่เคยอยู่ใน push_config (057/058) มาไว้ต่อบริษัทแล้ว
alter table private.push_config
  drop column customer_url,
  drop column staff_url,
  drop column line_reminder_minutes;

create or replace function private.line_webhook_url(p_company_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select replace(dispatch_url, '/push-dispatch', '/line-webhook') || '?c=' || p_company_id from private.push_config;
$$;

revoke all on function private.line_webhook_url(uuid) from public;

-- -----------------------------------------------------------------------------
-- เจ้าของร้าน: อ่าน/บันทึกการตั้งค่า
-- -----------------------------------------------------------------------------
create or replace function public.line_settings_get(p_company_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  s private.line_settings;
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'เฉพาะเจ้าของร้าน' using errcode = 'insufficient_privilege';
  end if;
  select * into s from private.line_settings where company_id = p_company_id;
  return jsonb_build_object(
    'has_access_token', s.access_token_secret_id is not null,
    'access_token_hint', s.access_token_hint,
    'has_channel_secret', s.channel_secret_secret_id is not null,
    'login_channel_id', s.login_channel_id,
    'liff_id', s.liff_id,
    'add_friend_url', s.add_friend_url,
    'bot_name', s.bot_name,
    'bot_basic_id', s.bot_basic_id,
    'customer_url', s.customer_url,
    'staff_url', s.staff_url,
    'confirm_enabled', coalesce(s.confirm_enabled, true),
    'reminder_enabled', coalesce(s.reminder_enabled, true),
    'reminder_minutes', coalesce(s.reminder_minutes, 120),
    'group_events', to_jsonb(coalesce(s.group_events, array['NEW_BOOKING', 'DEPOSIT_SLIP', 'BOOKING_CANCELLED'])),
    'webhook_url', private.line_webhook_url(p_company_id)
  );
end;
$$;

create or replace function public.line_settings_save(p_company_id uuid, p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'เฉพาะเจ้าของร้าน' using errcode = 'insufficient_privilege';
  end if;

  insert into private.line_settings (company_id) values (p_company_id) on conflict do nothing;
  update private.line_settings
     set login_channel_id = nullif(trim(p->>'login_channel_id'), ''),
         liff_id          = nullif(trim(p->>'liff_id'), ''),
         add_friend_url   = nullif(trim(p->>'add_friend_url'), ''),
         customer_url     = nullif(rtrim(trim(p->>'customer_url'), '/'), ''),
         staff_url        = nullif(rtrim(trim(p->>'staff_url'), '/'), ''),
         confirm_enabled  = coalesce((p->>'confirm_enabled')::boolean, true),
         reminder_enabled = coalesce((p->>'reminder_enabled')::boolean, true),
         reminder_minutes = coalesce((p->>'reminder_minutes')::integer, 120),
         group_events     = coalesce(array(select jsonb_array_elements_text(p->'group_events')), array[]::text[]),
         updated_at = now(), updated_by = auth.uid()
   where company_id = p_company_id;
exception
  when check_violation then
    raise exception 'ข้อมูลไม่ถูกต้อง: ตรวจรูปแบบ Channel ID / LIFF ID / URL (ต้องขึ้นต้น https://) และเวลาเตือน 15-1440 นาที'
      using errcode = 'check_violation';
  when invalid_text_representation then
    raise exception 'ข้อมูลไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
end;
$$;

-- p_access_token / p_channel_secret: NULL = ไม่เปลี่ยน · '' = ลบ
create or replace function public.line_set_credentials(p_company_id uuid, p_access_token text, p_channel_secret text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  s private.line_settings;
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'เฉพาะเจ้าของร้าน' using errcode = 'insufficient_privilege';
  end if;
  p_access_token := trim(p_access_token);
  p_channel_secret := trim(p_channel_secret);
  if p_access_token <> '' and (p_access_token !~ '^[A-Za-z0-9+/=._-]{20,1000}$') then
    raise exception 'Channel access token ไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  if p_channel_secret <> '' and p_channel_secret !~ '^[0-9a-f]{32}$' then
    raise exception 'Channel secret ต้องเป็นตัวอักษร 0-9 a-f 32 ตัว' using errcode = 'invalid_parameter_value';
  end if;

  insert into private.line_settings (company_id) values (p_company_id) on conflict do nothing;
  select * into s from private.line_settings where company_id = p_company_id for update;

  if p_access_token is not null then
    if p_access_token = '' then
      delete from vault.secrets where id = s.access_token_secret_id;
      s.access_token_secret_id := null;
      s.access_token_hint := null;
      s.bot_name := null;
      s.bot_basic_id := null;
    elsif s.access_token_secret_id is null then
      s.access_token_secret_id := vault.create_secret(p_access_token, 'line_access_token_' || p_company_id, 'LINE Messaging API channel access token');
      s.access_token_hint := right(p_access_token, 4);
    else
      perform vault.update_secret(s.access_token_secret_id, p_access_token);
      s.access_token_hint := right(p_access_token, 4);
    end if;
  end if;

  if p_channel_secret is not null then
    if p_channel_secret = '' then
      delete from vault.secrets where id = s.channel_secret_secret_id;
      s.channel_secret_secret_id := null;
    elsif s.channel_secret_secret_id is null then
      s.channel_secret_secret_id := vault.create_secret(p_channel_secret, 'line_channel_secret_' || p_company_id, 'LINE Messaging API channel secret');
    else
      perform vault.update_secret(s.channel_secret_secret_id, p_channel_secret);
    end if;
  end if;

  update private.line_settings
     set access_token_secret_id = s.access_token_secret_id, access_token_hint = s.access_token_hint,
         channel_secret_secret_id = s.channel_secret_secret_id, bot_name = s.bot_name, bot_basic_id = s.bot_basic_id,
         updated_at = now(), updated_by = auth.uid()
   where company_id = p_company_id;
end;
$$;

revoke all on function public.line_settings_get(uuid) from public, anon;
revoke all on function public.line_settings_save(uuid, jsonb) from public, anon;
revoke all on function public.line_set_credentials(uuid, text, text) from public, anon;
grant execute on function public.line_settings_get(uuid) to authenticated;
grant execute on function public.line_settings_save(uuid, jsonb) to authenticated;
grant execute on function public.line_set_credentials(uuid, text, text) to authenticated;

-- แอปลูกค้า (ไม่ต้อง login): LIFF ID + ลิงก์เพิ่มเพื่อน (ค่าสาธารณะ)
create or replace function public.line_public_config(p_company_code text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('liff_id', s.liff_id, 'add_friend_url', s.add_friend_url)
    from public.companies c
    join private.line_settings s on s.company_id = c.id
   where c.code = upper(p_company_code) and c.is_active
     and s.liff_id is not null and s.login_channel_id is not null and s.access_token_secret_id is not null;
$$;

revoke all on function public.line_public_config(text) from public;
grant execute on function public.line_public_config(text) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Edge Functions (service_role)
-- -----------------------------------------------------------------------------
-- ค่าลับของบริษัท (ระบุด้วย id หรือ code)
create or replace function public.line_secret(p_company_id uuid, p_company_code text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'company_id', s.company_id,
    'access_token', (select ds.decrypted_secret from vault.decrypted_secrets ds where ds.id = s.access_token_secret_id),
    'channel_secret', (select ds.decrypted_secret from vault.decrypted_secrets ds where ds.id = s.channel_secret_secret_id),
    'login_channel_id', s.login_channel_id,
    'confirm_enabled', s.confirm_enabled,
    'webhook_url', private.line_webhook_url(s.company_id)
  )
    from private.line_settings s
   where s.company_id = coalesce(p_company_id, (select c.id from public.companies c where c.code = upper(p_company_code)));
$$;

-- line-admin: บันทึกชื่อบอท/basic ID หลังตรวจ token · ตั้งลิงก์เพิ่มเพื่อนให้ถ้ายังว่าง
create or replace function public.line_save_bot_info(p_company_id uuid, p_bot_name text, p_basic_id text)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.line_settings
     set bot_name = left(p_bot_name, 200), bot_basic_id = left(p_basic_id, 50),
         add_friend_url = coalesce(add_friend_url,
           case when p_basic_id ~ '^@?[A-Za-z0-9._-]{2,40}$' then 'https://line.me/R/ti/p/' || replace(p_basic_id, '@', '%40') end)
   where company_id = p_company_id;
$$;

revoke all on function public.line_secret(uuid, text) from public, anon, authenticated;
revoke all on function public.line_save_bot_info(uuid, text, text) from public, anon, authenticated;
grant execute on function public.line_secret(uuid, text) to service_role;
grant execute on function public.line_save_bot_info(uuid, text, text) to service_role;

-- line-webhook: รหัสต้องเป็นของบริษัทเดียวกับ webhook ที่ถูกเรียก
drop function public.line_link_group(text, text, text);
create or replace function public.line_link_group(p_company_id uuid, p_code text, p_group_id text, p_group_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c private.line_link_codes;
begin
  delete from private.line_link_codes
   where code = upper(trim(p_code)) and company_id = p_company_id and expires_at > now()
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
    'branch_name', (select br.name from public.branches br where br.id = c.branch_id),
    'events', to_jsonb((select s.group_events from private.line_settings s where s.company_id = c.company_id))
  );
end;
$$;

revoke all on function public.line_link_group(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.line_link_group(uuid, text, text, text) to service_role;

-- guest-booking: ผูกการจองกับ LINE ของลูกค้า → ข้อความยืนยัน (NULL = ปิดการยืนยันไว้)
-- p_site_url: origin ของแอปลูกค้าที่ผ่าน ALLOWED_ORIGINS แล้ว (ใช้เมื่อยังไม่ได้ตั้ง customer_url)
drop function public.line_attach_booking(text, text);
create or replace function public.line_attach_booking(p_token text, p_line_user_id text, p_site_url text)
returns text
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
  return private.line_booking_text(v_id, 'CONFIRM')
      || coalesce(E'\n\nดูสถานะ · ชำระมัดจำ · ยกเลิก\n' || v_url || '/t/' || p_token, '');
end;
$$;

revoke all on function public.line_attach_booking(text, text, text) from public, anon, authenticated;
grant execute on function public.line_attach_booking(text, text, text) to service_role;

-- -----------------------------------------------------------------------------
-- คิวแจ้งเตือน: เหตุการณ์ที่ส่งเข้ากลุ่มตามที่ตั้งไว้ต่อบริษัท
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
                   || coalesce(E'\n\nตรวจสอบการจอง ' || ls.customer_url || '/check-booking', '')
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
    'line_to', case when o.event = any (coalesce(ls.group_events, array[]::text[])) then coalesce((
      select jsonb_agg(g.group_id)
        from private.line_groups g
       where g.company_id = o.company_id and (g.branch_id is null or g.branch_id = o.branch_id)
    ), '[]'::jsonb) else '[]'::jsonb end,
    'line_text', '🔔 ' || v_title || E'\n' || v_body || coalesce(E'\n' || ls.staff_url || v_url, '')
  );
end;
$$;

create or replace function private.line_send_reminders()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
begin
  for r in
    select rcp.booking_id, b.company_id, b.branch_id
      from private.booking_line_recipients rcp
      join public.bookings b on b.id = rcp.booking_id
      join private.line_settings ls on ls.company_id = b.company_id
     where rcp.reminded_at is null
       and ls.reminder_enabled and ls.access_token_secret_id is not null
       and b.status in ('PENDING', 'CONFIRMED')
       and b.deposit_status <> 'AWAITING_PAYMENT'
       and b.starts_at > now()
       and b.starts_at <= now() + make_interval(mins => ls.reminder_minutes)
     for update of rcp skip locked
  loop
    update private.booking_line_recipients set reminded_at = now() where booking_id = r.booking_id;
    perform private.push_enqueue('BOOKING_REMINDER', r.company_id, r.branch_id, r.booking_id, null);
  end loop;
end;
$$;
