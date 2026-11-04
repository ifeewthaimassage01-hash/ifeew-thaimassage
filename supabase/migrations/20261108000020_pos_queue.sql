-- =============================================================================
-- Phase 5 / 020 — POS Session, Service Order, คิว และการมอบหมายหมอ
--   pos_sessions        กะ POS (เปิดได้ครั้งละ 1 กะต่อสาขา) — ปิดกะ/นับเงินอยู่ใน Phase 7
--   service_orders      ใบงานของลูกค้าที่มาใช้บริการจริง (Walk-in หรือเช็กอินจากการจอง)
--   service_order_items รายการบริการ (Snapshot ราคา/เวลา/ค่ามือ) 1 รายการ = 1 คน
--   queue_items         คิวของแต่ละรายการ (1 รายการ = 1 คิว) เลขคิวรายวันต่อสาขา
--   service_assignments หมอที่รับรายการนั้น (1 รายการ = หมอ 1 คน, หมอ 1 คน = 1 คิวที่ยังไม่จบ)
-- ทุกการเปลี่ยนแปลงผ่าน Function เท่านั้น; Client อ่านได้ตาม RLS ของสาขา
-- =============================================================================

-- -----------------------------------------------------------------------------
-- วันทำการ (business date) ของเวลาใดๆ: ช่วงหลังเที่ยงคืนที่ร้านยังเปิดนับเป็นวันก่อนหน้า
--   คืน 1 แถวเสมอ (ถ้าสาขามีอยู่) opens_at/closes_at = NULL ถ้าวันนั้นปิด
-- -----------------------------------------------------------------------------
create or replace function private.branch_window_at(p_branch_id uuid, p_at timestamptz)
returns table (business_date date, opens_at timestamptz, closes_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tz    text;
  v_local date;
  w       record;
begin
  select s.timezone into v_tz
    from public.branches b join public.company_settings s on s.company_id = b.company_id
   where b.id = p_branch_id;
  if v_tz is null then
    return;
  end if;
  v_local := (p_at at time zone v_tz)::date;

  for w in select * from private.branch_open_window(p_branch_id, v_local - 1) loop
    if p_at >= w.opens_at and p_at < w.closes_at then
      business_date := v_local - 1;
      opens_at := w.opens_at;
      closes_at := w.closes_at;
      return next;
      return;
    end if;
  end loop;

  business_date := v_local;
  select x.opens_at, x.closes_at into opens_at, closes_at
    from private.branch_open_window(p_branch_id, v_local) x;
  return next;
end;
$$;

revoke all on function private.branch_window_at(uuid, timestamptz) from public;

-- option ทุกตัวต้องเปิดขายในสาขาและมีราคา ณ ตอนนี้
create or replace function private.assert_branch_options(p_branch_id uuid, p_option_ids uuid[])
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_option_ids is null or cardinality(p_option_ids) = 0 or cardinality(p_option_ids) > 10 then
    raise exception 'จำนวนรายการต้องอยู่ระหว่าง 1-10' using errcode = 'invalid_parameter_value';
  end if;
  if exists (
    select 1 from unnest(p_option_ids) u(id)
     where not exists (
       select 1 from public.branch_service_options x
         join public.branch_services bs on bs.id = x.branch_service_id and bs.is_active
         join public.services sv on sv.id = bs.service_id and sv.is_active
        where x.id = u.id and x.is_active and bs.branch_id = p_branch_id
          and (private.option_price_at(x.id)).id is not null)
  ) then
    raise exception 'บริการที่เลือกไม่เปิดขายที่สาขานี้' using errcode = 'invalid_parameter_value';
  end if;
end;
$$;

revoke all on function private.assert_branch_options(uuid, uuid[]) from public;

-- -----------------------------------------------------------------------------
-- pos_sessions
-- -----------------------------------------------------------------------------
create table public.pos_sessions (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null,
  branch_id      uuid not null,
  status         text not null default 'OPEN' check (status in ('OPEN', 'CLOSED')),
  business_date  date not null,
  opened_at      timestamptz not null default now(),
  opened_by      uuid not null references public.profiles (id),
  opening_cash   numeric(12,2) not null check (opening_cash between 0 and 1000000),
  opening_note   text check (opening_note is null or char_length(opening_note) <= 300),
  closed_at      timestamptz,
  closed_by      uuid references public.profiles (id),
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id),
  updated_at     timestamptz not null default now(),
  constraint pos_sessions_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint pos_sessions_company_id_id_key unique (company_id, id),
  constraint pos_sessions_closed_chk check ((status = 'CLOSED') = (closed_at is not null))
);

comment on table public.pos_sessions is 'กะ POS ของสาขา (ลิ้นชักเงินสดเดียว = เปิดได้ครั้งละ 1 กะ) ห้าม DELETE';

create unique index pos_sessions_one_open on public.pos_sessions (branch_id) where status = 'OPEN';
create index pos_sessions_branch_date_idx on public.pos_sessions (branch_id, business_date);

-- -----------------------------------------------------------------------------
-- service_orders
-- -----------------------------------------------------------------------------
create table public.service_orders (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null,
  branch_id      uuid not null,
  customer_id    uuid,              -- NULL = ลูกค้าทั่วไปที่ไม่ให้ข้อมูล (Walk-in เท่านั้น)
  booking_id     uuid,
  channel        text not null check (channel in ('ONLINE', 'WALK_IN', 'STAFF')),
  business_date  date not null,
  status         text not null default 'OPEN' check (status in ('OPEN', 'COMPLETED', 'CANCELLED')),
  note           text check (note is null or char_length(note) <= 500),
  completed_at   timestamptz,
  cancelled_at   timestamptz,
  cancelled_by   uuid references public.profiles (id),
  cancel_reason  text check (cancel_reason is null or char_length(cancel_reason) <= 500),
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id),
  updated_at     timestamptz not null default now(),
  constraint service_orders_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint service_orders_customer_fk foreign key (company_id, customer_id)
    references public.customers (company_id, id) on delete restrict,
  constraint service_orders_booking_fk foreign key (company_id, booking_id)
    references public.bookings (company_id, id) on delete restrict,
  constraint service_orders_company_id_id_key unique (company_id, id),
  constraint service_orders_branch_id_key unique (company_id, branch_id, id),
  constraint service_orders_booking_key unique (booking_id),
  constraint service_orders_channel_chk check ((channel = 'WALK_IN') = (booking_id is null)),
  constraint service_orders_booking_customer_chk check (booking_id is null or customer_id is not null),
  constraint service_orders_cancel_chk check ((status = 'CANCELLED') = (cancelled_at is not null)),
  constraint service_orders_completed_chk check (status <> 'COMPLETED' or completed_at is not null)
);

comment on table public.service_orders is
  'ใบงานบริการหน้าร้าน (1 การจอง = 1 Order) ห้าม DELETE เปลี่ยนผ่าน Function เท่านั้น';

create index service_orders_branch_date_idx on public.service_orders (branch_id, business_date);
create index service_orders_customer_idx on public.service_orders (customer_id);

-- -----------------------------------------------------------------------------
-- service_order_items (Snapshot)
-- -----------------------------------------------------------------------------
create table public.service_order_items (
  id                        uuid primary key default gen_random_uuid(),
  company_id                uuid not null,
  branch_id                 uuid not null,
  service_order_id          uuid not null,
  booking_item_id           uuid references public.booking_items (id) on delete restrict,
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
  status                    text not null default 'ACTIVE' check (status in ('ACTIVE', 'CANCELLED')),
  cancelled_at              timestamptz,
  cancelled_by              uuid references public.profiles (id),
  cancel_reason             text check (cancel_reason is null or char_length(cancel_reason) <= 500),
  created_at                timestamptz not null default now(),
  created_by                uuid references public.profiles (id),
  updated_at                timestamptz not null default now(),
  constraint service_order_items_order_fk foreign key (company_id, branch_id, service_order_id)
    references public.service_orders (company_id, branch_id, id) on delete restrict,
  constraint service_order_items_option_fk foreign key (company_id, branch_service_option_id)
    references public.branch_service_options (company_id, id) on delete restrict,
  constraint service_order_items_service_fk foreign key (company_id, service_id)
    references public.services (company_id, id) on delete restrict,
  constraint service_order_items_company_id_id_key unique (company_id, id),
  constraint service_order_items_branch_id_key unique (company_id, branch_id, id),
  constraint service_order_items_booking_item_key unique (booking_item_id),
  constraint service_order_items_total_chk check (line_total = unit_price * quantity - discount_amount),
  constraint service_order_items_cancel_chk check ((status = 'CANCELLED') = (cancelled_at is not null))
);

comment on column public.service_order_items.therapist_fee is 'ค่ามือหมอ ณ ตอนสร้างรายการ (ไม่ grant ให้ Client)';

create index service_order_items_order_idx on public.service_order_items (service_order_id);

-- -----------------------------------------------------------------------------
-- queue_items
-- -----------------------------------------------------------------------------
create table public.queue_items (
  id                     uuid primary key default gen_random_uuid(),
  company_id             uuid not null,
  branch_id              uuid not null,
  service_order_item_id  uuid not null,
  queue_date             date not null,
  queue_number           integer not null check (queue_number between 1 and 9999),
  status                 text not null default 'WAITING'
                           check (status in ('WAITING', 'CALLED', 'ACCEPTED', 'IN_SERVICE', 'COMPLETED', 'CANCELLED')),
  planned_starts_at      timestamptz not null,
  planned_ends_at        timestamptz not null,
  called_at              timestamptz,
  called_by              uuid references public.profiles (id),
  accepted_at            timestamptz,
  accepted_by            uuid references public.profiles (id),
  started_at             timestamptz,
  started_by             uuid references public.profiles (id),
  completed_at           timestamptz,
  completed_by           uuid references public.profiles (id),
  cancelled_at           timestamptz,
  cancelled_by           uuid references public.profiles (id),
  cancel_reason          text check (cancel_reason is null or char_length(cancel_reason) <= 500),
  created_at             timestamptz not null default now(),
  created_by             uuid references public.profiles (id),
  updated_at             timestamptz not null default now(),
  constraint queue_items_item_fk foreign key (company_id, branch_id, service_order_item_id)
    references public.service_order_items (company_id, branch_id, id) on delete restrict,
  constraint queue_items_branch_id_key unique (company_id, branch_id, id),
  constraint queue_items_item_key unique (service_order_item_id),
  constraint queue_items_number_key unique (branch_id, queue_date, queue_number),
  constraint queue_items_period_chk check (planned_ends_at > planned_starts_at),
  constraint queue_items_started_chk check ((status in ('IN_SERVICE', 'COMPLETED')) = (started_at is not null)),
  constraint queue_items_completed_chk check ((status = 'COMPLETED') = (completed_at is not null)),
  constraint queue_items_cancel_chk check ((status = 'CANCELLED') = (cancelled_at is not null))
);

comment on table public.queue_items is
  'คิวต่อรายการบริการ เลขคิว unique ต่อ (สาขา, วันทำการ) ห้าม DELETE; Realtime ใช้แสดงผลเท่านั้น';

create index queue_items_branch_date_idx on public.queue_items (branch_id, queue_date);

-- -----------------------------------------------------------------------------
-- service_assignments
-- -----------------------------------------------------------------------------
create table public.service_assignments (
  id                   uuid primary key default gen_random_uuid(),
  company_id           uuid not null,
  branch_id            uuid not null,
  queue_item_id        uuid not null,
  employee_id          uuid not null,
  status               text not null default 'ASSIGNED'
                         check (status in ('ASSIGNED', 'ACCEPTED', 'IN_SERVICE', 'COMPLETED', 'CANCELLED')),
  off_shift_confirmed  boolean not null default false,
  assigned_at          timestamptz not null default now(),
  assigned_by          uuid references public.profiles (id),
  accepted_at          timestamptz,
  accepted_by          uuid references public.profiles (id),
  started_at           timestamptz,
  completed_at         timestamptz,
  cancelled_at         timestamptz,
  cancelled_by         uuid references public.profiles (id),
  cancel_reason        text check (cancel_reason is null or char_length(cancel_reason) <= 500),
  created_at           timestamptz not null default now(),
  created_by           uuid references public.profiles (id),
  updated_at           timestamptz not null default now(),
  constraint service_assignments_queue_fk foreign key (company_id, branch_id, queue_item_id)
    references public.queue_items (company_id, branch_id, id) on delete restrict,
  constraint service_assignments_employee_fk foreign key (company_id, employee_id)
    references public.employees (company_id, id) on delete restrict,
  constraint service_assignments_cancel_chk check ((status = 'CANCELLED') = (cancelled_at is not null)),
  constraint service_assignments_completed_chk check ((status = 'COMPLETED') = (completed_at is not null))
);

comment on table public.service_assignments is
  'หมอที่รับรายการบริการ (ประวัติการเปลี่ยนหมอเก็บเป็นแถว CANCELLED) ใช้คิดค่ามือใน Phase ถัดไป';

-- 1 รายการ = หมอ 1 คน (ที่ไม่ได้ยกเลิก)
create unique index service_assignments_one_per_queue
  on public.service_assignments (queue_item_id) where status <> 'CANCELLED';
-- หมอ 1 คน = 1 คิวที่ยังไม่จบ
create unique index service_assignments_one_active_per_employee
  on public.service_assignments (employee_id) where status in ('ASSIGNED', 'ACCEPTED', 'IN_SERVICE');
create index service_assignments_employee_idx on public.service_assignments (employee_id, assigned_at desc);

-- -----------------------------------------------------------------------------
-- resource_allocations: ผูกกับรายการของ Order ได้ (Walk-in / หลังเช็กอิน)
-- -----------------------------------------------------------------------------
alter table public.resource_allocations
  add column service_order_item_id uuid references public.service_order_items (id) on delete restrict,
  add constraint resource_allocations_owner_chk check (booking_item_id is not null or service_order_item_id is not null);

create index resource_allocations_order_item_idx on public.resource_allocations (service_order_item_id);

-- (แทนที่ 018) ผูก service_order_item_id ได้ครั้งเดียว (ตอนเช็กอิน) นอกนั้นเหมือนเดิม
create or replace function private.tg_resource_allocations_capacity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.company_id <> old.company_id or new.branch_id <> old.branch_id
       or new.resource_type_id <> old.resource_type_id or new.booking_item_id is distinct from old.booking_item_id
       or (old.service_order_item_id is not null and new.service_order_item_id is distinct from old.service_order_item_id) then
      raise exception 'ห้ามเปลี่ยนเจ้าของ/ประเภทของการจัดสรร' using errcode = 'check_violation';
    end if;
    if old.status = 'RELEASED' then
      raise exception 'การจัดสรรที่คืนแล้วแก้ไขไม่ได้' using errcode = 'check_violation';
    end if;
    if new.status = 'RELEASED'
       or (new.starts_at = old.starts_at and new.ends_at = old.ends_at and new.quantity = old.quantity
           and private.allocation_is_active(old.status, old.expires_at)) then
      return new;
    end if;
  end if;

  if not private.allocation_is_active(new.status, new.expires_at) then
    return new;
  end if;

  if not private.has_capacity(
       new.branch_id,
       jsonb_build_array(jsonb_build_object(
         'resource_type_id', new.resource_type_id, 'quantity', new.quantity,
         'starts_at', new.starts_at, 'ends_at', new.ends_at)),
       true,
       array[new.id]
     ) then
    raise exception 'ทรัพยากรไม่พอในช่วงเวลานี้' using errcode = 'P0001', hint = 'CAPACITY_FULL';
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- (แก้ 018) get_available_slots: ช่องแรกต้องตรงตารางช่วงเวลา (เช่น :00/:30)
--   เดิมเริ่มนับจากเวลาเปิดร้าน ถ้าร้านเปิด 10:15 ทุกช่องจะถูก create_booking_core ปฏิเสธ
-- -----------------------------------------------------------------------------
create or replace function public.get_available_slots(p_branch_id uuid, p_date date, p_option_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  s          public.company_settings;
  v_company  uuid;
  w          record;
  v_slot     timestamptz;
  v_offset   integer;
  v_max_dur  integer;
  v_demands  jsonb;
  v_result   jsonb := '[]'::jsonb;
  v_opt      uuid;
begin
  select b.company_id into v_company from public.branches b where b.id = p_branch_id and b.is_active;
  if v_company is null or not private.is_company_active(v_company) then
    return v_result;
  end if;
  select * into s from public.company_settings where company_id = v_company;

  if p_option_ids is null or cardinality(p_option_ids) = 0 or cardinality(p_option_ids) > s.booking_max_items then
    raise exception 'จำนวนรายการไม่ถูกต้อง (1-%)', s.booking_max_items using errcode = 'invalid_parameter_value';
  end if;
  if exists (
    select 1 from unnest(p_option_ids) x(id)
     where not exists (
       select 1 from public.branch_service_options o
         join public.branch_services bs on bs.id = o.branch_service_id and bs.is_active
         join public.services sv on sv.id = bs.service_id and sv.is_active
        where o.id = x.id and o.is_active and bs.branch_id = p_branch_id
          and (private.option_price_at(o.id)).id is not null)
  ) then
    raise exception 'บริการที่เลือกไม่เปิดให้จองที่สาขานี้' using errcode = 'invalid_parameter_value';
  end if;

  select max(o.duration_minutes) into v_max_dur
    from public.branch_service_options o where o.id = any (p_option_ids);

  for w in select * from private.branch_open_window(p_branch_id, p_date) loop
    -- ปัดเวลาเปิดขึ้นไปที่ช่องถัดไปตามเวลาท้องถิ่น
    v_offset := (extract(hour from w.opens_at at time zone s.timezone) * 60
                 + extract(minute from w.opens_at at time zone s.timezone))::int % s.booking_slot_minutes;
    v_slot := date_trunc('minute', w.opens_at)
              + make_interval(mins => case when v_offset = 0 then 0 else s.booking_slot_minutes - v_offset end);
    while v_slot + make_interval(mins => v_max_dur) <= w.closes_at loop
      if v_slot >= now() + make_interval(mins => s.booking_min_lead_minutes)
         and v_slot <= now() + make_interval(days => s.booking_max_advance_days) then
        v_demands := '[]'::jsonb;
        foreach v_opt in array p_option_ids loop
          v_demands := v_demands || private.option_demands(v_opt, v_slot, s.booking_buffer_minutes);
        end loop;
        if private.has_capacity(p_branch_id, v_demands, false) then
          v_result := v_result || jsonb_build_object(
            'starts_at', v_slot,
            'time', to_char(v_slot at time zone s.timezone, 'HH24:MI'));
        end if;
      end if;
      v_slot := v_slot + make_interval(mins => s.booking_slot_minutes);
    end loop;
  end loop;

  return v_result;
end;
$$;

-- -----------------------------------------------------------------------------
-- stamp / audit / no delete
-- -----------------------------------------------------------------------------
create trigger pos_sessions_stamp before insert or update on public.pos_sessions
  for each row execute function private.tg_stamp();
create trigger service_orders_stamp before insert or update on public.service_orders
  for each row execute function private.tg_stamp();
create trigger service_order_items_stamp before insert or update on public.service_order_items
  for each row execute function private.tg_stamp();
create trigger queue_items_stamp before insert or update on public.queue_items
  for each row execute function private.tg_stamp();
create trigger service_assignments_stamp before insert or update on public.service_assignments
  for each row execute function private.tg_stamp();

create trigger pos_sessions_audit after insert or update or delete on public.pos_sessions
  for each row execute function private.tg_audit();
create trigger service_orders_audit after insert or update or delete on public.service_orders
  for each row execute function private.tg_audit('note');
create trigger service_order_items_audit after insert or update or delete on public.service_order_items
  for each row execute function private.tg_audit();
create trigger queue_items_audit after insert or update or delete on public.queue_items
  for each row execute function private.tg_audit();
create trigger service_assignments_audit after insert or update or delete on public.service_assignments
  for each row execute function private.tg_audit();

create trigger pos_sessions_no_delete before delete on public.pos_sessions
  for each row execute function private.tg_no_delete();
create trigger service_orders_no_delete before delete on public.service_orders
  for each row execute function private.tg_no_delete();
create trigger service_order_items_no_delete before delete on public.service_order_items
  for each row execute function private.tg_no_delete();
create trigger queue_items_no_delete before delete on public.queue_items
  for each row execute function private.tg_no_delete();
create trigger service_assignments_no_delete before delete on public.service_assignments
  for each row execute function private.tg_no_delete();

-- -----------------------------------------------------------------------------
-- Guards (State transition และข้อมูลที่ห้ามแก้)
-- -----------------------------------------------------------------------------
create or replace function private.tg_pos_sessions_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.company_id <> old.company_id or new.branch_id <> old.branch_id or new.business_date <> old.business_date
     or new.opened_at <> old.opened_at or new.opened_by <> old.opened_by or new.opening_cash <> old.opening_cash then
    raise exception 'ห้ามแก้ข้อมูลการเปิดกะ' using errcode = 'check_violation';
  end if;
  if old.status = 'CLOSED' and new.status <> 'CLOSED' then
    raise exception 'กะที่ปิดแล้วเปิดใหม่ไม่ได้' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger pos_sessions_guard before update on public.pos_sessions
  for each row execute function private.tg_pos_sessions_guard();

create or replace function private.tg_service_orders_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- customer_id เปลี่ยนได้ (รวมลูกค้า Phase 3) นอกนั้นห้าม
  if new.company_id <> old.company_id or new.branch_id <> old.branch_id
     or new.booking_id is distinct from old.booking_id or new.channel <> old.channel
     or new.business_date <> old.business_date then
    raise exception 'ห้ามแก้ข้อมูลหลักของ Order' using errcode = 'check_violation';
  end if;
  if new.status <> old.status and not (
       (old.status = 'OPEN' and new.status in ('COMPLETED', 'CANCELLED'))
    or (old.status = 'COMPLETED' and new.status = 'OPEN')
  ) then
    raise exception 'เปลี่ยนสถานะ Order จาก % เป็น % ไม่ได้', old.status, new.status using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger service_orders_guard before update on public.service_orders
  for each row execute function private.tg_service_orders_guard();

create or replace function private.tg_service_order_items_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.company_id, new.branch_id, new.service_order_id, new.booking_item_id, new.branch_service_option_id,
      new.service_id, new.service_name, new.service_name_en, new.duration_minutes, new.unit_price,
      new.therapist_fee, new.quantity, new.discount_amount, new.line_total)
     is distinct from
     (old.company_id, old.branch_id, old.service_order_id, old.booking_item_id, old.branch_service_option_id,
      old.service_id, old.service_name, old.service_name_en, old.duration_minutes, old.unit_price,
      old.therapist_fee, old.quantity, old.discount_amount, old.line_total) then
    raise exception 'ห้ามแก้ Snapshot ของรายการบริการ' using errcode = 'check_violation';
  end if;
  if old.status = 'CANCELLED' and new.status <> 'CANCELLED' then
    raise exception 'รายการที่ยกเลิกแล้วกลับมาใช้ไม่ได้' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger service_order_items_guard before update on public.service_order_items
  for each row execute function private.tg_service_order_items_guard();

-- สเปกข้อ 11: WAITING → CALLED → ACCEPTED → IN_SERVICE → COMPLETED และ CANCELLED
--   (CALLED/ACCEPTED → CALLED = เปลี่ยนหมอ)
create or replace function private.tg_queue_items_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.company_id <> old.company_id or new.branch_id <> old.branch_id
     or new.service_order_item_id <> old.service_order_item_id
     or new.queue_date <> old.queue_date or new.queue_number <> old.queue_number then
    raise exception 'ห้ามแก้เลขคิว/รายการของคิว' using errcode = 'check_violation';
  end if;
  if new.status <> old.status and not (
       (old.status = 'WAITING' and new.status in ('CALLED', 'CANCELLED'))
    or (old.status = 'CALLED' and new.status in ('ACCEPTED', 'CANCELLED'))
    or (old.status = 'ACCEPTED' and new.status in ('IN_SERVICE', 'CALLED', 'CANCELLED'))
    or (old.status = 'IN_SERVICE' and new.status = 'COMPLETED')
  ) then
    raise exception 'เปลี่ยนสถานะคิวจาก % เป็น % ไม่ได้', old.status, new.status using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger queue_items_guard before update on public.queue_items
  for each row execute function private.tg_queue_items_guard();

create or replace function private.tg_service_assignments_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.company_id <> old.company_id or new.branch_id <> old.branch_id
     or new.queue_item_id <> old.queue_item_id or new.employee_id <> old.employee_id then
    raise exception 'ห้ามเปลี่ยนหมอ/คิวของการมอบหมาย (ให้ยกเลิกแล้วมอบหมายใหม่)' using errcode = 'check_violation';
  end if;
  if new.status <> old.status and not (
       (old.status = 'ASSIGNED' and new.status in ('ACCEPTED', 'CANCELLED'))
    or (old.status = 'ACCEPTED' and new.status in ('IN_SERVICE', 'CANCELLED'))
    or (old.status = 'IN_SERVICE' and new.status = 'COMPLETED')
  ) then
    raise exception 'เปลี่ยนสถานะการมอบหมายจาก % เป็น % ไม่ได้', old.status, new.status using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger service_assignments_guard before update on public.service_assignments
  for each row execute function private.tg_service_assignments_guard();

-- -----------------------------------------------------------------------------
-- Helpers ภายใน
-- -----------------------------------------------------------------------------
-- สร้างคิวพร้อมเลขรายวันของสาขา (เลขรันใน Transaction เดียวกัน ไม่ข้าม/ไม่ซ้ำ)
create or replace function private.new_queue_item(
  p_company_id uuid,
  p_branch_id  uuid,
  p_item_id    uuid,
  p_queue_date date,
  p_starts_at  timestamptz,
  p_ends_at    timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tz  text;
  v_no  bigint;
  v_id  uuid;
begin
  select timezone into v_tz from public.company_settings where company_id = p_company_id;
  select seq_value into v_no
    from private.next_sequence_value(p_company_id, p_branch_id, 'QUE', (p_queue_date + time '12:00') at time zone v_tz);
  if v_no > 9999 then
    raise exception 'เลขคิววันนี้เต็มแล้ว' using errcode = 'numeric_value_out_of_range';
  end if;

  insert into public.queue_items (company_id, branch_id, service_order_item_id, queue_date, queue_number,
                                  planned_starts_at, planned_ends_at)
  values (p_company_id, p_branch_id, p_item_id, p_queue_date, v_no, p_starts_at, p_ends_at)
  returning id into v_id;
  return v_id;
end;
$$;

-- เพิ่มรายการใหม่ใน Order (Walk-in/เพิ่มบริการ) ด้วยราคาปัจจุบัน + จองทรัพยากร RESERVED + คิว
--   ผู้เรียกต้องตรวจเวลา/สิทธิ์ และล็อก capacity (has_capacity p_lock) ก่อนแล้ว
create or replace function private.add_order_item(p_order_id uuid, p_option_id uuid, p_starts_at timestamptz)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  o         public.service_orders;
  v_buffer  integer;
  x         record;
  p         public.service_price_histories;
  v_item    uuid;
  sr        record;
begin
  select * into o from public.service_orders where id = p_order_id;
  select booking_buffer_minutes into v_buffer from public.company_settings where company_id = o.company_id;

  select op.duration_minutes, bs.service_id, sv.name, sv.name_en
    into x
    from public.branch_service_options op
    join public.branch_services bs on bs.id = op.branch_service_id
    join public.services sv on sv.id = bs.service_id
   where op.id = p_option_id;
  p := private.option_price_at(p_option_id);

  insert into public.service_order_items (
    company_id, branch_id, service_order_id, branch_service_option_id, service_id, service_name, service_name_en,
    duration_minutes, unit_price, therapist_fee, discount_amount, line_total
  ) values (
    o.company_id, o.branch_id, o.id, p_option_id, x.service_id, x.name, x.name_en,
    x.duration_minutes, p.price, p.therapist_fee, 0, p.price
  )
  returning id into v_item;

  for sr in select resource_type_id, quantity from public.service_resources where service_id = x.service_id loop
    insert into public.resource_allocations (
      company_id, branch_id, resource_type_id, service_order_item_id, quantity, starts_at, ends_at, status
    ) values (
      o.company_id, o.branch_id, sr.resource_type_id, v_item, sr.quantity, p_starts_at,
      p_starts_at + make_interval(mins => x.duration_minutes + v_buffer), 'RESERVED'
    );
  end loop;

  perform private.new_queue_item(o.company_id, o.branch_id, v_item, o.business_date, p_starts_at,
                                 p_starts_at + make_interval(mins => x.duration_minutes));
  return v_item;
end;
$$;

-- ตรวจเวลาเริ่มของ Walk-in/เพิ่มบริการ: ต้องอยู่ในวันทำการปัจจุบัน และทำเสร็จก่อนร้านปิด
--   แล้วล็อกทรัพยากรและตรวจ capacity ของทุกรายการพร้อมกัน
create or replace function private.reserve_walkin(p_branch_id uuid, p_starts_at timestamptz, p_option_ids uuid[])
returns date
language plpgsql
security definer
set search_path = ''
as $$
declare
  w         record;
  v_buffer  integer;
  v_max_dur integer;
  v_demands jsonb := '[]'::jsonb;
  v_opt     uuid;
begin
  perform private.assert_branch_options(p_branch_id, p_option_ids);
  select * into w from private.branch_window_at(p_branch_id, now());
  if w.opens_at is null then
    raise exception 'วันนี้สาขาปิดทำการ' using errcode = 'invalid_parameter_value';
  end if;
  if p_starts_at is null or p_starts_at < now() - interval '15 minutes' then
    raise exception 'เวลาเริ่มผ่านมาแล้ว กรุณาเลือกเวลาใหม่' using errcode = 'invalid_parameter_value';
  end if;
  select max(duration_minutes) into v_max_dur from public.branch_service_options where id = any (p_option_ids);
  if p_starts_at < w.opens_at or p_starts_at + make_interval(mins => v_max_dur) > w.closes_at then
    raise exception 'เวลาที่เลือกอยู่นอกเวลาทำการวันนี้ (วันอื่นให้สร้างเป็นการจอง)' using errcode = 'invalid_parameter_value';
  end if;

  select s.booking_buffer_minutes into v_buffer
    from public.branches b join public.company_settings s on s.company_id = b.company_id where b.id = p_branch_id;
  foreach v_opt in array p_option_ids loop
    v_demands := v_demands || private.option_demands(v_opt, p_starts_at, v_buffer);
  end loop;
  if not private.has_capacity(p_branch_id, v_demands, true) then
    raise exception 'เวลานี้เตียง/อุปกรณ์ไม่ว่างพอ กรุณาเลือกเวลาอื่น' using errcode = 'P0001', hint = 'CAPACITY_FULL';
  end if;
  return w.business_date;
end;
$$;

-- อัปเดตสถานะ Order ตามคิว: ไม่มีคิวค้าง → COMPLETED (หรือ CANCELLED ถ้ายกเลิกทั้งหมด)
--   และการจองที่เช็กอินแล้ว → COMPLETED
create or replace function private.refresh_order_status(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  o        public.service_orders;
  v_open   integer;
  v_done   integer;
begin
  select * into o from public.service_orders where id = p_order_id for update;
  select count(*) filter (where q.status not in ('COMPLETED', 'CANCELLED')),
         count(*) filter (where q.status = 'COMPLETED')
    into v_open, v_done
    from public.service_order_items i
    join public.queue_items q on q.service_order_item_id = i.id
   where i.service_order_id = o.id;

  if v_open > 0 then
    if o.status = 'COMPLETED' then
      update public.service_orders set status = 'OPEN' where id = o.id;
    end if;
  elsif v_done > 0 then
    if o.status = 'OPEN' then
      update public.service_orders set status = 'COMPLETED', completed_at = now() where id = o.id;
    end if;
    if o.booking_id is not null then
      update public.bookings set status = 'COMPLETED' where id = o.booking_id and status = 'CHECKED_IN';
    end if;
  elsif o.status = 'OPEN' then
    update public.service_orders
       set status = 'CANCELLED', cancelled_at = now(), cancelled_by = auth.uid(),
           cancel_reason = coalesce(cancel_reason, 'ยกเลิกทุกรายการ')
     where id = o.id;
  end if;
end;
$$;

-- หมอพร้อมรับคิว: STAFF ACTIVE ของสาขา, ไม่มีคิวค้าง, มีกะ ณ ตอนนี้ (ถ้าไม่มีต้องยืนยัน)
create or replace function private.assert_therapist_available(
  p_company_id         uuid,
  p_branch_id          uuid,
  p_employee_id        uuid,
  p_confirm_off_shift  boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  e          public.employees;
  v_on_shift boolean;
begin
  -- ล็อกแถวพนักงาน กันมอบหมายหมอคนเดียวกันพร้อมกันสองคิว
  select * into e from public.employees where id = p_employee_id and company_id = p_company_id for update;
  if e.id is null or e.status <> 'ACTIVE' or not private.is_active_staff_of_branch(e.user_id, p_branch_id) then
    raise exception 'พนักงานคนนี้ไม่ได้ประจำสาขานี้ หรือไม่ได้อยู่ในสถานะใช้งาน' using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.service_assignments
              where employee_id = e.id and status in ('ASSIGNED', 'ACCEPTED', 'IN_SERVICE')) then
    raise exception '% มีคิวที่รับไว้หรือกำลังให้บริการอยู่', e.nickname using errcode = 'check_violation';
  end if;

  v_on_shift := exists (
    select 1 from public.employee_schedules s
     where s.employee_id = e.id and s.branch_id = p_branch_id and s.status = 'SCHEDULED'
       and s.starts_at <= now() and s.ends_at > now());
  if not v_on_shift and not coalesce(p_confirm_off_shift, false) then
    raise exception '% ไม่มีกะในเวลานี้ ยืนยันเพื่อมอบหมายต่อ', e.nickname using errcode = 'P0001', hint = 'OFF_SHIFT';
  end if;
  return v_on_shift;
end;
$$;

-- มุมมอง Order สำหรับพนักงาน (ไม่มีค่ามือ)
create or replace function private.pos_order_view(p_order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'order_id', o.id,
    'channel', o.channel,
    'status', o.status,
    'business_date', o.business_date,
    'booking_id', o.booking_id,
    'booking_code', b.booking_code,
    'customer_id', o.customer_id,
    'customer_name', case when c.id is null then null else trim(c.first_name || ' ' || c.last_name) end,
    'phone_masked', private.mask_phone(c.phone),
    'note', o.note,
    'cancel_reason', o.cancel_reason,
    'created_at', o.created_at,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'item_id', i.id,
        'service_name', i.service_name,
        'duration_minutes', i.duration_minutes,
        'unit_price', i.unit_price,
        'item_status', i.status,
        'queue_id', q.id,
        'queue_number', q.queue_number,
        'queue_status', q.status,
        'planned_starts_at', q.planned_starts_at,
        'planned_ends_at', q.planned_ends_at,
        'called_at', q.called_at,
        'started_at', q.started_at,
        'completed_at', q.completed_at,
        'cancel_reason', coalesce(q.cancel_reason, i.cancel_reason),
        'therapist', (
          select jsonb_build_object('employee_id', e.id, 'nickname', e.nickname, 'user_id', e.user_id,
                                    'assignment_status', a.status, 'off_shift_confirmed', a.off_shift_confirmed)
            from public.service_assignments a join public.employees e on e.id = a.employee_id
           where a.queue_item_id = q.id and a.status <> 'CANCELLED')
      ) order by q.queue_number)
        from public.service_order_items i
        join public.queue_items q on q.service_order_item_id = i.id
       where i.service_order_id = o.id), '[]'::jsonb)
  )
  from public.service_orders o
  left join public.customers c on c.id = o.customer_id
  left join public.bookings b on b.id = o.booking_id
  where o.id = p_order_id;
$$;

revoke all on function private.new_queue_item(uuid, uuid, uuid, date, timestamptz, timestamptz) from public;
revoke all on function private.add_order_item(uuid, uuid, timestamptz) from public;
revoke all on function private.reserve_walkin(uuid, timestamptz, uuid[]) from public;
revoke all on function private.refresh_order_status(uuid) from public;
revoke all on function private.assert_therapist_available(uuid, uuid, uuid, boolean) from public;
revoke all on function private.pos_order_view(uuid) from public;

-- -----------------------------------------------------------------------------
-- กะ POS
-- -----------------------------------------------------------------------------
create or replace function public.pos_open_session(p_branch_id uuid, p_opening_cash numeric, p_note text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid;
  v_date    date;
  v_id      uuid;
begin
  perform private.require_branch_access(p_branch_id);
  select company_id into v_company from public.branches where id = p_branch_id and is_active;
  if v_company is null then
    raise exception 'สาขาไม่เปิดใช้งาน' using errcode = 'invalid_parameter_value';
  end if;
  if p_opening_cash is null or p_opening_cash < 0 then
    raise exception 'กรุณาระบุเงินสดเริ่มต้น' using errcode = 'invalid_parameter_value';
  end if;
  -- ล็อกสาขาก่อนตรวจ กันสองเครื่องเปิดกะพร้อมกัน (มี unique index เป็นชั้นสุดท้าย)
  perform 1 from public.branches where id = p_branch_id for update;
  if exists (select 1 from public.pos_sessions where branch_id = p_branch_id and status = 'OPEN') then
    raise exception 'สาขานี้มีกะที่เปิดอยู่แล้ว' using errcode = 'check_violation';
  end if;
  select business_date into v_date from private.branch_window_at(p_branch_id, now());

  insert into public.pos_sessions (company_id, branch_id, business_date, opened_by, opening_cash, opening_note)
  values (v_company, p_branch_id, v_date, auth.uid(), round(p_opening_cash, 2),
          nullif(left(trim(coalesce(p_note, '')), 300), ''))
  returning id into v_id;
  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- เวลาเริ่มที่ว่างของวันนี้ (ทุก 5 นาที) — ตัวแรก = เวลาที่ระบบเสนอ
-- -----------------------------------------------------------------------------
create or replace function public.pos_available_starts(p_branch_id uuid, p_option_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  w          record;
  v_tz       text;
  v_buffer   integer;
  v_max_dur  integer;
  v_t        timestamptz;
  v_demands  jsonb;
  v_opt      uuid;
  v_result   jsonb := '[]'::jsonb;
begin
  perform private.require_branch_access(p_branch_id);
  perform private.assert_branch_options(p_branch_id, p_option_ids);
  select * into w from private.branch_window_at(p_branch_id, now());
  if w.opens_at is null then
    return v_result;
  end if;
  select s.timezone, s.booking_buffer_minutes into v_tz, v_buffer
    from public.branches b join public.company_settings s on s.company_id = b.company_id where b.id = p_branch_id;
  select max(duration_minutes) into v_max_dur from public.branch_service_options where id = any (p_option_ids);

  v_t := greatest(w.opens_at, to_timestamp(ceil(extract(epoch from now()) / 300) * 300));
  while v_t + make_interval(mins => v_max_dur) <= w.closes_at and jsonb_array_length(v_result) < 60 loop
    v_demands := '[]'::jsonb;
    foreach v_opt in array p_option_ids loop
      v_demands := v_demands || private.option_demands(v_opt, v_t, v_buffer);
    end loop;
    if private.has_capacity(p_branch_id, v_demands, false) then
      v_result := v_result || jsonb_build_object('starts_at', v_t, 'time', to_char(v_t at time zone v_tz, 'HH24:MI'));
    end if;
    v_t := v_t + interval '5 minutes';
  end loop;
  return v_result;
end;
$$;

-- -----------------------------------------------------------------------------
-- Walk-in: สร้าง Order + รายการ + จองทรัพยากร + คิว (Transaction เดียว, Idempotent)
--   p_customer_id = NULL ได้ (ลูกค้าทั่วไป)
-- -----------------------------------------------------------------------------
create or replace function public.pos_create_walkin(
  p_branch_id        uuid,
  p_customer_id      uuid,
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
  v_company uuid;
  v_date    date;
  v_prev    jsonb;
  v_order   uuid;
  v_opt     uuid;
  v_result  jsonb;
  v_hash    text := private.request_hash(jsonb_build_object(
                      'b', p_branch_id, 'c', p_customer_id, 's', p_starts_at, 'o', p_option_ids, 'n', p_note));
begin
  perform private.require_branch_access(p_branch_id);
  select company_id into v_company from public.branches where id = p_branch_id and is_active;
  if p_customer_id is not null and not exists (
    select 1 from public.customers where id = p_customer_id and company_id = v_company and status = 'ACTIVE'
  ) then
    raise exception 'ไม่พบข้อมูลลูกค้า' using errcode = 'invalid_parameter_value';
  end if;

  v_prev := private.idempotency_begin('pos_create_walkin', p_idempotency_key, v_hash);
  if v_prev is not null then
    return v_prev -> 'body';
  end if;

  perform private.expire_stale_bookings();
  v_date := private.reserve_walkin(p_branch_id, p_starts_at, p_option_ids);

  insert into public.service_orders (company_id, branch_id, customer_id, channel, business_date, note)
  values (v_company, p_branch_id, p_customer_id, 'WALK_IN', v_date, nullif(left(trim(coalesce(p_note, '')), 500), ''))
  returning id into v_order;

  foreach v_opt in array p_option_ids loop
    perform private.add_order_item(v_order, v_opt, p_starts_at);
  end loop;

  v_result := private.pos_order_view(v_order);
  perform private.idempotency_complete('pos_create_walkin', p_idempotency_key, 200, v_result);
  return v_result;
end;
$$;

-- เพิ่มบริการใน Order เดิม (เช่น ต่อเวลา/เพิ่มคน) — ได้จนกว่าจะออก Invoice (Phase 7)
create or replace function public.pos_add_order_items(
  p_order_id         uuid,
  p_starts_at        timestamptz,
  p_option_ids       uuid[],
  p_idempotency_key  text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  o         public.service_orders;
  v_date    date;
  v_prev    jsonb;
  v_opt     uuid;
  v_result  jsonb;
  v_hash    text := private.request_hash(jsonb_build_object('o', p_order_id, 's', p_starts_at, 'i', p_option_ids));
begin
  select * into o from public.service_orders where id = p_order_id for update;
  if o.id is null then
    raise exception 'ไม่พบ Order' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(o.branch_id);
  if o.status not in ('OPEN', 'COMPLETED') then
    raise exception 'Order นี้ถูกยกเลิกแล้ว' using errcode = 'check_violation';
  end if;

  v_prev := private.idempotency_begin('pos_add_order_items', p_idempotency_key, v_hash);
  if v_prev is not null then
    return v_prev -> 'body';
  end if;

  perform private.expire_stale_bookings();
  v_date := private.reserve_walkin(o.branch_id, p_starts_at, p_option_ids);
  if v_date <> o.business_date then
    raise exception 'เพิ่มบริการได้เฉพาะ Order ของวันทำการนี้' using errcode = 'check_violation';
  end if;

  foreach v_opt in array p_option_ids loop
    perform private.add_order_item(o.id, v_opt, p_starts_at);
  end loop;
  perform private.refresh_order_status(o.id);

  v_result := private.pos_order_view(o.id);
  perform private.idempotency_complete('pos_add_order_items', p_idempotency_key, 200, v_result);
  return v_result;
end;
$$;

-- -----------------------------------------------------------------------------
-- เช็กอินการจอง: สร้าง Order/รายการ (Snapshot จากการจอง)/คิว, Allocation เดิม → IN_USE
-- -----------------------------------------------------------------------------
create or replace function public.pos_check_in_booking(p_booking_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  b        public.bookings;
  v_date   date;
  v_order  uuid;
  v_item   uuid;
  bi       record;
begin
  select * into b from public.bookings where id = p_booking_id for update;
  if b.id is null then
    raise exception 'ไม่พบการจอง' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(b.branch_id);
  if b.status = 'CHECKED_IN' then
    raise exception 'การจองนี้เช็กอินแล้ว' using errcode = 'check_violation';
  end if;
  if b.status <> 'CONFIRMED' then
    raise exception 'เช็กอินได้เฉพาะการจองที่ยืนยันแล้ว' using errcode = 'check_violation';
  end if;
  select business_date into v_date from private.branch_window_at(b.branch_id, b.starts_at);
  if v_date <> (select business_date from private.branch_window_at(b.branch_id, now())) then
    raise exception 'เช็กอินได้เฉพาะการจองของวันนี้' using errcode = 'check_violation';
  end if;

  insert into public.service_orders (company_id, branch_id, customer_id, booking_id, channel, business_date)
  values (b.company_id, b.branch_id, b.customer_id, b.id, b.channel, v_date)
  returning id into v_order;

  for bi in select * from public.booking_items where booking_id = b.id order by created_at, id loop
    insert into public.service_order_items (
      company_id, branch_id, service_order_id, booking_item_id, branch_service_option_id, service_id,
      service_name, service_name_en, duration_minutes, unit_price, therapist_fee, quantity, discount_amount, line_total
    ) values (
      b.company_id, b.branch_id, v_order, bi.id, bi.branch_service_option_id, bi.service_id,
      bi.service_name, bi.service_name_en, bi.duration_minutes, bi.unit_price, bi.therapist_fee, bi.quantity,
      bi.discount_amount, bi.line_total
    )
    returning id into v_item;

    update public.resource_allocations
       set status = 'IN_USE', expires_at = null, service_order_item_id = v_item
     where booking_item_id = bi.id and status <> 'RELEASED';

    perform private.new_queue_item(b.company_id, b.branch_id, v_item, v_date, bi.starts_at, bi.ends_at);
  end loop;

  update public.bookings set status = 'CHECKED_IN' where id = b.id;
  return private.pos_order_view(v_order);
end;
$$;

-- -----------------------------------------------------------------------------
-- คิว
-- -----------------------------------------------------------------------------
-- หน้าร้านเรียกคิวและเลือกหมอ (หรือเปลี่ยนหมอก่อนเริ่มบริการ ต้องมีเหตุผล)
create or replace function public.queue_call(
  p_queue_id           uuid,
  p_employee_id        uuid,
  p_confirm_off_shift  boolean default false,
  p_reason             text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  q          public.queue_items;
  a          public.service_assignments;
  v_on_shift boolean;
  v_order    uuid;
begin
  select * into q from public.queue_items where id = p_queue_id for update;
  if q.id is null then
    raise exception 'ไม่พบคิว' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(q.branch_id);
  if q.status not in ('WAITING', 'CALLED', 'ACCEPTED') then
    raise exception 'คิวนี้เริ่มบริการหรือปิดไปแล้ว' using errcode = 'check_violation';
  end if;

  select * into a from public.service_assignments
   where queue_item_id = q.id and status in ('ASSIGNED', 'ACCEPTED') for update;
  if a.id is not null then
    if a.employee_id = p_employee_id then
      raise exception 'หมอคนนี้ได้รับคิวนี้อยู่แล้ว' using errcode = 'check_violation';
    end if;
    if p_reason is null or char_length(trim(p_reason)) < 3 then
      raise exception 'กรุณาระบุเหตุผลที่เปลี่ยนหมอ' using errcode = 'invalid_parameter_value';
    end if;
    update public.service_assignments
       set status = 'CANCELLED', cancelled_at = now(), cancelled_by = auth.uid(), cancel_reason = left(trim(p_reason), 500)
     where id = a.id;
  end if;

  v_on_shift := private.assert_therapist_available(q.company_id, q.branch_id, p_employee_id, p_confirm_off_shift);

  insert into public.service_assignments (company_id, branch_id, queue_item_id, employee_id, off_shift_confirmed, assigned_by)
  values (q.company_id, q.branch_id, q.id, p_employee_id, not v_on_shift, auth.uid());

  update public.queue_items
     set status = 'CALLED', called_at = now(), called_by = auth.uid(), accepted_at = null, accepted_by = null
   where id = q.id;

  select i.service_order_id into v_order from public.service_order_items i where i.id = q.service_order_item_id;
  return private.pos_order_view(v_order);
end;
$$;

-- หมอรับคิว (หรือหน้าร้านกดแทน)
create or replace function public.queue_accept(p_queue_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  q       public.queue_items;
  v_order uuid;
begin
  select * into q from public.queue_items where id = p_queue_id for update;
  if q.id is null then
    raise exception 'ไม่พบคิว' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(q.branch_id);
  if q.status <> 'CALLED' then
    raise exception 'รับได้เฉพาะคิวที่ถูกเรียกแล้ว' using errcode = 'check_violation';
  end if;

  update public.service_assignments
     set status = 'ACCEPTED', accepted_at = now(), accepted_by = auth.uid()
   where queue_item_id = q.id and status = 'ASSIGNED';
  update public.queue_items set status = 'ACCEPTED', accepted_at = now(), accepted_by = auth.uid() where id = q.id;

  select i.service_order_id into v_order from public.service_order_items i where i.id = q.service_order_item_id;
  return private.pos_order_view(v_order);
end;
$$;

-- เริ่มบริการ: เลื่อนช่วงจองทรัพยากรไปเริ่มตามเวลาจริง (ตรวจ capacity ใหม่) → IN_USE
create or replace function public.queue_start(p_queue_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  q        public.queue_items;
  i        public.service_order_items;
  v_buffer integer;
  v_hint   text;
begin
  select * into q from public.queue_items where id = p_queue_id for update;
  if q.id is null then
    raise exception 'ไม่พบคิว' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(q.branch_id);
  if q.status <> 'ACCEPTED' then
    raise exception 'เริ่มบริการได้เฉพาะคิวที่หมอรับแล้ว' using errcode = 'check_violation';
  end if;
  select * into i from public.service_order_items where id = q.service_order_item_id;
  select booking_buffer_minutes into v_buffer from public.company_settings where company_id = q.company_id;

  begin
    update public.resource_allocations
       set status = 'IN_USE', expires_at = null,
           starts_at = now(), ends_at = now() + make_interval(mins => i.duration_minutes + v_buffer)
     where service_order_item_id = i.id and status <> 'RELEASED';
  exception when sqlstate 'P0001' then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint = 'CAPACITY_FULL' then
      raise exception 'เตียง/อุปกรณ์ไม่ว่างพอที่จะเริ่มตอนนี้ (ช่วงถัดไปมีคิวจองไว้) กรุณารอหรือเปลี่ยนบริการ'
        using errcode = 'P0001', hint = 'CAPACITY_FULL';
    end if;
    raise;
  end;

  update public.service_assignments set status = 'IN_SERVICE', started_at = now()
   where queue_item_id = q.id and status = 'ACCEPTED';
  update public.queue_items set status = 'IN_SERVICE', started_at = now(), started_by = auth.uid() where id = q.id;
  return private.pos_order_view(i.service_order_id);
end;
$$;

-- จบบริการ: คืนทรัพยากรทันที, ปิดการมอบหมาย, อัปเดต Order/การจอง
create or replace function public.queue_complete(p_queue_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  q       public.queue_items;
  v_order uuid;
begin
  select * into q from public.queue_items where id = p_queue_id for update;
  if q.id is null then
    raise exception 'ไม่พบคิว' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(q.branch_id);
  if q.status <> 'IN_SERVICE' then
    raise exception 'จบบริการได้เฉพาะคิวที่กำลังให้บริการ' using errcode = 'check_violation';
  end if;

  update public.resource_allocations
     set status = 'RELEASED', released_at = now(), release_reason = 'จบบริการ', expires_at = null
   where service_order_item_id = q.service_order_item_id and status <> 'RELEASED';
  update public.service_assignments set status = 'COMPLETED', completed_at = now()
   where queue_item_id = q.id and status = 'IN_SERVICE';
  update public.queue_items set status = 'COMPLETED', completed_at = now(), completed_by = auth.uid() where id = q.id;

  select i.service_order_id into v_order from public.service_order_items i where i.id = q.service_order_item_id;
  perform private.refresh_order_status(v_order);
  return private.pos_order_view(v_order);
end;
$$;

-- ยกเลิกรายการ/คิว (ก่อนเริ่มบริการเท่านั้น ต้องมีเหตุผล)
--   Order จากการจอง: ต้องเหลืออย่างน้อย 1 รายการ (การจองที่เช็กอินแล้วยกเลิกไม่ได้ตามสเปกข้อ 9)
create or replace function public.queue_cancel(p_queue_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  q  public.queue_items;
  i  public.service_order_items;
  o  public.service_orders;
begin
  -- ลำดับล็อกเดียวกับ Function คิวอื่น: คิว → Order (กัน deadlock)
  select * into q from public.queue_items where id = p_queue_id for update;
  if q.id is null then
    raise exception 'ไม่พบคิว' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(q.branch_id);
  select * into i from public.service_order_items where id = q.service_order_item_id;
  select * into o from public.service_orders where id = i.service_order_id for update;

  if q.status not in ('WAITING', 'CALLED', 'ACCEPTED') then
    raise exception 'ยกเลิกได้เฉพาะคิวที่ยังไม่เริ่มบริการ' using errcode = 'check_violation';
  end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาระบุเหตุผล' using errcode = 'invalid_parameter_value';
  end if;
  if o.booking_id is not null and not exists (
    select 1 from public.service_order_items x join public.queue_items y on y.service_order_item_id = x.id
     where x.service_order_id = o.id and x.id <> i.id and y.status <> 'CANCELLED'
  ) then
    raise exception 'ยกเลิกรายการสุดท้ายของการจองที่เช็กอินแล้วไม่ได้ (เปลี่ยนบริการโดยเพิ่มรายการใหม่ก่อน)'
      using errcode = 'check_violation';
  end if;

  perform set_config('app.audit_reason', trim(p_reason), true);
  update public.resource_allocations
     set status = 'RELEASED', released_at = now(), release_reason = 'ยกเลิกรายการ', expires_at = null
   where service_order_item_id = i.id and status <> 'RELEASED';
  update public.service_assignments
     set status = 'CANCELLED', cancelled_at = now(), cancelled_by = auth.uid(), cancel_reason = left(trim(p_reason), 500)
   where queue_item_id = q.id and status in ('ASSIGNED', 'ACCEPTED');
  update public.queue_items
     set status = 'CANCELLED', cancelled_at = now(), cancelled_by = auth.uid(), cancel_reason = left(trim(p_reason), 500)
   where id = q.id;
  update public.service_order_items
     set status = 'CANCELLED', cancelled_at = now(), cancelled_by = auth.uid(), cancel_reason = left(trim(p_reason), 500)
   where id = i.id;

  if not exists (
    select 1 from public.service_order_items x join public.queue_items y on y.service_order_item_id = x.id
     where x.service_order_id = o.id and y.status <> 'CANCELLED'
  ) then
    update public.service_orders set cancel_reason = left(trim(p_reason), 500) where id = o.id;
  end if;
  perform private.refresh_order_status(o.id);
  return private.pos_order_view(o.id);
end;
$$;

-- -----------------------------------------------------------------------------
-- กระดานคิวของสาขา (วันทำการ) + กะที่เปิดอยู่ + สถานะหมอ
-- -----------------------------------------------------------------------------
create or replace function public.pos_board(p_branch_id uuid, p_date date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_today date;
  v_date  date;
begin
  perform private.require_branch_access(p_branch_id);
  select business_date into v_today from private.branch_window_at(p_branch_id, now());
  v_date := coalesce(p_date, v_today);

  return jsonb_build_object(
    'business_date', v_date,
    'is_today', v_date = v_today,
    'session', (
      select jsonb_build_object('session_id', s.id, 'opened_at', s.opened_at, 'opening_cash', s.opening_cash,
                                'opened_by_name', p.display_name, 'business_date', s.business_date)
        from public.pos_sessions s left join public.profiles p on p.id = s.opened_by
       where s.branch_id = p_branch_id and s.status = 'OPEN'),
    'orders', coalesce((
      select jsonb_agg(private.pos_order_view(o.id) order by o.created_at)
        from public.service_orders o
       where o.branch_id = p_branch_id and o.business_date = v_date), '[]'::jsonb),
    'therapists', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employee_id', e.id, 'nickname', e.nickname, 'user_id', e.user_id, 'photo_path', e.photo_path,
        'on_shift', exists (
          select 1 from public.employee_schedules s
           where s.employee_id = e.id and s.branch_id = p_branch_id and s.status = 'SCHEDULED'
             and s.starts_at <= now() and s.ends_at > now()),
        'busy_queue_number', (
          select q.queue_number from public.service_assignments a join public.queue_items q on q.id = a.queue_item_id
           where a.employee_id = e.id and a.status in ('ASSIGNED', 'ACCEPTED', 'IN_SERVICE')),
        'busy_status', (
          select a.status from public.service_assignments a
           where a.employee_id = e.id and a.status in ('ASSIGNED', 'ACCEPTED', 'IN_SERVICE'))
      ) order by e.nickname)
        from public.employees e
        join public.branches br on br.id = p_branch_id and br.company_id = e.company_id
       where e.status = 'ACTIVE' and private.is_active_staff_of_branch(e.user_id, p_branch_id)), '[]'::jsonb)
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- (แทนที่ 019) รวมลูกค้า/ลบข้อมูล ต้องครอบคลุม service_orders ด้วย
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
    update public.service_orders set customer_id = new.merged_into_id where customer_id = new.id;
  end if;
  if new.status = 'ANONYMIZED' and old.status <> 'ANONYMIZED' then
    update public.bookings set customer_note = null where customer_id = new.id;
    update public.booking_tracking_tokens t set revoked_at = now()
      from public.bookings b where b.id = t.booking_id and b.customer_id = new.id and t.revoked_at is null;
    update public.service_orders set note = null where customer_id = new.id and note is not null;
  end if;
  return null;
end;
$$;

-- -----------------------------------------------------------------------------
-- Realtime (แสดงผลเท่านั้น) — Supabase ส่งเฉพาะแถวที่ผ่าน RLS ของผู้ subscribe
-- -----------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.queue_items, public.service_orders, public.pos_sessions;
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
    'public.pos_open_session(uuid, numeric, text)',
    'public.pos_available_starts(uuid, uuid[])',
    'public.pos_create_walkin(uuid, uuid, timestamptz, uuid[], text, text)',
    'public.pos_add_order_items(uuid, timestamptz, uuid[], text)',
    'public.pos_check_in_booking(uuid)',
    'public.queue_call(uuid, uuid, boolean, text)',
    'public.queue_accept(uuid)',
    'public.queue_start(uuid)',
    'public.queue_complete(uuid)',
    'public.queue_cancel(uuid, text)',
    'public.pos_board(uuid, date)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;

alter table public.pos_sessions enable row level security;
alter table public.service_orders enable row level security;
alter table public.service_order_items enable row level security;
alter table public.queue_items enable row level security;
alter table public.service_assignments enable row level security;

revoke all on public.pos_sessions, public.service_orders, public.service_order_items,
              public.queue_items, public.service_assignments from anon, authenticated;
grant all on public.pos_sessions, public.service_orders, public.service_order_items,
             public.queue_items, public.service_assignments to service_role;

grant select on public.pos_sessions, public.service_orders, public.queue_items, public.service_assignments
  to authenticated;
-- ค่ามือ (therapist_fee) ไม่ grant ให้ Client
grant select (id, company_id, branch_id, service_order_id, booking_item_id, branch_service_option_id, service_id,
              service_name, service_name_en, duration_minutes, unit_price, quantity, discount_amount, line_total,
              status, cancelled_at, cancelled_by, cancel_reason, created_at, created_by, updated_at)
  on public.service_order_items to authenticated;

create policy pos_sessions_select_branch on public.pos_sessions
  for select to authenticated using (private.has_branch_access(branch_id));
create policy service_orders_select_branch on public.service_orders
  for select to authenticated using (private.has_branch_access(branch_id));
create policy service_order_items_select_branch on public.service_order_items
  for select to authenticated using (private.has_branch_access(branch_id));
create policy queue_items_select_branch on public.queue_items
  for select to authenticated using (private.has_branch_access(branch_id));
create policy service_assignments_select_branch on public.service_assignments
  for select to authenticated using (private.has_branch_access(branch_id));
