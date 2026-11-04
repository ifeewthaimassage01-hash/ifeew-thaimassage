-- ตรวจ Service Management: ต่อเวลา, เปลี่ยนหมอระหว่างบริการ, แบ่งค่ามือ, ย้อนเริ่ม/จบ, PIN บนเครื่องสาขา,
-- ประวัติบริการ (ลูกค้า/หมอ/OWNER), แดชบอร์ด
begin;
create extension if not exists pgtap with schema extensions;

select plan(31);

-- เวลาเปิดร้านครอบตอนนี้ (ไม่ขึ้นกับเวลาที่รัน) และหมอทั้งสองมีกะ
update public.branch_holidays set is_active = false;
update public.branch_opening_hours
   set is_closed = false,
       opens_at = case when extract(hour from now() at time zone 'Asia/Bangkok') < 1 then time '00:00'
                       else date_trunc('minute', (now() at time zone 'Asia/Bangkok') - interval '1 hour')::time end,
       closes_at = case when extract(hour from now() at time zone 'Asia/Bangkok') < 1 then time '23:59'
                       else date_trunc('minute', (now() at time zone 'Asia/Bangkok') - interval '61 minutes')::time end;
update public.employee_schedules set status = 'CANCELLED'
 where branch_id = '30000000-0000-4000-8000-000000000001' and status = 'SCHEDULED';
insert into public.employee_schedules (company_id, branch_id, employee_id, starts_at, ends_at)
select '20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', e, now() - interval '2 hours',
       now() + interval '8 hours'
  from unnest(array['40000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000004']::uuid[]) e;

create temporary table t (k text primary key, v text) on commit drop;
grant all on t to authenticated, anon, service_role;
insert into t select 'thai60', o.id::text from public.branch_service_options o
  join public.branch_services bs on bs.id = o.branch_service_id
 where bs.branch_id = '30000000-0000-4000-8000-000000000001'
   and bs.service_id = '51000000-0000-4000-8000-000000000001' and o.duration_minutes = 60;
insert into t select 'foot30', o.id::text from public.branch_service_options o
  join public.branch_services bs on bs.id = o.branch_service_id
 where bs.branch_id = '30000000-0000-4000-8000-000000000001'
   and bs.service_id = '51000000-0000-4000-8000-000000000002' and o.duration_minutes = 30;
insert into t select 'bd', business_date::text
  from private.branch_window_at('30000000-0000-4000-8000-000000000001', now());
create or replace function pg_temp.v(p_key text) returns text language sql as $$ select v from t where k = p_key $$;
create or replace function pg_temp.put(p_key text, p_val text) returns text language sql as $$
  insert into t values (p_key, p_val) on conflict (k) do update set v = excluded.v returning v
$$;
create or replace function pg_temp.q(p_key text, p_n int) returns uuid language sql as $$
  select (pg_temp.v(p_key)::jsonb -> 'items' -> p_n ->> 'queue_id')::uuid
$$;
create or replace function pg_temp.as_user(p_sub text, p_aal text default 'aal1') returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_sub, 'role', 'authenticated', 'aal', p_aal)::text, true)::text;
  select null::void;
$$;

-- ผูกเครื่องสาขา SKV (OWNER) สำหรับทดสอบ PIN
select pg_temp.as_user('10000000-0000-4000-8000-000000000001', 'aal2');
set local role authenticated;
select pg_temp.put('device', public.pair_branch_device('30000000-0000-4000-8000-000000000001', 'iPad คิว') ->> 'device_token');
reset role;

-- ---------------------------------------------------------------------------
-- Walk-in (มานี สมาชิก) → นภา เริ่มบริการ
-- ---------------------------------------------------------------------------
select pg_temp.as_user('10000000-0000-4000-8000-000000000002');   -- นภา (หน้าร้าน)
set local role authenticated;
select pg_temp.put('o1', public.pos_create_walkin('30000000-0000-4000-8000-000000000001',
  '60000000-0000-4000-8000-000000000001',
  (public.pos_available_starts('30000000-0000-4000-8000-000000000001', array[pg_temp.v('thai60')::uuid]) -> 0 ->> 'starts_at')::timestamptz,
  array[pg_temp.v('thai60')::uuid], null, 'p6-walkin-00000000001')::text);
select public.queue_call(pg_temp.q('o1', 0), '40000000-0000-4000-8000-000000000002');
select public.queue_accept(pg_temp.q('o1', 0));
select public.queue_start(pg_temp.q('o1', 0));

-- ---------------------------------------------------------------------------
-- ต่อเวลา
-- ---------------------------------------------------------------------------
select pg_temp.put('o1x', public.queue_extend(pg_temp.q('o1', 0), pg_temp.v('thai60')::uuid, 'p6-extend-00000000001')::text);
select ok(
  (pg_temp.v('o1x')::jsonb -> 'items' -> 1 ->> 'follows_queue_id')::uuid = pg_temp.q('o1', 0)
  and (pg_temp.v('o1x')::jsonb -> 'items' -> 1 ->> 'queue_status') = 'WAITING'
  and (pg_temp.v('o1x')::jsonb -> 'items' -> 1 ->> 'planned_starts_at')::timestamptz = now() + interval '60 minutes',
  'ต่อเวลา = คิวใหม่ต่อจากคิวเดิม เริ่มตอนรายการเดิมจบ');
select ok(
  (select bool_and(a.ends_at = now() + interval '60 minutes')
     from public.resource_allocations a where a.service_order_item_id = (pg_temp.v('o1')::jsonb -> 'items' -> 0 ->> 'item_id')::uuid),
  'ต่อเวลา = ย้ายเวลาเผื่อทำความสะอาดของรายการเดิมไปหลังรายการต่อเวลา (เตียงเดิมใช้ต่อได้)');
select is(
  public.queue_extend(pg_temp.q('o1', 0), pg_temp.v('thai60')::uuid, 'p6-extend-00000000001') -> 'items' -> 1 ->> 'queue_id',
  pg_temp.v('o1x')::jsonb -> 'items' -> 1 ->> 'queue_id', 'Idempotency-Key เดิมไม่ต่อเวลาซ้ำ');
select throws_ok(
  format($$select public.queue_extend(%L, %L, 'p6-extend-00000000002')$$, pg_temp.q('o1', 0), pg_temp.v('thai60')),
  '23514', 'คิวนี้ต่อเวลาไว้แล้ว', 'ต่อเวลาซ้อนสองครั้งไม่ได้');

-- ---------------------------------------------------------------------------
-- เปลี่ยนหมอระหว่างให้บริการ
-- ---------------------------------------------------------------------------
select throws_ok(
  format($$select public.queue_handover(%L, '40000000-0000-4000-8000-000000000004', '')$$, pg_temp.q('o1', 0)),
  '22023', null, 'เปลี่ยนหมอระหว่างบริการต้องมีเหตุผล');
select pg_temp.put('h1', public.queue_handover(pg_temp.q('o1', 0), '40000000-0000-4000-8000-000000000004', 'นภาไม่สบาย')::text);
select ok(
  (pg_temp.v('h1')::jsonb -> 'items' -> 0 -> 'therapist' ->> 'nickname') = 'ดาว'
  and jsonb_array_length(pg_temp.v('h1')::jsonb -> 'items' -> 0 -> 'handovers') = 1
  and (pg_temp.v('h1')::jsonb -> 'items' -> 0 ->> 'queue_status') = 'IN_SERVICE',
  'ส่งต่อให้ดาว: คิวยังให้บริการต่อ และบันทึกประวัติการส่งต่อ');
select ok(
  (select x ->> 'busy_queue_number' from jsonb_array_elements(
     public.pos_board('30000000-0000-4000-8000-000000000001') -> 'therapists') x
    where x ->> 'nickname' = 'นภา') is null,
  'นภาว่างทันทีหลังส่งต่อ');

-- ---------------------------------------------------------------------------
-- จบ → คิวต่อเวลาเริ่มอัตโนมัติด้วยหมอคนเดิม (ดาว)
-- ---------------------------------------------------------------------------
select pg_temp.put('c1', public.queue_complete(pg_temp.q('o1', 0))::text);
select ok(
  (pg_temp.v('c1')::jsonb -> 'items' -> 1 ->> 'queue_status') = 'IN_SERVICE'
  and (pg_temp.v('c1')::jsonb -> 'items' -> 1 -> 'therapist' ->> 'nickname') = 'ดาว',
  'จบรายการเดิม = รายการต่อเวลาเริ่มทันทีกับหมอคนเดิม');
reset role;
select is(
  (select sum(private.assignment_fee(a.id)) from public.service_assignments a where a.queue_item_id = pg_temp.q('o1', 0)),
  120.00::numeric, 'ค่ามือของคิวที่เปลี่ยนหมอ แบ่งรวมกันได้เท่าค่ามือเต็ม (120)');
select pg_temp.as_user('10000000-0000-4000-8000-000000000002');
set local role authenticated;
select throws_ok(
  format($$select public.queue_undo_complete(%L, 'กดผิด')$$, pg_temp.q('o1', 0)),
  '23514', 'รายการต่อเวลาเริ่มไปแล้ว ย้อนไม่ได้', 'ย้อนจบไม่ได้เมื่อรายการต่อเวลาเริ่มแล้ว');

-- ---------------------------------------------------------------------------
-- ย้อนเริ่ม / ย้อนจบ
-- ---------------------------------------------------------------------------
select is(public.queue_undo_start(pg_temp.q('o1x', 1), 'กดเริ่มผิดคิว') -> 'items' -> 1 ->> 'queue_status', 'ACCEPTED',
  'ย้อนเริ่มบริการภายใน 15 นาทีได้');
select public.queue_start(pg_temp.q('o1x', 1));
reset role;
update public.queue_items set started_at = now() - interval '20 minutes' where id = pg_temp.q('o1x', 1);
select pg_temp.as_user('10000000-0000-4000-8000-000000000002');
set local role authenticated;
select throws_ok(
  format($$select public.queue_undo_start(%L, 'กดเริ่มผิดคิว')$$, pg_temp.q('o1x', 1)),
  '23514', 'ย้อนการเริ่มบริการได้ภายใน 15 นาทีเท่านั้น', 'เกิน 15 นาทีย้อนเริ่มไม่ได้');
reset role;

-- หมอกดจบเองด้วย PIN บนเครื่องสาขา (Edge Function เรียกด้วย service role หลังตรวจ PIN)
set local role service_role;
select throws_ok(
  format($$select public.device_queue_action(%L, '10000000-0000-4000-8000-000000000002', %L, 'COMPLETE')$$,
         pg_temp.v('device'), pg_temp.q('o1x', 1)),
  '42501', 'คิวนี้ไม่ใช่คิวของคุณ', 'หมอกดคิวของคนอื่นด้วย PIN ไม่ได้');
select throws_ok(
  format($$select public.device_queue_action('dvc_%s', '10000000-0000-4000-8000-000000000007', %L, 'COMPLETE')$$,
         repeat('0', 64), pg_temp.q('o1x', 1)),
  '42501', null, 'เครื่องที่ไม่ได้ผูกใช้ไม่ได้');
select is(
  public.device_queue_action(pg_temp.v('device'), '10000000-0000-4000-8000-000000000007', pg_temp.q('o1x', 1), 'COMPLETE')
    -> 'items' -> 1 ->> 'queue_status',
  'COMPLETED', 'ดาวกดจบคิวของตัวเองด้วย PIN');
reset role;
select is((select completed_by from public.queue_items where id = pg_temp.q('o1x', 1)),
  '10000000-0000-4000-8000-000000000007'::uuid, 'บันทึกว่าดาวเป็นผู้กดจบ (ไม่ใช่คนที่ login หน้าร้าน)');
select is((select status from public.service_orders where id = (pg_temp.v('o1')::jsonb ->> 'order_id')::uuid),
  'COMPLETED', 'ทุกคิวเสร็จ = Order เสร็จ');

select pg_temp.as_user('10000000-0000-4000-8000-000000000002');
set local role authenticated;
select throws_ok(
  format($$select public.queue_undo_complete(%L, '')$$, pg_temp.q('o1x', 1)),
  '22023', null, 'ย้อนจบต้องมีเหตุผล');
select pg_temp.put('u1', public.queue_undo_complete(pg_temp.q('o1x', 1), 'ลูกค้ายังไม่เสร็จ')::text);
select ok(
  (pg_temp.v('u1')::jsonb ->> 'status') = 'OPEN'
  and (pg_temp.v('u1')::jsonb -> 'items' -> 1 ->> 'queue_status') = 'IN_SERVICE'
  and exists (select 1 from public.resource_allocations a
               where a.service_order_item_id = (pg_temp.v('u1')::jsonb -> 'items' -> 1 ->> 'item_id')::uuid
                 and a.status = 'IN_USE'),
  'ย้อนจบ = กลับมาให้บริการ จองเตียงกลับ และ Order กลับเป็น OPEN');
select public.queue_complete(pg_temp.q('o1x', 1));
reset role;
update public.queue_items set completed_at = now() - interval '20 minutes' where id = pg_temp.q('o1x', 1);
select pg_temp.as_user('10000000-0000-4000-8000-000000000002');
set local role authenticated;
select throws_ok(
  format($$select public.queue_undo_complete(%L, 'กดผิด')$$, pg_temp.q('o1x', 1)),
  '23514', 'ย้อนการจบบริการได้ภายใน 15 นาทีเท่านั้น', 'เกิน 15 นาทีย้อนจบไม่ได้');

-- ---------------------------------------------------------------------------
-- แดชบอร์ด
-- ---------------------------------------------------------------------------
select pg_temp.put('dash', public.staff_dashboard('30000000-0000-4000-8000-000000000001')::text);
select ok(
  (pg_temp.v('dash')::jsonb -> 'queue' ->> 'completed')::int = 2
  and jsonb_array_length(pg_temp.v('dash')::jsonb -> 'resources') = 3
  and (pg_temp.v('dash')::jsonb ->> 'walk_in_orders')::int = 1,
  'แดชบอร์ดสรุปคิว ทรัพยากร และ Walk-in ของวันนี้');

-- ---------------------------------------------------------------------------
-- งานของฉัน (หมอ)
-- ---------------------------------------------------------------------------
select pg_temp.put('w_napa', public.my_work_history(pg_temp.v('bd')::date, pg_temp.v('bd')::date)::text);
select ok(
  (pg_temp.v('w_napa')::jsonb ->> 'total_count')::int = 1
  and (pg_temp.v('w_napa')::jsonb ->> 'total_fee_estimate')::numeric = 60
  and (pg_temp.v('w_napa')::jsonb -> 'rows' -> 0 ->> 'handover')::boolean,
  'นภาเห็นงานของตัวเอง 1 รายการ (ส่งต่อ) ค่ามือประมาณการครึ่งหนึ่ง');
select throws_ok(
  format($$select public.my_work_history(%L, %L)$$, (pg_temp.v('bd')::date - 100)::text, pg_temp.v('bd')),
  '22023', null, 'ช่วงวันที่ยาวเกินกำหนดไม่ได้');
select throws_ok(
  format($$select public.therapist_work_summary('20000000-0000-4000-8000-000000000001', null, %L, %L)$$,
         pg_temp.v('bd'), pg_temp.v('bd')),
  '42501', null, 'STAFF ดูสรุปงานรายหมอไม่ได้');
reset role;

select pg_temp.as_user('10000000-0000-4000-8000-000000000007');   -- ดาว
set local role authenticated;
select pg_temp.put('w_dao', public.my_work_history(pg_temp.v('bd')::date, pg_temp.v('bd')::date)::text);
select ok(
  (pg_temp.v('w_dao')::jsonb ->> 'total_count')::int = 2
  and (pg_temp.v('w_dao')::jsonb ->> 'total_fee_estimate')::numeric = 180,
  'ดาวเห็นงานของตัวเอง 2 รายการ (ครึ่งหนึ่งของคิวแรก + คิวต่อเวลาเต็ม)');
select throws_ok($$select therapist_fee from public.service_order_items$$, '42501', null, 'หมออ่านค่ามือตรงจากตารางไม่ได้');
reset role;

select pg_temp.as_user('10000000-0000-4000-8000-000000000001', 'aal2');   -- OWNER
set local role authenticated;
select pg_temp.put('sum', public.therapist_work_summary('20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001', pg_temp.v('bd')::date, pg_temp.v('bd')::date)::text);
select ok(
  jsonb_array_length(pg_temp.v('sum')::jsonb) = 2
  and (select sum((x ->> 'fee_estimate')::numeric) from jsonb_array_elements(pg_temp.v('sum')::jsonb) x) = 240
  and (select (x ->> 'handover_count')::int from jsonb_array_elements(pg_temp.v('sum')::jsonb) x where x ->> 'nickname' = 'นภา') = 1,
  'OWNER เห็นสรุปงานรายหมอ (ค่ามือรวม = 120 + 120)');
reset role;

-- ---------------------------------------------------------------------------
-- ประวัติบริการของลูกค้า
-- ---------------------------------------------------------------------------
select pg_temp.as_user('10000000-0000-4000-8000-000000000010');   -- มานี
set local role authenticated;
select pg_temp.put('hist', public.my_service_history('IFEEW')::text);
select ok(
  jsonb_array_length(pg_temp.v('hist')::jsonb) = 2
  and (pg_temp.v('hist')::jsonb -> 0 ->> 'branch_name') = 'สาขาสุขุมวิท'
  and (select bool_or(x -> 'therapists' = '["นภา", "ดาว"]'::jsonb) from jsonb_array_elements(pg_temp.v('hist')::jsonb) x)
  and not (pg_temp.v('hist')::text like '%therapist_fee%'),
  'ลูกค้าเห็นประวัติบริการที่เสร็จแล้ว พร้อมชื่อเล่นหมอ (ไม่มีค่ามือ)');
select is(jsonb_array_length(public.export_my_data('IFEEW') -> 'service_history'), 2, 'ส่งออกข้อมูล (PDPA) รวมประวัติบริการ');
reset role;

select pg_temp.as_user('10000000-0000-4000-8000-000000000003');   -- สมใจ (ARI)
set local role authenticated;
select throws_ok($$select public.staff_dashboard('30000000-0000-4000-8000-000000000001')$$, '42501', null,
  'STAFF สาขาอื่นดูแดชบอร์ด SKV ไม่ได้');
select throws_ok(
  format($$select public.queue_handover(%L, '40000000-0000-4000-8000-000000000003', 'ทดสอบสิทธิ์')$$, pg_temp.q('o1x', 1)),
  '42501', null, 'STAFF สาขาอื่นเปลี่ยนหมอคิว SKV ไม่ได้');
reset role;

select * from finish();
rollback;
