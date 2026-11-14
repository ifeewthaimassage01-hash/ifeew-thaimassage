-- แจ้งเตือนเข้ามือถือพนักงาน (Web Push) เมื่อ:
--   NEW_BOOKING       ลูกค้าจองออนไลน์
--   DEPOSIT_SLIP      ลูกค้าส่งสลิปมัดจำ
--   BOOKING_CANCELLED ลูกค้ายกเลิกการจองเอง
--   WALK_IN           รับลูกค้าหน้าร้าน (POS)
--   SERVICE_DONE      บริการเสร็จ (คิว → COMPLETED)
--
-- ขั้นตอน: trigger → private.push_outbox (1 แถว/เหตุการณ์) → pg_net POST {id} ไป Edge Function push-dispatch
--   → push-dispatch เรียก public.push_claim(id) (service_role เท่านั้น) ได้ข้อความ + รายการเครื่องผู้รับ → ส่ง Web Push
-- pg_net ส่งคำขอหลัง transaction commit → ถ้า rollback จะไม่มีแจ้งเตือน · id ใช้ได้ครั้งเดียว (ปลอม/ยิงซ้ำไม่ได้ผล)
-- การแจ้งเตือนล้มเหลวต้องไม่ทำให้การจอง/คิวล้มเหลว (กลืน error ใน push_enqueue)

create extension if not exists pg_net with schema extensions;

-- -----------------------------------------------------------------------------
-- เครื่องที่รับแจ้งเตือน (1 แถวต่อ endpoint ของเบราว์เซอร์)
-- branch_id NULL = ทุกสาขาของบริษัท (เจ้าของร้าน)
-- -----------------------------------------------------------------------------
create table public.push_subscriptions (
  endpoint    text primary key check (char_length(endpoint) between 10 and 1000),
  company_id  uuid not null references public.companies (id) on delete cascade,
  branch_id   uuid references public.branches (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  p256dh      text not null check (char_length(p256dh) between 10 and 200),
  auth        text not null check (char_length(auth) between 8 and 100),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.push_subscriptions is 'เครื่องที่เปิดรับแจ้งเตือน Web Push — เข้าถึงผ่าน push_subscribe/push_unsubscribe เท่านั้น';

alter table public.push_subscriptions enable row level security;
revoke all on public.push_subscriptions from anon, authenticated;
create index push_subscriptions_company_idx on public.push_subscriptions (company_id, branch_id);

create or replace function public.push_subscribe(
  p_company_id uuid, p_branch_id uuid, p_endpoint text, p_p256dh text, p_auth text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_branch uuid;
begin
  if auth.uid() is null or not private.is_company_member(p_company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if p_endpoint is null or p_endpoint !~ '^https://' then
    raise exception 'ข้อมูลการแจ้งเตือนไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  if private.is_company_owner(p_company_id) then
    v_branch := null; -- เจ้าของร้านรับทุกสาขา
  else
    if p_branch_id is null or not private.has_branch_access(p_branch_id) then
      raise exception 'ไม่มีสิทธิ์สาขานี้' using errcode = 'insufficient_privilege';
    end if;
    v_branch := p_branch_id;
  end if;

  insert into public.push_subscriptions (endpoint, company_id, branch_id, user_id, p256dh, auth)
  values (p_endpoint, p_company_id, v_branch, auth.uid(), p_p256dh, p_auth)
  on conflict (endpoint) do update
    set company_id = excluded.company_id, branch_id = excluded.branch_id, user_id = excluded.user_id,
        p256dh = excluded.p256dh, auth = excluded.auth, updated_at = now();
end;
$$;

create or replace function public.push_unsubscribe(p_endpoint text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.push_subscriptions s
   where s.endpoint = p_endpoint
     and (s.user_id = auth.uid() or private.is_company_member(s.company_id));
end;
$$;

revoke all on function public.push_subscribe(uuid, uuid, text, text, text) from public, anon;
revoke all on function public.push_unsubscribe(text) from public, anon;
grant execute on function public.push_subscribe(uuid, uuid, text, text, text) to authenticated;
grant execute on function public.push_unsubscribe(text) to authenticated;

-- -----------------------------------------------------------------------------
-- ปลายทาง Edge Function + คิวเหตุการณ์
-- -----------------------------------------------------------------------------
create table private.push_config (
  id            boolean primary key default true check (id),
  dispatch_url  text not null
);
insert into private.push_config (dispatch_url)
values ('https://yyfpuzufkeazjhvyobhf.supabase.co/functions/v1/push-dispatch');

create table private.push_outbox (
  id          uuid primary key default gen_random_uuid(),
  event       text not null check (event in ('NEW_BOOKING', 'DEPOSIT_SLIP', 'BOOKING_CANCELLED', 'WALK_IN', 'SERVICE_DONE')),
  company_id  uuid not null,
  branch_id   uuid not null,
  ref_id      uuid not null,
  actor_id    uuid,
  created_at  timestamptz not null default now(),
  claimed_at  timestamptz
);
create index push_outbox_created_idx on private.push_outbox (created_at);

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
  -- ไม่มีเครื่องรับในสาขานี้ → ไม่ต้องส่ง
  if not exists (
    select 1 from public.push_subscriptions s
     where s.company_id = p_company_id and (s.branch_id is null or s.branch_id = p_branch_id)
  ) then
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

revoke all on function private.push_enqueue(text, uuid, uuid, uuid, uuid) from public;

-- -----------------------------------------------------------------------------
-- push-dispatch เรียก: รับเหตุการณ์ (ครั้งเดียว) + ข้อความ + เครื่องผู้รับ
-- -----------------------------------------------------------------------------
create or replace function public.push_claim(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  o       private.push_outbox;
  v_title text;
  v_body  text;
  v_url   text;
  v_branch text;
  r       record;
begin
  update private.push_outbox
     set claimed_at = now()
   where id = p_id and claimed_at is null and created_at > now() - interval '15 minutes'
  returning * into o;
  if o.id is null then
    return null;
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
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.push_remove_subscriptions(p_endpoints text[])
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.push_subscriptions where endpoint = any (p_endpoints);
$$;

revoke all on function public.push_claim(uuid) from public, anon, authenticated;
revoke all on function public.push_remove_subscriptions(text[]) from public, anon, authenticated;
grant execute on function public.push_claim(uuid) to service_role;
grant execute on function public.push_remove_subscriptions(text[]) to service_role;

-- -----------------------------------------------------------------------------
-- Triggers
-- -----------------------------------------------------------------------------
create or replace function private.tg_push_bookings()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.channel = 'ONLINE' then
      perform private.push_enqueue('NEW_BOOKING', new.company_id, new.branch_id, new.id, null);
    end if;
  elsif new.status = 'CANCELLED' and old.status is distinct from 'CANCELLED' and new.cancelled_by_role = 'CUSTOMER' then
    perform private.push_enqueue('BOOKING_CANCELLED', new.company_id, new.branch_id, new.id, null);
  end if;
  return null;
end;
$$;

create trigger bookings_push
  after insert or update of status on public.bookings
  for each row execute function private.tg_push_bookings();

create or replace function private.tg_push_booking_deposits()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'PENDING_REVIEW' then
    perform private.push_enqueue('DEPOSIT_SLIP', new.company_id, new.branch_id, new.id, null);
  end if;
  return null;
end;
$$;

create trigger booking_deposits_push
  after insert on public.booking_deposits
  for each row execute function private.tg_push_booking_deposits();

create or replace function private.tg_push_service_orders()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.channel = 'WALK_IN' then
    perform private.push_enqueue('WALK_IN', new.company_id, new.branch_id, new.id, new.created_by);
  end if;
  return null;
end;
$$;

create trigger service_orders_push
  after insert on public.service_orders
  for each row execute function private.tg_push_service_orders();

create or replace function private.tg_push_queue_items()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'COMPLETED' and old.status is distinct from 'COMPLETED' then
    perform private.push_enqueue('SERVICE_DONE', new.company_id, new.branch_id, new.id, new.completed_by);
  end if;
  return null;
end;
$$;

create trigger queue_items_push
  after update of status on public.queue_items
  for each row execute function private.tg_push_queue_items();

-- -----------------------------------------------------------------------------
-- Guest ยกเลิกการจองเองผ่านลิงก์ติดตาม (Edge Function booking-tracking action=cancel, service role)
-- กติกาเดียวกับ cancel_my_booking เดิม (ระบบสมาชิกถูกปิดใน migration 052)
-- -----------------------------------------------------------------------------
create or replace function public.cancel_booking_by_token(p_token text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  b        public.bookings;
  v_cutoff integer;
begin
  select * into b from public.bookings where id = private.booking_id_by_token(p_token) for update;
  if b.id is null then
    raise exception 'ไม่พบการจอง' using errcode = 'no_data_found';
  end if;
  if b.status not in ('PENDING', 'CONFIRMED') then
    raise exception 'การจองนี้ยกเลิกไม่ได้' using errcode = 'check_violation';
  end if;
  if b.deposit_status = 'PENDING_REVIEW' then
    raise exception 'สลิปกำลังรอตรวจสอบ กรุณาติดต่อร้าน' using errcode = 'check_violation';
  end if;
  select cancellation_cutoff_hours into v_cutoff from public.company_settings where company_id = b.company_id;
  if b.status = 'CONFIRMED' and now() > b.starts_at - make_interval(hours => coalesce(v_cutoff, 0)) then
    raise exception 'ยกเลิกเองได้ก่อนเวลานัดอย่างน้อย % ชั่วโมง กรุณาติดต่อร้าน', v_cutoff using errcode = 'check_violation';
  end if;

  perform private.release_booking_allocations(b.id, 'ลูกค้ายกเลิก');
  update public.bookings
     set status = 'CANCELLED', cancelled_at = now(), cancelled_by = null, cancelled_by_role = 'CUSTOMER',
         cancel_reason = nullif(left(trim(coalesce(p_reason, '')), 500), ''),
         deposit_status = case when deposit_status = 'PAID' then 'REFUND_PENDING' else deposit_status end
   where id = b.id;
  update public.booking_deposits set refund_status = 'PENDING' where booking_id = b.id and status = 'VERIFIED';

  -- ไม่ revoke token: ให้ลูกค้ายังเปิดลิงก์ดูสถานะ "ยกเลิกแล้ว" ได้
  return private.booking_customer_view(b.id);
end;
$$;

revoke all on function public.cancel_booking_by_token(text, text) from public, anon, authenticated;
grant execute on function public.cancel_booking_by_token(text, text) to service_role;
