-- =============================================================================
-- Phase 1 / 001 — Extensions, private schema และ Trigger พื้นฐาน
-- =============================================================================
-- private schema: เก็บ helper function ที่ไม่เปิดผ่าน Data API (PostgREST เปิดแค่ public)

create extension if not exists pgcrypto with schema extensions;
create extension if not exists btree_gist with schema extensions;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- tg_stamp: ตั้ง created_at/created_by/updated_at ฝั่ง Database
--  - INSERT: created_by = auth.uid() เสมอเมื่อมีผู้ใช้ (ไม่เชื่อค่าจาก client)
--            ถ้าไม่มี auth.uid() (service role / seed) ใช้ค่าที่ส่งมา
--  - UPDATE: ห้ามเปลี่ยน created_at/created_by และตั้ง updated_at = now()
-- -----------------------------------------------------------------------------
create or replace function private.tg_stamp()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
    new.updated_at := now();
    if auth.uid() is not null then
      new.created_by := auth.uid();
    end if;
  elsif tg_op = 'UPDATE' then
    new.created_at := old.created_at;
    new.created_by := old.created_by;
    new.updated_at := now();
  end if;
  return new;
end;
$$;

comment on function private.tg_stamp() is
  'BEFORE INSERT/UPDATE: บังคับ created_at, created_by, updated_at ฝั่ง DB';

-- ตรวจรหัส (company.code / branch.code)
create or replace function private.is_valid_code(p_code text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_code ~ '^[A-Z0-9]{2,10}$';
$$;
