-- =============================================================================
-- Phase 1 / 008 — Helper ตรวจสิทธิ์ (ใช้ใน RLS และ Function)
-- =============================================================================
-- ทุก helper เป็น SECURITY DEFINER + search_path = '' เพื่ออ่านตาราง membership
-- โดยไม่ติด RLS ของตัวเอง (กัน recursion) และคืนค่าเฉพาะของ auth.uid() ปัจจุบัน

-- ระดับการยืนยันตัวตนของ session ปัจจุบัน ('aal1' | 'aal2')
create or replace function private.current_aal()
returns text
language sql
stable
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'aal', 'aal1');
$$;

-- สมาชิกบริษัทที่ ACTIVE และอยู่ในช่วงเวลา (role ใดก็ได้)
create or replace function private.is_company_member(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.company_memberships cm
     where cm.company_id = p_company_id
       and cm.user_id = auth.uid()
       and cm.status = 'ACTIVE'
       and cm.effective_from <= now()
       and (cm.effective_to is null or cm.effective_to > now())
  );
$$;

-- OWNER ของบริษัท — ต้องผ่าน MFA (aal2) แล้วเท่านั้น
create or replace function private.is_company_owner(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.current_aal() = 'aal2'
     and exists (
       select 1
         from public.company_memberships cm
        where cm.company_id = p_company_id
          and cm.user_id = auth.uid()
          and cm.role = 'OWNER'
          and cm.status = 'ACTIVE'
          and cm.effective_from <= now()
          and (cm.effective_to is null or cm.effective_to > now())
     );
$$;

-- เข้าถึงสาขาได้: OWNER (aal2) ของบริษัท หรือ STAFF ที่มี branch_membership ACTIVE ณ ตอนนี้
create or replace function private.has_branch_access(p_branch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.branches b
     where b.id = p_branch_id
       and (
         private.is_company_owner(b.company_id)
         or exists (
           select 1
             from public.branch_memberships bm
             join public.company_memberships cm
               on cm.company_id = bm.company_id and cm.user_id = bm.user_id
            where bm.branch_id = b.id
              and bm.user_id = auth.uid()
              and bm.status = 'ACTIVE'
              and bm.effective_from <= now()
              and (bm.effective_to is null or bm.effective_to > now())
              and cm.status = 'ACTIVE'
              and cm.effective_from <= now()
              and (cm.effective_to is null or cm.effective_to > now())
         )
       )
  );
$$;

-- ผู้ใช้ปัจจุบันกับผู้ใช้อื่นอยู่บริษัทเดียวกัน (ใช้ให้เห็นชื่อเพื่อนร่วมงาน)
create or replace function private.shares_company_with(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.company_memberships me
      join public.company_memberships other
        on other.company_id = me.company_id
     where me.user_id = auth.uid()
       and other.user_id = p_user_id
       and me.status = 'ACTIVE'
       and me.effective_from <= now()
       and (me.effective_to is null or me.effective_to > now())
  );
$$;

revoke all on function private.is_company_member(uuid) from public;
revoke all on function private.is_company_owner(uuid) from public;
revoke all on function private.has_branch_access(uuid) from public;
revoke all on function private.shares_company_with(uuid) from public;
revoke all on function private.current_aal() from public;
grant execute on function private.is_company_member(uuid) to authenticated, service_role;
grant execute on function private.is_company_owner(uuid) to authenticated, service_role;
grant execute on function private.has_branch_access(uuid) to authenticated, service_role;
grant execute on function private.shares_company_with(uuid) to authenticated, service_role;
grant execute on function private.current_aal() to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- public.my_access(): สรุปสิทธิ์ของผู้ใช้ปัจจุบันให้ Frontend ใช้แสดงเมนู
-- (ใช้แสดงผลเท่านั้น การบังคับสิทธิ์จริงอยู่ที่ RLS)
-- -----------------------------------------------------------------------------
create or replace function public.my_access()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'user_id', auth.uid(),
    'aal', private.current_aal(),
    'companies', coalesce((
      select jsonb_agg(jsonb_build_object(
        'company_id', c.id,
        'company_code', c.code,
        'company_name', c.name,
        'role', cm.role,
        'owner_mfa_required', cm.role = 'OWNER' and private.current_aal() <> 'aal2',
        'branches', coalesce((
          select jsonb_agg(jsonb_build_object('branch_id', b.id, 'code', b.code, 'name', b.name)
                           order by b.sort_order, b.name)
            from public.branches b
           where b.company_id = c.id
             and b.is_active
             and private.has_branch_access(b.id)
        ), '[]'::jsonb)
      ) order by c.name)
        from public.company_memberships cm
        join public.companies c on c.id = cm.company_id
       where cm.user_id = auth.uid()
         and cm.status = 'ACTIVE'
         and cm.effective_from <= now()
         and (cm.effective_to is null or cm.effective_to > now())
         and c.is_active
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.my_access() from public, anon;
grant execute on function public.my_access() to authenticated;
