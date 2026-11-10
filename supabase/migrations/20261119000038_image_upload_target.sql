-- =============================================================================
-- 038 — ตรวจสิทธิ์อัปโหลดรูป (Cloudinary)
--   Edge Function cloudinary-sign เรียกด้วย JWT ของผู้ใช้ เพื่อถามว่าอัปโหลดรูปให้บริการ/สาขานี้ได้ไหม
--   ใช้ private.is_company_owner ตัวเดียวกับ RLS ของ services/branches (รวมเงื่อนไข MFA/PIN ของเจ้าของ)
--   คืน company_id ของเป้าหมาย หรือ raise ถ้าไม่มีสิทธิ์
-- =============================================================================

create or replace function public.image_upload_target(p_kind text, p_target_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_company uuid;
begin
  if p_kind = 'service' then
    select company_id into v_company from public.services where id = p_target_id;
  elsif p_kind = 'branch' then
    select company_id into v_company from public.branches where id = p_target_id;
  else
    raise exception 'ประเภทรูปไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;

  if v_company is null or not private.is_company_owner(v_company) then
    raise exception 'ไม่มีสิทธิ์อัปโหลดรูปนี้' using errcode = 'insufficient_privilege';
  end if;
  return v_company;
end;
$$;

revoke all on function public.image_upload_target(text, uuid) from public, anon;
grant execute on function public.image_upload_target(text, uuid) to authenticated;
