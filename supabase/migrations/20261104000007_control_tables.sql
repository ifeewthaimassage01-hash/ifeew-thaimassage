-- =============================================================================
-- Phase 1 / 007 — idempotency_keys, rate_limit_buckets
-- =============================================================================
-- ตารางควบคุมระบบ ไม่มี Policy ให้ client เข้าถึง ใช้ผ่าน Function / Edge Function เท่านั้น

-- -----------------------------------------------------------------------------
-- idempotency_keys
-- -----------------------------------------------------------------------------
create table public.idempotency_keys (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid references public.profiles (id) on delete restrict, -- NULL = guest
  endpoint         text not null check (endpoint ~ '^[a-z0-9_.:/-]{1,100}$'),
  key              text not null check (char_length(key) between 16 and 200),
  request_hash     text not null check (request_hash ~ '^[0-9a-f]{64}$'),
  status           text not null default 'IN_PROGRESS'
                     check (status in ('IN_PROGRESS', 'COMPLETED')),
  response_status  integer,
  response         jsonb,
  expires_at       timestamptz not null default (now() + interval '24 hours'),
  created_at       timestamptz not null default now(),
  created_by       uuid references public.profiles (id),
  updated_at       timestamptz not null default now(),
  constraint idempotency_keys_unique unique nulls not distinct (user_id, endpoint, key),
  constraint idempotency_keys_expiry_chk check (expires_at > created_at)
);

comment on table public.idempotency_keys is
  'กันคำสั่งซ้ำ (สร้าง Booking, รับชำระ, Refund, Void) ค่าซ้ำคืนผลเดิม';

create index idempotency_keys_expires_idx on public.idempotency_keys (expires_at);

create trigger idempotency_keys_stamp
  before insert or update on public.idempotency_keys
  for each row execute function private.tg_stamp();

-- -----------------------------------------------------------------------------
-- private.idempotency_begin
--   คืน NULL  = เป็นคำขอใหม่ ให้ทำงานต่อ (และต้องเรียก idempotency_complete ใน txn เดียวกัน)
--   คืน jsonb = คำขอซ้ำที่เสร็จแล้ว ให้คืนผลนี้
--   raise     = key เดิมแต่ request ต่างกัน หรือคำขอเดิมยังทำงานอยู่
-- -----------------------------------------------------------------------------
create or replace function private.idempotency_begin(
  p_endpoint     text,
  p_key          text,
  p_request_hash text,
  p_user_id      uuid default auth.uid()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.idempotency_keys%rowtype;
begin
  -- ล้างของหมดอายุของ key นี้
  delete from public.idempotency_keys
   where user_id is not distinct from p_user_id
     and endpoint = p_endpoint and key = p_key
     and expires_at <= now();

  insert into public.idempotency_keys (user_id, endpoint, key, request_hash)
  values (p_user_id, p_endpoint, p_key, p_request_hash)
  on conflict on constraint idempotency_keys_unique do nothing;

  if found then
    return null;
  end if;

  select * into r from public.idempotency_keys
   where user_id is not distinct from p_user_id and endpoint = p_endpoint and key = p_key
   for update;

  if r.request_hash <> p_request_hash then
    raise exception 'Idempotency-Key นี้ถูกใช้กับคำขออื่นแล้ว' using errcode = 'unique_violation';
  end if;
  if r.status <> 'COMPLETED' then
    raise exception 'คำขอนี้กำลังดำเนินการอยู่' using errcode = 'lock_not_available';
  end if;
  return jsonb_build_object('status', r.response_status, 'body', r.response);
end;
$$;

create or replace function private.idempotency_complete(
  p_endpoint        text,
  p_key             text,
  p_response_status integer,
  p_response        jsonb,
  p_user_id         uuid default auth.uid()
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.idempotency_keys
     set status = 'COMPLETED', response_status = p_response_status, response = p_response
   where user_id is not distinct from p_user_id and endpoint = p_endpoint and key = p_key
     and status = 'IN_PROGRESS';
  if not found then
    raise exception 'ไม่พบ Idempotency-Key ที่กำลังดำเนินการ' using errcode = 'no_data_found';
  end if;
end;
$$;

revoke all on function private.idempotency_begin(text, text, text, uuid) from public;
revoke all on function private.idempotency_complete(text, text, integer, jsonb, uuid) from public;

-- -----------------------------------------------------------------------------
-- rate_limit_buckets (fixed window)
-- -----------------------------------------------------------------------------
create table public.rate_limit_buckets (
  bucket_key    text primary key check (char_length(bucket_key) between 1 and 200),
  window_start  timestamptz not null default now(),
  hit_count     integer not null default 0 check (hit_count >= 0),
  created_at    timestamptz not null default now(),
  created_by    uuid references public.profiles (id),
  updated_at    timestamptz not null default now()
);

comment on table public.rate_limit_buckets is 'ตัวนับ Rate Limit ของ Public/Device Endpoint';

create index rate_limit_buckets_window_idx on public.rate_limit_buckets (window_start);

create trigger rate_limit_buckets_stamp
  before insert or update on public.rate_limit_buckets
  for each row execute function private.tg_stamp();

-- คืน true = อนุญาต, false = เกินโควตา
-- เรียกจาก Edge Function ด้วย secret key เท่านั้น
create or replace function public.rate_limit_hit(
  p_bucket_key     text,
  p_limit          integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if p_limit < 1 or p_window_seconds < 1 then
    raise exception 'ค่า rate limit ไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;

  insert into public.rate_limit_buckets as b (bucket_key, window_start, hit_count)
  values (p_bucket_key, now(), 1)
  on conflict (bucket_key) do update
    set window_start = case
          when b.window_start <= now() - make_interval(secs => p_window_seconds) then now()
          else b.window_start end,
        hit_count = case
          when b.window_start <= now() - make_interval(secs => p_window_seconds) then 1
          else b.hit_count + 1 end
  returning hit_count into v_count;

  return v_count <= p_limit;
end;
$$;

revoke all on function public.rate_limit_hit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.rate_limit_hit(text, integer, integer) to service_role;
