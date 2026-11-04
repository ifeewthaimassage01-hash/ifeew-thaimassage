-- =============================================================================
-- Phase 4 / 018 — ค่าตั้งค่าการจอง, ทรัพยากร, บัญชีรับเงินสาขา, การจัดสรร และ Capacity
-- =============================================================================

-- -----------------------------------------------------------------------------
-- company_settings: ค่าการจอง/มัดจำ
-- -----------------------------------------------------------------------------
alter table public.company_settings
  add column booking_slot_minutes        integer not null default 30 check (booking_slot_minutes in (10, 15, 20, 30, 60)),
  add column booking_buffer_minutes      integer not null default 10 check (booking_buffer_minutes between 0 and 60),
  add column booking_hold_minutes        integer not null default 15 check (booking_hold_minutes between 5 and 60),
  add column booking_max_advance_days    integer not null default 30 check (booking_max_advance_days between 1 and 180),
  add column booking_min_lead_minutes    integer not null default 60 check (booking_min_lead_minutes between 0 and 1440),
  add column booking_max_items           integer not null default 4 check (booking_max_items between 1 and 10),
  add column deposit_per_person          numeric(12,2) not null default 100.00 check (deposit_per_person >= 0),
  add column guest_max_active_bookings   integer not null default 3 check (guest_max_active_bookings between 1 and 20),
  add column tracking_token_days_after   integer not null default 7 check (tracking_token_days_after between 1 and 90),
  add column no_show_grace_minutes       integer not null default 15 check (no_show_grace_minutes between 0 and 240);

grant update (
  booking_slot_minutes, booking_buffer_minutes, booking_hold_minutes, booking_max_advance_days,
  booking_min_lead_minutes, booking_max_items, deposit_per_person, guest_max_active_bookings,
  tracking_token_days_after, no_show_grace_minutes
) on public.company_settings to authenticated;

-- -----------------------------------------------------------------------------
-- resource_types (ระดับบริษัท)
-- -----------------------------------------------------------------------------
create table public.resource_types (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies (id) on delete restrict,
  name        text not null check (char_length(trim(name)) between 1 and 100),
  description text check (description is null or char_length(description) <= 500),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  created_by  uuid references public.profiles (id),
  updated_at  timestamptz not null default now(),
  constraint resource_types_company_id_id_key unique (company_id, id)
);

create unique index resource_types_company_name_key
  on public.resource_types (company_id, lower(trim(name))) where is_active;

-- -----------------------------------------------------------------------------
-- branch_resources (จำนวนต่อสาขา)
-- -----------------------------------------------------------------------------
create table public.branch_resources (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null,
  branch_id         uuid not null,
  resource_type_id  uuid not null,
  total_quantity    integer not null default 0 check (total_quantity between 0 and 1000),
  status            text not null default 'ACTIVE' check (status in ('ACTIVE', 'MAINTENANCE', 'DISABLED')),
  created_at        timestamptz not null default now(),
  created_by        uuid references public.profiles (id),
  updated_at        timestamptz not null default now(),
  constraint branch_resources_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint branch_resources_type_fk foreign key (company_id, resource_type_id)
    references public.resource_types (company_id, id) on delete restrict,
  constraint branch_resources_key unique (branch_id, resource_type_id)
);

comment on table public.branch_resources is
  'จำนวนทรัพยากรต่อสาขา (นับรวม ไม่ระบุหมายเลขเตียง) ใช้เป็นจุดล็อกตอนตรวจ capacity';

-- -----------------------------------------------------------------------------
-- service_resources (บริการใช้ทรัพยากรอะไรกี่หน่วย — ทุกช่วงเวลาเหมือนกัน)
-- -----------------------------------------------------------------------------
create table public.service_resources (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null,
  service_id        uuid not null,
  resource_type_id  uuid not null,
  quantity          integer not null default 1 check (quantity between 1 and 10),
  created_at        timestamptz not null default now(),
  created_by        uuid references public.profiles (id),
  updated_at        timestamptz not null default now(),
  constraint service_resources_service_fk foreign key (company_id, service_id)
    references public.services (company_id, id) on delete restrict,
  constraint service_resources_type_fk foreign key (company_id, resource_type_id)
    references public.resource_types (company_id, id) on delete restrict,
  constraint service_resources_key unique (service_id, resource_type_id)
);

comment on table public.service_resources is 'การใช้ทรัพยากรของบริการ แก้ผ่าน set_service_resources เท่านั้น';

-- -----------------------------------------------------------------------------
-- branch_payment_accounts (บัญชีรับมัดจำของสาขา)
-- -----------------------------------------------------------------------------
create table public.branch_payment_accounts (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null,
  branch_id         uuid not null,
  promptpay_id      text not null check (promptpay_id ~ '^(0[0-9]{9}|[0-9]{13}|[0-9]{15})$'),
  account_name      text not null check (char_length(trim(account_name)) between 1 and 150),
  bank_name         text check (bank_name is null or char_length(bank_name) <= 100),
  slipok_branch_id  text check (slipok_branch_id is null or slipok_branch_id ~ '^[0-9A-Za-z_-]{1,40}$'),
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  created_by        uuid references public.profiles (id),
  updated_at        timestamptz not null default now(),
  constraint branch_payment_accounts_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint branch_payment_accounts_branch_key unique (branch_id)
);

comment on column public.branch_payment_accounts.promptpay_id is
  'เบอร์มือถือ 10 หลัก / เลขประจำตัว 13 หลัก / e-Wallet 15 หลัก';
comment on column public.branch_payment_accounts.slipok_branch_id is
  'Branch ID ของ SlipOK ที่ผูกบัญชีรับเงินนี้ (ใช้ตรวจบัญชีผู้รับและสลิปซ้ำ)';

-- -----------------------------------------------------------------------------
-- resource_allocations
-- -----------------------------------------------------------------------------
create table public.resource_allocations (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null,
  branch_id         uuid not null,
  resource_type_id  uuid not null,
  booking_item_id   uuid,            -- FK เพิ่มใน migration 019 (booking_items)
  quantity          integer not null check (quantity between 1 and 10),
  starts_at         timestamptz not null,
  ends_at           timestamptz not null,
  status            text not null check (status in ('HELD', 'RESERVED', 'IN_USE', 'RELEASED')),
  expires_at        timestamptz,
  released_at       timestamptz,
  release_reason    text check (release_reason is null or char_length(release_reason) <= 200),
  created_at        timestamptz not null default now(),
  created_by        uuid references public.profiles (id),
  updated_at        timestamptz not null default now(),
  constraint resource_allocations_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint resource_allocations_type_fk foreign key (company_id, resource_type_id)
    references public.resource_types (company_id, id) on delete restrict,
  constraint resource_allocations_period_chk check (ends_at > starts_at),
  constraint resource_allocations_held_chk check ((status = 'HELD') = (expires_at is not null)),
  constraint resource_allocations_expiry_chk check (expires_at is null or expires_at > created_at),
  constraint resource_allocations_released_chk check ((status = 'RELEASED') = (released_at is not null))
);

comment on table public.resource_allocations is
  'การจัดสรรทรัพยากร [starts_at, ends_at) ห้าม DELETE; Source of Truth ของ capacity';

create index resource_allocations_active_idx
  on public.resource_allocations (branch_id, resource_type_id, starts_at, ends_at)
  where status <> 'RELEASED';
create index resource_allocations_item_idx on public.resource_allocations (booking_item_id);
create index resource_allocations_held_idx on public.resource_allocations (expires_at) where status = 'HELD';

-- -----------------------------------------------------------------------------
-- stamp / audit / guards
-- -----------------------------------------------------------------------------
create trigger resource_types_stamp before insert or update on public.resource_types
  for each row execute function private.tg_stamp();
create trigger branch_resources_stamp before insert or update on public.branch_resources
  for each row execute function private.tg_stamp();
create trigger service_resources_stamp before insert or update on public.service_resources
  for each row execute function private.tg_stamp();
create trigger branch_payment_accounts_stamp before insert or update on public.branch_payment_accounts
  for each row execute function private.tg_stamp();
create trigger resource_allocations_stamp before insert or update on public.resource_allocations
  for each row execute function private.tg_stamp();

create trigger resource_types_audit after insert or update or delete on public.resource_types
  for each row execute function private.tg_audit();
create trigger branch_resources_audit after insert or update or delete on public.branch_resources
  for each row execute function private.tg_audit();
create trigger service_resources_audit after insert or update or delete on public.service_resources
  for each row execute function private.tg_audit();
create trigger branch_payment_accounts_audit after insert or update or delete on public.branch_payment_accounts
  for each row execute function private.tg_audit();

create or replace function private.tg_resources_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.company_id <> old.company_id then
      raise exception 'ห้ามย้ายข้อมูลข้ามบริษัท' using errcode = 'check_violation';
    end if;
    if tg_table_name = 'branch_resources' then
      if new.branch_id <> old.branch_id or new.resource_type_id <> old.resource_type_id then
        raise exception 'ห้ามเปลี่ยนสาขา/ประเภทของทรัพยากรเดิม' using errcode = 'check_violation';
      end if;
    elsif tg_table_name = 'branch_payment_accounts' then
      if new.branch_id <> old.branch_id then
        raise exception 'ห้ามย้ายบัญชีรับเงินไปสาขาอื่น' using errcode = 'check_violation';
      end if;
    end if;
  end if;
  return new;
end;
$$;

create trigger branch_resources_guard before update on public.branch_resources
  for each row execute function private.tg_resources_guard();
create trigger branch_payment_accounts_guard before update on public.branch_payment_accounts
  for each row execute function private.tg_resources_guard();
create trigger resource_types_guard before update on public.resource_types
  for each row execute function private.tg_resources_guard();

-- ลดจำนวน/ปิดทรัพยากรได้ แต่ต้องไม่ต่ำกว่าที่จัดสรรไว้ในอนาคต (กัน overselling ย้อนหลัง)
create or replace function private.tg_branch_resources_capacity_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_peak    integer;
  v_cap     integer;
  v_old_cap integer;
begin
  v_cap := case when new.status = 'ACTIVE' then new.total_quantity else 0 end;
  v_old_cap := case when old.status = 'ACTIVE' then old.total_quantity else 0 end;
  if v_cap >= v_old_cap then
    return new;
  end if;
  select coalesce(max(load), 0) into v_peak
    from (
      select p.t, sum(a.quantity) as load
        from (select distinct starts_at as t from public.resource_allocations
               where branch_id = new.branch_id and resource_type_id = new.resource_type_id
                 and ends_at > now()
                 and (status in ('RESERVED', 'IN_USE') or (status = 'HELD' and expires_at > now()))) p
        join public.resource_allocations a
          on a.branch_id = new.branch_id and a.resource_type_id = new.resource_type_id
         and a.starts_at <= p.t and p.t < a.ends_at
         and (a.status in ('RESERVED', 'IN_USE') or (a.status = 'HELD' and a.expires_at > now()))
       group by p.t
    ) x;
  if v_peak > v_cap then
    raise exception 'มีการจองในอนาคตใช้ทรัพยากรนี้สูงสุด % หน่วย ลดจำนวนต่ำกว่านี้ไม่ได้', v_peak
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger branch_resources_capacity_guard before update of total_quantity, status on public.branch_resources
  for each row execute function private.tg_branch_resources_capacity_guard();

-- -----------------------------------------------------------------------------
-- Capacity
-- -----------------------------------------------------------------------------
-- allocation ที่ยังกินทรัพยากรอยู่
create or replace function private.allocation_is_active(p_status text, p_expires_at timestamptz)
returns boolean
language sql
stable
set search_path = ''
as $$
  select p_status in ('RESERVED', 'IN_USE') or (p_status = 'HELD' and p_expires_at > now());
$$;

-- ความต้องการใหม่ (ยังไม่ insert) + ของเดิม ต้องไม่เกินจำนวนทรัพยากร
--   p_demands = [{ "resource_type_id": uuid, "quantity": int, "starts_at": ts, "ends_at": ts }, ...]
--   p_lock = true: ล็อกแถว branch_resources (ใช้ตอนจองจริง) | false: แค่ตรวจ (ใช้แสดงเวลาว่าง)
--   p_exclude_ids: allocation ที่ไม่นับ (เช่นของตัวเองตอนเปลี่ยนสถานะ)
create or replace function private.has_capacity(
  p_branch_id   uuid,
  p_demands     jsonb,
  p_lock        boolean default false,
  p_exclude_ids uuid[] default '{}'
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  r       record;
  v_cap   integer;
  v_peak  integer;
begin
  for r in
    select (d ->> 'resource_type_id')::uuid as type_id
      from jsonb_array_elements(coalesce(p_demands, '[]'::jsonb)) d
     group by 1
     order by 1
  loop
    if p_lock then
      select case when status = 'ACTIVE' then total_quantity else 0 end into v_cap
        from public.branch_resources
       where branch_id = p_branch_id and resource_type_id = r.type_id
       for update;
    else
      select case when status = 'ACTIVE' then total_quantity else 0 end into v_cap
        from public.branch_resources
       where branch_id = p_branch_id and resource_type_id = r.type_id;
    end if;
    v_cap := coalesce(v_cap, 0);

    with demand as (
      select (d ->> 'starts_at')::timestamptz as s, (d ->> 'ends_at')::timestamptz as e, (d ->> 'quantity')::int as q
        from jsonb_array_elements(p_demands) d
       where (d ->> 'resource_type_id')::uuid = r.type_id
    ),
    win as (select min(s) as ws, max(e) as we from demand),
    existing as (
      select a.starts_at as s, a.ends_at as e, a.quantity as q
        from public.resource_allocations a, win
       where a.branch_id = p_branch_id and a.resource_type_id = r.type_id
         and a.starts_at < win.we and a.ends_at > win.ws
         and private.allocation_is_active(a.status, a.expires_at)
         and not (a.id = any (p_exclude_ids))
    ),
    rects as (select * from demand union all select * from existing),
    points as (select distinct greatest(rects.s, win.ws) as t from rects, win where rects.s < win.we)
    select coalesce(max(load), 0) into v_peak
      from (
        select p.t, sum(x.q) as load
          from points p join rects x on x.s <= p.t and p.t < x.e
         group by p.t
      ) l;

    if v_peak > v_cap then
      return false;
    end if;
  end loop;
  return true;
end;
$$;

revoke all on function private.has_capacity(uuid, jsonb, boolean, uuid[]) from public;

-- Trigger: ทุก allocation ที่เป็น active ต้องไม่ทำให้เกิน capacity (ป้องกันชั้นสุดท้าย)
create or replace function private.tg_resource_allocations_capacity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.company_id <> old.company_id or new.branch_id <> old.branch_id
       or new.resource_type_id <> old.resource_type_id or new.booking_item_id is distinct from old.booking_item_id then
      raise exception 'ห้ามเปลี่ยนเจ้าของ/ประเภทของการจัดสรร' using errcode = 'check_violation';
    end if;
    if old.status = 'RELEASED' then
      raise exception 'การจัดสรรที่คืนแล้วแก้ไขไม่ได้' using errcode = 'check_violation';
    end if;
    -- ไม่ต้องตรวจซ้ำถ้าไม่ได้ขยายการใช้ทรัพยากร
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

create trigger resource_allocations_capacity
  before insert or update on public.resource_allocations
  for each row execute function private.tg_resource_allocations_capacity();

-- -----------------------------------------------------------------------------
-- เวลาเปิด-ปิดของสาขาในวันที่ระบุ (รวมวันหยุด/เวลาพิเศษ) คืน NULL ถ้าปิด
-- -----------------------------------------------------------------------------
create or replace function private.branch_open_window(p_branch_id uuid, p_date date)
returns table (opens_at timestamptz, closes_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tz     text;
  v_closed boolean;
  v_open   time;
  v_close  time;
  h        record;
begin
  select s.timezone into v_tz
    from public.branches b join public.company_settings s on s.company_id = b.company_id
   where b.id = p_branch_id and b.is_active;
  if v_tz is null then
    return;
  end if;

  select * into h from public.branch_holidays
   where branch_id = p_branch_id and holiday_date = p_date and is_active;
  if h.id is not null then
    v_closed := h.is_closed; v_open := h.opens_at; v_close := h.closes_at;
  else
    select o.is_closed, o.opens_at, o.closes_at into v_closed, v_open, v_close
      from public.branch_opening_hours o
     where o.branch_id = p_branch_id and o.iso_dow = extract(isodow from p_date);
  end if;

  if v_closed is distinct from false then
    return;
  end if;

  opens_at := (p_date + v_open) at time zone v_tz;
  closes_at := ((case when v_close <= v_open then p_date + 1 else p_date end) + v_close) at time zone v_tz;
  return next;
end;
$$;

revoke all on function private.branch_open_window(uuid, date) from public;

-- -----------------------------------------------------------------------------
-- ความต้องการทรัพยากรของรายการ (option) ที่เวลาเริ่ม
--   คืน jsonb array ของ demand (รวม buffer) และ error ถ้าบริการยังไม่กำหนดทรัพยากร
-- -----------------------------------------------------------------------------
create or replace function private.option_demands(p_option_id uuid, p_starts_at timestamptz, p_buffer integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_service  uuid;
  v_duration integer;
  v_result   jsonb;
begin
  select bs.service_id, o.duration_minutes into v_service, v_duration
    from public.branch_service_options o join public.branch_services bs on bs.id = o.branch_service_id
   where o.id = p_option_id;

  select jsonb_agg(jsonb_build_object(
           'resource_type_id', sr.resource_type_id,
           'quantity', sr.quantity,
           'starts_at', p_starts_at,
           'ends_at', p_starts_at + make_interval(mins => v_duration + p_buffer)))
    into v_result
    from public.service_resources sr
   where sr.service_id = v_service;

  if v_result is null then
    raise exception 'บริการนี้ยังไม่ได้กำหนดเตียง/อุปกรณ์ที่ใช้ กรุณาติดต่อร้าน' using errcode = 'check_violation';
  end if;
  return v_result;
end;
$$;

revoke all on function private.option_demands(uuid, timestamptz, integer) from public;

-- -----------------------------------------------------------------------------
-- public.get_available_slots — เวลาเริ่มที่จองได้ (anon เรียกได้ แสดงแค่เวลาว่าง)
--   p_option_ids = ช่วงเวลาที่เลือก (1 ต่อคน ซ้ำได้ เช่น 2 คนนวดไทย 60 นาที)
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
  -- ทุก option ต้องเป็นของสาขานี้และเปิดขาย
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
    v_slot := w.opens_at;
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

revoke all on function public.get_available_slots(uuid, date, uuid[]) from public;
grant execute on function public.get_available_slots(uuid, date, uuid[]) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Grants + RLS
-- -----------------------------------------------------------------------------
alter table public.resource_types enable row level security;
alter table public.branch_resources enable row level security;
alter table public.service_resources enable row level security;
alter table public.branch_payment_accounts enable row level security;
alter table public.resource_allocations enable row level security;

revoke all on public.resource_types, public.branch_resources, public.service_resources,
              public.branch_payment_accounts, public.resource_allocations from anon, authenticated;
grant all on public.resource_types, public.branch_resources, public.service_resources,
             public.branch_payment_accounts, public.resource_allocations to service_role;

grant select on public.resource_types, public.branch_resources, public.service_resources,
               public.branch_payment_accounts, public.resource_allocations to authenticated;
grant insert (company_id, name, description) on public.resource_types to authenticated;
grant update (name, description, is_active) on public.resource_types to authenticated;
grant insert (company_id, branch_id, resource_type_id, total_quantity, status) on public.branch_resources to authenticated;
grant update (total_quantity, status) on public.branch_resources to authenticated;
grant insert (company_id, branch_id, promptpay_id, account_name, bank_name, slipok_branch_id, is_active)
  on public.branch_payment_accounts to authenticated;
grant update (promptpay_id, account_name, bank_name, slipok_branch_id, is_active)
  on public.branch_payment_accounts to authenticated;

create policy resource_types_select_member on public.resource_types
  for select to authenticated using (private.is_company_member(company_id));
create policy resource_types_insert_owner on public.resource_types
  for insert to authenticated with check (private.is_company_owner(company_id));
create policy resource_types_update_owner on public.resource_types
  for update to authenticated using (private.is_company_owner(company_id)) with check (private.is_company_owner(company_id));

create policy branch_resources_select_member on public.branch_resources
  for select to authenticated using (private.has_branch_access(branch_id) or private.is_company_owner(company_id));
create policy branch_resources_insert_owner on public.branch_resources
  for insert to authenticated with check (private.is_company_owner(company_id));
create policy branch_resources_update_owner on public.branch_resources
  for update to authenticated using (private.is_company_owner(company_id)) with check (private.is_company_owner(company_id));

create policy service_resources_select_member on public.service_resources
  for select to authenticated using (private.is_company_member(company_id));

create policy branch_payment_accounts_select_member on public.branch_payment_accounts
  for select to authenticated using (private.has_branch_access(branch_id) or private.is_company_owner(company_id));
create policy branch_payment_accounts_insert_owner on public.branch_payment_accounts
  for insert to authenticated with check (private.is_company_owner(company_id));
create policy branch_payment_accounts_update_owner on public.branch_payment_accounts
  for update to authenticated using (private.is_company_owner(company_id)) with check (private.is_company_owner(company_id));

create policy resource_allocations_select_branch on public.resource_allocations
  for select to authenticated using (private.has_branch_access(branch_id));

-- -----------------------------------------------------------------------------
-- public.set_service_resources — OWNER กำหนดทรัพยากรที่บริการใช้ (แทนที่ทั้งชุด, มี audit)
--   p_items = [{ "resource_type_id": uuid, "quantity": int }, ...]
-- -----------------------------------------------------------------------------
create or replace function public.set_service_resources(p_service_id uuid, p_items jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid;
begin
  select company_id into v_company from public.services where id = p_service_id;
  if v_company is null or not private.is_company_owner(v_company) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'บริการต้องใช้ทรัพยากรอย่างน้อย 1 ประเภท' using errcode = 'invalid_parameter_value';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) i
     where not exists (select 1 from public.resource_types t
                        where t.id = (i ->> 'resource_type_id')::uuid and t.company_id = v_company and t.is_active)
  ) then
    raise exception 'ประเภททรัพยากรไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;

  delete from public.service_resources
   where service_id = p_service_id
     and resource_type_id not in (select (i ->> 'resource_type_id')::uuid from jsonb_array_elements(p_items) i);

  insert into public.service_resources (company_id, service_id, resource_type_id, quantity)
  select v_company, p_service_id, (i ->> 'resource_type_id')::uuid, coalesce((i ->> 'quantity')::int, 1)
    from jsonb_array_elements(p_items) i
  on conflict (service_id, resource_type_id) do update set quantity = excluded.quantity;
end;
$$;

revoke all on function public.set_service_resources(uuid, jsonb) from public, anon;
grant execute on function public.set_service_resources(uuid, jsonb) to authenticated;
