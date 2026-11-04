-- =============================================================================
-- Phase 1 / 006 — document_sequences และการออกเลขเอกสาร
-- =============================================================================
-- รอบเลขรัน (period_key):
--   YEAR (YYYY)     : INV, RCP, RFD และเอกสารการเงินอื่น
--   DAY  (YYYYMMDD) : BKG (Booking Code), QUE (เลขคิว)
-- รูปแบบ:
--   INV-{branch_code}-{YYYY}-{NNNNNN}
--   RCP-{branch_code}-{YYYY}-{NNNNNN}
--   BKG-{branch_code}-{YYYYMMDD}-{NNNN}
--   QUE = เลขจำนวนเต็มรายวัน (ใช้ private.next_sequence_value โดยตรง)
-- เลขไม่ข้าม: เพิ่มค่าด้วย INSERT .. ON CONFLICT DO UPDATE .. RETURNING
-- ภายใน Transaction เดียวกับเอกสาร ถ้า rollback เลขจะถูกคืนด้วย

create table public.document_sequences (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null,
  branch_id    uuid not null,
  doc_type     text not null check (doc_type ~ '^[A-Z]{3}$'),
  period_key   text not null check (period_key ~ '^[0-9]{4}([0-9]{4})?$'),
  last_number  bigint not null default 0 check (last_number >= 0),
  created_at   timestamptz not null default now(),
  created_by   uuid references public.profiles (id),
  updated_at   timestamptz not null default now(),
  constraint document_sequences_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint document_sequences_key unique (company_id, branch_id, doc_type, period_key)
);

comment on table public.document_sequences is
  'เลขรันเอกสารต่อสาขา/ประเภท/รอบ ห้ามลดค่าหรือนำเลขกลับมาใช้';

create trigger document_sequences_stamp
  before insert or update on public.document_sequences
  for each row execute function private.tg_stamp();

-- ห้ามลดเลข / ห้ามเปลี่ยน key / ห้ามลบ
create or replace function private.tg_document_sequences_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'ห้ามลบ document_sequences' using errcode = 'insufficient_privilege';
  end if;
  if new.company_id <> old.company_id or new.branch_id <> old.branch_id
     or new.doc_type <> old.doc_type or new.period_key <> old.period_key then
    raise exception 'ห้ามเปลี่ยน key ของ document_sequences' using errcode = 'check_violation';
  end if;
  if new.last_number < old.last_number then
    raise exception 'ห้ามลดเลขรันเอกสาร' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger document_sequences_guard
  before update or delete on public.document_sequences
  for each row execute function private.tg_document_sequences_guard();

-- -----------------------------------------------------------------------------
-- รอบของเอกสารแต่ละประเภท
-- -----------------------------------------------------------------------------
create or replace function private.document_period_kind(p_doc_type text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_doc_type in ('BKG', 'QUE') then 'DAY'
    else 'YEAR'
  end;
$$;

-- -----------------------------------------------------------------------------
-- private.next_sequence_value: เพิ่มเลขและคืนค่าใหม่ (ล็อกแถวจนจบ Transaction)
-- ไม่เปิดให้ client เรียกตรง — ใช้จาก Function ธุรกรรมใน Phase ถัดไปเท่านั้น
-- -----------------------------------------------------------------------------
create or replace function private.next_sequence_value(
  p_company_id uuid,
  p_branch_id  uuid,
  p_doc_type   text,
  p_at         timestamptz default now()
)
returns table (seq_value bigint, period_key text, branch_code text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tz      text;
  v_code    text;
  v_period  text;
  v_value   bigint;
begin
  if p_doc_type is null or p_doc_type !~ '^[A-Z]{3}$' then
    raise exception 'doc_type ไม่ถูกต้อง: %', p_doc_type using errcode = 'invalid_parameter_value';
  end if;

  select b.code, s.timezone
    into v_code, v_tz
    from public.branches b
    join public.company_settings s on s.company_id = b.company_id
   where b.id = p_branch_id
     and b.company_id = p_company_id;

  if v_code is null then
    raise exception 'ไม่พบสาขาในบริษัทนี้' using errcode = 'foreign_key_violation';
  end if;

  v_period := to_char(
    p_at at time zone v_tz,
    case private.document_period_kind(p_doc_type) when 'DAY' then 'YYYYMMDD' else 'YYYY' end
  );

  insert into public.document_sequences as ds (company_id, branch_id, doc_type, period_key, last_number)
  values (p_company_id, p_branch_id, p_doc_type, v_period, 1)
  on conflict on constraint document_sequences_key
  do update set last_number = ds.last_number + 1
  returning ds.last_number into v_value;

  seq_value := v_value;
  period_key := v_period;
  branch_code := v_code;
  return next;
end;
$$;

revoke all on function private.next_sequence_value(uuid, uuid, text, timestamptz) from public;

-- -----------------------------------------------------------------------------
-- private.next_document_number: คืนเลขเอกสารที่จัดรูปแบบแล้ว
-- -----------------------------------------------------------------------------
create or replace function private.next_document_number(
  p_company_id uuid,
  p_branch_id  uuid,
  p_doc_type   text,
  p_at         timestamptz default now()
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_width int;
begin
  if p_doc_type = 'QUE' then
    raise exception 'เลขคิวใช้ private.next_sequence_value' using errcode = 'invalid_parameter_value';
  end if;

  select * into r from private.next_sequence_value(p_company_id, p_branch_id, p_doc_type, p_at);

  v_width := case private.document_period_kind(p_doc_type) when 'DAY' then 4 else 6 end;
  if r.seq_value >= power(10, v_width) then
    raise exception 'เลขเอกสาร % เกินจำนวนหลักที่กำหนด (%)', p_doc_type, v_width
      using errcode = 'numeric_value_out_of_range';
  end if;

  return format('%s-%s-%s-%s', p_doc_type, r.branch_code, r.period_key, lpad(r.seq_value::text, v_width, '0'));
end;
$$;

revoke all on function private.next_document_number(uuid, uuid, text, timestamptz) from public;

-- -----------------------------------------------------------------------------
-- branch.code แก้ไม่ได้หลังสาขามีเอกสารแล้ว (code อยู่ในเลขเอกสาร)
-- -----------------------------------------------------------------------------
create or replace function private.tg_branches_code_lock()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.code <> old.code and exists (
    select 1 from public.document_sequences ds
     where ds.branch_id = old.id and ds.last_number > 0
  ) then
    raise exception 'สาขานี้ออกเอกสารแล้ว ไม่สามารถเปลี่ยนรหัสสาขาได้'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger branches_code_lock
  before update of code on public.branches
  for each row execute function private.tg_branches_code_lock();
