-- ล็อกพื้นที่เข้าระบบ: ใช้ GPS อย่างเดียว (เลิกใช้ IP Wi-Fi ร้าน)
alter table public.branch_login_locks drop constraint branch_login_locks_method_chk;
alter table public.branch_login_locks drop column allowed_ips;
alter table public.branch_login_locks add constraint branch_login_locks_method_chk
  check (not enabled or latitude is not null);

create or replace function public.login_location_rule(p_company_code text, p_branch_id uuid, p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('latitude', l.latitude, 'longitude', l.longitude, 'radius_m', l.radius_m)
    from public.branch_login_locks l
   where l.branch_id = p_branch_id
     and l.company_id = private.company_id_by_code(p_company_code)
     and l.enabled
     and not exists (
       select 1 from public.company_memberships cm
        where cm.company_id = l.company_id and cm.user_id = p_user_id and cm.role = 'OWNER' and cm.status = 'ACTIVE'
          and cm.effective_from <= now() and (cm.effective_to is null or cm.effective_to > now()));
$$;

create or replace function public.login_branch_lock_hint(p_company_code text, p_branch_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('enabled', coalesce(l.enabled, false), 'gps', coalesce(l.enabled, false))
    from (select 1) x
    left join public.branch_login_locks l
      on l.branch_id = p_branch_id and l.company_id = private.company_id_by_code(p_company_code);
$$;
