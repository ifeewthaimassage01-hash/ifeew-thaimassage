-- =============================================================================
-- Phase 3 / 017 — customers, privacy_policy_versions, customer_consents, customer_data_requests
-- =============================================================================
-- หลักการ:
--  - ลูกค้าเป็นข้อมูลระดับบริษัท phone ไม่ UNIQUE, Guest มี auth_user_id = NULL
--  - ไม่มี SELECT ตรงสำหรับ STAFF/ลูกค้า: ใช้ Function ที่ปิดบังข้อมูลและบันทึก audit
--  - OWNER (aal2) อ่านตารางตรงได้
--  - จับคู่ Guest ต้องให้พนักงานยืนยัน (merge_customers) ไม่รวมอัตโนมัติ
--  - ลบข้อมูลตาม PDPA = anonymize ไม่ลบแถว

-- -----------------------------------------------------------------------------
-- Helpers: เบอร์โทร
-- -----------------------------------------------------------------------------
-- เก็บเป็นตัวเลขล้วนรูปแบบไทย 0XXXXXXXX(X); รับ +66 / 66 / ขีด / ช่องว่าง
create or replace function private.normalize_phone(p_phone text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
begin
  if v like '66%' and length(v) in (11, 12) then
    v := '0' || substr(v, 3);
  end if;
  if v !~ '^0[0-9]{8,9}$' then
    return null;
  end if;
  return v;
end;
$$;

-- 0812345678 -> 081-xxx-5678
create or replace function private.mask_phone(p_phone text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_phone is null then null
    else substr(p_phone, 1, 3) || '-xxx-' || right(p_phone, 4)
  end;
$$;

-- -----------------------------------------------------------------------------
-- customers
-- -----------------------------------------------------------------------------
create table public.customers (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references public.companies (id) on delete restrict,
  auth_user_id     uuid references public.profiles (id) on delete restrict,
  first_name       text not null check (char_length(first_name) between 1 and 100),
  last_name        text not null default '' check (char_length(last_name) <= 100),
  phone            text check (phone is null or phone ~ '^0[0-9]{8,9}$'),
  email            text check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  staff_note       text check (staff_note is null or char_length(staff_note) <= 1000),
  created_channel  text not null check (created_channel in ('ONLINE', 'STAFF')),
  status           text not null default 'ACTIVE' check (status in ('ACTIVE', 'MERGED', 'ANONYMIZED')),
  merged_into_id   uuid,
  merged_at        timestamptz,
  anonymized_at    timestamptz,
  created_at       timestamptz not null default now(),
  created_by       uuid references public.profiles (id),
  updated_at       timestamptz not null default now(),
  constraint customers_company_id_id_key unique (company_id, id),
  constraint customers_merged_fk foreign key (company_id, merged_into_id)
    references public.customers (company_id, id) on delete restrict,
  constraint customers_phone_required_chk check (status = 'ANONYMIZED' or phone is not null),
  constraint customers_merged_chk check (
    (status <> 'MERGED' or (merged_into_id is not null and merged_at is not null))
    and ((merged_into_id is null) = (merged_at is null))
  ),
  constraint customers_anonymized_chk check ((status = 'ANONYMIZED') = (anonymized_at is not null)),
  constraint customers_not_self_merge_chk check (merged_into_id is distinct from id)
);

comment on table public.customers is 'ลูกค้าระดับบริษัท ห้าม DELETE (MERGED/ANONYMIZED แทน)';

create unique index customers_company_auth_user_key
  on public.customers (company_id, auth_user_id)
  where auth_user_id is not null and status = 'ACTIVE';
create index customers_company_phone_idx on public.customers (company_id, phone) where status = 'ACTIVE';

create trigger customers_stamp before insert or update on public.customers
  for each row execute function private.tg_stamp();
-- ปิดบัง PII ใน audit เพื่อให้การ anonymize ตาม PDPA มีผลจริง (audit แก้/ลบไม่ได้)
create trigger customers_audit after insert or update or delete on public.customers
  for each row execute function private.tg_audit('first_name', 'last_name', 'phone', 'email', 'staff_note');

create or replace function private.tg_customers_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.first_name := trim(new.first_name);
  new.last_name := trim(coalesce(new.last_name, ''));
  new.email := nullif(lower(trim(new.email)), '');
  if tg_op = 'UPDATE' then
    if new.company_id <> old.company_id then
      raise exception 'ห้ามย้ายลูกค้าข้ามบริษัท' using errcode = 'check_violation';
    end if;
    if old.status = 'ANONYMIZED'
       or (old.status = 'MERGED' and new.status <> 'ANONYMIZED') then
      raise exception 'ลูกค้ารายนี้ถูกรวมหรือลบข้อมูลแล้ว แก้ไขไม่ได้' using errcode = 'check_violation';
    end if;
    if old.auth_user_id is not null and new.auth_user_id is distinct from old.auth_user_id and new.status <> 'ANONYMIZED' then
      raise exception 'ห้ามเปลี่ยนบัญชีสมาชิกของลูกค้า' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;

create trigger customers_guard before insert or update on public.customers
  for each row execute function private.tg_customers_guard();

-- -----------------------------------------------------------------------------
-- privacy_policy_versions (เผยแพร่แล้วแก้ไม่ได้ ออกเวอร์ชันใหม่แทน)
-- -----------------------------------------------------------------------------
create table public.privacy_policy_versions (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references public.companies (id) on delete restrict,
  policy_type   text not null check (policy_type in ('PRIVACY_NOTICE', 'MARKETING')),
  version       text not null check (version ~ '^[0-9A-Za-z._-]{1,20}$'),
  title         text not null check (char_length(title) between 1 and 200),
  content       text not null check (char_length(content) between 1 and 50000),
  published_at  timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  created_by    uuid references public.profiles (id),
  updated_at    timestamptz not null default now(),
  constraint privacy_policy_versions_key unique (company_id, policy_type, version),
  constraint privacy_policy_versions_company_id_id_key unique (company_id, id)
);

create trigger privacy_policy_versions_stamp before insert or update on public.privacy_policy_versions
  for each row execute function private.tg_stamp();
create trigger privacy_policy_versions_audit after insert or update or delete on public.privacy_policy_versions
  for each row execute function private.tg_audit();

create or replace function private.tg_immutable_row()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% แก้ไข/ลบไม่ได้', tg_table_name using errcode = 'insufficient_privilege';
end;
$$;

create trigger privacy_policy_versions_immutable before update or delete on public.privacy_policy_versions
  for each row execute function private.tg_immutable_row();

-- เวอร์ชันปัจจุบันของแต่ละประเภท
create or replace function private.current_policy_version(p_company_id uuid, p_type text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.privacy_policy_versions
   where company_id = p_company_id and policy_type = p_type and published_at <= now()
   order by published_at desc
   limit 1;
$$;

revoke all on function private.current_policy_version(uuid, text) from public;

-- -----------------------------------------------------------------------------
-- customer_consents (append-only: แถวล่าสุดต่อประเภท = สถานะปัจจุบัน)
-- -----------------------------------------------------------------------------
create table public.customer_consents (
  id                 uuid primary key default gen_random_uuid(),
  company_id         uuid not null,
  customer_id        uuid not null,
  policy_version_id  uuid not null,
  consent_type       text not null check (consent_type in ('PRIVACY_NOTICE', 'MARKETING')),
  granted            boolean not null,
  channel            text not null check (channel in ('ONLINE', 'STAFF')),
  recorded_at        timestamptz not null default now(),
  created_at         timestamptz not null default now(),
  created_by         uuid references public.profiles (id),
  updated_at         timestamptz not null default now(),
  constraint customer_consents_customer_fk foreign key (company_id, customer_id)
    references public.customers (company_id, id) on delete restrict,
  constraint customer_consents_policy_fk foreign key (company_id, policy_version_id)
    references public.privacy_policy_versions (company_id, id) on delete restrict
);

create index customer_consents_customer_idx on public.customer_consents (customer_id, consent_type, recorded_at desc);

create trigger customer_consents_stamp before insert or update on public.customer_consents
  for each row execute function private.tg_stamp();
create trigger customer_consents_immutable before update or delete on public.customer_consents
  for each row execute function private.tg_immutable_row();

create or replace function private.record_consent(
  p_customer_id uuid, p_type text, p_granted boolean, p_channel text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid;
  v_policy  uuid;
begin
  select company_id into v_company from public.customers where id = p_customer_id;
  v_policy := private.current_policy_version(v_company, p_type);
  if v_policy is null then
    raise exception 'ยังไม่มีนโยบายประเภท % ที่เผยแพร่', p_type using errcode = 'no_data_found';
  end if;
  insert into public.customer_consents (company_id, customer_id, policy_version_id, consent_type, granted, channel)
  values (v_company, p_customer_id, v_policy, p_type, p_granted, p_channel);
end;
$$;

revoke all on function private.record_consent(uuid, text, boolean, text) from public;

-- -----------------------------------------------------------------------------
-- customer_data_requests (คำขอลบข้อมูล)
-- -----------------------------------------------------------------------------
create table public.customer_data_requests (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null,
  customer_id    uuid not null,
  request_type   text not null default 'DELETE' check (request_type in ('DELETE')),
  status         text not null default 'PENDING' check (status in ('PENDING', 'COMPLETED', 'REJECTED')),
  reason         text check (reason is null or char_length(reason) <= 1000),
  requested_at   timestamptz not null default now(),
  processed_by   uuid references public.profiles (id),
  processed_at   timestamptz,
  response_note  text check (response_note is null or char_length(response_note) <= 1000),
  created_at     timestamptz not null default now(),
  created_by     uuid references public.profiles (id),
  updated_at     timestamptz not null default now(),
  constraint customer_data_requests_customer_fk foreign key (company_id, customer_id)
    references public.customers (company_id, id) on delete restrict,
  constraint customer_data_requests_processed_chk
    check ((status = 'PENDING') = (processed_at is null))
);

create unique index customer_data_requests_one_pending
  on public.customer_data_requests (customer_id, request_type) where status = 'PENDING';

create trigger customer_data_requests_stamp before insert or update on public.customer_data_requests
  for each row execute function private.tg_stamp();
create trigger customer_data_requests_audit after insert or update or delete on public.customer_data_requests
  for each row execute function private.tg_audit();

-- -----------------------------------------------------------------------------
-- Functions: สาธารณะ / ลูกค้า
-- -----------------------------------------------------------------------------

-- ข้อมูลบริษัทสำหรับ Customer App (ตั้ง company code ใน env ของแอป)
create or replace function public.get_public_company(p_code text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('company_id', c.id, 'code', c.code, 'name', c.name)
    from public.companies c
   where c.code = upper(p_code) and c.is_active;
$$;

-- นโยบายฉบับปัจจุบัน
create or replace function public.get_current_policies(p_company_code text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(v.policy_type, jsonb_build_object(
           'id', v.id, 'version', v.version, 'title', v.title, 'content', v.content, 'published_at', v.published_at)), '{}'::jsonb)
    from public.companies c
    join lateral (
      select distinct on (p.policy_type) p.*
        from public.privacy_policy_versions p
       where p.company_id = c.id and p.published_at <= now()
       order by p.policy_type, p.published_at desc
    ) v on true
   where c.code = upper(p_company_code) and c.is_active;
$$;

create or replace function private.company_id_by_code(p_code text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.companies where code = upper(p_code) and is_active;
$$;

revoke all on function private.company_id_by_code(text) from public;

create or replace function private.my_customer_row(p_company_code text)
returns public.customers
language sql
stable
security definer
set search_path = ''
as $$
  select c.* from public.customers c
   where c.company_id = private.company_id_by_code(p_company_code)
     and c.auth_user_id = auth.uid()
     and c.status = 'ACTIVE';
$$;

revoke all on function private.my_customer_row(text) from public;

-- สมัครเป็นลูกค้าของบริษัท (หลัง signUp/login) + บันทึกความยินยอม
create or replace function public.register_customer(
  p_company_code         text,
  p_first_name           text,
  p_last_name            text,
  p_phone                text,
  p_privacy_version_id   uuid,
  p_marketing_consent    boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid := private.company_id_by_code(p_company_code);
  v_email   text;
  v_phone   text := private.normalize_phone(p_phone);
  v_id      uuid;
begin
  if auth.uid() is null or v_company is null then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  select email into v_email from auth.users where id = auth.uid();
  if v_email like '%@' || private.staff_email_domain() then
    raise exception 'บัญชีพนักงานสมัครเป็นลูกค้าไม่ได้' using errcode = 'insufficient_privilege';
  end if;
  if (private.my_customer_row(p_company_code)).id is not null then
    raise exception 'บัญชีนี้ลงทะเบียนเป็นลูกค้าแล้ว' using errcode = 'unique_violation';
  end if;
  if v_phone is null then
    raise exception 'เบอร์โทรไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  if p_privacy_version_id is distinct from private.current_policy_version(v_company, 'PRIVACY_NOTICE') then
    raise exception 'กรุณายอมรับนโยบายความเป็นส่วนตัวฉบับปัจจุบัน' using errcode = 'invalid_parameter_value';
  end if;

  insert into public.customers (company_id, auth_user_id, first_name, last_name, phone, email, created_channel)
  values (v_company, auth.uid(), p_first_name, coalesce(p_last_name, ''), v_phone, v_email, 'ONLINE')
  returning id into v_id;

  update public.profiles set display_name = left(trim(p_first_name || ' ' || coalesce(p_last_name, '')), 120), phone = v_phone
   where id = auth.uid();

  perform private.record_consent(v_id, 'PRIVACY_NOTICE', true, 'ONLINE');
  if private.current_policy_version(v_company, 'MARKETING') is not null then
    perform private.record_consent(v_id, 'MARKETING', coalesce(p_marketing_consent, false), 'ONLINE');
  end if;

  return v_id;
end;
$$;

-- ข้อมูลลูกค้าของตัวเอง (ไม่รวม staff_note)
create or replace function public.my_customer(p_company_code text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when c.id is null then null else jsonb_build_object(
    'customer_id', c.id,
    'first_name', c.first_name,
    'last_name', c.last_name,
    'phone', c.phone,
    'email', c.email,
    'created_at', c.created_at,
    'consents', coalesce((
      select jsonb_object_agg(x.consent_type, jsonb_build_object('granted', x.granted, 'recorded_at', x.recorded_at, 'version', x.version))
        from (
          select distinct on (cc.consent_type) cc.consent_type, cc.granted, cc.recorded_at, p.version
            from public.customer_consents cc
            join public.privacy_policy_versions p on p.id = cc.policy_version_id
           where cc.customer_id = c.id
           order by cc.consent_type, cc.recorded_at desc, cc.created_at desc
        ) x
    ), '{}'::jsonb),
    'pending_deletion', exists (
      select 1 from public.customer_data_requests r where r.customer_id = c.id and r.status = 'PENDING'
    )
  ) end
  from (select (private.my_customer_row(p_company_code)).*) c;
$$;

create or replace function public.update_my_customer(
  p_company_code text, p_first_name text, p_last_name text, p_phone text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id    uuid := (private.my_customer_row(p_company_code)).id;
  v_phone text := private.normalize_phone(p_phone);
begin
  if v_id is null then
    raise exception 'ไม่พบข้อมูลลูกค้า' using errcode = 'no_data_found';
  end if;
  if v_phone is null then
    raise exception 'เบอร์โทรไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  update public.customers
     set first_name = p_first_name, last_name = coalesce(p_last_name, ''), phone = v_phone
   where id = v_id;
  update public.profiles set display_name = left(trim(p_first_name || ' ' || coalesce(p_last_name, '')), 120), phone = v_phone
   where id = auth.uid();
end;
$$;

create or replace function public.set_my_marketing_consent(p_company_code text, p_granted boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := (private.my_customer_row(p_company_code)).id;
begin
  if v_id is null then
    raise exception 'ไม่พบข้อมูลลูกค้า' using errcode = 'no_data_found';
  end if;
  perform private.record_consent(v_id, 'MARKETING', coalesce(p_granted, false), 'ONLINE');
end;
$$;

-- ส่งออกข้อมูลของตัวเอง (PDPA: สิทธิ์ขอรับข้อมูล) — Phase ถัดไปจะเพิ่มประวัติการจอง/บริการ
create or replace function public.export_my_data(p_company_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.customers := private.my_customer_row(p_company_code);
begin
  if c.id is null then
    raise exception 'ไม่พบข้อมูลลูกค้า' using errcode = 'no_data_found';
  end if;
  perform private.write_audit(p_action => 'CUSTOMER_DATA_EXPORTED', p_company_id => c.company_id,
                              p_table_name => 'customers', p_record_id => c.id);
  return jsonb_build_object(
    'exported_at', now(),
    'profile', (select jsonb_build_object('display_name', p.display_name, 'phone', p.phone) from public.profiles p where p.id = auth.uid()),
    'customer', jsonb_build_object(
      'first_name', c.first_name, 'last_name', c.last_name, 'phone', c.phone, 'email', c.email, 'created_at', c.created_at),
    'consents', coalesce((
      select jsonb_agg(jsonb_build_object('type', cc.consent_type, 'granted', cc.granted, 'channel', cc.channel,
                                          'version', p.version, 'recorded_at', cc.recorded_at) order by cc.recorded_at)
        from public.customer_consents cc join public.privacy_policy_versions p on p.id = cc.policy_version_id
       where cc.customer_id = c.id), '[]'::jsonb),
    'data_requests', coalesce((
      select jsonb_agg(jsonb_build_object('type', r.request_type, 'status', r.status, 'requested_at', r.requested_at,
                                          'processed_at', r.processed_at) order by r.requested_at)
        from public.customer_data_requests r where r.customer_id = c.id), '[]'::jsonb)
  );
end;
$$;

create or replace function public.request_my_data_deletion(p_company_code text, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  c    public.customers := private.my_customer_row(p_company_code);
  v_id uuid;
begin
  if c.id is null then
    raise exception 'ไม่พบข้อมูลลูกค้า' using errcode = 'no_data_found';
  end if;
  insert into public.customer_data_requests (company_id, customer_id, reason)
  values (c.company_id, c.id, nullif(trim(p_reason), ''))
  returning id into v_id;
  return v_id;
exception when unique_violation then
  raise exception 'มีคำขอลบข้อมูลที่รอดำเนินการอยู่แล้ว' using errcode = 'unique_violation';
end;
$$;

-- -----------------------------------------------------------------------------
-- Functions: พนักงาน
-- -----------------------------------------------------------------------------

-- ค้นหาด้วยเบอร์เต็มเท่านั้น คืนข้อมูลแบบปิดบัง
create or replace function public.search_customers_by_phone(p_company_id uuid, p_phone text)
returns table (
  customer_id   uuid,
  display_name  text,
  phone_masked  text,
  is_member     boolean,
  created_at    timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := private.normalize_phone(p_phone);
begin
  if not private.is_company_member(p_company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if v_phone is null then
    raise exception 'กรุณากรอกเบอร์โทรให้ครบ' using errcode = 'invalid_parameter_value';
  end if;

  perform private.write_audit(p_action => 'CUSTOMER_SEARCHED', p_company_id => p_company_id,
                              p_metadata => jsonb_build_object('phone_masked', private.mask_phone(v_phone)));

  return query
    select c.id,
           c.first_name || case when c.last_name <> '' then ' ' || left(c.last_name, 1) || '.' else '' end,
           private.mask_phone(c.phone),
           c.auth_user_id is not null,
           c.created_at
      from public.customers c
     where c.company_id = p_company_id and c.phone = v_phone and c.status = 'ACTIVE'
     order by c.auth_user_id is null, c.created_at;
end;
$$;

-- รายละเอียดเต็ม (บันทึก audit ทุกครั้ง)
create or replace function public.get_customer(p_customer_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.customers;
begin
  select * into c from public.customers where id = p_customer_id;
  if c.id is null or not private.is_company_member(c.company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;

  perform private.write_audit(p_action => 'CUSTOMER_VIEWED', p_company_id => c.company_id,
                              p_table_name => 'customers', p_record_id => c.id);

  return jsonb_build_object(
    'customer_id', c.id, 'first_name', c.first_name, 'last_name', c.last_name,
    'phone', c.phone, 'email', c.email, 'staff_note', c.staff_note,
    'is_member', c.auth_user_id is not null, 'created_channel', c.created_channel,
    'status', c.status, 'merged_into_id', c.merged_into_id, 'created_at', c.created_at,
    'marketing_consent', (
      select cc.granted from public.customer_consents cc
       where cc.customer_id = c.id and cc.consent_type = 'MARKETING'
       order by cc.recorded_at desc, cc.created_at desc limit 1)
  );
end;
$$;

-- พนักงานเพิ่มลูกค้า (Walk-in / โทรจอง) — ต้องแจ้งนโยบายความเป็นส่วนตัวให้ลูกค้ารับทราบแล้ว
create or replace function public.create_customer(
  p_company_id                uuid,
  p_first_name                text,
  p_last_name                 text,
  p_phone                     text,
  p_email                     text,
  p_staff_note                text,
  p_privacy_acknowledged      boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := private.normalize_phone(p_phone);
  v_id    uuid;
begin
  if not private.is_company_member(p_company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if v_phone is null then
    raise exception 'เบอร์โทรไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  if p_privacy_acknowledged is not true then
    raise exception 'ต้องแจ้งนโยบายความเป็นส่วนตัวให้ลูกค้ารับทราบก่อน' using errcode = 'invalid_parameter_value';
  end if;

  insert into public.customers (company_id, first_name, last_name, phone, email, staff_note, created_channel)
  values (p_company_id, p_first_name, coalesce(p_last_name, ''), v_phone, p_email, nullif(trim(p_staff_note), ''), 'STAFF')
  returning id into v_id;

  perform private.record_consent(v_id, 'PRIVACY_NOTICE', true, 'STAFF');
  return v_id;
end;
$$;

create or replace function public.update_customer(
  p_customer_id uuid, p_first_name text, p_last_name text, p_phone text, p_email text, p_staff_note text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c       public.customers;
  v_phone text := private.normalize_phone(p_phone);
begin
  select * into c from public.customers where id = p_customer_id for update;
  if c.id is null or not private.is_company_member(c.company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if v_phone is null then
    raise exception 'เบอร์โทรไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  -- ข้อมูลของสมาชิก (ชื่อ/เบอร์/อีเมล) ให้ลูกค้าแก้เอง พนักงานแก้ได้เฉพาะหมายเหตุ
  if c.auth_user_id is not null then
    update public.customers set staff_note = nullif(trim(p_staff_note), '') where id = c.id;
  else
    update public.customers
       set first_name = p_first_name, last_name = coalesce(p_last_name, ''), phone = v_phone,
           email = p_email, staff_note = nullif(trim(p_staff_note), '')
     where id = c.id;
  end if;
end;
$$;

-- จับคู่ Guest เข้ากับลูกค้าเดิม (พนักงานยืนยัน) ต้นทางต้องเป็น Guest
-- หมายเหตุ: Phase ที่มีตารางอ้าง customers (booking, order) ต้องย้าย reference ใน function นี้ด้วย
create or replace function public.merge_customers(p_source_id uuid, p_target_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.customers;
  t public.customers;
begin
  if p_source_id = p_target_id then
    raise exception 'เลือกลูกค้าคนเดียวกัน' using errcode = 'invalid_parameter_value';
  end if;
  -- ล็อกตามลำดับ id กัน deadlock
  perform 1 from public.customers where id in (p_source_id, p_target_id) order by id for update;
  select * into s from public.customers where id = p_source_id;
  select * into t from public.customers where id = p_target_id;

  if s.id is null or t.id is null or s.company_id <> t.company_id or not private.is_company_member(s.company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if s.status <> 'ACTIVE' or t.status <> 'ACTIVE' then
    raise exception 'ลูกค้าต้องอยู่ในสถานะใช้งานทั้งคู่' using errcode = 'check_violation';
  end if;
  if s.auth_user_id is not null then
    raise exception 'รวมได้เฉพาะลูกค้า Guest เข้ากับลูกค้าอื่น' using errcode = 'check_violation';
  end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาระบุเหตุผล' using errcode = 'invalid_parameter_value';
  end if;

  perform set_config('app.audit_reason', trim(p_reason), true);

  update public.customers
     set status = 'MERGED', merged_into_id = t.id, merged_at = now()
   where id = s.id;

  -- ย้ายหมายเหตุของร้านไปไว้ที่ปลายทาง
  if s.staff_note is not null then
    update public.customers
       set staff_note = left(concat_ws(E'\n', t.staff_note, '[รวมจาก Guest] ' || s.staff_note), 1000)
     where id = t.id;
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- Functions: OWNER — คำขอลบข้อมูล
-- -----------------------------------------------------------------------------
-- อนุมัติ: anonymize customers + profiles และคืน auth_user_id ให้ Edge Function ปิดบัญชี Auth
create or replace function public.process_data_deletion(p_request_id uuid, p_approve boolean, p_note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.customer_data_requests;
  c public.customers;
begin
  select * into r from public.customer_data_requests where id = p_request_id for update;
  if r.id is null then
    raise exception 'ไม่พบคำขอ' using errcode = 'no_data_found';
  end if;

  perform private.require_owner_step_up(r.company_id);

  if r.status <> 'PENDING' then
    raise exception 'คำขอนี้ดำเนินการแล้ว' using errcode = 'check_violation';
  end if;
  if not p_approve and (p_note is null or char_length(trim(p_note)) < 3) then
    raise exception 'กรุณาระบุเหตุผลที่ปฏิเสธ' using errcode = 'invalid_parameter_value';
  end if;

  select * into c from public.customers where id = r.customer_id for update;

  if p_approve then
    update public.customers
       set first_name = 'ลบข้อมูลแล้ว', last_name = '', phone = null, email = null, staff_note = null,
           status = 'ANONYMIZED', anonymized_at = now(), auth_user_id = null
     where id = c.id;

    -- Guest ที่เคยรวมเข้ากับลูกค้ารายนี้ก็ต้องลบด้วย
    update public.customers
       set first_name = 'ลบข้อมูลแล้ว', last_name = '', phone = null, email = null, staff_note = null,
           status = 'ANONYMIZED', anonymized_at = now()
     where merged_into_id = c.id and status = 'MERGED';

    if c.auth_user_id is not null then
      update public.profiles set display_name = '', phone = null, avatar_path = null where id = c.auth_user_id;
    end if;
  end if;

  update public.customer_data_requests
     set status = case when p_approve then 'COMPLETED' else 'REJECTED' end,
         processed_by = auth.uid(), processed_at = now(), response_note = nullif(trim(p_note), '')
   where id = r.id;

  return jsonb_build_object('request_id', r.id, 'approved', p_approve, 'auth_user_id', case when p_approve then c.auth_user_id end);
end;
$$;

-- -----------------------------------------------------------------------------
-- Grants
-- -----------------------------------------------------------------------------
revoke all on function public.get_public_company(text) from public;
revoke all on function public.get_current_policies(text) from public;
grant execute on function public.get_public_company(text) to anon, authenticated;
grant execute on function public.get_current_policies(text) to anon, authenticated;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.register_customer(text, text, text, text, uuid, boolean)',
    'public.my_customer(text)',
    'public.update_my_customer(text, text, text, text)',
    'public.set_my_marketing_consent(text, boolean)',
    'public.export_my_data(text)',
    'public.request_my_data_deletion(text, text)',
    'public.search_customers_by_phone(uuid, text)',
    'public.get_customer(uuid)',
    'public.create_customer(uuid, text, text, text, text, text, boolean)',
    'public.update_customer(uuid, text, text, text, text, text)',
    'public.merge_customers(uuid, uuid, text)',
    'public.process_data_deletion(uuid, boolean, text)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end;
$$;

alter table public.customers enable row level security;
alter table public.privacy_policy_versions enable row level security;
alter table public.customer_consents enable row level security;
alter table public.customer_data_requests enable row level security;

revoke all on public.customers, public.privacy_policy_versions, public.customer_consents, public.customer_data_requests
  from anon, authenticated;
grant all on public.customers, public.privacy_policy_versions, public.customer_consents, public.customer_data_requests
  to service_role;

-- OWNER อ่านตรงได้ (รายงาน/ตรวจสอบ) — STAFF และลูกค้าใช้ Function
grant select on public.customers, public.privacy_policy_versions, public.customer_consents, public.customer_data_requests
  to authenticated;
grant insert (company_id, policy_type, version, title, content, published_at) on public.privacy_policy_versions to authenticated;

create policy customers_select_owner on public.customers
  for select to authenticated using (private.is_company_owner(company_id));
create policy customer_consents_select_owner on public.customer_consents
  for select to authenticated using (private.is_company_owner(company_id));
create policy customer_data_requests_select_owner on public.customer_data_requests
  for select to authenticated using (private.is_company_owner(company_id));

create policy privacy_policy_versions_select_member on public.privacy_policy_versions
  for select to authenticated using (private.is_company_member(company_id));
create policy privacy_policy_versions_insert_owner on public.privacy_policy_versions
  for insert to authenticated
  with check (private.is_company_owner(company_id) and published_at >= now() - interval '1 minute');
