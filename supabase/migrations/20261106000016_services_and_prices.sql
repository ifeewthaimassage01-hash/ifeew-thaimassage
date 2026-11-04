-- =============================================================================
-- Phase 3 / 016 — บริการ, ช่วงเวลา, ราคา และค่าแรงหมอนวด
-- =============================================================================
-- service_categories      หมวดหมู่
-- services                บริการกลางของบริษัท (ชื่อไทย/อังกฤษ รูป รายละเอียด)
-- branch_services         บริการที่สาขาเปิดขาย
-- branch_service_options  ช่วงเวลาที่ขายของบริการในสาขา (60, 90, 120 นาที ...)
-- service_price_histories ราคา + ค่าแรงหมอนวด ต่อช่วงเวลา ตามช่วงเวลามีผล (Source of Truth)
-- ราคาเป็นราคารวม ไม่มี VAT, ค่าแรงเห็นเฉพาะ OWNER

-- -----------------------------------------------------------------------------
-- service_categories
-- -----------------------------------------------------------------------------
create table public.service_categories (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies (id) on delete restrict,
  name        text not null check (char_length(trim(name)) between 1 and 100),
  description text check (description is null or char_length(description) <= 500),
  sort_order  integer not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  created_by  uuid references public.profiles (id),
  updated_at  timestamptz not null default now(),
  constraint service_categories_company_id_id_key unique (company_id, id)
);

create unique index service_categories_company_name_key
  on public.service_categories (company_id, lower(trim(name))) where is_active;

-- -----------------------------------------------------------------------------
-- services (บริการกลาง)
-- -----------------------------------------------------------------------------
create table public.services (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null,
  category_id  uuid not null,
  name         text not null check (char_length(trim(name)) between 1 and 150),
  name_en      text check (name_en is null or char_length(name_en) <= 150),
  description  text check (description is null or char_length(description) <= 2000),
  image_path   text check (image_path is null or image_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,100}$'),
  sort_order   integer not null default 0,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  created_by   uuid references public.profiles (id),
  updated_at   timestamptz not null default now(),
  constraint services_category_fk foreign key (company_id, category_id)
    references public.service_categories (company_id, id) on delete restrict,
  constraint services_company_id_id_key unique (company_id, id)
);

create index services_company_idx on public.services (company_id, is_active, sort_order);

-- -----------------------------------------------------------------------------
-- branch_services
-- -----------------------------------------------------------------------------
create table public.branch_services (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null,
  branch_id   uuid not null,
  service_id  uuid not null,
  is_active   boolean not null default true,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  created_by  uuid references public.profiles (id),
  updated_at  timestamptz not null default now(),
  constraint branch_services_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint branch_services_service_fk foreign key (company_id, service_id)
    references public.services (company_id, id) on delete restrict,
  constraint branch_services_branch_service_key unique (branch_id, service_id),
  constraint branch_services_company_id_id_key unique (company_id, id)
);

create index branch_services_branch_idx on public.branch_services (branch_id, is_active, sort_order);

-- -----------------------------------------------------------------------------
-- branch_service_options (ช่วงเวลาที่ขาย)
-- -----------------------------------------------------------------------------
create table public.branch_service_options (
  id                 uuid primary key default gen_random_uuid(),
  company_id         uuid not null,
  branch_service_id  uuid not null,
  duration_minutes   integer not null check (duration_minutes between 5 and 600),
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  created_by         uuid references public.profiles (id),
  updated_at         timestamptz not null default now(),
  constraint branch_service_options_bs_fk foreign key (company_id, branch_service_id)
    references public.branch_services (company_id, id) on delete restrict,
  constraint branch_service_options_duration_key unique (branch_service_id, duration_minutes),
  constraint branch_service_options_company_id_id_key unique (company_id, id)
);

comment on table public.branch_service_options is
  'ช่วงเวลาที่ขายของบริการในสาขา ห้าม DELETE ใช้ is_active; เปลี่ยนนาที = ปิดช่วงเดิมแล้วเพิ่มช่วงใหม่';

-- -----------------------------------------------------------------------------
-- service_price_histories (ราคา + ค่าแรง ต่อช่วงเวลา)
-- -----------------------------------------------------------------------------
create table public.service_price_histories (
  id                        uuid primary key default gen_random_uuid(),
  company_id                uuid not null,
  branch_service_option_id  uuid not null,
  price                     numeric(12,2) not null check (price >= 0),
  therapist_fee             numeric(12,2) not null default 0 check (therapist_fee >= 0),
  effective_from            timestamptz not null,
  effective_to              timestamptz,
  status                    text not null default 'ACTIVE' check (status in ('ACTIVE', 'CANCELLED')),
  reason                    text not null check (char_length(trim(reason)) between 3 and 500),
  cancelled_at              timestamptz,
  cancelled_by              uuid references public.profiles (id),
  created_at                timestamptz not null default now(),
  created_by                uuid references public.profiles (id),
  updated_at                timestamptz not null default now(),
  constraint service_price_histories_option_fk foreign key (company_id, branch_service_option_id)
    references public.branch_service_options (company_id, id) on delete restrict,
  constraint service_price_histories_period_chk check (effective_to is null or effective_to > effective_from),
  constraint service_price_histories_cancel_chk check ((status = 'CANCELLED') = (cancelled_at is not null)),
  constraint service_price_histories_no_overlap exclude using gist (
    branch_service_option_id with =,
    tstzrange(effective_from, coalesce(effective_to, 'infinity'::timestamptz), '[)') with &&
  ) where (status = 'ACTIVE')
);

comment on table public.service_price_histories is
  'ราคา/ค่าแรงตามช่วงเวลามีผล ห้าม DELETE เปลี่ยนผ่าน save_branch_service_pricing เท่านั้น';
comment on column public.service_price_histories.therapist_fee is
  'ค่าแรงหมอนวดต่อการให้บริการ 1 ครั้ง (ฐานคอมมิชชันแบบจำนวนเงิน) เห็นเฉพาะ OWNER';

create index service_price_histories_option_idx
  on public.service_price_histories (branch_service_option_id, effective_from desc);

create or replace function private.tg_service_price_histories_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.company_id <> old.company_id or new.branch_service_option_id <> old.branch_service_option_id
     or new.price <> old.price or new.therapist_fee <> old.therapist_fee
     or new.effective_from <> old.effective_from or new.reason <> old.reason then
    raise exception 'ห้ามแก้ไขประวัติราคา ให้ตั้งราคาใหม่แทน' using errcode = 'check_violation';
  end if;
  if old.status = 'CANCELLED' then
    raise exception 'รายการราคาที่ยกเลิกแล้วแก้ไม่ได้' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger service_price_histories_guard
  before update on public.service_price_histories
  for each row execute function private.tg_service_price_histories_guard();

-- -----------------------------------------------------------------------------
-- stamp + audit + guard ทั่วไป
-- -----------------------------------------------------------------------------
create trigger service_categories_stamp before insert or update on public.service_categories
  for each row execute function private.tg_stamp();
create trigger services_stamp before insert or update on public.services
  for each row execute function private.tg_stamp();
create trigger branch_services_stamp before insert or update on public.branch_services
  for each row execute function private.tg_stamp();
create trigger branch_service_options_stamp before insert or update on public.branch_service_options
  for each row execute function private.tg_stamp();
create trigger service_price_histories_stamp before insert or update on public.service_price_histories
  for each row execute function private.tg_stamp();

create trigger service_categories_audit after insert or update or delete on public.service_categories
  for each row execute function private.tg_audit();
create trigger services_audit after insert or update or delete on public.services
  for each row execute function private.tg_audit();
create trigger branch_services_audit after insert or update or delete on public.branch_services
  for each row execute function private.tg_audit();
create trigger branch_service_options_audit after insert or update or delete on public.branch_service_options
  for each row execute function private.tg_audit();
create trigger service_price_histories_audit after insert or update or delete on public.service_price_histories
  for each row execute function private.tg_audit();

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
    if new.image_path is not null
       and (split_part(new.image_path, '/', 1) <> new.company_id::text
            or split_part(new.image_path, '/', 2) <> new.id::text) then
      raise exception 'ตำแหน่งรูปบริการไม่ถูกต้อง' using errcode = 'check_violation';
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

create trigger service_categories_guard before insert or update on public.service_categories
  for each row execute function private.tg_services_guard();
create trigger services_guard before insert or update on public.services
  for each row execute function private.tg_services_guard();
create trigger branch_services_guard before insert or update on public.branch_services
  for each row execute function private.tg_services_guard();
create trigger branch_service_options_guard before insert or update on public.branch_service_options
  for each row execute function private.tg_services_guard();

-- -----------------------------------------------------------------------------
-- Functions
-- -----------------------------------------------------------------------------

-- ราคา/ค่าแรงที่มีผล ณ เวลาที่กำหนด (ใช้ใน Phase 4+ ตอนทำ Snapshot)
create or replace function private.option_price_at(p_option_id uuid, p_at timestamptz default now())
returns public.service_price_histories
language sql
stable
security definer
set search_path = ''
as $$
  select *
    from public.service_price_histories
   where branch_service_option_id = p_option_id
     and status = 'ACTIVE'
     and effective_from <= p_at
     and (effective_to is null or effective_to > p_at)
   limit 1;
$$;

revoke all on function private.option_price_at(uuid, timestamptz) from public;

-- ตั้งราคาใหม่ของช่วงเวลาหนึ่ง (ภายใน — เรียกจาก save_branch_service_pricing)
create or replace function private.set_option_price(
  p_option_id uuid, p_price numeric, p_fee numeric, p_eff timestamptz, p_reason text
)
returns boolean   -- true = มีการเปลี่ยนแปลง
language plpgsql
security definer
set search_path = ''
as $$
declare
  o         public.branch_service_options;
  v_current public.service_price_histories;
begin
  select * into o from public.branch_service_options where id = p_option_id;

  if exists (
    select 1 from public.service_price_histories
     where branch_service_option_id = o.id and status = 'ACTIVE' and effective_from > now()
  ) then
    raise exception 'ช่วง % นาทีมีราคาที่ตั้งล่วงหน้าไว้แล้ว กรุณายกเลิกก่อน', o.duration_minutes
      using errcode = 'check_violation';
  end if;

  select * into v_current from public.service_price_histories
   where branch_service_option_id = o.id and status = 'ACTIVE'
     and effective_from <= p_eff and (effective_to is null or effective_to > p_eff)
   for update;

  if v_current.id is not null then
    if v_current.price = p_price and v_current.therapist_fee = p_fee then
      return false;
    end if;
    if v_current.effective_from >= p_eff then
      update public.service_price_histories
         set status = 'CANCELLED', cancelled_at = now(), cancelled_by = auth.uid()
       where id = v_current.id;
    else
      update public.service_price_histories set effective_to = p_eff where id = v_current.id;
    end if;
  end if;

  insert into public.service_price_histories
    (company_id, branch_service_option_id, price, therapist_fee, effective_from, reason)
  values (o.company_id, o.id, p_price, p_fee, p_eff, trim(p_reason));
  return true;
end;
$$;

revoke all on function private.set_option_price(uuid, numeric, numeric, timestamptz, text) from public;

-- -----------------------------------------------------------------------------
-- public.save_branch_service_pricing
-- บันทึกช่วงเวลา + ราคา + ค่าแรงของบริการหนึ่ง ในสาขาที่ระบุ (หลายสาขาได้) ใน Transaction เดียว
--   p_options = [{ "duration_minutes": 60, "price": 300, "therapist_fee": 120 }, ...]
--   ช่วงเวลาที่ไม่อยู่ในรายการจะถูกปิด (is_active = false)
--   ถ้าสาขาใดมีราคาของบริการนี้อยู่แล้ว = แก้ของเดิม -> ต้อง step-up TOTP + เหตุผล
--   p_effective_from: NULL/ปัจจุบัน = มีผลทันที, อนาคต = ตั้งล่วงหน้า, ห้ามย้อนหลัง
-- -----------------------------------------------------------------------------
create or replace function public.save_branch_service_pricing(
  p_branch_ids      uuid[],
  p_service_id      uuid,
  p_options         jsonb,
  p_effective_from  timestamptz,
  p_reason          text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company   uuid;
  v_eff       timestamptz := coalesce(p_effective_from, now());
  v_editing   boolean;
  v_reason    text;
  v_branch    uuid;
  v_bs        uuid;
  v_opt       public.branch_service_options;
  v_item      jsonb;
  v_duration  integer;
  v_price     numeric;
  v_fee       numeric;
  v_durations integer[] := '{}';
  v_changed   integer := 0;
begin
  select company_id into v_company from public.services where id = p_service_id and is_active;
  if v_company is null or not private.is_company_owner(v_company) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if p_branch_ids is null or cardinality(p_branch_ids) = 0 then
    raise exception 'กรุณาเลือกสาขา' using errcode = 'invalid_parameter_value';
  end if;
  if exists (
    select 1 from unnest(p_branch_ids) b(id)
     where not exists (select 1 from public.branches x where x.id = b.id and x.company_id = v_company)
  ) then
    raise exception 'สาขาไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;

  -- ตรวจรายการช่วงเวลา
  if jsonb_typeof(p_options) <> 'array' or jsonb_array_length(p_options) = 0 then
    raise exception 'กรุณาเพิ่มช่วงเวลาอย่างน้อย 1 ช่วง' using errcode = 'invalid_parameter_value';
  end if;
  for v_item in select * from jsonb_array_elements(p_options) loop
    v_duration := (v_item ->> 'duration_minutes')::integer;
    v_price := (v_item ->> 'price')::numeric;
    v_fee := coalesce((v_item ->> 'therapist_fee')::numeric, 0);
    if v_duration is null or v_duration not between 5 and 600 then
      raise exception 'ช่วงเวลาต้องอยู่ระหว่าง 5-600 นาที' using errcode = 'invalid_parameter_value';
    end if;
    if v_price is null or v_price < 0 or v_fee < 0 or v_price <> round(v_price, 2) or v_fee <> round(v_fee, 2) then
      raise exception 'ราคา/ค่าแรงของช่วง % นาทีไม่ถูกต้อง', v_duration using errcode = 'invalid_parameter_value';
    end if;
    if v_fee > v_price then
      raise exception 'ค่าแรงของช่วง % นาทีมากกว่าราคา', v_duration using errcode = 'invalid_parameter_value';
    end if;
    if v_duration = any (v_durations) then
      raise exception 'ช่วงเวลา % นาทีซ้ำ', v_duration using errcode = 'invalid_parameter_value';
    end if;
    v_durations := v_durations || v_duration;
  end loop;

  if v_eff < now() - interval '1 minute' then
    raise exception 'ห้ามเปลี่ยนราคาย้อนหลัง' using errcode = 'invalid_parameter_value';
  end if;
  if v_eff < now() then
    v_eff := now();
  end if;

  -- แก้ของเดิม = มีช่วงเวลาที่มีราคาอยู่แล้วในสาขาใดสาขาหนึ่ง
  v_editing := exists (
    select 1
      from public.branch_services bs
      join public.branch_service_options o on o.branch_service_id = bs.id
      join public.service_price_histories p on p.branch_service_option_id = o.id and p.status = 'ACTIVE'
     where bs.service_id = p_service_id and bs.branch_id = any (p_branch_ids)
  );
  if v_editing then
    perform private.require_owner_step_up(v_company);
    if p_reason is null or char_length(trim(p_reason)) < 3 then
      raise exception 'กรุณาระบุเหตุผลการเปลี่ยนราคา' using errcode = 'invalid_parameter_value';
    end if;
    v_reason := trim(p_reason);
  else
    v_reason := coalesce(nullif(trim(p_reason), ''), 'ราคาเริ่มต้น');
    if char_length(v_reason) < 3 then
      v_reason := 'ราคาเริ่มต้น';
    end if;
  end if;

  foreach v_branch in array p_branch_ids loop
    -- เปิดบริการที่สาขา (หรือเปิดกลับ)
    insert into public.branch_services (company_id, branch_id, service_id)
    values (v_company, v_branch, p_service_id)
    on conflict (branch_id, service_id) do update set is_active = true
    returning id into v_bs;

    -- ปิดช่วงเวลาที่ไม่อยู่ในรายการ
    update public.branch_service_options
       set is_active = false
     where branch_service_id = v_bs and is_active and not (duration_minutes = any (v_durations));
    v_changed := v_changed + (case when found then 1 else 0 end);

    for v_item in select * from jsonb_array_elements(p_options) loop
      v_duration := (v_item ->> 'duration_minutes')::integer;
      v_price := (v_item ->> 'price')::numeric;
      v_fee := coalesce((v_item ->> 'therapist_fee')::numeric, 0);

      insert into public.branch_service_options (company_id, branch_service_id, duration_minutes)
      values (v_company, v_bs, v_duration)
      on conflict (branch_service_id, duration_minutes) do update set is_active = true
      returning * into v_opt;

      if private.set_option_price(v_opt.id, v_price, v_fee, v_eff, v_reason) then
        v_changed := v_changed + 1;
      end if;
    end loop;
  end loop;

  return jsonb_build_object('changed', v_changed, 'effective_from', v_eff, 'step_up_required', v_editing);
end;
$$;

revoke all on function public.save_branch_service_pricing(uuid[], uuid, jsonb, timestamptz, text) from public, anon;
grant execute on function public.save_branch_service_pricing(uuid[], uuid, jsonb, timestamptz, text) to authenticated;

-- ยกเลิกราคาที่ตั้งล่วงหน้า (ยังไม่มีผล) แล้วคืนช่วงเวลาให้ราคาเดิม
create or replace function public.cancel_scheduled_price(p_price_history_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.service_price_histories;
begin
  select * into p from public.service_price_histories where id = p_price_history_id for update;
  if p.id is null then
    raise exception 'ไม่พบรายการราคา' using errcode = 'no_data_found';
  end if;

  perform private.require_owner_step_up(p.company_id);

  if p.status <> 'ACTIVE' or p.effective_from <= now() then
    raise exception 'ยกเลิกได้เฉพาะราคาที่ยังไม่มีผล' using errcode = 'check_violation';
  end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาระบุเหตุผล' using errcode = 'invalid_parameter_value';
  end if;

  perform set_config('app.audit_reason', trim(p_reason), true);

  update public.service_price_histories
     set status = 'CANCELLED', cancelled_at = now(), cancelled_by = auth.uid()
   where id = p.id;

  update public.service_price_histories set effective_to = null
   where branch_service_option_id = p.branch_service_option_id and status = 'ACTIVE'
     and effective_to = p.effective_from;
end;
$$;

revoke all on function public.cancel_scheduled_price(uuid, text) from public, anon;
grant execute on function public.cancel_scheduled_price(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- public.owner_service_pricing — ราคา + ค่าแรง (ปัจจุบันและล่วงหน้า) ของสาขา สำหรับ OWNER
-- -----------------------------------------------------------------------------
create or replace function public.owner_service_pricing(p_branch_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_company uuid;
begin
  select company_id into v_company from public.branches where id = p_branch_id;
  if v_company is null or not private.is_company_owner(v_company) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'branch_service_id', bs.id,
             'service_id', bs.service_id,
             'is_active', bs.is_active,
             'options', coalesce((
               select jsonb_agg(jsonb_build_object(
                        'option_id', o.id,
                        'duration_minutes', o.duration_minutes,
                        'is_active', o.is_active,
                        'current', (
                          select jsonb_build_object('id', p.id, 'price', p.price, 'therapist_fee', p.therapist_fee,
                                                    'effective_from', p.effective_from)
                            from public.service_price_histories p
                           where p.branch_service_option_id = o.id and p.status = 'ACTIVE'
                             and p.effective_from <= now() and (p.effective_to is null or p.effective_to > now())),
                        'scheduled', (
                          select jsonb_build_object('id', p.id, 'price', p.price, 'therapist_fee', p.therapist_fee,
                                                    'effective_from', p.effective_from)
                            from public.service_price_histories p
                           where p.branch_service_option_id = o.id and p.status = 'ACTIVE' and p.effective_from > now()),
                        'history', (
                          select jsonb_agg(jsonb_build_object('id', p.id, 'price', p.price, 'therapist_fee', p.therapist_fee,
                                                              'effective_from', p.effective_from, 'effective_to', p.effective_to,
                                                              'status', p.status, 'reason', p.reason)
                                           order by p.effective_from desc)
                            from public.service_price_histories p
                           where p.branch_service_option_id = o.id)
                      ) order by o.duration_minutes)
                 from public.branch_service_options o
                where o.branch_service_id = bs.id
             ), '[]'::jsonb)
           ) order by bs.sort_order)
      from public.branch_services bs
     where bs.branch_id = p_branch_id
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.owner_service_pricing(uuid) from public, anon;
grant execute on function public.owner_service_pricing(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Grants + RLS
-- -----------------------------------------------------------------------------
alter table public.service_categories enable row level security;
alter table public.services enable row level security;
alter table public.branch_services enable row level security;
alter table public.branch_service_options enable row level security;
alter table public.service_price_histories enable row level security;

revoke all on public.service_categories, public.services, public.branch_services,
              public.branch_service_options, public.service_price_histories
  from anon, authenticated;
grant all on public.service_categories, public.services, public.branch_services,
             public.branch_service_options, public.service_price_histories
  to service_role;

grant select (id, company_id, name, description, sort_order, is_active) on public.service_categories to anon;
grant select (id, company_id, category_id, name, name_en, description, image_path, sort_order, is_active)
  on public.services to anon;
grant select (id, company_id, branch_id, service_id, is_active, sort_order) on public.branch_services to anon;
grant select (id, company_id, branch_service_id, duration_minutes, is_active) on public.branch_service_options to anon;

-- ราคา: ไม่ grant therapist_fee ให้ client ทั้ง anon และ authenticated (OWNER อ่านผ่าน owner_service_pricing)
grant select (id, company_id, branch_service_option_id, price, effective_from, effective_to, status)
  on public.service_price_histories to anon, authenticated;

grant select on public.service_categories, public.services, public.branch_services, public.branch_service_options
  to authenticated;
grant insert (company_id, name, description, sort_order) on public.service_categories to authenticated;
grant update (name, description, sort_order, is_active) on public.service_categories to authenticated;
grant insert (company_id, category_id, name, name_en, description, sort_order) on public.services to authenticated;
grant update (category_id, name, name_en, description, image_path, sort_order, is_active) on public.services to authenticated;
grant update (is_active, sort_order) on public.branch_services to authenticated;

create policy service_categories_select_public on public.service_categories
  for select to anon, authenticated
  using (is_active and private.is_company_active(company_id));
create policy service_categories_select_member on public.service_categories
  for select to authenticated using (private.is_company_member(company_id));
create policy service_categories_insert_owner on public.service_categories
  for insert to authenticated with check (private.is_company_owner(company_id));
create policy service_categories_update_owner on public.service_categories
  for update to authenticated
  using (private.is_company_owner(company_id)) with check (private.is_company_owner(company_id));

create policy services_select_public on public.services
  for select to anon, authenticated
  using (is_active and private.is_company_active(company_id));
create policy services_select_member on public.services
  for select to authenticated using (private.is_company_member(company_id));
create policy services_insert_owner on public.services
  for insert to authenticated with check (private.is_company_owner(company_id));
create policy services_update_owner on public.services
  for update to authenticated
  using (private.is_company_owner(company_id)) with check (private.is_company_owner(company_id));

create policy branch_services_select_public on public.branch_services
  for select to anon, authenticated
  using (is_active and private.is_public_branch(branch_id));
create policy branch_services_select_member on public.branch_services
  for select to authenticated using (private.is_company_member(company_id));
create policy branch_services_update_owner on public.branch_services
  for update to authenticated
  using (private.is_company_owner(company_id)) with check (private.is_company_owner(company_id));

create policy branch_service_options_select_public on public.branch_service_options
  for select to anon, authenticated
  using (is_active and private.is_company_active(company_id));
create policy branch_service_options_select_member on public.branch_service_options
  for select to authenticated using (private.is_company_member(company_id));

-- ราคาสาธารณะ: เฉพาะราคาที่มีผลแล้ว (ไม่เผยราคาล่วงหน้า)
create policy service_price_histories_select_public on public.service_price_histories
  for select to anon, authenticated
  using (status = 'ACTIVE' and effective_from <= now() and private.is_company_active(company_id));
create policy service_price_histories_select_member on public.service_price_histories
  for select to authenticated using (private.is_company_member(company_id));

-- -----------------------------------------------------------------------------
-- View แคตตาล็อกสาธารณะ: 1 แถวต่อช่วงเวลาที่ขาย + ราคาปัจจุบัน (ใช้สิทธิ์ของผู้เรียก)
-- -----------------------------------------------------------------------------
create view public.v_public_branch_services
with (security_invoker = true)
as
select
  o.id               as option_id,
  bs.id              as branch_service_id,
  bs.company_id,
  bs.branch_id,
  s.id               as service_id,
  s.name,
  s.name_en,
  s.description,
  s.image_path,
  c.id               as category_id,
  c.name             as category_name,
  o.duration_minutes,
  p.price,
  bs.sort_order,
  c.sort_order       as category_sort_order
from public.branch_services bs
join public.services s on s.id = bs.service_id and s.is_active
join public.service_categories c on c.id = s.category_id and c.is_active
join public.branch_service_options o on o.branch_service_id = bs.id and o.is_active
join public.service_price_histories p
  on p.branch_service_option_id = o.id
 and p.status = 'ACTIVE'
 and p.effective_from <= now()
 and (p.effective_to is null or p.effective_to > now())
where bs.is_active;

grant select on public.v_public_branch_services to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Storage: รูปบริการ (public) path {company_id}/{service_id}/{file}
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('service-images', 'service-images', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create or replace function private.is_service_image_folder(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.services s
     where s.company_id = private.try_uuid(split_part(p_name, '/', 1))
       and s.id = private.try_uuid(split_part(p_name, '/', 2))
  );
$$;

revoke all on function private.is_service_image_folder(text) from public;
grant execute on function private.is_service_image_folder(text) to authenticated, service_role;

create policy service_images_insert_owner on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'service-images'
    and private.is_company_owner(private.try_uuid(split_part(name, '/', 1)))
    and private.is_service_image_folder(name)
  );

create policy service_images_update_owner on storage.objects
  for update to authenticated
  using (bucket_id = 'service-images' and private.is_company_owner(private.try_uuid(split_part(name, '/', 1))))
  with check (
    bucket_id = 'service-images'
    and private.is_company_owner(private.try_uuid(split_part(name, '/', 1)))
    and private.is_service_image_folder(name)
  );

create policy service_images_delete_owner on storage.objects
  for delete to authenticated
  using (bucket_id = 'service-images' and private.is_company_owner(private.try_uuid(split_part(name, '/', 1))));
