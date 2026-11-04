-- =============================================================================
-- Phase 1 / 003 — companies, company_settings, branches
-- =============================================================================

-- -----------------------------------------------------------------------------
-- companies
-- -----------------------------------------------------------------------------
create table public.companies (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique check (private.is_valid_code(code)),
  name        text not null check (char_length(name) between 1 and 200),
  legal_name  text check (legal_name is null or char_length(legal_name) <= 200),
  tax_id      text check (tax_id is null or tax_id ~ '^[0-9]{13}$'),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  created_by  uuid references public.profiles (id),
  updated_at  timestamptz not null default now()
);

comment on table public.companies is 'บริษัท (รองรับหลายบริษัท ระยะแรกมีบริษัทเดียว) ห้าม DELETE ใช้ is_active';

create trigger companies_stamp
  before insert or update on public.companies
  for each row execute function private.tg_stamp();

-- -----------------------------------------------------------------------------
-- company_settings (1:1)
-- -----------------------------------------------------------------------------
create table public.company_settings (
  company_id                 uuid primary key references public.companies (id) on delete restrict,
  timezone                   text not null default 'Asia/Bangkok'
                               check (timezone = 'Asia/Bangkok'),
  cancellation_cutoff_hours  integer not null default 3
                               check (cancellation_cutoff_hours between 0 and 168),
  large_expense_threshold    numeric(12,2) not null default 5000.00
                               check (large_expense_threshold >= 0),
  staff_pin_max_attempts     integer not null default 5
                               check (staff_pin_max_attempts between 3 and 10),
  staff_pin_lockout_minutes  integer not null default 15
                               check (staff_pin_lockout_minutes between 1 and 1440),
  staff_idle_lock_minutes    integer not null default 5
                               check (staff_idle_lock_minutes between 1 and 120),
  created_at                 timestamptz not null default now(),
  created_by                 uuid references public.profiles (id),
  updated_at                 timestamptz not null default now()
);

comment on column public.company_settings.timezone is
  'เฟสแรกล็อก Asia/Bangkok — การคำนวณวันที่ทำงาน/เลขเอกสารใช้ค่านี้';

create trigger company_settings_stamp
  before insert or update on public.company_settings
  for each row execute function private.tg_stamp();

-- สร้าง settings อัตโนมัติเมื่อสร้างบริษัท
create or replace function private.handle_new_company()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.company_settings (company_id, created_by)
  values (new.id, new.created_by)
  on conflict (company_id) do nothing;
  return new;
end;
$$;

create trigger companies_create_settings
  after insert on public.companies
  for each row execute function private.handle_new_company();

-- -----------------------------------------------------------------------------
-- branches
-- -----------------------------------------------------------------------------
create table public.branches (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies (id) on delete restrict,
  code        text not null check (private.is_valid_code(code)),
  name        text not null check (char_length(name) between 1 and 200),
  address     text check (address is null or char_length(address) <= 500),
  phone       text check (phone is null or phone ~ '^[0-9+\-\s]{6,20}$'),
  map_url     text check (map_url is null or map_url ~ '^https://'),
  is_active   boolean not null default true,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  created_by  uuid references public.profiles (id),
  updated_at  timestamptz not null default now(),
  constraint branches_company_code_key unique (company_id, code),
  -- ใช้เป็นปลายทางของ composite FK (company_id, branch_id) ในตารางอื่น
  constraint branches_company_id_id_key unique (company_id, id)
);

comment on table public.branches is 'สาขา ห้าม DELETE ใช้ is_active; code แก้ไม่ได้หลังออกเอกสาร';

create index branches_company_active_idx on public.branches (company_id, is_active, sort_order);

create trigger branches_stamp
  before insert or update on public.branches
  for each row execute function private.tg_stamp();

-- ห้ามย้ายสาขาข้ามบริษัท
create or replace function private.tg_branches_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.company_id <> old.company_id then
    raise exception 'ไม่สามารถย้ายสาขาไปบริษัทอื่นได้'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger branches_guard
  before update on public.branches
  for each row execute function private.tg_branches_guard();
