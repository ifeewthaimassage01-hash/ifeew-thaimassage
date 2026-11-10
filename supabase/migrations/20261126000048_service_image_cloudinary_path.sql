-- =============================================================================
-- 048 — แก้เพิ่มรูปบริการไม่ได้ ("ตำแหน่งรูปบริการไม่ถูกต้อง") หลังย้ายรูปไป Cloudinary
--   services.image_path รับได้ 2 แบบ:
--     - Supabase Storage เดิม : <company_id>/<service_id>/<file>
--     - Cloudinary           : cloudinary:ifeew/<company_id>/services/<service_id>/<public_id>
--   ยังตรวจว่า company_id / service_id ใน path ตรงกับแถวเสมอ (กันใช้รูปของร้าน/บริการอื่น)
-- =============================================================================

alter table public.services drop constraint if exists services_image_path_check;
alter table public.services add constraint services_image_path_check check (
  image_path is null
  or image_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,100}$'
  or image_path ~ '^cloudinary:ifeew/[0-9a-f-]{36}/services/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,100}$'
);

create or replace function private.tg_services_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.company_id <> old.company_id then
    raise exception 'ห้ามย้ายข้อมูลข้ามบริษัท' using errcode = 'check_violation';
  end if;
  -- แยก IF ตามตาราง เพื่อไม่อ้างคอลัมน์ที่ตารางนั้นไม่มี
  if tg_table_name = 'services' then
    if new.image_path is not null then
      if new.image_path like 'cloudinary:%' then
        -- cloudinary:ifeew/<company>/services/<service>/<id>
        if split_part(new.image_path, '/', 2) <> new.company_id::text
           or split_part(new.image_path, '/', 3) <> 'services'
           or split_part(new.image_path, '/', 4) <> new.id::text then
          raise exception 'ตำแหน่งรูปบริการไม่ถูกต้อง' using errcode = 'check_violation';
        end if;
      elsif split_part(new.image_path, '/', 1) <> new.company_id::text
            or split_part(new.image_path, '/', 2) <> new.id::text then
        raise exception 'ตำแหน่งรูปบริการไม่ถูกต้อง' using errcode = 'check_violation';
      end if;
    end if;
  elsif tg_table_name = 'branch_services' then
    if tg_op = 'UPDATE' then
      if new.branch_id <> old.branch_id or new.service_id <> old.service_id then
        raise exception 'ห้ามเปลี่ยนสาขา/บริการของรายการเดิม' using errcode = 'check_violation';
      end if;
    end if;
  elsif tg_table_name = 'branch_service_options' then
    if tg_op = 'UPDATE' then
      if new.branch_service_id <> old.branch_service_id or new.duration_minutes <> old.duration_minutes then
        raise exception 'ห้ามเปลี่ยนนาทีของช่วงเวลาเดิม ให้ปิดแล้วเพิ่มช่วงใหม่' using errcode = 'check_violation';
      end if;
    end if;
  end if;
  return new;
end;
$$;
