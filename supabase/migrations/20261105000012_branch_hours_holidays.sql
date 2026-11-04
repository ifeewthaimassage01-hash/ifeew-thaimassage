-- =============================================================================
-- Phase 2 / 012 — branch_opening_hours, branch_holidays
-- =============================================================================
-- เวลาเป็นเวลาท้องถิ่นของบริษัท (Asia/Bangkok)
-- closes_at < opens_at หมายถึงปิดหลังเที่ยงคืนของวันถัดไป

-- -----------------------------------------------------------------------------
-- branch_opening_hours: 1 แถวต่อวันในสัปดาห์ (ISO: 1=จันทร์ .. 7=อาทิตย์)
-- -----------------------------------------------------------------------------
create table public.branch_opening_hours (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null,
  branch_id   uuid not null,
  iso_dow     smallint not null check (iso_dow between 1 and 7),
  is_closed   boolean not null default true,
  opens_at    time,
  closes_at   time,
  created_at  timestamptz not null default now(),
  created_by  uuid references public.profiles (id),
  updated_at  timestamptz not null default now(),
  constraint branch_opening_hours_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint branch_opening_hours_day_key unique (branch_id, iso_dow),
  constraint branch_opening_hours_times_chk check (
    (is_closed and opens_at is null and closes_at is null)
    or (not is_closed and opens_at is not null and closes_at is not null and opens_at <> closes_at)
  )
);

comment on table public.branch_opening_hours is
  'เวลาทำการรายวันในสัปดาห์ (ครบ 7 แถวต่อสาขา) closes_at < opens_at = ปิดหลังเที่ยงคืน';

create trigger branch_opening_hours_stamp
  before insert or update on public.branch_opening_hours
  for each row execute function private.tg_stamp();

create trigger branch_opening_hours_audit
  after insert or update or delete on public.branch_opening_hours
  for each row execute function private.tg_audit();

-- ห้ามเปลี่ยน branch/day ของแถวเดิม
create or replace function private.tg_branch_opening_hours_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.company_id <> old.company_id or new.branch_id <> old.branch_id or new.iso_dow <> old.iso_dow then
    raise exception 'ห้ามเปลี่ยนสาขาหรือวันของเวลาทำการ' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger branch_opening_hours_guard
  before update on public.branch_opening_hours
  for each row execute function private.tg_branch_opening_hours_guard();

-- สร้างเวลาทำการ 7 วัน (ปิดไว้ก่อน) เมื่อสร้างสาขา — ไม่มีสาขาใดรับจองได้จนกว่า OWNER ตั้งเวลา
create or replace function private.handle_new_branch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.branch_opening_hours (company_id, branch_id, iso_dow, is_closed, created_by)
  select new.company_id, new.id, d, true, new.created_by
    from generate_series(1, 7) d
  on conflict (branch_id, iso_dow) do nothing;
  return new;
end;
$$;

create trigger branches_create_opening_hours
  after insert on public.branches
  for each row execute function private.handle_new_branch();

-- เติมให้สาขาที่มีอยู่แล้ว
insert into public.branch_opening_hours (company_id, branch_id, iso_dow, is_closed)
select b.company_id, b.id, d, true
  from public.branches b
  cross join generate_series(1, 7) d
on conflict (branch_id, iso_dow) do nothing;

-- -----------------------------------------------------------------------------
-- branch_holidays: วันหยุดหรือวันเปิดเวลาพิเศษ
-- -----------------------------------------------------------------------------
create table public.branch_holidays (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null,
  branch_id     uuid not null,
  holiday_date  date not null,
  name          text not null check (char_length(trim(name)) between 1 and 120),
  is_closed     boolean not null default true,
  opens_at      time,
  closes_at     time,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  created_by    uuid references public.profiles (id),
  updated_at    timestamptz not null default now(),
  constraint branch_holidays_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint branch_holidays_times_chk check (
    (is_closed and opens_at is null and closes_at is null)
    or (not is_closed and opens_at is not null and closes_at is not null and opens_at <> closes_at)
  )
);

comment on table public.branch_holidays is 'วันหยุด/วันเวลาพิเศษของสาขา ห้าม DELETE ใช้ is_active';

create unique index branch_holidays_active_day_key
  on public.branch_holidays (branch_id, holiday_date)
  where is_active;

create index branch_holidays_branch_date_idx on public.branch_holidays (branch_id, holiday_date);

create trigger branch_holidays_stamp
  before insert or update on public.branch_holidays
  for each row execute function private.tg_stamp();

create trigger branch_holidays_audit
  after insert or update or delete on public.branch_holidays
  for each row execute function private.tg_audit();

create or replace function private.tg_branch_holidays_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.company_id <> old.company_id or new.branch_id <> old.branch_id then
    raise exception 'ห้ามย้ายวันหยุดไปสาขาอื่น' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger branch_holidays_guard
  before update on public.branch_holidays
  for each row execute function private.tg_branch_holidays_guard();

-- -----------------------------------------------------------------------------
-- Grants + RLS
-- -----------------------------------------------------------------------------
alter table public.branch_opening_hours enable row level security;
alter table public.branch_holidays enable row level security;

revoke all on public.branch_opening_hours, public.branch_holidays from anon, authenticated;
grant all on public.branch_opening_hours, public.branch_holidays to service_role;

grant select (id, branch_id, iso_dow, is_closed, opens_at, closes_at)
  on public.branch_opening_hours to anon;
grant select on public.branch_opening_hours to authenticated;
grant update (is_closed, opens_at, closes_at) on public.branch_opening_hours to authenticated;

grant select (id, branch_id, holiday_date, name, is_closed, opens_at, closes_at, is_active)
  on public.branch_holidays to anon;
grant select on public.branch_holidays to authenticated;
grant insert (company_id, branch_id, holiday_date, name, is_closed, opens_at, closes_at)
  on public.branch_holidays to authenticated;
grant update (name, is_closed, opens_at, closes_at, is_active)
  on public.branch_holidays to authenticated;

-- สาขาที่เปิดให้บริการ (ใช้ร่วมกับ policy สาธารณะ)
create or replace function private.is_public_branch(p_branch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.branches b
      join public.companies c on c.id = b.company_id
     where b.id = p_branch_id and b.is_active and c.is_active
  );
$$;

revoke all on function private.is_public_branch(uuid) from public;
grant execute on function private.is_public_branch(uuid) to anon, authenticated, service_role;

create policy branch_opening_hours_select_public on public.branch_opening_hours
  for select to anon, authenticated
  using (private.is_public_branch(branch_id));

create policy branch_opening_hours_select_member on public.branch_opening_hours
  for select to authenticated
  using (private.is_company_member(company_id));

create policy branch_opening_hours_update_owner on public.branch_opening_hours
  for update to authenticated
  using (private.is_company_owner(company_id))
  with check (private.is_company_owner(company_id));

create policy branch_holidays_select_public on public.branch_holidays
  for select to anon, authenticated
  using (is_active and private.is_public_branch(branch_id));

create policy branch_holidays_select_member on public.branch_holidays
  for select to authenticated
  using (private.is_company_member(company_id));

create policy branch_holidays_insert_owner on public.branch_holidays
  for insert to authenticated
  with check (private.is_company_owner(company_id));

create policy branch_holidays_update_owner on public.branch_holidays
  for update to authenticated
  using (private.is_company_owner(company_id))
  with check (private.is_company_owner(company_id));
