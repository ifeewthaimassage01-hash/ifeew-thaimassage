-- =============================================================================
-- Phase 2 / 015 — Storage bucket รูปพนักงาน (private)
-- =============================================================================
-- path: {company_id}/{employee_id}/{file}
-- อ่าน: สมาชิกบริษัท | เขียน/ลบ: OWNER ของบริษัท
-- เครื่องประจำสาขา (ยังไม่มี session) ได้ signed URL จาก Edge Function device-staff-list

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('employee-photos', 'employee-photos', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- แปลงข้อความเป็น uuid แบบไม่ error (คืน NULL ถ้าไม่ใช่ uuid)
create or replace function private.try_uuid(p_value text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
begin
  return p_value::uuid;
exception when invalid_text_representation then
  return null;
end;
$$;

grant execute on function private.try_uuid(text) to authenticated, service_role;

-- รูปต้องอยู่ใต้โฟลเดอร์ของพนักงานในบริษัทนั้นจริง
create or replace function private.is_employee_photo_folder(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.employees e
     where e.company_id = private.try_uuid(split_part(p_name, '/', 1))
       and e.id = private.try_uuid(split_part(p_name, '/', 2))
  );
$$;

revoke all on function private.is_employee_photo_folder(text) from public;
grant execute on function private.is_employee_photo_folder(text) to authenticated, service_role;

create policy employee_photos_select_member on storage.objects
  for select to authenticated
  using (
    bucket_id = 'employee-photos'
    and private.is_company_member(private.try_uuid(split_part(name, '/', 1)))
  );

create policy employee_photos_insert_owner on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'employee-photos'
    and private.is_company_owner(private.try_uuid(split_part(name, '/', 1)))
    and private.is_employee_photo_folder(name)
  );

create policy employee_photos_update_owner on storage.objects
  for update to authenticated
  using (
    bucket_id = 'employee-photos'
    and private.is_company_owner(private.try_uuid(split_part(name, '/', 1)))
  )
  with check (
    bucket_id = 'employee-photos'
    and private.is_company_owner(private.try_uuid(split_part(name, '/', 1)))
    and private.is_employee_photo_folder(name)
  );

create policy employee_photos_delete_owner on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'employee-photos'
    and private.is_company_owner(private.try_uuid(split_part(name, '/', 1)))
  );
