-- =============================================================================
-- Phase 1 / 005 — audit_logs (append-only)
-- =============================================================================
-- บันทึกทุกการเปลี่ยนข้อมูลหลัก (old_values, new_values) และเหตุการณ์สำคัญ (login, pairing)
-- ห้าม UPDATE/DELETE/TRUNCATE ทั้งจาก RLS (ไม่มี policy) และ Trigger (กัน service role ด้วย)
-- ไม่มี updated_at เพราะแถวไม่มีวันถูกแก้

create table public.audit_logs (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid references public.companies (id) on delete restrict,
  branch_id      uuid,
  actor_user_id  uuid references public.profiles (id) on delete restrict,
  action         text not null check (action ~ '^[A-Z_]{2,60}$'),
  table_name     text,
  record_id      uuid,
  old_values     jsonb,
  new_values     jsonb,
  reason         text check (reason is null or char_length(reason) <= 1000),
  metadata       jsonb not null default '{}'::jsonb,
  occurred_at    timestamptz not null default now(),
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id) on delete restrict
);

comment on table public.audit_logs is 'Audit log แบบ append-only ห้าม UPDATE/DELETE';

create index audit_logs_company_time_idx on public.audit_logs (company_id, occurred_at desc);
create index audit_logs_record_idx on public.audit_logs (table_name, record_id, occurred_at desc);
create index audit_logs_actor_idx on public.audit_logs (actor_user_id, occurred_at desc);

-- -----------------------------------------------------------------------------
-- ห้ามแก้หรือลบ
-- -----------------------------------------------------------------------------
create or replace function private.tg_audit_logs_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'audit_logs เป็น append-only ห้าม %', tg_op
    using errcode = 'insufficient_privilege';
end;
$$;

create trigger audit_logs_no_update_delete
  before update or delete on public.audit_logs
  for each row execute function private.tg_audit_logs_immutable();

create trigger audit_logs_no_truncate
  before truncate on public.audit_logs
  for each statement execute function private.tg_audit_logs_immutable();

-- -----------------------------------------------------------------------------
-- private.write_audit: บันทึกเหตุการณ์จาก Function อื่น (login, pairing, void ฯลฯ)
-- -----------------------------------------------------------------------------
create or replace function private.write_audit(
  p_action      text,
  p_company_id  uuid default null,
  p_branch_id   uuid default null,
  p_table_name  text default null,
  p_record_id   uuid default null,
  p_old_values  jsonb default null,
  p_new_values  jsonb default null,
  p_reason      text default null,
  p_metadata    jsonb default '{}'::jsonb,
  p_actor       uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_actor uuid := coalesce(p_actor, auth.uid());
begin
  insert into public.audit_logs (
    company_id, branch_id, actor_user_id, action, table_name, record_id,
    old_values, new_values, reason, metadata, created_by
  ) values (
    p_company_id, p_branch_id, v_actor, p_action, p_table_name, p_record_id,
    p_old_values, p_new_values,
    coalesce(p_reason, nullif(current_setting('app.audit_reason', true), '')),
    coalesce(p_metadata, '{}'::jsonb), v_actor
  )
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function private.write_audit(text, uuid, uuid, text, uuid, jsonb, jsonb, text, jsonb, uuid) from public;

-- -----------------------------------------------------------------------------
-- private.tg_audit: Trigger ร่วมสำหรับตารางข้อมูลหลัก
--   TG_ARGV = รายชื่อคอลัมน์ที่ต้องปิดบัง (เช่น pin_hash, token_hash)
--   เหตุผลส่งผ่าน: select set_config('app.audit_reason', '...', true);
-- -----------------------------------------------------------------------------
create or replace function private.tg_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_row jsonb;
  v_company uuid;
  v_branch uuid;
  v_record uuid;
  i int;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    v_old := to_jsonb(old);
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    v_new := to_jsonb(new);
  end if;

  -- ปิดบังคอลัมน์ลับ
  if tg_nargs > 0 then
    for i in 0 .. tg_nargs - 1 loop
      if v_old ? tg_argv[i] then v_old := jsonb_set(v_old, array[tg_argv[i]], '"***"'); end if;
      if v_new ? tg_argv[i] then v_new := jsonb_set(v_new, array[tg_argv[i]], '"***"'); end if;
    end loop;
  end if;

  -- ไม่บันทึก UPDATE ที่ไม่มีอะไรเปลี่ยนนอกจาก updated_at
  if tg_op = 'UPDATE' and (v_old - 'updated_at') = (v_new - 'updated_at') then
    return null;
  end if;

  v_row := coalesce(v_new, v_old);
  v_company := case
    when tg_table_name = 'companies' then (v_row ->> 'id')::uuid
    else (v_row ->> 'company_id')::uuid
  end;
  v_branch := case
    when tg_table_name = 'branches' then (v_row ->> 'id')::uuid
    else (v_row ->> 'branch_id')::uuid
  end;
  v_record := case
    when v_row ? 'id' then (v_row ->> 'id')::uuid
    else null
  end;

  perform private.write_audit(
    p_action     => tg_op,
    p_company_id => v_company,
    p_branch_id  => v_branch,
    p_table_name => tg_table_name,
    p_record_id  => v_record,
    p_old_values => v_old,
    p_new_values => v_new
  );
  return null;
end;
$$;

comment on function private.tg_audit() is
  'AFTER INSERT/UPDATE/DELETE: บันทึก old/new ลง audit_logs; TG_ARGV = คอลัมน์ที่ปิดบัง';

-- ผูก trigger กับตารางข้อมูลหลักของ Phase 1
create trigger companies_audit
  after insert or update or delete on public.companies
  for each row execute function private.tg_audit();

create trigger company_settings_audit
  after insert or update or delete on public.company_settings
  for each row execute function private.tg_audit();

create trigger branches_audit
  after insert or update or delete on public.branches
  for each row execute function private.tg_audit();

create trigger company_memberships_audit
  after insert or update or delete on public.company_memberships
  for each row execute function private.tg_audit();

create trigger branch_memberships_audit
  after insert or update or delete on public.branch_memberships
  for each row execute function private.tg_audit();
