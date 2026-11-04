-- =============================================================================
-- Phase 1 / 002 — profiles (1:1 กับ auth.users)
-- =============================================================================
-- profiles เก็บข้อมูลแสดงผลของผู้ใช้ทุกประเภท (OWNER, STAFF, CUSTOMER)
-- ห้ามเก็บ role ที่นี่ — role มาจาก company_memberships เท่านั้น
-- ไม่ลบแถว: ข้อมูลส่วนบุคคลจะถูก anonymize ตามนโยบาย PDPA (Phase 3)

create table public.profiles (
  id            uuid primary key references auth.users (id) on delete restrict,
  display_name  text not null default '' check (char_length(display_name) <= 120),
  phone         text check (phone is null or phone ~ '^[0-9+\-\s]{6,20}$'),
  avatar_path   text check (avatar_path is null or char_length(avatar_path) <= 300),
  created_at    timestamptz not null default now(),
  created_by    uuid references public.profiles (id),
  updated_at    timestamptz not null default now()
);

comment on table public.profiles is 'ข้อมูลแสดงผลของผู้ใช้ 1:1 กับ auth.users';

create trigger profiles_stamp
  before insert or update on public.profiles
  for each row execute function private.tg_stamp();

-- สร้าง profile อัตโนมัติเมื่อมีผู้ใช้ใหม่ใน auth.users
-- อ่านเฉพาะ display_name จาก metadata (ข้อมูลแสดงผล ไม่มีผลต่อสิทธิ์)
create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, created_by)
  values (
    new.id,
    left(coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), ''), 120),
    new.id
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_auth_user();
