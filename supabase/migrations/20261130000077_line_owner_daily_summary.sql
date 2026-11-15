-- =============================================================================
-- 077 — สรุปรายวันส่งเข้า LINE ส่วนตัวของเจ้าของร้าน (คนเดียว)
--   ผูก LINE: เจ้าของสร้างรหัสในแอปพนักงาน (line_create_link_code) → พิมพ์ "เชื่อมเจ้าของ รหัส" ในแชท 1:1 กับ OA
--            → line-webhook เรียก line_link_owner
--   ส่งอัตโนมัติ: pg_cron ทุก 5 นาที → private.line_daily_summary_tick → push_outbox 'DAILY_SUMMARY' (ref_date)
--            → push-dispatch → push_claim คืน line_to = เจ้าของ + ข้อมูลการ์ด (kind 'summary')
--   เวลาส่ง < 12:00 = สรุปของเมื่อวาน · ตั้งแต่ 12:00 = สรุปของวันนี้
--   พิมพ์ "สรุป" ในแชท (เฉพาะเจ้าของที่ผูกไว้) → line-webhook ตอบสรุปวันนี้ทันที (line_owner_summary_now)
-- =============================================================================

alter table private.line_settings
  add column owner_line_user_id text check (owner_line_user_id is null or owner_line_user_id ~ '^U[0-9a-f]{32}$'),
  add column owner_line_name    text,
  add column owner_linked_at    timestamptz,
  add column summary_enabled    boolean not null default true,
  add column summary_time       time not null default '00:30',
  add column summary_last_date  date;

alter table private.push_outbox add column ref_date date;
alter table private.push_outbox drop constraint push_outbox_event_check;
alter table private.push_outbox add constraint push_outbox_event_check
  check (event in ('NEW_BOOKING', 'DEPOSIT_SLIP', 'DEPOSIT_REVIEWED', 'BOOKING_CANCELLED', 'WALK_IN', 'SERVICE_DONE',
                   'BOOKING_REMINDER', 'DAILY_SUMMARY'));

-- -----------------------------------------------------------------------------
-- ข้อมูลสรุปของวัน (ทุกสาขารวม + แยกสาขา) — ใช้ทั้งการ์ด LINE และข้อความสำรอง
--   สูตรเงินเดียวกับ branch_money_summary: รายได้สุทธิ − (รายจ่าย + ค่าแรงหมอประจำ + ค่าแรงหมอวิ่ง)
-- -----------------------------------------------------------------------------
create or replace function private.line_daily_summary_data(p_company_id uuid, p_date date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tz       text;
  v_branches jsonb;
  v_total    jsonb;
begin
  select coalesce(s.timezone, 'Asia/Bangkok') into v_tz from public.company_settings s where s.company_id = p_company_id;
  v_tz := coalesce(v_tz, 'Asia/Bangkok');
  perform private.sync_commissions(p_company_id);

  with br as (
    select b.id, b.name, b.sort_order from public.branches b where b.company_id = p_company_id and b.is_active
  ),
  fin as (
    select f.branch_id, sum(f.net_revenue) as revenue, sum(f.expenses) as expenses, sum(f.commission_cost) as commission
      from private.daily_finance(p_company_id, p_date, p_date) f group by f.branch_id
  ),
  done as (
    -- คิวที่เสร็จวันนี้ + หมอคนสุดท้าย (หมอวิ่ง = freelance_name)
    select q.branch_id, i.therapist_fee, so.channel, la.freelance_name
      from public.queue_items q
      join public.service_order_items i on i.id = q.service_order_item_id
      join public.service_orders so on so.id = i.service_order_id and so.status <> 'CANCELLED'
      left join lateral (
        select sa.freelance_name from public.service_assignments sa
         where sa.queue_item_id = q.id and sa.status <> 'CANCELLED' order by sa.assigned_at desc limit 1) la on true
     where q.company_id = p_company_id and q.status = 'COMPLETED' and q.queue_date = p_date
  ),
  svc as (
    select d.branch_id, count(*) as customers,
           count(*) filter (where d.channel <> 'WALK_IN') as from_booking,
           coalesce(sum(d.therapist_fee) filter (where d.freelance_name is not null), 0) as walkin_fee
      from done d group by d.branch_id
  ),
  bk as (
    select b.branch_id,
           count(*) filter (where b.status = 'CANCELLED') as cancelled,
           count(*) filter (where b.status = 'NO_SHOW') as no_show
      from public.bookings b
     where b.company_id = p_company_id and (b.starts_at at time zone v_tz)::date = p_date
     group by b.branch_id
  ),
  rows as (
    select br.id, br.name, br.sort_order,
           coalesce(fin.revenue, 0) as revenue,
           coalesce(fin.expenses, 0) as expenses,
           coalesce(fin.commission, 0) + coalesce(svc.walkin_fee, 0) as therapist_pay,
           coalesce(fin.revenue, 0) - coalesce(fin.expenses, 0) - coalesce(fin.commission, 0) - coalesce(svc.walkin_fee, 0) as net,
           coalesce(svc.customers, 0) as customers,
           coalesce(svc.from_booking, 0) as from_booking,
           coalesce(bk.cancelled, 0) as cancelled,
           coalesce(bk.no_show, 0) as no_show
      from br
      left join fin on fin.branch_id = br.id
      left join svc on svc.branch_id = br.id
      left join bk on bk.branch_id = br.id
  )
  select jsonb_agg(jsonb_build_object(
           'name', r.name, 'revenue', r.revenue, 'expenses', r.expenses, 'therapist_pay', r.therapist_pay,
           'net', r.net, 'customers', r.customers, 'from_booking', r.from_booking,
           'cancelled', r.cancelled, 'no_show', r.no_show) order by r.sort_order, r.name),
         jsonb_build_object(
           'revenue', coalesce(sum(r.revenue), 0), 'expenses', coalesce(sum(r.expenses), 0),
           'therapist_pay', coalesce(sum(r.therapist_pay), 0), 'net', coalesce(sum(r.net), 0),
           'customers', coalesce(sum(r.customers), 0), 'from_booking', coalesce(sum(r.from_booking), 0),
           'cancelled', coalesce(sum(r.cancelled), 0), 'no_show', coalesce(sum(r.no_show), 0))
    into v_branches, v_total
    from rows r;

  return jsonb_build_object(
    'date', p_date,
    'date_label', to_char(p_date, 'DD/MM/YYYY'),
    'total', v_total,
    'branches', case when jsonb_array_length(coalesce(v_branches, '[]'::jsonb)) > 1 then v_branches else '[]'::jsonb end,
    -- เรื่องที่ต้องดู (ณ ตอนส่ง)
    'pending_slips', (select count(*) from public.booking_deposits d
                       where d.company_id = p_company_id and d.status = 'PENDING_REVIEW'),
    'unpaid_bills', (select count(*) from public.invoices iv
                      where iv.company_id = p_company_id and iv.status in ('ISSUED', 'PARTIALLY_PAID')),
    'unpaid_amount', (select coalesce(sum(iv.total - iv.paid_amount), 0) from public.invoices iv
                       where iv.company_id = p_company_id and iv.status in ('ISSUED', 'PARTIALLY_PAID')),
    'tomorrow_bookings', (select count(*) from public.bookings b
                           where b.company_id = p_company_id and b.status in ('PENDING', 'CONFIRMED')
                             and (b.starts_at at time zone v_tz)::date = p_date + 1)
  );
end;
$$;

-- ข้อความสำรอง (ใช้เมื่อ LINE ไม่รับการ์ด)
create or replace function private.line_daily_summary_text(p jsonb, p_title text)
returns text
language sql
immutable
set search_path = ''
as $$
  select concat_ws(E'\n',
    '📊 ' || p_title,
    'รายได้ ฿' || to_char((p->'total'->>'revenue')::numeric, 'FM999,999,990'),
    'รายจ่าย ฿' || to_char((p->'total'->>'expenses')::numeric, 'FM999,999,990'),
    'ค่าแรงหมอ ฿' || to_char((p->'total'->>'therapist_pay')::numeric, 'FM999,999,990'),
    'ยอดสุทธิ ฿' || to_char((p->'total'->>'net')::numeric, 'FM999,999,990'),
    'ลูกค้า ' || (p->'total'->>'customers') || ' คน',
    case when (p->>'pending_slips')::int > 0 then 'สลิปรอตรวจ ' || (p->>'pending_slips') || ' รายการ' end,
    case when (p->>'unpaid_bills')::int > 0 then 'บิลค้างชำระ ' || (p->>'unpaid_bills') || ' บิล' end,
    'นัดพรุ่งนี้ ' || (p->>'tomorrow_bookings') || ' การจอง');
$$;

-- ส่งสรุปของวันที่กำหนด (เข้าคิวส่ง) — ใช้ร่วมกันโดย tick อัตโนมัติและปุ่ม "ส่งตัวอย่าง"
create or replace function private.line_daily_summary_enqueue(p_company_id uuid, p_date date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id  uuid;
  v_url text;
begin
  select dispatch_url into v_url from private.push_config;
  insert into private.push_outbox (event, company_id, branch_id, ref_id, actor_id, ref_date)
  values ('DAILY_SUMMARY', p_company_id, null, null, null, p_date)
  returning id into v_id;
  perform net.http_post(
    url := v_url,
    body := jsonb_build_object('id', v_id),
    headers := '{"Content-Type": "application/json"}'::jsonb,
    timeout_milliseconds := 10000
  );
end;
$$;

-- ทุก 5 นาที: บริษัทที่ถึงเวลาส่งและยังไม่ได้ส่งของวันนั้น
create or replace function private.line_daily_summary_tick()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r        record;
  v_now    timestamp;
  v_target date;
begin
  for r in
    select ls.company_id, ls.summary_time, ls.summary_last_date, coalesce(s.timezone, 'Asia/Bangkok') as tz
      from private.line_settings ls
      left join public.company_settings s on s.company_id = ls.company_id
     where ls.summary_enabled and ls.owner_line_user_id is not null and ls.access_token_secret_id is not null
     for update of ls skip locked
  loop
    v_now := now() at time zone r.tz;
    if v_now::time < r.summary_time then
      continue;
    end if;
    -- ส่งก่อนเที่ยงวัน = สรุปของเมื่อวาน
    v_target := case when r.summary_time < '12:00' then v_now::date - 1 else v_now::date end;
    if r.summary_last_date is not null and r.summary_last_date >= v_target then
      continue;
    end if;
    update private.line_settings set summary_last_date = v_target where company_id = r.company_id;
    begin
      perform private.line_daily_summary_enqueue(r.company_id, v_target);
    exception when others then
      raise warning 'line_daily_summary_tick %: %', r.company_id, sqlerrm;
    end;
  end loop;
end;
$$;

select cron.unschedule('line-daily-summary') where exists (select 1 from cron.job where jobname = 'line-daily-summary');
select cron.schedule('line-daily-summary', '*/5 * * * *', 'select private.line_daily_summary_tick()');

-- -----------------------------------------------------------------------------
-- ผูก / ยกเลิก LINE ของเจ้าของ (line-webhook — service_role)
-- -----------------------------------------------------------------------------
create or replace function public.line_link_owner(p_company_id uuid, p_code text, p_line_user_id text, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c private.line_link_codes;
begin
  if p_line_user_id !~ '^U[0-9a-f]{32}$' then
    return null;
  end if;
  delete from private.line_link_codes
   where code = upper(trim(p_code)) and company_id = p_company_id and expires_at > now()
  returning * into c;
  if c.code is null or not exists (
    select 1 from public.company_memberships cm
     where cm.company_id = c.company_id and cm.user_id = c.created_by and cm.role = 'OWNER' and cm.status = 'ACTIVE'
  ) then
    return null;
  end if;
  insert into private.line_settings (company_id) values (p_company_id) on conflict do nothing;
  update private.line_settings
     set owner_line_user_id = p_line_user_id, owner_line_name = left(nullif(trim(p_name), ''), 100),
         owner_linked_at = now(), summary_enabled = true
   where company_id = p_company_id;
  return (select jsonb_build_object('company_name', co.name, 'summary_time', to_char(ls.summary_time, 'HH24:MI'))
            from public.companies co join private.line_settings ls on ls.company_id = co.id where co.id = p_company_id);
end;
$$;
revoke all on function public.line_link_owner(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.line_link_owner(uuid, text, text, text) to service_role;

-- ข้อมูลสรุปวันนี้ (พิมพ์ "สรุป" ในแชท) · null = ไม่ใช่เจ้าของที่ผูกไว้
create or replace function public.line_owner_summary_now(p_company_id uuid, p_line_user_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tz text;
begin
  if not exists (select 1 from private.line_settings ls
                  where ls.company_id = p_company_id and ls.owner_line_user_id = p_line_user_id) then
    return null;
  end if;
  select coalesce(s.timezone, 'Asia/Bangkok') into v_tz from public.company_settings s where s.company_id = p_company_id;
  return private.line_daily_summary_data(p_company_id, (now() at time zone coalesce(v_tz, 'Asia/Bangkok'))::date)
         || jsonb_build_object('company_name', (select name from public.companies where id = p_company_id));
end;
$$;
revoke all on function public.line_owner_summary_now(uuid, text) from public, anon, authenticated;
grant execute on function public.line_owner_summary_now(uuid, text) to service_role;

-- เลิกรับสรุป (พิมพ์ในแชท) · true = เป็นเจ้าของที่ผูกไว้และยกเลิกแล้ว
create or replace function public.line_unlink_owner_by_line(p_company_id uuid, p_line_user_id text)
returns boolean
language sql
security definer
set search_path = ''
as $$
  with u as (
    update private.line_settings
       set owner_line_user_id = null, owner_line_name = null, owner_linked_at = null
     where company_id = p_company_id and owner_line_user_id = p_line_user_id
    returning 1)
  select exists (select 1 from u);
$$;
revoke all on function public.line_unlink_owner_by_line(uuid, text) from public, anon, authenticated;
grant execute on function public.line_unlink_owner_by_line(uuid, text) to service_role;

-- -----------------------------------------------------------------------------
-- หน้าตั้งค่า LINE OA (เจ้าของร้าน)
-- -----------------------------------------------------------------------------
create or replace function public.line_owner_summary_get(p_company_id uuid)
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
    'linked', s.owner_line_user_id is not null,
    'owner_name', s.owner_line_name,
    'linked_at', s.owner_linked_at,
    'enabled', coalesce(s.summary_enabled, true),
    'time', to_char(coalesce(s.summary_time, '00:30'), 'HH24:MI'),
    'last_date', s.summary_last_date
  );
end;
$$;

create or replace function public.line_owner_summary_save(p_company_id uuid, p_enabled boolean, p_time text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'เฉพาะเจ้าของร้าน' using errcode = 'insufficient_privilege';
  end if;
  if p_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception 'เวลาไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  insert into private.line_settings (company_id) values (p_company_id) on conflict do nothing;
  update private.line_settings
     set summary_enabled = coalesce(p_enabled, true), summary_time = p_time::time,
         -- เปลี่ยนเวลาแล้ว: กันส่งซ้ำของวันที่ส่งไปแล้ว (คงค่าเดิม) · updated_by เพื่อ audit
         updated_at = now(), updated_by = auth.uid()
   where company_id = p_company_id;
end;
$$;

create or replace function public.line_owner_unlink(p_company_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'เฉพาะเจ้าของร้าน' using errcode = 'insufficient_privilege';
  end if;
  update private.line_settings
     set owner_line_user_id = null, owner_line_name = null, owner_linked_at = null, updated_at = now(), updated_by = auth.uid()
   where company_id = p_company_id;
end;
$$;

-- ส่งสรุปของวันนี้ทันที (ปุ่ม "ส่งสรุปตอนนี้")
create or replace function public.line_owner_summary_send_now(p_company_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tz text;
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'เฉพาะเจ้าของร้าน' using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from private.line_settings where company_id = p_company_id and owner_line_user_id is not null) then
    raise exception 'ยังไม่ได้เชื่อม LINE ของเจ้าของร้าน' using errcode = 'check_violation';
  end if;
  select coalesce(s.timezone, 'Asia/Bangkok') into v_tz from public.company_settings s where s.company_id = p_company_id;
  perform private.line_daily_summary_enqueue(p_company_id, (now() at time zone coalesce(v_tz, 'Asia/Bangkok'))::date);
end;
$$;

revoke all on function public.line_owner_summary_get(uuid) from public, anon;
revoke all on function public.line_owner_summary_save(uuid, boolean, text) from public, anon;
revoke all on function public.line_owner_unlink(uuid) from public, anon;
revoke all on function public.line_owner_summary_send_now(uuid) from public, anon;
grant execute on function public.line_owner_summary_get(uuid) to authenticated;
grant execute on function public.line_owner_summary_save(uuid, boolean, text) to authenticated;
grant execute on function public.line_owner_unlink(uuid) to authenticated;
grant execute on function public.line_owner_summary_send_now(uuid) to authenticated;

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
  v_summary   jsonb;
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

  -- สรุปรายวัน: ส่ง LINE หาเจ้าของร้านคนเดียว ไม่มี Web Push (migration 077)
  if o.event = 'DAILY_SUMMARY' then
    if ls.owner_line_user_id is null then
      return null;
    end if;
    v_summary := private.line_daily_summary_data(o.company_id, coalesce(o.ref_date, (o.created_at at time zone 'Asia/Bangkok')::date))
                 || jsonb_build_object('company_name', (select name from public.companies where id = o.company_id));
    v_title := 'สรุปประจำวัน ' || (v_summary->>'date_label');
    return jsonb_build_object(
      'company_id', o.company_id,
      'title', v_title, 'body', '', 'url', '', 'tag', 'summary-' || (v_summary->>'date'),
      'subscriptions', '[]'::jsonb,
      'line_to', jsonb_build_array(ls.owner_line_user_id),
      'line_text', private.line_daily_summary_text(v_summary, v_title),
      'line_flex', jsonb_build_object('kind', 'summary', 'summary', v_summary, 'link', ls.staff_url)
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
