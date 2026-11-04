-- =============================================================================
-- Phase 9 / 025 — สร้างบริษัทแรกบน Production (เรียกจาก tools/bootstrap ด้วย service role เท่านั้น)
--   ผู้ใช้ OWNER ต้องถูกเชิญผ่าน Supabase Auth ก่อน (ตั้งรหัสผ่านเองจากอีเมล แล้วผูก TOTP ตอน login ครั้งแรก)
--   p_payload = {
--     "company": { "code": "IFEEW", "name": "...", "legal_name": "...", "tax_id": "..." },
--     "owner_display_name": "...",
--     "branches": [ { "code": "SKV", "name": "...", "address": "...", "phone": "..." }, ... ],
--     "policies": [ { "type": "PRIVACY_NOTICE", "version": "1.0", "title": "...", "content": "..." },
--                   { "type": "MARKETING", ... } ]
--   }
-- =============================================================================

create or replace function public.bootstrap_company(p_payload jsonb, p_owner_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid;
  v_code    text := upper(trim(p_payload -> 'company' ->> 'code'));
  b         jsonb;
  p         jsonb;
begin
  if not exists (select 1 from auth.users where id = p_owner_user_id) then
    raise exception 'ไม่พบผู้ใช้ OWNER ใน Auth (ต้องเชิญก่อน)' using errcode = 'invalid_parameter_value';
  end if;
  if exists (select 1 from public.companies where upper(code) = v_code) then
    raise exception 'มีบริษัทรหัส % แล้ว' , v_code using errcode = 'unique_violation';
  end if;
  if exists (select 1 from public.company_memberships where user_id = p_owner_user_id) then
    raise exception 'ผู้ใช้นี้เป็นสมาชิกบริษัทอื่นอยู่แล้ว' using errcode = 'check_violation';
  end if;
  if jsonb_typeof(p_payload -> 'branches') <> 'array' or jsonb_array_length(p_payload -> 'branches') = 0 then
    raise exception 'ต้องมีสาขาอย่างน้อย 1 สาขา' using errcode = 'invalid_parameter_value';
  end if;
  if not exists (select 1 from jsonb_array_elements(coalesce(p_payload -> 'policies', '[]')) x
                  where x ->> 'type' = 'PRIVACY_NOTICE' and char_length(coalesce(x ->> 'content', '')) >= 50) then
    raise exception 'ต้องมีนโยบายความเป็นส่วนตัว (PRIVACY_NOTICE) ฉบับจริง' using errcode = 'invalid_parameter_value';
  end if;

  insert into public.companies (code, name, legal_name, tax_id, created_by)
  values (v_code, trim(p_payload -> 'company' ->> 'name'), nullif(trim(p_payload -> 'company' ->> 'legal_name'), ''),
          nullif(trim(p_payload -> 'company' ->> 'tax_id'), ''), p_owner_user_id)
  returning id into v_company;

  insert into public.company_memberships (company_id, user_id, role, created_by)
  values (v_company, p_owner_user_id, 'OWNER', p_owner_user_id);

  update public.profiles set display_name = coalesce(nullif(trim(p_payload ->> 'owner_display_name'), ''), display_name)
   where id = p_owner_user_id;

  for b in select * from jsonb_array_elements(p_payload -> 'branches') loop
    insert into public.branches (company_id, code, name, address, phone, sort_order, created_by)
    values (v_company, upper(trim(b ->> 'code')), trim(b ->> 'name'), nullif(trim(b ->> 'address'), ''),
            nullif(trim(b ->> 'phone'), ''), coalesce((b ->> 'sort_order')::int, 0), p_owner_user_id);
  end loop;

  for p in select * from jsonb_array_elements(coalesce(p_payload -> 'policies', '[]')) loop
    insert into public.privacy_policy_versions (company_id, policy_type, version, title, content, published_at)
    values (v_company, p ->> 'type', p ->> 'version', p ->> 'title', p ->> 'content', now());
  end loop;

  perform private.write_audit(p_action => 'COMPANY_BOOTSTRAPPED', p_company_id => v_company,
                              p_table_name => 'companies', p_record_id => v_company, p_actor => p_owner_user_id);
  return v_company;
end;
$$;

revoke all on function public.bootstrap_company(jsonb, uuid) from public, anon, authenticated;
grant execute on function public.bootstrap_company(jsonb, uuid) to service_role;
