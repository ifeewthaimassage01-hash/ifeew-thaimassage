-- =============================================================================
-- 036 — รูปสาขา
--   - branches.image_path: path ใน bucket branch-images ({company_id}/{branch_id}/{file})
--   - bucket branch-images: public (ลูกค้าเห็นได้โดยไม่ login), อัปโหลด/แก้/ลบได้เฉพาะ OWNER ของบริษัท
--   เขียนแบบรันซ้ำได้ (if not exists / drop policy if exists)
-- =============================================================================

alter table public.branches add column if not exists image_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('branch-images', 'branch-images', true, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- โฟลเดอร์ต้องเป็น {company_id}/{branch_id} ของสาขาที่มีอยู่จริงในบริษัทนั้น
create or replace function private.is_branch_image_folder(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.branches b
     where b.company_id = private.try_uuid(split_part(p_name, '/', 1))
       and b.id = private.try_uuid(split_part(p_name, '/', 2))
  );
$$;

revoke all on function private.is_branch_image_folder(text) from public;
grant execute on function private.is_branch_image_folder(text) to authenticated, service_role;

drop policy if exists branch_images_insert_owner on storage.objects;
create policy branch_images_insert_owner on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'branch-images'
    and private.is_company_owner(private.try_uuid(split_part(name, '/', 1)))
    and private.is_branch_image_folder(name)
  );

drop policy if exists branch_images_update_owner on storage.objects;
create policy branch_images_update_owner on storage.objects
  for update to authenticated
  using (bucket_id = 'branch-images' and private.is_company_owner(private.try_uuid(split_part(name, '/', 1))))
  with check (
    bucket_id = 'branch-images'
    and private.is_company_owner(private.try_uuid(split_part(name, '/', 1)))
    and private.is_branch_image_folder(name)
  );

drop policy if exists branch_images_delete_owner on storage.objects;
create policy branch_images_delete_owner on storage.objects
  for delete to authenticated
  using (bucket_id = 'branch-images' and private.is_company_owner(private.try_uuid(split_part(name, '/', 1))));

-- ลูกค้าที่ไม่ login อ่าน branches ได้เฉพาะคอลัมน์ที่ให้สิทธิ์ (migration 010) — เพิ่ม image_path
grant select (image_path) on public.branches to anon;
