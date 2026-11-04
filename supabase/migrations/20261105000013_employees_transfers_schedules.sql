-- =============================================================================
-- Phase 2 / 013 — employees, employee_transfers, employee_schedules
-- =============================================================================

-- -----------------------------------------------------------------------------
-- employees: ข้อมูลพนักงาน 1:1 กับ company_memberships (role STAFF เท่านั้น)
-- สร้างผ่าน public.create_staff_member, เปลี่ยนสถานะผ่าน public.set_employee_status
-- -----------------------------------------------------------------------------
create table public.employees (
  id                 uuid primary key default gen_random_uuid(),
  company_id         uuid not null,
  user_id            uuid not null,
  employee_code      text not null check (employee_code ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,19}$'),
  nickname           text not null check (char_length(trim(nickname)) between 1 and 60),
  photo_path         text check (photo_path is null or photo_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,100}$'),
  start_date         date not null,
  status             text not null default 'ACTIVE' check (status in ('ACTIVE', 'INACTIVE', 'RESIGNED')),
  status_changed_at  timestamptz not null default now(),
  resigned_at        timestamptz,
  created_at         timestamptz not null default now(),
  created_by         uuid references public.profiles (id),
  updated_at         timestamptz not null default now(),
  constraint employees_member_fk foreign key (company_id, user_id)
    references public.company_memberships (company_id, user_id) on delete restrict,
  constraint employees_company_user_key unique (company_id, user_id),
  constraint employees_company_id_id_key unique (company_id, id),
  constraint employees_resigned_chk check ((status = 'RESIGNED') = (resigned_at is not null))
);

comment on table public.employees is 'พนักงาน (STAFF) 1:1 กับ membership ห้าม DELETE';

create unique index employees_company_code_key on public.employees (company_id, upper(employee_code));
create index employees_company_status_idx on public.employees (company_id, status);

create trigger employees_stamp
  before insert or update on public.employees
  for each row execute function private.tg_stamp();

create trigger employees_audit
  after insert or update or delete on public.employees
  for each row execute function private.tg_audit();

create or replace function private.tg_employees_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if not exists (
      select 1 from public.company_memberships
       where company_id = new.company_id and user_id = new.user_id and role = 'STAFF'
    ) then
      raise exception 'พนักงานต้องเป็นสมาชิก role STAFF' using errcode = 'check_violation';
    end if;
    new.nickname := trim(new.nickname);
  else
    if new.company_id <> old.company_id or new.user_id <> old.user_id then
      raise exception 'ห้ามเปลี่ยนบริษัท/ผู้ใช้ของพนักงาน' using errcode = 'check_violation';
    end if;
    if old.status = 'RESIGNED' and new.status <> 'RESIGNED' then
      raise exception 'พนักงานที่ลาออกแล้วเปลี่ยนสถานะไม่ได้' using errcode = 'check_violation';
    end if;
    if new.status <> old.status then
      new.status_changed_at := now();
    end if;
    new.nickname := trim(new.nickname);
  end if;

  if new.photo_path is not null
     and (split_part(new.photo_path, '/', 1) <> new.company_id::text
          or split_part(new.photo_path, '/', 2) <> new.id::text) then
    raise exception 'ตำแหน่งรูปพนักงานไม่ถูกต้อง' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger employees_guard
  before insert or update on public.employees
  for each row execute function private.tg_employees_guard();

-- ชื่อเล่นคือชื่อที่แสดงของบัญชีพนักงาน
create or replace function private.tg_employees_sync_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles set display_name = new.nickname
   where id = new.user_id and display_name is distinct from new.nickname;
  return null;
end;
$$;

create trigger employees_sync_profile
  after insert or update of nickname on public.employees
  for each row execute function private.tg_employees_sync_profile();

-- -----------------------------------------------------------------------------
-- employee_transfers: ประวัติย้ายสาขา (รวมการเริ่มงานครั้งแรก from_branch_id = NULL)
-- -----------------------------------------------------------------------------
create table public.employee_transfers (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null,
  employee_id         uuid not null,
  from_branch_id      uuid,
  to_branch_id        uuid not null,
  from_membership_id  uuid references public.branch_memberships (id) on delete restrict,
  to_membership_id    uuid not null references public.branch_memberships (id) on delete restrict,
  effective_from      timestamptz not null,
  reason              text not null check (char_length(trim(reason)) between 3 and 500),
  status              text not null default 'ACTIVE' check (status in ('ACTIVE', 'CANCELLED')),
  cancelled_at        timestamptz,
  cancelled_by        uuid references public.profiles (id),
  cancel_reason       text check (cancel_reason is null or char_length(trim(cancel_reason)) between 3 and 500),
  created_at          timestamptz not null default now(),
  created_by          uuid references public.profiles (id),
  updated_at          timestamptz not null default now(),
  constraint employee_transfers_employee_fk foreign key (company_id, employee_id)
    references public.employees (company_id, id) on delete restrict,
  constraint employee_transfers_from_branch_fk foreign key (company_id, from_branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint employee_transfers_to_branch_fk foreign key (company_id, to_branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint employee_transfers_branch_chk check (from_branch_id is distinct from to_branch_id),
  constraint employee_transfers_from_chk check ((from_branch_id is null) = (from_membership_id is null)),
  constraint employee_transfers_cancel_chk check (
    (status = 'ACTIVE' and cancelled_at is null and cancel_reason is null)
    or (status = 'CANCELLED' and cancelled_at is not null and cancel_reason is not null)
  )
);

comment on table public.employee_transfers is 'ประวัติย้ายสาขา (append + cancel) แก้ผ่าน Function เท่านั้น';

create index employee_transfers_employee_idx on public.employee_transfers (employee_id, effective_from desc);

create trigger employee_transfers_stamp
  before insert or update on public.employee_transfers
  for each row execute function private.tg_stamp();

create trigger employee_transfers_audit
  after insert or update or delete on public.employee_transfers
  for each row execute function private.tg_audit();

-- -----------------------------------------------------------------------------
-- employee_schedules: กะงานรายวัน
-- -----------------------------------------------------------------------------
create table public.employee_schedules (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null,
  branch_id    uuid not null,
  employee_id  uuid not null,
  starts_at    timestamptz not null,
  ends_at      timestamptz not null,
  status       text not null default 'SCHEDULED' check (status in ('SCHEDULED', 'LEAVE', 'CANCELLED')),
  note         text check (note is null or char_length(note) <= 300),
  created_at   timestamptz not null default now(),
  created_by   uuid references public.profiles (id),
  updated_at   timestamptz not null default now(),
  constraint employee_schedules_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint employee_schedules_employee_fk foreign key (company_id, employee_id)
    references public.employees (company_id, id) on delete restrict,
  constraint employee_schedules_period_chk
    check (ends_at > starts_at and ends_at - starts_at <= interval '16 hours'),
  constraint employee_schedules_no_overlap exclude using gist (
    employee_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  ) where (status <> 'CANCELLED')
);

comment on table public.employee_schedules is 'กะงานพนักงาน [starts_at, ends_at) ห้าม DELETE ใช้ CANCELLED';

create index employee_schedules_branch_time_idx on public.employee_schedules (branch_id, starts_at);
create index employee_schedules_employee_time_idx on public.employee_schedules (employee_id, starts_at);

create trigger employee_schedules_stamp
  before insert or update on public.employee_schedules
  for each row execute function private.tg_stamp();

create trigger employee_schedules_audit
  after insert or update or delete on public.employee_schedules
  for each row execute function private.tg_audit();

-- ตรวจกะ: สถานะ, การแก้เวลา, พนักงานต้องสังกัดสาขานั้นตลอดช่วงกะ
create or replace function private.tg_employee_schedules_validate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_emp public.employees;
  v_check boolean := false;
begin
  if tg_op = 'INSERT' then
    if new.status <> 'SCHEDULED' then
      raise exception 'กะใหม่ต้องมีสถานะ SCHEDULED' using errcode = 'check_violation';
    end if;
    v_check := true;
  else
    if new.company_id <> old.company_id or new.employee_id <> old.employee_id or new.branch_id <> old.branch_id then
      raise exception 'ห้ามเปลี่ยนพนักงาน/สาขาของกะ ให้ยกเลิกแล้วสร้างใหม่' using errcode = 'check_violation';
    end if;
    if old.status = 'CANCELLED' then
      raise exception 'กะที่ยกเลิกแล้วแก้ไขไม่ได้' using errcode = 'check_violation';
    end if;
    if (new.starts_at <> old.starts_at or new.ends_at <> old.ends_at) and old.status <> 'SCHEDULED' then
      raise exception 'แก้เวลาได้เฉพาะกะสถานะ SCHEDULED' using errcode = 'check_violation';
    end if;
    v_check := new.status = 'SCHEDULED'
               and (new.starts_at <> old.starts_at or new.ends_at <> old.ends_at or old.status <> 'SCHEDULED');
  end if;

  if v_check then
    select * into v_emp from public.employees where id = new.employee_id;
    if v_emp.status <> 'ACTIVE' then
      raise exception 'พนักงานไม่ได้อยู่ในสถานะใช้งาน' using errcode = 'check_violation';
    end if;
    if not exists (
      select 1 from public.branch_memberships bm
       where bm.company_id = new.company_id
         and bm.branch_id = new.branch_id
         and bm.user_id = v_emp.user_id
         and bm.status = 'ACTIVE'
         and bm.effective_from <= new.starts_at
         and (bm.effective_to is null or bm.effective_to >= new.ends_at)
    ) then
      raise exception 'พนักงานไม่ได้สังกัดสาขานี้ตลอดช่วงเวลากะ' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;

create trigger employee_schedules_validate
  before insert or update on public.employee_schedules
  for each row execute function private.tg_employee_schedules_validate();

-- -----------------------------------------------------------------------------
-- Grants + RLS
-- -----------------------------------------------------------------------------
alter table public.employees enable row level security;
alter table public.employee_transfers enable row level security;
alter table public.employee_schedules enable row level security;

revoke all on public.employees, public.employee_transfers, public.employee_schedules from anon, authenticated;
grant all on public.employees, public.employee_transfers, public.employee_schedules to service_role;

grant select on public.employees to authenticated;
grant update (employee_code, nickname, photo_path, start_date) on public.employees to authenticated;

grant select on public.employee_transfers to authenticated;

grant select on public.employee_schedules to authenticated;
grant insert (company_id, branch_id, employee_id, starts_at, ends_at, note)
  on public.employee_schedules to authenticated;
grant update (starts_at, ends_at, status, note) on public.employee_schedules to authenticated;

-- employees: สมาชิกบริษัทเห็นรายชื่อเพื่อนร่วมงาน (ใช้ในคิว/ตารางงาน), OWNER แก้ข้อมูลทั่วไป
create policy employees_select_member on public.employees
  for select to authenticated
  using (private.is_company_member(company_id));

create policy employees_update_owner on public.employees
  for update to authenticated
  using (private.is_company_owner(company_id))
  with check (private.is_company_owner(company_id));

-- employee_transfers: OWNER หรือเจ้าตัว
create policy employee_transfers_select_owner_or_self on public.employee_transfers
  for select to authenticated
  using (
    private.is_company_owner(company_id)
    or exists (select 1 from public.employees e where e.id = employee_id and e.user_id = auth.uid())
  );

-- employee_schedules: คนที่เข้าถึงสาขาได้ หรือกะของตัวเอง; OWNER เขียน
create policy employee_schedules_select_branch_or_self on public.employee_schedules
  for select to authenticated
  using (
    private.has_branch_access(branch_id)
    or exists (select 1 from public.employees e where e.id = employee_id and e.user_id = auth.uid())
  );

create policy employee_schedules_insert_owner on public.employee_schedules
  for insert to authenticated
  with check (private.is_company_owner(company_id));

create policy employee_schedules_update_owner on public.employee_schedules
  for update to authenticated
  using (private.is_company_owner(company_id))
  with check (private.is_company_owner(company_id));
