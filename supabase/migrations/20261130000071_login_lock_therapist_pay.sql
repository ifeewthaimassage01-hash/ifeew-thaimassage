-- 1) ปิดช่องโหว่: policy ที่ถูกเพิ่มเองใน Dashboard ให้ผู้ใช้ที่ล็อกอินทุกคน (รวมลูกค้า) แก้ข้อมูลสาขาได้
--    (เจ้าของแก้ได้ผ่าน branches_update_owner อยู่แล้ว)
drop policy if exists "Allow authenticated users to update branches" on public.branches;

-- 2) ล็อกการเข้าระบบพนักงานตามพื้นที่ร้าน (ต่อสาขา)
--    ผ่านเมื่อ IP อยู่ในรายการ (Wi-Fi ร้าน) หรือ GPS อยู่ในรัศมีจากร้าน · เจ้าของร้านและเครื่องที่ผูกกับสาขาไม่ถูกล็อก
--    ตรวจใน Edge Function staff-pin-login ก่อนตรวจ PIN
create table public.branch_login_locks (
  branch_id    uuid primary key references public.branches (id) on delete cascade,
  company_id   uuid not null references public.companies (id) on delete cascade,
  enabled      boolean not null default false,
  allowed_ips  text[] not null default '{}'
               check (cardinality(allowed_ips) <= 20),
  latitude     double precision check (latitude between -90 and 90),
  longitude    double precision check (longitude between -180 and 180),
  radius_m     integer not null default 150 check (radius_m between 30 and 2000),
  updated_at   timestamptz not null default now(),
  updated_by   uuid references public.profiles (id),
  constraint branch_login_locks_point_chk check ((latitude is null) = (longitude is null)),
  -- เปิดล็อกแล้วต้องมีอย่างน้อยหนึ่งวิธี ไม่อย่างนั้นไม่มีใครเข้าได้
  constraint branch_login_locks_method_chk check (not enabled or cardinality(allowed_ips) > 0 or latitude is not null)
);

alter table public.branch_login_locks enable row level security;
create policy branch_login_locks_select_owner on public.branch_login_locks
  for select to authenticated using (private.is_company_owner(company_id));
create policy branch_login_locks_insert_owner on public.branch_login_locks
  for insert to authenticated with check (
    private.is_company_owner(company_id)
    and exists (select 1 from public.branches b where b.id = branch_id and b.company_id = branch_login_locks.company_id));
create policy branch_login_locks_update_owner on public.branch_login_locks
  for update to authenticated using (private.is_company_owner(company_id)) with check (private.is_company_owner(company_id));
grant select, insert, update on public.branch_login_locks to authenticated;

create or replace function private.tg_branch_login_locks_stamp()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$$;
create trigger branch_login_locks_stamp before insert or update on public.branch_login_locks
  for each row execute function private.tg_branch_login_locks_stamp();
create trigger branch_login_locks_audit after insert or update or delete on public.branch_login_locks
  for each row execute function private.tg_audit();

-- กฎที่ต้องตรวจตอนพนักงานเข้าระบบ · null = ไม่ต้องตรวจ (ไม่ได้เปิด / เป็นเจ้าของร้าน)
create or replace function public.login_location_rule(p_company_code text, p_branch_id uuid, p_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('allowed_ips', l.allowed_ips, 'latitude', l.latitude, 'longitude', l.longitude, 'radius_m', l.radius_m)
    from public.branch_login_locks l
   where l.branch_id = p_branch_id
     and l.company_id = private.company_id_by_code(p_company_code)
     and l.enabled
     and not exists (
       select 1 from public.company_memberships cm
        where cm.company_id = l.company_id and cm.user_id = p_user_id and cm.role = 'OWNER' and cm.status = 'ACTIVE'
          and cm.effective_from <= now() and (cm.effective_to is null or cm.effective_to > now()));
$$;
revoke all on function public.login_location_rule(text, uuid, uuid) from public, anon, authenticated;
grant execute on function public.login_location_rule(text, uuid, uuid) to service_role;

-- หน้า login: ต้องขอตำแหน่ง GPS ไหม (ไม่เปิดเผย IP / พิกัดร้าน)
create or replace function public.login_branch_lock_hint(p_company_code text, p_branch_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('enabled', coalesce(l.enabled, false), 'gps', coalesce(l.enabled and l.latitude is not null, false))
    from (select 1) x
    left join public.branch_login_locks l
      on l.branch_id = p_branch_id and l.company_id = private.company_id_by_code(p_company_code);
$$;
revoke all on function public.login_branch_lock_hint(text, uuid) from public, anon, authenticated;
grant execute on function public.login_branch_lock_hint(text, uuid) to service_role;

-- 3) ค่าแรงหมอ (ค่ามือ + ทิป) — แทนหน้าระบบคอมมิชชันที่เอาออก
--    สรุปรายหมอ: เพิ่มทิป และรวมหมอที่มีแต่ทิป
create or replace function public.therapist_work_summary(p_company_id uuid, p_branch_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then
    raise exception 'ช่วงวันที่ต้องไม่เกิน 1 ปี' using errcode = 'invalid_parameter_value';
  end if;

  return coalesce((
    with s as (
      select a.employee_id,
             count(distinct a.queue_item_id) as services,
             coalesce(round(sum(extract(epoch from (a.completed_at - a.started_at))) / 60), 0)::int as worked_minutes,
             count(*) filter (where a.off_shift_confirmed) as off_shift_count,
             count(*) filter (where a.handover_reason is not null) as handover_count,
             coalesce(sum(private.assignment_fee(a.id)), 0) as fee_estimate
        from public.service_assignments a
        join public.queue_items q on q.id = a.queue_item_id
       where a.company_id = p_company_id
         and (p_branch_id is null or a.branch_id = p_branch_id)
         and a.status = 'COMPLETED' and q.status = 'COMPLETED'
         and q.queue_date between p_from and p_to
       group by a.employee_id
    ),
    t as (
      select t.employee_id, sum(t.amount) as tips
        from public.tips t
       where t.company_id = p_company_id
         and (p_branch_id is null or t.branch_id = p_branch_id)
         and t.status <> 'VOID'
         and (t.created_at at time zone 'Asia/Bangkok')::date between p_from and p_to
       group by t.employee_id
    ),
    x as (
      select coalesce(s.employee_id, t.employee_id) as employee_id,
             coalesce(s.services, 0) as services, coalesce(s.worked_minutes, 0) as worked_minutes,
             coalesce(s.off_shift_count, 0) as off_shift_count, coalesce(s.handover_count, 0) as handover_count,
             coalesce(s.fee_estimate, 0) as fee_estimate, coalesce(t.tips, 0) as tips
        from s full join t on t.employee_id = s.employee_id
    )
    select jsonb_agg(jsonb_build_object(
      'employee_id', x.employee_id,
      'employee_code', e.employee_code,
      'nickname', e.nickname,
      'services', x.services,
      'worked_minutes', x.worked_minutes,
      'off_shift_count', x.off_shift_count,
      'handover_count', x.handover_count,
      'fee_estimate', x.fee_estimate,
      'tips', x.tips,
      'pay_total', x.fee_estimate + x.tips
    ) order by x.fee_estimate + x.tips desc, e.nickname)
    from x join public.employees e on e.id = x.employee_id
  ), '[]'::jsonb);
end;
$$;

-- รายวันของหมอหนึ่งคน: ค่ามือ + ทิป ต่อวัน พร้อมงานแต่ละรายการ
create or replace function public.therapist_pay_daily(p_company_id uuid, p_branch_id uuid, p_employee_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then
    raise exception 'ช่วงวันที่ต้องไม่เกิน 1 ปี' using errcode = 'invalid_parameter_value';
  end if;

  return coalesce((
    with jobs as (
      select q.queue_date as d,
             a.started_at,
             i.service_name,
             i.duration_minutes,
             coalesce(private.assignment_fee(a.id), 0) as fee,
             a.handover_reason is not null as handover
        from public.service_assignments a
        join public.queue_items q on q.id = a.queue_item_id
        join public.service_order_items i on i.id = q.service_order_item_id
       where a.company_id = p_company_id
         and a.employee_id = p_employee_id
         and (p_branch_id is null or a.branch_id = p_branch_id)
         and a.status = 'COMPLETED' and q.status = 'COMPLETED'
         and q.queue_date between p_from and p_to
    ),
    tips as (
      select (t.created_at at time zone 'Asia/Bangkok')::date as d, sum(t.amount) as amount
        from public.tips t
       where t.company_id = p_company_id
         and t.employee_id = p_employee_id
         and (p_branch_id is null or t.branch_id = p_branch_id)
         and t.status <> 'VOID'
         and (t.created_at at time zone 'Asia/Bangkok')::date between p_from and p_to
       group by 1
    ),
    days as (select d from jobs union select d from tips)
    select jsonb_agg(jsonb_build_object(
      'date', days.d,
      'services', (select count(*) from jobs where jobs.d = days.d),
      'fee', coalesce((select sum(fee) from jobs where jobs.d = days.d), 0),
      'tips', coalesce((select amount from tips where tips.d = days.d), 0),
      'total', coalesce((select sum(fee) from jobs where jobs.d = days.d), 0) + coalesce((select amount from tips where tips.d = days.d), 0),
      'jobs', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'time', to_char(jobs.started_at at time zone 'Asia/Bangkok', 'HH24:MI'),
                 'service_name', jobs.service_name,
                 'minutes', jobs.duration_minutes,
                 'fee', jobs.fee,
                 'handover', jobs.handover) order by jobs.started_at)
          from jobs where jobs.d = days.d), '[]'::jsonb)
    ) order by days.d desc)
    from days
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.therapist_pay_daily(uuid, uuid, uuid, date, date) from public, anon;
grant execute on function public.therapist_pay_daily(uuid, uuid, uuid, date, date) to authenticated;
