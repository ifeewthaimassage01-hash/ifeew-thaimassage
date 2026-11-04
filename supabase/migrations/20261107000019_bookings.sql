-- =============================================================================
-- Phase 4 / 019 — bookings, booking_items, booking_tracking_tokens, booking_deposits
-- =============================================================================

-- -----------------------------------------------------------------------------
-- bookings
-- -----------------------------------------------------------------------------
create table public.bookings (
  id                 uuid primary key default gen_random_uuid(),
  company_id         uuid not null,
  branch_id          uuid not null,
  customer_id        uuid not null,
  booking_code       text unique check (booking_code is null or booking_code ~ '^BKG-[A-Z0-9]{2,10}-[0-9]{8}-[0-9]{4}$'),
  channel            text not null check (channel in ('ONLINE', 'STAFF')),
  status             text not null default 'PENDING'
                       check (status in ('PENDING', 'CONFIRMED', 'CHECKED_IN', 'COMPLETED', 'CANCELLED', 'NO_SHOW', 'EXPIRED')),
  starts_at          timestamptz not null,
  ends_at            timestamptz not null,
  items_count        integer not null check (items_count between 1 and 10),
  total_amount       numeric(12,2) not null check (total_amount >= 0),
  deposit_required   numeric(12,2) not null default 0 check (deposit_required >= 0),
  deposit_status     text not null default 'NOT_REQUIRED'
                       check (deposit_status in ('NOT_REQUIRED', 'AWAITING_PAYMENT', 'PENDING_REVIEW', 'PAID',
                                                 'REFUND_PENDING', 'REFUNDED', 'FORFEITED')),
  hold_expires_at    timestamptz,
  customer_note      text check (customer_note is null or char_length(customer_note) <= 500),
  staff_note         text check (staff_note is null or char_length(staff_note) <= 500),
  confirmed_at       timestamptz,
  cancelled_at       timestamptz,
  cancelled_by       uuid references public.profiles (id),
  cancelled_by_role  text check (cancelled_by_role in ('CUSTOMER', 'STAFF', 'SYSTEM')),
  cancel_reason      text check (cancel_reason is null or char_length(cancel_reason) <= 500),
  no_show_at         timestamptz,
  created_at         timestamptz not null default now(),
  created_by         uuid references public.profiles (id),
  updated_at         timestamptz not null default now(),
  constraint bookings_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint bookings_customer_fk foreign key (company_id, customer_id)
    references public.customers (company_id, id) on delete restrict,
  constraint bookings_company_id_id_key unique (company_id, id),
  constraint bookings_period_chk check (ends_at > starts_at),
  constraint bookings_code_chk check (
    status in ('PENDING', 'EXPIRED') or booking_code is not null or (status = 'CANCELLED' and confirmed_at is null)
  ),
  constraint bookings_deposit_chk check ((deposit_required = 0) = (deposit_status = 'NOT_REQUIRED')),
  constraint bookings_cancel_chk check ((status = 'CANCELLED') = (cancelled_at is not null))
);

comment on table public.bookings is 'การจอง ห้าม DELETE สถานะเปลี่ยนผ่าน Function ตามตารางที่อนุญาตเท่านั้น';

create index bookings_branch_time_idx on public.bookings (branch_id, starts_at);
create index bookings_customer_idx on public.bookings (customer_id, starts_at desc);
create index bookings_pending_hold_idx on public.bookings (hold_expires_at) where status = 'PENDING';

-- -----------------------------------------------------------------------------
-- booking_items (Snapshot ราคา/ระยะเวลา/ค่าแรง)
-- -----------------------------------------------------------------------------
create table public.booking_items (
  id                        uuid primary key default gen_random_uuid(),
  company_id                uuid not null,
  booking_id                uuid not null,
  branch_service_option_id  uuid not null,
  service_id                uuid not null,
  service_name              text not null,
  service_name_en           text,
  duration_minutes          integer not null check (duration_minutes between 5 and 600),
  unit_price                numeric(12,2) not null check (unit_price >= 0),
  therapist_fee             numeric(12,2) not null check (therapist_fee >= 0),
  quantity                  integer not null default 1 check (quantity = 1),
  discount_amount           numeric(12,2) not null default 0 check (discount_amount >= 0),
  line_total                numeric(12,2) not null check (line_total >= 0),
  starts_at                 timestamptz not null,
  ends_at                   timestamptz not null,
  created_at                timestamptz not null default now(),
  created_by                uuid references public.profiles (id),
  updated_at                timestamptz not null default now(),
  constraint booking_items_booking_fk foreign key (company_id, booking_id)
    references public.bookings (company_id, id) on delete restrict,
  constraint booking_items_option_fk foreign key (company_id, branch_service_option_id)
    references public.branch_service_options (company_id, id) on delete restrict,
  constraint booking_items_service_fk foreign key (company_id, service_id)
    references public.services (company_id, id) on delete restrict,
  constraint booking_items_total_chk check (line_total = unit_price * quantity - discount_amount),
  constraint booking_items_period_chk check (ends_at > starts_at)
);

create index booking_items_booking_idx on public.booking_items (booking_id);

alter table public.resource_allocations
  add constraint resource_allocations_booking_item_fk
  foreign key (booking_item_id) references public.booking_items (id) on delete restrict;

-- -----------------------------------------------------------------------------
-- booking_tracking_tokens
-- -----------------------------------------------------------------------------
create table public.booking_tracking_tokens (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null,
  booking_id        uuid not null,
  token_hash        text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  token_expires_at  timestamptz not null,
  revoked_at        timestamptz,
  created_at        timestamptz not null default now(),
  created_by        uuid references public.profiles (id),
  updated_at        timestamptz not null default now(),
  constraint booking_tracking_tokens_booking_fk foreign key (company_id, booking_id)
    references public.bookings (company_id, id) on delete restrict,
  constraint booking_tracking_tokens_expiry_chk check (token_expires_at > created_at)
);

create unique index booking_tracking_tokens_one_active
  on public.booking_tracking_tokens (booking_id) where revoked_at is null;

-- -----------------------------------------------------------------------------
-- booking_deposits (ข้อมูลการเงิน ห้าม DELETE)
-- -----------------------------------------------------------------------------
create table public.booking_deposits (
  id                     uuid primary key default gen_random_uuid(),
  company_id             uuid not null,
  branch_id              uuid not null,
  booking_id             uuid not null,
  amount                 numeric(12,2) not null check (amount > 0),
  status                 text not null check (status in ('PENDING_REVIEW', 'VERIFIED', 'REJECTED')),
  slip_path              text check (slip_path is null or char_length(slip_path) <= 300),
  verification_source    text check (verification_source in ('AUTO', 'STAFF')),
  provider               text not null default 'SLIPOK',
  provider_code          integer,
  provider_message       text check (provider_message is null or char_length(provider_message) <= 300),
  slip_trans_ref         text check (slip_trans_ref is null or char_length(slip_trans_ref) <= 40),
  slip_amount            numeric(12,2),
  slip_trans_at          timestamptz,
  slip_sender_name       text check (slip_sender_name is null or char_length(slip_sender_name) <= 100),
  slip_receiver_name     text check (slip_receiver_name is null or char_length(slip_receiver_name) <= 100),
  slip_receiver_account  text check (slip_receiver_account is null or char_length(slip_receiver_account) <= 60),
  reviewed_by            uuid references public.profiles (id),
  reviewed_at            timestamptz,
  review_note            text check (review_note is null or char_length(review_note) <= 500),
  refund_status          text not null default 'NONE' check (refund_status in ('NONE', 'PENDING', 'REFUNDED', 'FORFEITED')),
  refund_reference       text check (refund_reference is null or char_length(refund_reference) <= 100),
  refunded_at            timestamptz,
  refunded_by            uuid references public.profiles (id),
  created_at             timestamptz not null default now(),
  created_by             uuid references public.profiles (id),
  updated_at             timestamptz not null default now(),
  constraint booking_deposits_booking_fk foreign key (company_id, booking_id)
    references public.bookings (company_id, id) on delete restrict,
  constraint booking_deposits_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint booking_deposits_verified_chk check (status <> 'VERIFIED' or verification_source is not null),
  constraint booking_deposits_refund_chk check ((refund_status = 'REFUNDED') = (refunded_at is not null)),
  constraint booking_deposits_refund_verified_chk check (refund_status = 'NONE' or status = 'VERIFIED')
);

comment on table public.booking_deposits is 'มัดจำการจอง (สลิป) ข้อมูลการเงิน ห้าม DELETE แก้ผ่าน Function เท่านั้น';

create unique index booking_deposits_trans_ref_key
  on public.booking_deposits (slip_trans_ref) where slip_trans_ref is not null and status <> 'REJECTED';
create unique index booking_deposits_one_verified
  on public.booking_deposits (booking_id) where status = 'VERIFIED';
create index booking_deposits_review_idx on public.booking_deposits (branch_id, status) where status = 'PENDING_REVIEW';

-- -----------------------------------------------------------------------------
-- stamp / audit / guards
-- -----------------------------------------------------------------------------
create trigger bookings_stamp before insert or update on public.bookings
  for each row execute function private.tg_stamp();
create trigger booking_items_stamp before insert or update on public.booking_items
  for each row execute function private.tg_stamp();
create trigger booking_tracking_tokens_stamp before insert or update on public.booking_tracking_tokens
  for each row execute function private.tg_stamp();
create trigger booking_deposits_stamp before insert or update on public.booking_deposits
  for each row execute function private.tg_stamp();

create trigger bookings_audit after insert or update or delete on public.bookings
  for each row execute function private.tg_audit('customer_note');
create trigger booking_deposits_audit after insert or update or delete on public.booking_deposits
  for each row execute function private.tg_audit('slip_sender_name', 'slip_receiver_name', 'slip_receiver_account');

create trigger booking_items_immutable before update or delete on public.booking_items
  for each row execute function private.tg_immutable_row();

create or replace function private.tg_no_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'ห้ามลบ % (ใช้สถานะแทน)', tg_table_name using errcode = 'insufficient_privilege';
end;
$$;

create trigger bookings_no_delete before delete on public.bookings
  for each row execute function private.tg_no_delete();
create trigger booking_deposits_no_delete before delete on public.booking_deposits
  for each row execute function private.tg_no_delete();
create trigger resource_allocations_no_delete before delete on public.resource_allocations
  for each row execute function private.tg_no_delete();

-- State transition ของ Booking (สเปกข้อ 9) — ตัว function อยู่ด้านล่าง (หลัง create_booking_core)
create or replace function private.tg_bookings_guard()
returns trigger language plpgsql set search_path = '' as $$ begin return new; end; $$;

create trigger bookings_guard before update on public.bookings
  for each row execute function private.tg_bookings_guard();

-- ข้อมูลมัดจำเปลี่ยนได้เฉพาะสถานะ/ผลตรวจ/การคืนเงิน
create or replace function private.tg_booking_deposits_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.company_id <> old.company_id or new.booking_id <> old.booking_id or new.amount <> old.amount
     or new.slip_path is distinct from old.slip_path
     or new.slip_trans_ref is distinct from old.slip_trans_ref
     or new.slip_amount is distinct from old.slip_amount then
    raise exception 'ห้ามแก้ข้อมูลสลิป/ยอดมัดจำ' using errcode = 'check_violation';
  end if;
  if old.status <> 'PENDING_REVIEW' and new.status <> old.status then
    raise exception 'ผลตรวจสลิปที่สรุปแล้วเปลี่ยนไม่ได้' using errcode = 'check_violation';
  end if;
  if old.refund_status in ('REFUNDED', 'FORFEITED') and new.refund_status <> old.refund_status then
    raise exception 'สถานะคืนมัดจำสรุปแล้ว' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger booking_deposits_guard before update on public.booking_deposits
  for each row execute function private.tg_booking_deposits_guard();

-- -----------------------------------------------------------------------------
-- Helpers ภายใน
-- -----------------------------------------------------------------------------
create or replace function private.release_booking_allocations(p_booking_id uuid, p_reason text)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.resource_allocations a
     set status = 'RELEASED', released_at = now(), release_reason = left(p_reason, 200), expires_at = null
    from public.booking_items i
   where i.id = a.booking_item_id and i.booking_id = p_booking_id and a.status <> 'RELEASED';
$$;

create or replace function private.confirm_booking(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  b public.bookings;
begin
  select * into b from public.bookings where id = p_booking_id for update;
  if b.status <> 'PENDING' then
    raise exception 'ยืนยันได้เฉพาะการจองที่รอยืนยัน' using errcode = 'check_violation';
  end if;

  update public.resource_allocations a
     set status = 'RESERVED', expires_at = null
    from public.booking_items i
   where i.id = a.booking_item_id and i.booking_id = b.id and a.status = 'HELD';

  update public.bookings
     set status = 'CONFIRMED',
         confirmed_at = now(),
         hold_expires_at = null,
         booking_code = coalesce(booking_code, private.next_document_number(b.company_id, b.branch_id, 'BKG', now()))
   where id = b.id;
end;
$$;

create or replace function private.issue_tracking_token(p_booking_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  b       public.bookings;
  v_days  integer;
  v_token text := 'trk_' || encode(extensions.gen_random_bytes(32), 'hex');
begin
  select * into b from public.bookings where id = p_booking_id;
  select tracking_token_days_after into v_days from public.company_settings where company_id = b.company_id;

  update public.booking_tracking_tokens set revoked_at = now()
   where booking_id = b.id and revoked_at is null;

  insert into public.booking_tracking_tokens (company_id, booking_id, token_hash, token_expires_at)
  values (b.company_id, b.id, encode(extensions.digest(v_token, 'sha256'), 'hex'),
          greatest(b.ends_at, now()) + make_interval(days => v_days));
  return v_token;
end;
$$;

create or replace function private.booking_id_by_token(p_token text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select t.booking_id from public.booking_tracking_tokens t
   where p_token ~ '^trk_[0-9a-f]{64}$'
     and t.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
     and t.revoked_at is null and t.token_expires_at > now();
$$;

-- มุมมองการจองสำหรับลูกค้า/Guest (ไม่มีค่าแรง, ชื่อปิดบังบางส่วน)
create or replace function private.booking_customer_view(p_booking_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'booking_id', b.id,
    'booking_code', b.booking_code,
    'status', b.status,
    'channel', b.channel,
    'starts_at', b.starts_at,
    'ends_at', b.ends_at,
    'branch', jsonb_build_object('id', br.id, 'name', br.name, 'phone', br.phone, 'address', br.address),
    'customer_name', c.first_name || case when c.last_name <> '' then ' ' || left(c.last_name, 1) || '.' else '' end,
    'customer_note', b.customer_note,
    'items', (select jsonb_agg(jsonb_build_object(
                'service_name', i.service_name, 'service_name_en', i.service_name_en,
                'duration_minutes', i.duration_minutes, 'unit_price', i.unit_price, 'line_total', i.line_total)
                order by i.created_at, i.id)
                from public.booking_items i where i.booking_id = b.id),
    'total_amount', b.total_amount,
    'deposit_required', b.deposit_required,
    'deposit_status', b.deposit_status,
    'hold_expires_at', b.hold_expires_at,
    'can_upload_slip', b.status = 'PENDING' and b.deposit_status = 'AWAITING_PAYMENT' and b.hold_expires_at > now(),
    'payment', case when b.deposit_status = 'AWAITING_PAYMENT' then (
       select jsonb_build_object('promptpay_id', pa.promptpay_id, 'account_name', pa.account_name,
                                 'bank_name', pa.bank_name, 'amount', b.deposit_required)
         from public.branch_payment_accounts pa where pa.branch_id = b.branch_id and pa.is_active) end,
    'last_slip', (select jsonb_build_object('status', d.status, 'message', d.provider_message, 'created_at', d.created_at)
                    from public.booking_deposits d where d.booking_id = b.id order by d.created_at desc limit 1),
    'cancel_reason', b.cancel_reason,
    'cancelled_at', b.cancelled_at,
    'created_at', b.created_at
  )
  from public.bookings b
  join public.branches br on br.id = b.branch_id
  join public.customers c on c.id = b.customer_id
  where b.id = p_booking_id;
$$;

-- ปิดรายการค้างที่หมดเวลา (เรียกโดย pg_cron ทุกนาที และก่อนจองใหม่)
create or replace function private.expire_stale_bookings()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  n integer := 0;
begin
  for r in
    select id from public.bookings
     where status = 'PENDING' and deposit_status = 'AWAITING_PAYMENT' and hold_expires_at <= now()
     for update skip locked
  loop
    perform private.release_booking_allocations(r.id, 'หมดเวลาชำระมัดจำ');
    update public.bookings set status = 'EXPIRED' where id = r.id;
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- -----------------------------------------------------------------------------
-- แกนกลางการสร้างการจอง (ทุกช่องทาง) — Transaction เดียว
-- -----------------------------------------------------------------------------
create or replace function private.create_booking_core(
  p_branch_id     uuid,
  p_customer_id   uuid,
  p_channel       text,
  p_starts_at     timestamptz,
  p_option_ids    uuid[],
  p_note          text,
  p_with_deposit  boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  s          public.company_settings;
  v_company  uuid;
  v_tz       text;
  w          record;
  v_open     boolean := false;
  v_max_dur  integer;
  v_demands  jsonb := '[]'::jsonb;
  v_opt      uuid;
  v_booking  uuid;
  v_item     uuid;
  v_hold     timestamptz;
  v_deposit  numeric(12,2);
  v_total    numeric(12,2) := 0;
  o          record;
  p          public.service_price_histories;
  sr         record;
  v_local    timestamp;
begin
  select b.company_id into v_company from public.branches b where b.id = p_branch_id and b.is_active;
  if v_company is null or not private.is_company_active(v_company) then
    raise exception 'สาขาไม่เปิดให้บริการ' using errcode = 'invalid_parameter_value';
  end if;
  if not exists (select 1 from public.customers where id = p_customer_id and company_id = v_company and status = 'ACTIVE') then
    raise exception 'ไม่พบข้อมูลลูกค้า' using errcode = 'invalid_parameter_value';
  end if;
  select * into s from public.company_settings where company_id = v_company;
  v_tz := s.timezone;

  if p_option_ids is null or cardinality(p_option_ids) = 0 or cardinality(p_option_ids) > s.booking_max_items then
    raise exception 'จำนวนรายการต้องอยู่ระหว่าง 1-%', s.booking_max_items using errcode = 'invalid_parameter_value';
  end if;

  -- เวลาเริ่มต้องตรงช่อง (slot) ตามเวลาท้องถิ่น และอยู่ในช่วงที่อนุญาต
  v_local := p_starts_at at time zone v_tz;
  if extract(second from v_local) <> 0
     or (extract(hour from v_local) * 60 + extract(minute from v_local))::int % s.booking_slot_minutes <> 0 then
    raise exception 'เวลาเริ่มต้องเป็นช่วงละ % นาที', s.booking_slot_minutes using errcode = 'invalid_parameter_value';
  end if;
  if p_channel = 'ONLINE' and p_starts_at < now() + make_interval(mins => s.booking_min_lead_minutes) then
    raise exception 'ต้องจองล่วงหน้าอย่างน้อย % นาที', s.booking_min_lead_minutes using errcode = 'invalid_parameter_value';
  end if;
  if p_starts_at < now() then
    raise exception 'ไม่สามารถจองเวลาที่ผ่านมาแล้ว' using errcode = 'invalid_parameter_value';
  end if;
  if p_starts_at > now() + make_interval(days => s.booking_max_advance_days) then
    raise exception 'จองล่วงหน้าได้ไม่เกิน % วัน', s.booking_max_advance_days using errcode = 'invalid_parameter_value';
  end if;

  -- option ต้องเปิดขายในสาขานี้และมีราคา
  select max(x.duration_minutes) into v_max_dur
    from public.branch_service_options x where x.id = any (p_option_ids);
  if exists (
    select 1 from unnest(p_option_ids) u(id)
     where not exists (
       select 1 from public.branch_service_options x
         join public.branch_services bs on bs.id = x.branch_service_id and bs.is_active
         join public.services sv on sv.id = bs.service_id and sv.is_active
        where x.id = u.id and x.is_active and bs.branch_id = p_branch_id
          and (private.option_price_at(x.id)).id is not null)
  ) then
    raise exception 'บริการที่เลือกไม่เปิดให้จองที่สาขานี้' using errcode = 'invalid_parameter_value';
  end if;

  -- เวลาทำการ (ตรวจทั้งวันที่เริ่มและวันก่อนหน้า เผื่อร้านเปิดข้ามเที่ยงคืน)
  for w in
    select * from private.branch_open_window(p_branch_id, (p_starts_at at time zone v_tz)::date)
    union all
    select * from private.branch_open_window(p_branch_id, (p_starts_at at time zone v_tz)::date - 1)
  loop
    if p_starts_at >= w.opens_at and p_starts_at + make_interval(mins => v_max_dur) <= w.closes_at then
      v_open := true;
    end if;
  end loop;
  if not v_open then
    raise exception 'เวลาที่เลือกอยู่นอกเวลาทำการของสาขา' using errcode = 'invalid_parameter_value';
  end if;

  -- ล็อกทรัพยากรและตรวจ capacity ของทุกรายการพร้อมกัน
  foreach v_opt in array p_option_ids loop
    v_demands := v_demands || private.option_demands(v_opt, p_starts_at, s.booking_buffer_minutes);
  end loop;
  if not private.has_capacity(p_branch_id, v_demands, true) then
    raise exception 'ช่วงเวลานี้เตียง/อุปกรณ์เต็มแล้ว กรุณาเลือกเวลาอื่น' using errcode = 'P0001', hint = 'CAPACITY_FULL';
  end if;

  v_deposit := case when p_with_deposit then s.deposit_per_person * cardinality(p_option_ids) else 0 end;
  v_hold := case when v_deposit > 0 then now() + make_interval(mins => s.booking_hold_minutes) end;

  insert into public.bookings (
    company_id, branch_id, customer_id, channel, starts_at, ends_at, items_count, total_amount,
    deposit_required, deposit_status, hold_expires_at, customer_note
  ) values (
    v_company, p_branch_id, p_customer_id, p_channel, p_starts_at,
    p_starts_at + make_interval(mins => v_max_dur), cardinality(p_option_ids), 0,
    v_deposit, case when v_deposit > 0 then 'AWAITING_PAYMENT' else 'NOT_REQUIRED' end, v_hold,
    nullif(left(trim(coalesce(p_note, '')), 500), '')
  )
  returning id into v_booking;

  foreach v_opt in array p_option_ids loop
    select x.id, x.duration_minutes, bs.service_id, sv.name, sv.name_en
      into o
      from public.branch_service_options x
      join public.branch_services bs on bs.id = x.branch_service_id
      join public.services sv on sv.id = bs.service_id
     where x.id = v_opt;
    p := private.option_price_at(v_opt);

    insert into public.booking_items (
      company_id, booking_id, branch_service_option_id, service_id, service_name, service_name_en,
      duration_minutes, unit_price, therapist_fee, discount_amount, line_total, starts_at, ends_at
    ) values (
      v_company, v_booking, v_opt, o.service_id, o.name, o.name_en,
      o.duration_minutes, p.price, p.therapist_fee, 0, p.price, p_starts_at,
      p_starts_at + make_interval(mins => o.duration_minutes)
    )
    returning id into v_item;
    v_total := v_total + p.price;

    for sr in select resource_type_id, quantity from public.service_resources where service_id = o.service_id loop
      insert into public.resource_allocations (
        company_id, branch_id, resource_type_id, booking_item_id, quantity, starts_at, ends_at, status, expires_at
      ) values (
        v_company, p_branch_id, sr.resource_type_id, v_item, sr.quantity, p_starts_at,
        p_starts_at + make_interval(mins => o.duration_minutes + s.booking_buffer_minutes),
        case when v_deposit > 0 then 'HELD' else 'RESERVED' end, v_hold
      );
    end loop;
  end loop;

  -- total_amount ห้ามแก้หลังสร้าง (guard) จึงใช้ bypass ด้วยการตั้งค่าภายใน transaction นี้
  perform set_config('app.booking_total_init', v_booking::text, true);
  update public.bookings set total_amount = v_total where id = v_booking;
  perform set_config('app.booking_total_init', '', true);

  if v_deposit = 0 then
    perform private.confirm_booking(v_booking);
  end if;
  return v_booking;
end;
$$;

-- อนุญาตตั้ง total_amount ครั้งแรกภายใน create_booking_core เท่านั้น
create or replace function private.tg_bookings_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.company_id <> old.company_id or new.branch_id <> old.branch_id
     or new.starts_at <> old.starts_at or new.ends_at <> old.ends_at
     or new.items_count <> old.items_count
     or new.deposit_required <> old.deposit_required or new.channel <> old.channel
     or (new.total_amount <> old.total_amount
         and current_setting('app.booking_total_init', true) is distinct from old.id::text) then
    raise exception 'ห้ามแก้ข้อมูลหลักของการจอง' using errcode = 'check_violation';
  end if;
  if old.booking_code is not null and new.booking_code is distinct from old.booking_code then
    raise exception 'ห้ามเปลี่ยนรหัสการจอง' using errcode = 'check_violation';
  end if;
  if new.status <> old.status and not (
       (old.status = 'PENDING' and new.status in ('CONFIRMED', 'EXPIRED', 'CANCELLED'))
    or (old.status = 'CONFIRMED' and new.status in ('CHECKED_IN', 'CANCELLED', 'NO_SHOW'))
    or (old.status = 'CHECKED_IN' and new.status = 'COMPLETED')
  ) then
    raise exception 'เปลี่ยนสถานะการจองจาก % เป็น % ไม่ได้', old.status, new.status using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

revoke all on function private.release_booking_allocations(uuid, text) from public;
revoke all on function private.confirm_booking(uuid) from public;
revoke all on function private.issue_tracking_token(uuid) from public;
revoke all on function private.booking_id_by_token(text) from public;
revoke all on function private.booking_customer_view(uuid) from public;
revoke all on function private.expire_stale_bookings() from public;
revoke all on function private.create_booking_core(uuid, uuid, text, timestamptz, uuid[], text, boolean) from public;

-- Idempotency wrapper: hash ของพารามิเตอร์
create or replace function private.request_hash(p_payload jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(extensions.digest(p_payload::text, 'sha256'), 'hex');
$$;

-- -----------------------------------------------------------------------------
-- สมาชิก
-- -----------------------------------------------------------------------------
create or replace function public.create_member_booking(
  p_company_code     text,
  p_branch_id        uuid,
  p_starts_at        timestamptz,
  p_option_ids       uuid[],
  p_note             text,
  p_idempotency_key  text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c        public.customers := private.my_customer_row(p_company_code);
  v_prev   jsonb;
  v_id     uuid;
  v_result jsonb;
  v_hash   text := private.request_hash(jsonb_build_object(
                     'b', p_branch_id, 's', p_starts_at, 'o', p_option_ids, 'n', p_note));
begin
  if c.id is null then
    raise exception 'กรุณาลงทะเบียนข้อมูลลูกค้าก่อนจอง' using errcode = 'insufficient_privilege';
  end if;
  if (select branch.company_id from public.branches branch where branch.id = p_branch_id) is distinct from c.company_id then
    raise exception 'สาขาไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;

  v_prev := private.idempotency_begin('create_member_booking', p_idempotency_key, v_hash);
  if v_prev is not null then
    return v_prev -> 'body';
  end if;

  perform private.expire_stale_bookings();
  v_id := private.create_booking_core(p_branch_id, c.id, 'ONLINE', p_starts_at, p_option_ids, p_note, true);
  v_result := private.booking_customer_view(v_id);
  perform private.idempotency_complete('create_member_booking', p_idempotency_key, 200, v_result);
  return v_result;
end;
$$;

create or replace function public.my_bookings(p_company_code text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(private.booking_customer_view(b.id) order by b.starts_at desc), '[]'::jsonb)
    from public.bookings b
   where b.customer_id = (private.my_customer_row(p_company_code)).id;
$$;

create or replace function public.my_booking(p_company_code text, p_booking_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select private.booking_customer_view(b.id)
    from public.bookings b
   where b.id = p_booking_id and b.customer_id = (private.my_customer_row(p_company_code)).id;
$$;

-- ข้อมูลสำหรับ Edge Function ตรวจสลิป (สมาชิก)
create or replace function public.my_booking_payment_context(p_company_code text, p_booking_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('booking_id', b.id, 'company_id', b.company_id, 'branch_id', b.branch_id,
                            'amount', b.deposit_required)
    from public.bookings b
   where b.id = p_booking_id and b.customer_id = (private.my_customer_row(p_company_code)).id;
$$;

-- ยกเลิกเอง: ก่อนนัดอย่างน้อย cancellation_cutoff_hours
create or replace function public.cancel_my_booking(p_company_code text, p_booking_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  b        public.bookings;
  v_cutoff integer;
begin
  select * into b from public.bookings
   where id = p_booking_id and customer_id = (private.my_customer_row(p_company_code)).id
   for update;
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
  if b.status = 'CONFIRMED' and now() > b.starts_at - make_interval(hours => v_cutoff) then
    raise exception 'ยกเลิกเองได้ก่อนเวลานัดอย่างน้อย % ชั่วโมง กรุณาติดต่อร้าน', v_cutoff using errcode = 'check_violation';
  end if;

  perform private.release_booking_allocations(b.id, 'ลูกค้ายกเลิก');
  update public.bookings
     set status = 'CANCELLED', cancelled_at = now(), cancelled_by = auth.uid(), cancelled_by_role = 'CUSTOMER',
         cancel_reason = nullif(left(trim(coalesce(p_reason, '')), 500), ''),
         deposit_status = case when deposit_status = 'PAID' then 'REFUND_PENDING' else deposit_status end
   where id = b.id;
  update public.booking_deposits set refund_status = 'PENDING' where booking_id = b.id and status = 'VERIFIED';
  update public.booking_tracking_tokens set revoked_at = now() where booking_id = b.id and revoked_at is null;

  return private.booking_customer_view(b.id);
end;
$$;

-- -----------------------------------------------------------------------------
-- Guest (เรียกจาก Edge Function guest-booking ด้วย service role หลังตรวจ CAPTCHA/Rate limit)
-- -----------------------------------------------------------------------------
create or replace function public.create_guest_booking(
  p_company_code        text,
  p_branch_id           uuid,
  p_starts_at           timestamptz,
  p_option_ids          uuid[],
  p_first_name          text,
  p_last_name           text,
  p_phone               text,
  p_email               text,
  p_note                text,
  p_privacy_version_id  uuid,
  p_idempotency_key     text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company  uuid := private.company_id_by_code(p_company_code);
  v_phone    text := private.normalize_phone(p_phone);
  v_limit    integer;
  v_prev     jsonb;
  v_customer uuid;
  v_booking  uuid;
  v_token    text;
  v_result   jsonb;
  v_hash     text := private.request_hash(jsonb_build_object(
                       'b', p_branch_id, 's', p_starts_at, 'o', p_option_ids, 'p', v_phone, 'f', p_first_name));
begin
  if v_company is null or (select company_id from public.branches where id = p_branch_id) is distinct from v_company then
    raise exception 'สาขาไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  if v_phone is null then
    raise exception 'เบอร์โทรไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  if p_first_name is null or char_length(trim(p_first_name)) = 0 then
    raise exception 'กรุณากรอกชื่อ' using errcode = 'invalid_parameter_value';
  end if;
  if p_privacy_version_id is distinct from private.current_policy_version(v_company, 'PRIVACY_NOTICE') then
    raise exception 'กรุณายอมรับนโยบายความเป็นส่วนตัวฉบับปัจจุบัน' using errcode = 'invalid_parameter_value';
  end if;

  v_prev := private.idempotency_begin('create_guest_booking', p_idempotency_key, v_hash, null);
  if v_prev is not null then
    return v_prev -> 'body';
  end if;

  perform private.expire_stale_bookings();

  select guest_max_active_bookings into v_limit from public.company_settings where company_id = v_company;
  if (select count(*) from public.bookings b join public.customers c on c.id = b.customer_id
       where c.company_id = v_company and c.phone = v_phone
         and b.status in ('PENDING', 'CONFIRMED') and b.starts_at > now()) >= v_limit then
    raise exception 'เบอร์นี้มีการจองที่ยังไม่ถึงวันนัดครบ % รายการแล้ว', v_limit using errcode = 'check_violation';
  end if;

  -- Guest ใหม่ทุกครั้ง (ไม่รวมอัตโนมัติ) พนักงานจับคู่ภายหลัง
  insert into public.customers (company_id, first_name, last_name, phone, email, created_channel)
  values (v_company, p_first_name, coalesce(p_last_name, ''), v_phone, nullif(trim(coalesce(p_email, '')), ''), 'ONLINE')
  returning id into v_customer;
  perform private.record_consent(v_customer, 'PRIVACY_NOTICE', true, 'ONLINE');

  v_booking := private.create_booking_core(p_branch_id, v_customer, 'ONLINE', p_starts_at, p_option_ids, p_note, true);
  v_token := private.issue_tracking_token(v_booking);
  v_result := private.booking_customer_view(v_booking) || jsonb_build_object('tracking_token', v_token);

  -- เก็บผลไว้ตอบคำขอซ้ำ (มี token เพราะเป็นผลเดิมของผู้ส่งคำขอเดิม)
  perform private.idempotency_complete('create_guest_booking', p_idempotency_key, 200, v_result, null);
  return v_result;
end;
$$;

create or replace function public.get_booking_by_token(p_token text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select private.booking_customer_view(private.booking_id_by_token(p_token));
$$;

create or replace function public.booking_payment_context_by_token(p_token text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('booking_id', b.id, 'company_id', b.company_id, 'branch_id', b.branch_id,
                            'amount', b.deposit_required)
    from public.bookings b where b.id = private.booking_id_by_token(p_token);
$$;

-- -----------------------------------------------------------------------------
-- บันทึกผลตรวจสลิปจาก Edge Function (service role)
--   p_outcome: VERIFIED | REJECTED | REVIEW
-- -----------------------------------------------------------------------------
create or replace function public.record_deposit_slip(
  p_booking_id        uuid,
  p_slip_path         text,
  p_outcome           text,
  p_provider_code     integer,
  p_provider_message  text,
  p_slip              jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  b          public.bookings;
  v_ref      text := nullif(p_slip ->> 'trans_ref', '');
  v_amount   numeric := (p_slip ->> 'amount')::numeric;
  v_outcome  text := p_outcome;
  v_message  text := p_provider_message;
  v_review_until timestamptz;
begin
  if p_outcome not in ('VERIFIED', 'REJECTED', 'REVIEW') then
    raise exception 'ผลตรวจไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  select * into b from public.bookings where id = p_booking_id for update;
  if b.id is null or b.status <> 'PENDING' or b.deposit_status <> 'AWAITING_PAYMENT' then
    raise exception 'การจองนี้ไม่ได้รอชำระมัดจำ' using errcode = 'check_violation';
  end if;
  if b.hold_expires_at <= now() then
    raise exception 'หมดเวลาชำระมัดจำแล้ว กรุณาจองใหม่' using errcode = 'check_violation';
  end if;

  -- ตรวจซ้ำฝั่ง DB: ยอดต้องตรง และเลขอ้างอิงสลิปต้องไม่ถูกใช้แล้ว
  if v_outcome = 'VERIFIED' then
    if v_amount is distinct from b.deposit_required then
      v_outcome := 'REJECTED'; v_message := 'ยอดเงินในสลิปไม่ตรงกับยอดมัดจำ';
    elsif v_ref is null then
      v_outcome := 'REVIEW'; v_message := 'ไม่พบเลขอ้างอิงสลิป';
    elsif exists (select 1 from public.booking_deposits where slip_trans_ref = v_ref and status <> 'REJECTED') then
      v_outcome := 'REJECTED'; v_message := 'สลิปนี้ถูกใช้แล้ว';
    end if;
  end if;

  insert into public.booking_deposits (
    company_id, branch_id, booking_id, amount, status, slip_path, verification_source,
    provider_code, provider_message, slip_trans_ref, slip_amount, slip_trans_at,
    slip_sender_name, slip_receiver_name, slip_receiver_account
  ) values (
    b.company_id, b.branch_id, b.id, b.deposit_required,
    case v_outcome when 'VERIFIED' then 'VERIFIED' when 'REJECTED' then 'REJECTED' else 'PENDING_REVIEW' end,
    p_slip_path, case when v_outcome = 'VERIFIED' then 'AUTO' end,
    p_provider_code, left(v_message, 300),
    case when v_outcome = 'REJECTED' then null else v_ref end,
    v_amount, (p_slip ->> 'trans_at')::timestamptz,
    left(p_slip ->> 'sender_name', 100), left(p_slip ->> 'receiver_name', 100), left(p_slip ->> 'receiver_account', 60)
  );

  if v_outcome = 'VERIFIED' then
    update public.bookings set deposit_status = 'PAID' where id = b.id;
    perform private.confirm_booking(b.id);
  elsif v_outcome = 'REVIEW' then
    -- กันที่ไว้ระหว่างรอพนักงานตรวจ (ไม่เกินเวลานัด)
    v_review_until := least(b.starts_at, now() + interval '12 hours');
    update public.bookings set deposit_status = 'PENDING_REVIEW', hold_expires_at = v_review_until where id = b.id;
    update public.resource_allocations a set expires_at = v_review_until
      from public.booking_items i
     where i.id = a.booking_item_id and i.booking_id = b.id and a.status = 'HELD';
  end if;

  return private.booking_customer_view(b.id) || jsonb_build_object('slip_outcome', v_outcome, 'slip_message', v_message);
end;
$$;

-- -----------------------------------------------------------------------------
-- พนักงาน
-- -----------------------------------------------------------------------------
create or replace function private.require_branch_access(p_branch_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.has_branch_access(p_branch_id) then
    raise exception 'ไม่มีสิทธิ์ในสาขานี้' using errcode = 'insufficient_privilege';
  end if;
end;
$$;

revoke all on function private.require_branch_access(uuid) from public;

create or replace function public.staff_create_booking(
  p_branch_id        uuid,
  p_customer_id      uuid,
  p_starts_at        timestamptz,
  p_option_ids       uuid[],
  p_note             text,
  p_collect_deposit  boolean,
  p_idempotency_key  text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prev   jsonb;
  v_id     uuid;
  v_result jsonb;
  v_hash   text := private.request_hash(jsonb_build_object(
                     'b', p_branch_id, 'c', p_customer_id, 's', p_starts_at, 'o', p_option_ids, 'd', p_collect_deposit));
begin
  perform private.require_branch_access(p_branch_id);

  v_prev := private.idempotency_begin('staff_create_booking', p_idempotency_key, v_hash);
  if v_prev is not null then
    return v_prev -> 'body';
  end if;

  perform private.expire_stale_bookings();
  v_id := private.create_booking_core(p_branch_id, p_customer_id, 'STAFF', p_starts_at, p_option_ids, p_note,
                                      coalesce(p_collect_deposit, false));
  v_result := jsonb_build_object('booking_id', v_id);
  -- ถ้าเก็บมัดจำ ออกลิงก์ติดตาม/ชำระให้พนักงานส่งต่อให้ลูกค้า
  if coalesce(p_collect_deposit, false) then
    v_result := v_result || jsonb_build_object('tracking_token', private.issue_tracking_token(v_id));
  end if;
  perform private.idempotency_complete('staff_create_booking', p_idempotency_key, 200, v_result);
  return v_result;
end;
$$;

-- รายการจองของสาขาในวันที่ระบุ (ชื่อเต็ม เบอร์ปิดบัง)
create or replace function public.staff_bookings(p_branch_id uuid, p_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tz text;
begin
  perform private.require_branch_access(p_branch_id);
  select s.timezone into v_tz from public.branches b join public.company_settings s on s.company_id = b.company_id
   where b.id = p_branch_id;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
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
    ) order by b.starts_at, b.created_at)
      from public.bookings b
      join public.customers c on c.id = b.customer_id
     where b.branch_id = p_branch_id
       and b.starts_at >= (p_date::timestamp at time zone v_tz)
       and b.starts_at < ((p_date + 1)::timestamp at time zone v_tz)
  ), '[]'::jsonb);
end;
$$;

-- พนักงานตรวจสลิปที่ระบบตรวจอัตโนมัติไม่ได้
create or replace function public.review_deposit(p_deposit_id uuid, p_approve boolean, p_note text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  d public.booking_deposits;
  b public.bookings;
begin
  select * into d from public.booking_deposits where id = p_deposit_id for update;
  if d.id is null then
    raise exception 'ไม่พบรายการมัดจำ' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(d.branch_id);
  if d.status <> 'PENDING_REVIEW' then
    raise exception 'รายการนี้ตรวจแล้ว' using errcode = 'check_violation';
  end if;
  if not p_approve and (p_note is null or char_length(trim(p_note)) < 3) then
    raise exception 'กรุณาระบุเหตุผลที่ปฏิเสธ' using errcode = 'invalid_parameter_value';
  end if;
  select * into b from public.bookings where id = d.booking_id for update;

  update public.booking_deposits
     set status = case when p_approve then 'VERIFIED' else 'REJECTED' end,
         verification_source = case when p_approve then 'STAFF' end,
         reviewed_by = auth.uid(), reviewed_at = now(), review_note = nullif(trim(coalesce(p_note, '')), '')
   where id = d.id;

  if p_approve then
    if b.status <> 'PENDING' then
      -- การจองหมดอายุ/ยกเลิกไปแล้ว: รับเงินไว้แต่ต้องคืน
      update public.booking_deposits set refund_status = 'PENDING' where id = d.id;
      update public.bookings set deposit_status = 'REFUND_PENDING' where id = b.id;
    else
      update public.bookings set deposit_status = 'PAID' where id = b.id;
      perform private.confirm_booking(b.id);
    end if;
  elsif b.status = 'PENDING' then
    perform private.release_booking_allocations(b.id, 'สลิปไม่ผ่านการตรวจสอบ');
    update public.bookings
       set status = 'CANCELLED', cancelled_at = now(), cancelled_by = auth.uid(), cancelled_by_role = 'STAFF',
           cancel_reason = 'สลิปไม่ผ่านการตรวจสอบ: ' || left(trim(p_note), 400),
           deposit_status = 'AWAITING_PAYMENT'
     where id = b.id;
  end if;
end;
$$;

-- พนักงานยกเลิก: มัดจำคืนอัตโนมัติถ้าทันเวลา, ช้ากว่านั้นริบ
-- p_force_refund = true (คืนแม้ช้า เช่น ร้านปิดฉุกเฉิน) ต้องเป็น OWNER + step-up
create or replace function public.staff_cancel_booking(p_booking_id uuid, p_reason text, p_force_refund boolean default false)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  b        public.bookings;
  v_cutoff integer;
  v_refund boolean;
begin
  select * into b from public.bookings where id = p_booking_id for update;
  if b.id is null then
    raise exception 'ไม่พบการจอง' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(b.branch_id);
  if b.status not in ('PENDING', 'CONFIRMED') then
    raise exception 'การจองนี้ยกเลิกไม่ได้' using errcode = 'check_violation';
  end if;
  if b.deposit_status = 'PENDING_REVIEW' then
    raise exception 'กรุณาตรวจสลิปก่อนยกเลิก' using errcode = 'check_violation';
  end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาระบุเหตุผล' using errcode = 'invalid_parameter_value';
  end if;

  select cancellation_cutoff_hours into v_cutoff from public.company_settings where company_id = b.company_id;
  v_refund := now() <= b.starts_at - make_interval(hours => v_cutoff);
  if coalesce(p_force_refund, false) and not v_refund and b.deposit_status = 'PAID' then
    perform private.require_owner_step_up(b.company_id);
    v_refund := true;
  end if;

  perform set_config('app.audit_reason', trim(p_reason), true);
  perform private.release_booking_allocations(b.id, 'พนักงานยกเลิก');
  update public.bookings
     set status = 'CANCELLED', cancelled_at = now(), cancelled_by = auth.uid(), cancelled_by_role = 'STAFF',
         cancel_reason = left(trim(p_reason), 500),
         deposit_status = case when deposit_status = 'PAID' then
                            case when v_refund then 'REFUND_PENDING' else 'FORFEITED' end
                          else deposit_status end
   where id = b.id;
  update public.booking_deposits
     set refund_status = case when v_refund then 'PENDING' else 'FORFEITED' end
   where booking_id = b.id and status = 'VERIFIED';
  update public.booking_tracking_tokens set revoked_at = now() where booking_id = b.id and revoked_at is null;
end;
$$;

create or replace function public.mark_no_show(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  b       public.bookings;
  v_grace integer;
begin
  select * into b from public.bookings where id = p_booking_id for update;
  if b.id is null then
    raise exception 'ไม่พบการจอง' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(b.branch_id);
  if b.status <> 'CONFIRMED' then
    raise exception 'บันทึกไม่มาตามนัดได้เฉพาะการจองที่ยืนยันแล้ว' using errcode = 'check_violation';
  end if;
  select no_show_grace_minutes into v_grace from public.company_settings where company_id = b.company_id;
  if now() < b.starts_at + make_interval(mins => v_grace) then
    raise exception 'บันทึกได้หลังเวลานัด % นาที', v_grace using errcode = 'check_violation';
  end if;

  perform private.release_booking_allocations(b.id, 'ไม่มาตามนัด');
  update public.bookings
     set status = 'NO_SHOW', no_show_at = now(),
         deposit_status = case when deposit_status = 'PAID' then 'FORFEITED' else deposit_status end
   where id = b.id;
  update public.booking_deposits set refund_status = 'FORFEITED' where booking_id = b.id and status = 'VERIFIED';
end;
$$;

-- บันทึกการโอนคืนมัดจำ (OWNER + step-up เพราะเป็นการคืนเงิน)
create or replace function public.record_deposit_refund(p_booking_id uuid, p_reference text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  b public.bookings;
begin
  select * into b from public.bookings where id = p_booking_id for update;
  if b.id is null then
    raise exception 'ไม่พบการจอง' using errcode = 'no_data_found';
  end if;
  perform private.require_owner_step_up(b.company_id);
  if b.deposit_status <> 'REFUND_PENDING' then
    raise exception 'การจองนี้ไม่มีมัดจำที่รอคืน' using errcode = 'check_violation';
  end if;
  if p_reference is null or char_length(trim(p_reference)) < 3 then
    raise exception 'กรุณาระบุเลขอ้างอิงการโอนคืน' using errcode = 'invalid_parameter_value';
  end if;

  update public.booking_deposits
     set refund_status = 'REFUNDED', refund_reference = left(trim(p_reference), 100),
         refunded_at = now(), refunded_by = auth.uid()
   where booking_id = b.id and status = 'VERIFIED' and refund_status = 'PENDING';
  update public.bookings set deposit_status = 'REFUNDED' where id = b.id;
end;
$$;

create or replace function public.set_booking_staff_note(p_booking_id uuid, p_note text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_branch uuid;
begin
  select branch_id into v_branch from public.bookings where id = p_booking_id;
  perform private.require_branch_access(v_branch);
  update public.bookings set staff_note = nullif(left(trim(coalesce(p_note, '')), 500), '') where id = p_booking_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- เชื่อมกับ Phase 3: รวม Guest ต้องย้ายการจองด้วย, anonymize ต้องล้างหมายเหตุ/ปิด token
-- -----------------------------------------------------------------------------
create or replace function private.tg_customers_cascade()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'MERGED' and old.status <> 'MERGED' then
    update public.bookings set customer_id = new.merged_into_id where customer_id = new.id;
  end if;
  if new.status = 'ANONYMIZED' and old.status <> 'ANONYMIZED' then
    update public.bookings set customer_note = null where customer_id = new.id;
    update public.booking_tracking_tokens t set revoked_at = now()
      from public.bookings b where b.id = t.booking_id and b.customer_id = new.id and t.revoked_at is null;
  end if;
  return null;
end;
$$;

-- bookings.customer_id เปลี่ยนได้เฉพาะตอนรวมลูกค้า (trigger นี้) — guard ของ bookings ไม่ห้าม customer_id
create trigger customers_cascade after update of status on public.customers
  for each row execute function private.tg_customers_cascade();

-- ส่งออกข้อมูล (PDPA) รวมประวัติการจอง
create or replace function public.export_my_data(p_company_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.customers := private.my_customer_row(p_company_code);
begin
  if c.id is null then
    raise exception 'ไม่พบข้อมูลลูกค้า' using errcode = 'no_data_found';
  end if;
  perform private.write_audit(p_action => 'CUSTOMER_DATA_EXPORTED', p_company_id => c.company_id,
                              p_table_name => 'customers', p_record_id => c.id);
  return jsonb_build_object(
    'exported_at', now(),
    'profile', (select jsonb_build_object('display_name', p.display_name, 'phone', p.phone) from public.profiles p where p.id = auth.uid()),
    'customer', jsonb_build_object(
      'first_name', c.first_name, 'last_name', c.last_name, 'phone', c.phone, 'email', c.email, 'created_at', c.created_at),
    'consents', coalesce((
      select jsonb_agg(jsonb_build_object('type', cc.consent_type, 'granted', cc.granted, 'channel', cc.channel,
                                          'version', p.version, 'recorded_at', cc.recorded_at) order by cc.recorded_at)
        from public.customer_consents cc join public.privacy_policy_versions p on p.id = cc.policy_version_id
       where cc.customer_id = c.id), '[]'::jsonb),
    'data_requests', coalesce((
      select jsonb_agg(jsonb_build_object('type', r.request_type, 'status', r.status, 'requested_at', r.requested_at,
                                          'processed_at', r.processed_at) order by r.requested_at)
        from public.customer_data_requests r where r.customer_id = c.id), '[]'::jsonb),
    'bookings', coalesce((
      select jsonb_agg(private.booking_customer_view(b.id) order by b.starts_at)
        from public.bookings b where b.customer_id = c.id), '[]'::jsonb)
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Storage: สลิปมัดจำ (private) path {company_id}/{branch_id}/{booking_id}/{file}
-- เขียนโดย Edge Function (service role) เท่านั้น, พนักงานสาขาอ่านได้
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('booking-slips', 'booking-slips', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy booking_slips_select_branch on storage.objects
  for select to authenticated
  using (bucket_id = 'booking-slips' and private.has_branch_access(private.try_uuid(split_part(name, '/', 2))));

-- -----------------------------------------------------------------------------
-- pg_cron: ปิดการจองที่หมดเวลาชำระทุกนาที (ถ้ามี pg_cron ในฐานข้อมูล)
-- -----------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('expire-stale-bookings', '* * * * *', 'select private.expire_stale_bookings()');
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- Grants + RLS
-- -----------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.create_member_booking(text, uuid, timestamptz, uuid[], text, text)',
    'public.my_bookings(text)',
    'public.my_booking(text, uuid)',
    'public.my_booking_payment_context(text, uuid)',
    'public.cancel_my_booking(text, uuid, text)',
    'public.staff_create_booking(uuid, uuid, timestamptz, uuid[], text, boolean, text)',
    'public.staff_bookings(uuid, date)',
    'public.review_deposit(uuid, boolean, text)',
    'public.staff_cancel_booking(uuid, text, boolean)',
    'public.mark_no_show(uuid)',
    'public.record_deposit_refund(uuid, text)',
    'public.set_booking_staff_note(uuid, text)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;

  foreach f in array array[
    'public.create_guest_booking(text, uuid, timestamptz, uuid[], text, text, text, text, text, uuid, text)',
    'public.get_booking_by_token(text)',
    'public.booking_payment_context_by_token(text)',
    'public.record_deposit_slip(uuid, text, text, integer, text, jsonb)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end;
$$;

alter table public.bookings enable row level security;
alter table public.booking_items enable row level security;
alter table public.booking_tracking_tokens enable row level security;
alter table public.booking_deposits enable row level security;

revoke all on public.bookings, public.booking_items, public.booking_tracking_tokens, public.booking_deposits
  from anon, authenticated;
grant all on public.bookings, public.booking_items, public.booking_tracking_tokens, public.booking_deposits
  to service_role;

-- พนักงานสาขาอ่านได้ (ค่าแรงใน booking_items ไม่ grant ให้ client)
grant select on public.bookings, public.booking_deposits to authenticated;
grant select (id, company_id, booking_id, branch_service_option_id, service_id, service_name, service_name_en,
              duration_minutes, unit_price, quantity, discount_amount, line_total, starts_at, ends_at, created_at)
  on public.booking_items to authenticated;

create policy bookings_select_branch on public.bookings
  for select to authenticated using (private.has_branch_access(branch_id));
create policy booking_items_select_branch on public.booking_items
  for select to authenticated
  using (exists (select 1 from public.bookings b where b.id = booking_id and private.has_branch_access(b.branch_id)));
create policy booking_deposits_select_branch on public.booking_deposits
  for select to authenticated using (private.has_branch_access(branch_id));
-- booking_tracking_tokens: ไม่มี policy (ใช้ผ่าน Function เท่านั้น)
