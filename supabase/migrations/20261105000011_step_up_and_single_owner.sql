-- =============================================================================
-- Phase 2 / 011 — Step-up TOTP และ OWNER คนเดียวต่อบริษัท
-- =============================================================================

-- OWNER ได้คนเดียวต่อบริษัท (ข้อตกลง Phase 2 ข้อ 10)
create unique index company_memberships_one_active_owner
  on public.company_memberships (company_id)
  where role = 'OWNER' and status = 'ACTIVE';

-- -----------------------------------------------------------------------------
-- private.has_recent_mfa: JWT ปัจจุบันยืนยัน TOTP ภายใน N วินาที
-- Supabase ใส่ claim amr = [{ "method": "totp", "timestamp": <unix> }, ...]
-- การยืนยันซ้ำ (mfa.challengeAndVerify) จะออก token ใหม่ที่ timestamp ล่าสุด
-- -----------------------------------------------------------------------------
create or replace function private.has_recent_mfa(p_max_age_seconds integer default 300)
returns boolean
language sql
stable
set search_path = ''
as $$
  select private.current_aal() = 'aal2'
     and exists (
       select 1
         from jsonb_array_elements(
                case when jsonb_typeof(auth.jwt() -> 'amr') = 'array' then auth.jwt() -> 'amr' else '[]'::jsonb end
              ) a
        where a ->> 'method' = 'totp'
          and (a ->> 'timestamp') ~ '^[0-9]+$'
          and (a ->> 'timestamp')::bigint >= extract(epoch from now())::bigint - p_max_age_seconds
     );
$$;

-- -----------------------------------------------------------------------------
-- private.require_owner_step_up: ใช้ในทุก Function เสี่ยงสูง
-- ข้อความ STEP_UP_REQUIRED ให้ Frontend เปิดหน้าต่างยืนยันรหัส Authenticator
-- -----------------------------------------------------------------------------
create or replace function private.require_owner_step_up(p_company_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_company_id is null or not private.is_company_owner(p_company_id) then
    raise exception 'ไม่มีสิทธิ์ดำเนินการ' using errcode = 'insufficient_privilege';
  end if;
  if not private.has_recent_mfa(300) then
    raise exception 'STEP_UP_REQUIRED'
      using errcode = 'insufficient_privilege',
            detail = 'กรุณายืนยันรหัสจากแอป Authenticator อีกครั้ง';
  end if;
end;
$$;

revoke all on function private.has_recent_mfa(integer) from public;
revoke all on function private.require_owner_step_up(uuid) from public;
grant execute on function private.has_recent_mfa(integer) to authenticated, service_role;
grant execute on function private.require_owner_step_up(uuid) to authenticated, service_role;

-- ให้ Edge Function ตรวจสิทธิ์ล่วงหน้าก่อนสร้างบัญชีใน Auth
create or replace function public.assert_can_manage_staff(p_company_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_owner_step_up(p_company_id);
end;
$$;

revoke all on function public.assert_can_manage_staff(uuid) from public, anon;
grant execute on function public.assert_can_manage_staff(uuid) to authenticated;
