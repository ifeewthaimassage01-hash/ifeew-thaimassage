-- =============================================================================
-- Phase 1 / 004 — company_memberships, branch_memberships
-- =============================================================================
-- Role ของระบบมี 3 แบบ: OWNER, STAFF (เก็บที่นี่) และ CUSTOMER (ผูกผ่าน customers ใน Phase 3)
-- การเพิ่ม/แก้ membership ทำผ่าน Function ที่ยืนยันรหัสผ่านซ้ำ (Phase 2)
-- Phase 1 ไม่มี Policy INSERT/UPDATE/DELETE สำหรับ client

-- -----------------------------------------------------------------------------
-- company_memberships: 1 แถวต่อคนต่อบริษัท
-- -----------------------------------------------------------------------------
create table public.company_memberships (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references public.companies (id) on delete restrict,
  user_id         uuid not null references public.profiles (id) on delete restrict,
  role            text not null check (role in ('OWNER', 'STAFF')),
  status          text not null default 'ACTIVE'
                    check (status in ('ACTIVE', 'SUSPENDED', 'REVOKED')),
  effective_from  timestamptz not null default now(),
  effective_to    timestamptz,
  created_at      timestamptz not null default now(),
  created_by      uuid references public.profiles (id),
  updated_at      timestamptz not null default now(),
  constraint company_memberships_company_user_key unique (company_id, user_id),
  constraint company_memberships_period_chk
    check (effective_to is null or effective_to > effective_from)
);

comment on table public.company_memberships is
  'สมาชิกบริษัทและ role (OWNER/STAFF) — แหล่งความจริงเดียวของ role';

create index company_memberships_user_idx on public.company_memberships (user_id, status);

create trigger company_memberships_stamp
  before insert or update on public.company_memberships
  for each row execute function private.tg_stamp();

-- -----------------------------------------------------------------------------
-- branch_memberships: สิทธิ์เข้าถึงสาขาของ STAFF ตามช่วงเวลา
-- OWNER เข้าถึงทุกสาขาในบริษัทโดยไม่ต้องมีแถวนี้
-- -----------------------------------------------------------------------------
create table public.branch_memberships (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null,
  branch_id       uuid not null,
  user_id         uuid not null,
  status          text not null default 'ACTIVE' check (status in ('ACTIVE', 'REVOKED')),
  effective_from  timestamptz not null default now(),
  effective_to    timestamptz,
  created_at      timestamptz not null default now(),
  created_by      uuid references public.profiles (id),
  updated_at      timestamptz not null default now(),
  constraint branch_memberships_period_chk
    check (effective_to is null or effective_to > effective_from),
  -- กันการผูกสาขาของบริษัทอื่น
  constraint branch_memberships_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  -- ผู้ใช้ต้องเป็นสมาชิกของบริษัทเดียวกัน
  constraint branch_memberships_member_fk foreign key (company_id, user_id)
    references public.company_memberships (company_id, user_id) on delete restrict,
  -- พนักงานประจำสาขาเดียวในช่วงเวลาหนึ่ง (ACTIVE ห้ามช่วงเวลาซ้อนกัน)
  constraint branch_memberships_no_overlap exclude using gist (
    company_id with =,
    user_id with =,
    tstzrange(effective_from, coalesce(effective_to, 'infinity'::timestamptz), '[)') with &&
  ) where (status = 'ACTIVE')
);

comment on table public.branch_memberships is
  'สิทธิ์สาขาของ STAFF ตามช่วงเวลา [effective_from, effective_to) ห้ามซ้อนกัน';

create index branch_memberships_user_idx on public.branch_memberships (user_id, status);
create index branch_memberships_branch_idx on public.branch_memberships (branch_id, status);

create trigger branch_memberships_stamp
  before insert or update on public.branch_memberships
  for each row execute function private.tg_stamp();

-- ห้ามเปลี่ยน company/branch/user ของแถวเดิม (ต้องปิดแถวเดิมแล้วสร้างใหม่ เพื่อเก็บประวัติ)
create or replace function private.tg_branch_memberships_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.company_id <> old.company_id
     or new.branch_id <> old.branch_id
     or new.user_id <> old.user_id then
    raise exception 'ห้ามเปลี่ยนบริษัท/สาขา/ผู้ใช้ของสิทธิ์เดิม ให้ปิดสิทธิ์เดิมและสร้างใหม่'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger branch_memberships_guard
  before update on public.branch_memberships
  for each row execute function private.tg_branch_memberships_guard();

create or replace function private.tg_company_memberships_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.company_id <> old.company_id or new.user_id <> old.user_id then
    raise exception 'ห้ามเปลี่ยนบริษัท/ผู้ใช้ของ membership เดิม'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger company_memberships_guard
  before update on public.company_memberships
  for each row execute function private.tg_company_memberships_guard();
