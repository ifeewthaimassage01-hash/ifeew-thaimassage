-- ตรวจการจองสมาชิก/Guest, มัดจำ (สลิป), Idempotency, ยกเลิก, คืนมัดจำ, หมดเวลา, สิทธิ์
begin;
create extension if not exists pgtap with schema extensions;

select plan(24);

create temporary table t (k text primary key, v text) on commit drop;
grant all on t to authenticated, anon, service_role;
insert into t values ('d', ((now() at time zone 'Asia/Bangkok')::date + 5)::text);
insert into t select 'thai60', o.id::text from public.branch_service_options o
  join public.branch_services bs on bs.id = o.branch_service_id
 where bs.branch_id = '30000000-0000-4000-8000-000000000001'
   and bs.service_id = '51000000-0000-4000-8000-000000000001' and o.duration_minutes = 60;
insert into t values ('privacy', public.get_current_policies('IFEEW') -> 'PRIVACY_NOTICE' ->> 'id');
create or replace function pg_temp.ts(p_time text) returns timestamptz language sql as $$
  select ((select v from t where k = 'd')::date + p_time::time) at time zone 'Asia/Bangkok'
$$;
create or replace function pg_temp.v(p_key text) returns text language sql as $$ select v from t where k = p_key $$;
create or replace function pg_temp.put(p_key text, p_val text) returns text language sql as $$
  insert into t values (p_key, p_val) on conflict (k) do update set v = excluded.v returning v
$$;
create or replace function pg_temp.owner_step_up() returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', '10000000-0000-4000-8000-000000000001', 'role', 'authenticated', 'aal', 'aal2',
    'amr', json_build_array(json_build_object('method', 'totp', 'timestamp', extract(epoch from now())::bigint))
  )::text, true)::text;
  select null::void;
$$;

-- ---------------------------------------------------------------------------
-- สมาชิก (มานี) จองออนไลน์ -> ต้องมัดจำ
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000010","role":"authenticated","aal":"aal1"}', true);
set local role authenticated;

select pg_temp.put('m1', public.create_member_booking('IFEEW', '30000000-0000-4000-8000-000000000001',
  pg_temp.ts('11:00'), array[pg_temp.v('thai60')::uuid], 'ขอนวดเบา', 'member-key-0000000001')::text);
select ok(
  (pg_temp.v('m1')::jsonb ->> 'status') = 'PENDING'
  and (pg_temp.v('m1')::jsonb ->> 'deposit_status') = 'AWAITING_PAYMENT'
  and (pg_temp.v('m1')::jsonb ->> 'deposit_required')::numeric = 100
  and (pg_temp.v('m1')::jsonb -> 'payment' ->> 'promptpay_id') = '0812345670',
  'จองออนไลน์ = รอมัดจำ 100 บาท พร้อมข้อมูล PromptPay ของสาขา');
select is(
  public.create_member_booking('IFEEW', '30000000-0000-4000-8000-000000000001',
    pg_temp.ts('11:00'), array[pg_temp.v('thai60')::uuid], 'ขอนวดเบา', 'member-key-0000000001') ->> 'booking_id',
  pg_temp.v('m1')::jsonb ->> 'booking_id', 'Idempotency-Key เดิมได้ผลเดิม ไม่จองซ้ำ');
select is(jsonb_array_length(public.my_bookings('IFEEW')), 1, 'มีการจองเดียว');
select is((select count(*)::int from public.bookings), 0, 'ลูกค้าอ่านตาราง bookings ตรงไม่ได้ (RLS)');
reset role;

-- ผลตรวจสลิป (Edge Function = service_role)
set local role service_role;
select is(
  public.record_deposit_slip((pg_temp.v('m1')::jsonb ->> 'booking_id')::uuid, 'x/slip1.jpg', 'VERIFIED', null, '✅',
    '{"trans_ref":"REF0001","amount":50}') ->> 'slip_outcome',
  'REJECTED', 'ยอดในสลิปไม่ตรง ถูกปฏิเสธแม้ API บอกผ่าน');
select ok(
  (public.record_deposit_slip((pg_temp.v('m1')::jsonb ->> 'booking_id')::uuid, 'x/slip2.jpg', 'VERIFIED', null, '✅',
    '{"trans_ref":"REF0001","amount":100,"trans_at":"2026-11-04T03:15:07Z"}') ->> 'booking_code') like 'BKG-SKV-%',
  'สลิปถูกต้อง = ยืนยันการจองและออกรหัส BKG');
reset role;

-- ---------------------------------------------------------------------------
-- Guest
-- ---------------------------------------------------------------------------
set local role service_role;
select pg_temp.put('g1', public.create_guest_booking('IFEEW', '30000000-0000-4000-8000-000000000001',
  pg_temp.ts('12:00'), array[pg_temp.v('thai60')::uuid], 'สมศรี', 'ทดสอบ', '089-111-2222', null, null,
  pg_temp.v('privacy')::uuid, 'guest-key-00000000001')::text);
select ok((pg_temp.v('g1')::jsonb ->> 'tracking_token') ~ '^trk_[0-9a-f]{64}$', 'Guest ได้ Tracking Token');
select is(
  public.get_booking_by_token(pg_temp.v('g1')::jsonb ->> 'tracking_token') ->> 'customer_name',
  'สมศรี ท.', 'ดูสถานะด้วย Token ได้ (ชื่อปิดบังบางส่วน)');
select ok(public.get_booking_by_token('trk_' || repeat('0', 64)) is null, 'Token ผิดดูไม่ได้');
select is(
  public.record_deposit_slip((pg_temp.v('g1')::jsonb ->> 'booking_id')::uuid, 'x/slip3.jpg', 'VERIFIED', null, '✅',
    '{"trans_ref":"REF0001","amount":100}') ->> 'slip_outcome',
  'REJECTED', 'สลิปที่ใช้แล้วใช้ซ้ำไม่ได้');
select is(
  public.record_deposit_slip((pg_temp.v('g1')::jsonb ->> 'booking_id')::uuid, 'x/slip4.jpg', 'REVIEW', 1009, 'ธนาคารขัดข้อง',
    '{}') ->> 'deposit_status',
  'PENDING_REVIEW', 'ตรวจอัตโนมัติไม่ได้ -> รอพนักงานตรวจ');
select ok(
  (select hold_expires_at > now() + interval '1 hour' from public.bookings
    where id = (pg_temp.v('g1')::jsonb ->> 'booking_id')::uuid),
  'ขยายเวลากันที่ระหว่างรอตรวจ');
reset role;

-- พนักงานตรวจสลิป
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1"}', true);
set local role authenticated;
select lives_ok(
  $$select public.review_deposit(
      (select id from public.booking_deposits where status = 'PENDING_REVIEW' limit 1), true, 'ตรวจกับบัญชีธนาคารแล้ว')$$,
  'พนักงานอนุมัติสลิปได้');
select is(
  (select status from public.bookings where id = (pg_temp.v('g1')::jsonb ->> 'booking_id')::uuid),
  'CONFIRMED', 'อนุมัติแล้วการจองยืนยัน');
select throws_ok($$select therapist_fee from public.booking_items$$, '42501', null, 'STAFF ไม่เห็นค่าแรงใน Snapshot');
select throws_ok(
  $$update public.bookings set status = 'CANCELLED'$$, '42501', null, 'STAFF แก้สถานะการจองตรงไม่ได้');
select throws_ok(
  format($$select public.mark_no_show(%L)$$, pg_temp.v('g1')::jsonb ->> 'booking_id'),
  '23514', null, 'บันทึกไม่มาตามนัดก่อนถึงเวลาไม่ได้');
reset role;

-- ---------------------------------------------------------------------------
-- สมาชิกยกเลิกทันเวลา -> รอคืนมัดจำ -> OWNER บันทึกการโอนคืน
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000010","role":"authenticated","aal":"aal1"}', true);
set local role authenticated;
select is(
  public.cancel_my_booking('IFEEW', (pg_temp.v('m1')::jsonb ->> 'booking_id')::uuid, 'ติดธุระ') ->> 'deposit_status',
  'REFUND_PENDING', 'ยกเลิกก่อนนัด 3 ชม. = รอคืนมัดจำ');

select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1"}', true);
select throws_ok(
  format($$select public.record_deposit_refund(%L, 'KBANK-123')$$, pg_temp.v('m1')::jsonb ->> 'booking_id'),
  '42501', null, 'STAFF บันทึกคืนเงินไม่ได้');
select pg_temp.owner_step_up();
select lives_ok(
  format($$select public.record_deposit_refund(%L, 'KBANK-123')$$, pg_temp.v('m1')::jsonb ->> 'booking_id'),
  'OWNER (step-up) บันทึกการโอนคืนได้');
reset role;

-- ---------------------------------------------------------------------------
-- หมดเวลาชำระ -> EXPIRED และคืนทรัพยากร
-- ---------------------------------------------------------------------------
set local role service_role;
select pg_temp.put('g2', public.create_guest_booking('IFEEW', '30000000-0000-4000-8000-000000000001',
  pg_temp.ts('13:00'), array[pg_temp.v('thai60')::uuid], 'ไม่จ่าย', '', '0891112223', null, null,
  pg_temp.v('privacy')::uuid, 'guest-key-00000000002')::text);
reset role;
alter table public.resource_allocations disable trigger resource_allocations_stamp;
update public.resource_allocations a set created_at = now() - interval '1 hour', expires_at = now() - interval '1 minute'
  from public.booking_items i where i.id = a.booking_item_id and i.booking_id = (pg_temp.v('g2')::jsonb ->> 'booking_id')::uuid;
alter table public.resource_allocations enable trigger resource_allocations_stamp;
update public.bookings set hold_expires_at = now() - interval '1 minute' where id = (pg_temp.v('g2')::jsonb ->> 'booking_id')::uuid;
select ok(private.expire_stale_bookings() >= 1, 'ปิดการจองที่หมดเวลาชำระ');
select ok(
  (select status from public.bookings where id = (pg_temp.v('g2')::jsonb ->> 'booking_id')::uuid) = 'EXPIRED'
  and not exists (select 1 from public.resource_allocations a join public.booking_items i on i.id = a.booking_item_id
                   where i.booking_id = (pg_temp.v('g2')::jsonb ->> 'booking_id')::uuid and a.status <> 'RELEASED'),
  'หมดเวลาแล้วคืนทรัพยากรทั้งหมด');
select throws_ok(
  format($$update public.bookings set status = 'CONFIRMED' where id = %L$$, pg_temp.v('g2')::jsonb ->> 'booking_id'),
  '23514', null, 'สถานะสุดท้ายเปลี่ยนกลับไม่ได้');

-- รวม Guest เข้าสมาชิก -> การจองย้ายตาม
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1"}', true);
set local role authenticated;
select public.merge_customers(
  (select customer_id from public.bookings where id = (pg_temp.v('g1')::jsonb ->> 'booking_id')::uuid),
  '60000000-0000-4000-8000-000000000001', 'ลูกค้ายืนยันว่าเป็นคนเดียวกัน');
reset role;
select is(
  (select customer_id from public.bookings where id = (pg_temp.v('g1')::jsonb ->> 'booking_id')::uuid),
  '60000000-0000-4000-8000-000000000001'::uuid, 'รวม Guest แล้วการจองย้ายไปลูกค้าปลายทาง');

select * from finish();
rollback;
