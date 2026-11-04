-- =============================================================================
-- Phase 1 / 010 — Grants และ RLS
-- =============================================================================
-- หลักการ:
--  - เปิด RLS ทุกตารางใน public
--  - ถอนสิทธิ์ทั้งหมดจาก anon/authenticated แล้ว grant เฉพาะที่ต้องใช้
--  - Policy แยก SELECT / INSERT / UPDATE / DELETE
--  - ไม่มี Policy DELETE ในทุกตาราง Phase 1 (ข้อมูลหลักใช้ is_active)
--  - membership / device / pin เปลี่ยนผ่าน Function เท่านั้น

-- -----------------------------------------------------------------------------
-- เปิด RLS
-- -----------------------------------------------------------------------------
alter table public.profiles             enable row level security;
alter table public.companies            enable row level security;
alter table public.company_settings     enable row level security;
alter table public.branches             enable row level security;
alter table public.company_memberships  enable row level security;
alter table public.branch_memberships   enable row level security;
alter table public.audit_logs           enable row level security;
alter table public.document_sequences   enable row level security;
alter table public.idempotency_keys     enable row level security;
alter table public.rate_limit_buckets   enable row level security;
alter table public.branch_devices       enable row level security;
alter table public.staff_pins           enable row level security;

-- -----------------------------------------------------------------------------
-- Grants (ตั้งชัดเจน ไม่พึ่งค่า default ของ project)
-- -----------------------------------------------------------------------------
revoke all on
  public.profiles, public.companies, public.company_settings, public.branches,
  public.company_memberships, public.branch_memberships, public.audit_logs,
  public.document_sequences, public.idempotency_keys, public.rate_limit_buckets,
  public.branch_devices, public.staff_pins
from anon, authenticated;

grant all on
  public.profiles, public.companies, public.company_settings, public.branches,
  public.company_memberships, public.branch_memberships, public.audit_logs,
  public.document_sequences, public.idempotency_keys, public.rate_limit_buckets,
  public.branch_devices, public.staff_pins
to service_role;

-- anon: อ่านสาขาที่เปิดให้บริการ (Customer App)
grant select (id, company_id, code, name, address, phone, map_url, is_active, sort_order)
  on public.branches to anon;

-- authenticated
grant select on public.profiles to authenticated;
grant update (display_name, phone, avatar_path) on public.profiles to authenticated;

grant select on public.companies to authenticated;
grant update (name, legal_name, tax_id) on public.companies to authenticated;

grant select on public.company_settings to authenticated;
grant update (
  cancellation_cutoff_hours, large_expense_threshold,
  staff_pin_max_attempts, staff_pin_lockout_minutes, staff_idle_lock_minutes
) on public.company_settings to authenticated;

grant select on public.branches to authenticated;
grant insert (company_id, code, name, address, phone, map_url, is_active, sort_order)
  on public.branches to authenticated;
grant update (code, name, address, phone, map_url, is_active, sort_order)
  on public.branches to authenticated;

grant select on public.company_memberships to authenticated;
grant select on public.branch_memberships to authenticated;
grant select on public.audit_logs to authenticated;
grant select on public.document_sequences to authenticated;
grant select (id, company_id, branch_id, name, status, paired_by, paired_at, last_seen_at,
              revoked_by, revoked_at, revoke_reason, created_at, updated_at)
  on public.branch_devices to authenticated;
-- idempotency_keys, rate_limit_buckets, staff_pins: ไม่ grant ให้ client

-- -----------------------------------------------------------------------------
-- profiles
-- -----------------------------------------------------------------------------
create policy profiles_select_self_or_colleague on public.profiles
  for select to authenticated
  using (id = auth.uid() or private.shares_company_with(id));

create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- -----------------------------------------------------------------------------
-- companies
-- -----------------------------------------------------------------------------
create policy companies_select_member on public.companies
  for select to authenticated
  using (private.is_company_member(id));

create policy companies_update_owner on public.companies
  for update to authenticated
  using (private.is_company_owner(id))
  with check (private.is_company_owner(id));

-- -----------------------------------------------------------------------------
-- company_settings
-- -----------------------------------------------------------------------------
create policy company_settings_select_member on public.company_settings
  for select to authenticated
  using (private.is_company_member(company_id));

create policy company_settings_update_owner on public.company_settings
  for update to authenticated
  using (private.is_company_owner(company_id))
  with check (private.is_company_owner(company_id));

-- -----------------------------------------------------------------------------
-- branches
-- -----------------------------------------------------------------------------
-- anon ไม่มีสิทธิ์อ่าน companies จึงตรวจผ่าน helper แบบ security definer
create or replace function private.is_company_active(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.companies c where c.id = p_company_id and c.is_active);
$$;

revoke all on function private.is_company_active(uuid) from public;
grant usage on schema private to anon;
grant execute on function private.is_company_active(uuid) to anon, authenticated, service_role;

create policy branches_select_public_active on public.branches
  for select to anon, authenticated
  using (is_active and private.is_company_active(company_id));

create policy branches_select_member on public.branches
  for select to authenticated
  using (private.is_company_member(company_id));

create policy branches_insert_owner on public.branches
  for insert to authenticated
  with check (private.is_company_owner(company_id));

create policy branches_update_owner on public.branches
  for update to authenticated
  using (private.is_company_owner(company_id))
  with check (private.is_company_owner(company_id));

-- -----------------------------------------------------------------------------
-- company_memberships / branch_memberships (อ่านอย่างเดียว)
-- -----------------------------------------------------------------------------
create policy company_memberships_select_self_or_owner on public.company_memberships
  for select to authenticated
  using (user_id = auth.uid() or private.is_company_owner(company_id));

create policy branch_memberships_select_self_or_owner on public.branch_memberships
  for select to authenticated
  using (user_id = auth.uid() or private.is_company_owner(company_id));

-- -----------------------------------------------------------------------------
-- audit_logs: OWNER อ่านได้ ไม่มี INSERT/UPDATE/DELETE จาก client
-- -----------------------------------------------------------------------------
create policy audit_logs_select_owner on public.audit_logs
  for select to authenticated
  using (company_id is not null and private.is_company_owner(company_id));

-- -----------------------------------------------------------------------------
-- document_sequences: OWNER อ่านได้
-- -----------------------------------------------------------------------------
create policy document_sequences_select_owner on public.document_sequences
  for select to authenticated
  using (private.is_company_owner(company_id));

-- -----------------------------------------------------------------------------
-- branch_devices: OWNER อ่านได้ (ไม่เห็น token_hash เพราะไม่ได้ grant คอลัมน์)
-- -----------------------------------------------------------------------------
create policy branch_devices_select_owner on public.branch_devices
  for select to authenticated
  using (private.is_company_owner(company_id));

-- staff_pins, idempotency_keys, rate_limit_buckets: RLS เปิดและไม่มี policy = ปิดทั้งหมด

-- -----------------------------------------------------------------------------
-- ค่าเริ่มต้นของ object ใหม่ใน public: ไม่ให้ anon/authenticated อัตโนมัติ
-- (Phase ถัดไปต้อง grant เองทุกตาราง/ฟังก์ชัน)
-- -----------------------------------------------------------------------------
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated, public;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
