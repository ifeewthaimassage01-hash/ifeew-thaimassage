-- ตรวจการเงินหน้าร้าน: Invoice, ส่วนลด, รับเงิน (เงินสด/QR+สลิป/มัดจำ), ทิป, Void, คืนเงิน,
-- ล็อกคิวหลังออก Invoice, เงินเข้าออกลิ้นชัก, รายจ่าย, ปิดกะ (ไม่เห็นยอดก่อน), OWNER ตรวจกะ, สิทธิ์
begin;
create extension if not exists pgtap with schema extensions;

select plan(51);

-- เวลาเปิดร้านครอบตอนนี้ และหมอทั้งสองมีกะ
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
-- รูปหลักฐานรายจ่าย (จำลองว่าอัปโหลดแล้ว)
insert into storage.objects (bucket_id, name) values
  ('expense-photos', '20000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000001/bill1.jpg'),
  ('expense-photos', '20000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000001/bill2.jpg'),
  ('expense-photos', '20000000-0000-4000-8000-000000000001/hq/rent.jpg');

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
create or replace function pg_temp.j(p_key text) returns jsonb language sql as $$ select v::jsonb from t where k = p_key $$;
create or replace function pg_temp.put(p_key text, p_val text) returns text language sql as $$
  insert into t values (p_key, p_val) on conflict (k) do update set v = excluded.v returning v
$$;
create or replace function pg_temp.q(p_key text, p_n int) returns uuid language sql as $$
  select (pg_temp.j(p_key) -> 'items' -> p_n ->> 'queue_id')::uuid
$$;
create or replace function pg_temp.as_user(p_sub text, p_aal text default 'aal1') returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_sub, 'role', 'authenticated', 'aal', p_aal)::text, true)::text;
  select null::void;
$$;
create or replace function pg_temp.owner_step_up() returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object(
    'sub', '10000000-0000-4000-8000-000000000001', 'role', 'authenticated', 'aal', 'aal2',
    'amr', json_build_array(json_build_object('method', 'totp', 'timestamp', extract(epoch from now())::bigint))
  )::text, true)::text;
  select null::void;
$$;
create or replace function pg_temp.walkin(p_key text, p_customer uuid, p_options uuid[], p_idem text) returns text language sql as $$
  select pg_temp.put(p_key, public.pos_create_walkin('30000000-0000-4000-8000-000000000001', p_customer,
    (public.pos_available_starts('30000000-0000-4000-8000-000000000001', p_options) -> 0 ->> 'starts_at')::timestamptz,
    p_options, null, p_idem)::text)
$$;
create or replace function pg_temp.serve(p_queue uuid, p_employee uuid) returns void language sql as $$
  select public.queue_call(p_queue, p_employee);
  select public.queue_accept(p_queue);
  select public.queue_start(p_queue);
  select null::void;
$$;

select pg_temp.as_user('10000000-0000-4000-8000-000000000002');   -- นภา (หน้าร้าน)
set local role authenticated;

-- ---------------------------------------------------------------------------
-- Invoice
-- ---------------------------------------------------------------------------
select pg_temp.walkin('oA', '60000000-0000-4000-8000-000000000003',
                      array[pg_temp.v('thai60')::uuid, pg_temp.v('thai60')::uuid], 'p7-walkin-0000000000A');
select throws_ok(
  format($$select public.pos_create_invoice(%L)$$, pg_temp.j('oA') ->> 'order_id'),
  '23514', null, 'ยังมีรายการที่ไม่เริ่มบริการ ออก Invoice ไม่ได้');
select pg_temp.serve(pg_temp.q('oA', 0), '40000000-0000-4000-8000-000000000002');
select pg_temp.serve(pg_temp.q('oA', 1), '40000000-0000-4000-8000-000000000004');

select pg_temp.put('iA', public.pos_create_invoice((pg_temp.j('oA') ->> 'order_id')::uuid)::text);
select ok(
  pg_temp.j('iA') ->> 'status' = 'DRAFT' and (pg_temp.j('iA') ->> 'total')::numeric = 600
  and jsonb_array_length(pg_temp.j('iA') -> 'items') = 2,
  'ร่าง Invoice รวมรายการที่กำลังให้บริการ 600 บาท');
select is(public.pos_create_invoice((pg_temp.j('oA') ->> 'order_id')::uuid) ->> 'invoice_id',
  pg_temp.j('iA') ->> 'invoice_id', '1 Order มี Invoice หลักใบเดียว');
select throws_ok(
  format($$select public.pos_set_invoice_discount(%L, 50, '')$$, pg_temp.j('iA') -> 'items' -> 0 ->> 'invoice_item_id'),
  '22023', null, 'ส่วนลดต้องมีเหตุผล');
select is(
  (public.pos_set_invoice_discount((pg_temp.j('iA') -> 'items' -> 0 ->> 'invoice_item_id')::uuid, 50, 'ลูกค้าประจำ') ->> 'total')::numeric,
  550::numeric, 'ส่วนลด 50 บาท (ไม่เกินเพดาน 20%) STAFF ทำได้');
select throws_ok(
  format($$select public.pos_set_invoice_discount(%L, 100, 'ลดพิเศษ')$$, pg_temp.j('iA') -> 'items' -> 1 ->> 'invoice_item_id'),
  '42501', 'ส่วนลดเกิน 20% ต้องให้เจ้าของร้านเป็นผู้ให้', 'ส่วนลดเกินเพดาน STAFF ทำไม่ได้');
select throws_ok(
  format($$select public.pos_record_payment(%L, 'CASH', 100, null, null, 0, null, 'p7-pay-000000000000')$$, pg_temp.j('iA') ->> 'invoice_id'),
  '23514', null, 'ร่าง Invoice ยังรับเงินไม่ได้');

select pg_temp.put('iA', public.pos_issue_invoice((pg_temp.j('iA') ->> 'invoice_id')::uuid)::text);
select ok(pg_temp.j('iA') ->> 'invoice_number' ~ '^INV-SKV-[0-9]{4}-000001$' and pg_temp.j('iA') ->> 'status' = 'ISSUED',
  'ออก Invoice ได้เลข INV ของสาขา');
select throws_ok(
  format($$select public.pos_set_invoice_discount(%L, 0, null)$$, pg_temp.j('iA') -> 'items' -> 0 ->> 'invoice_item_id'),
  '23514', null, 'ออกแล้วแก้ส่วนลด/ยอดไม่ได้');

-- ---------------------------------------------------------------------------
-- รับเงิน
-- ---------------------------------------------------------------------------
select throws_ok(
  format($$select public.pos_record_payment(%L, 'CASH', 100, null, null, 0, null, 'p7-pay-000000000001')$$, pg_temp.j('iA') ->> 'invoice_id'),
  '23514', 'ยังไม่ได้เปิดกะ กรุณาเปิดกะก่อนรับ/จ่ายเงินสด', 'ไม่มีกะเปิด รับเงินไม่ได้');
select pg_temp.put('sess', public.pos_open_session('30000000-0000-4000-8000-000000000001', 1000, null)::text);

select pg_temp.put('iA', public.pos_record_payment((pg_temp.j('iA') ->> 'invoice_id')::uuid, 'CASH', 300, null, null,
  40, '40000000-0000-4000-8000-000000000002', 'p7-pay-000000000002')::text);
select ok(pg_temp.j('iA') ->> 'status' = 'PARTIALLY_PAID' and (pg_temp.j('iA') ->> 'balance')::numeric = 250
  and jsonb_array_length(pg_temp.j('iA') -> 'tips') = 1,
  'รับเงินสด 300 + ทิปนภา 40 = จ่ายบางส่วน ค้าง 250');
select is(
  public.pos_record_payment((pg_temp.j('iA') ->> 'invoice_id')::uuid, 'CASH', 300, null, null,
    40, '40000000-0000-4000-8000-000000000002', 'p7-pay-000000000002') ->> 'paid_amount',
  pg_temp.j('iA') ->> 'paid_amount', 'กดรับเงินซ้ำด้วย Idempotency-Key เดิม ไม่รับซ้ำ');
select throws_ok(
  format($$select public.pos_record_payment(%L, 'CASH', 400, null, null, 0, null, 'p7-pay-000000000003')$$, pg_temp.j('iA') ->> 'invoice_id'),
  '22023', null, 'รับเกินยอดค้างไม่ได้');
select throws_ok(
  format($$select public.pos_record_payment(%L, 'QR', 250, null, null, 0, null, 'p7-pay-000000000004')$$, pg_temp.j('iA') ->> 'invoice_id'),
  '22023', null, 'QR ต้องมีรูปสลิป');
reset role;

-- Edge Function บันทึกผลตรวจสลิป (service role)
set local role service_role;
select pg_temp.put('chk1', public.record_payment_slip_check('10000000-0000-4000-8000-000000000002',
  (pg_temp.j('iA') ->> 'invoice_id')::uuid,
  '20000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000001/a/1.jpg', 260, 'VERIFIED', null, '✅',
  '{"trans_ref":"POSREF0001","amount":260}')::text);
select throws_ok(
  format($$select public.record_payment_slip_check('10000000-0000-4000-8000-000000000002', %L,
    '20000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000002/a/1.jpg', 260, 'VERIFIED', null, 'x', '{}')$$,
    pg_temp.j('iA') ->> 'invoice_id'),
  '22023', null, 'สลิปต้องเก็บในโฟลเดอร์สาขาของ Invoice');
reset role;

select pg_temp.as_user('10000000-0000-4000-8000-000000000002');
set local role authenticated;
select throws_ok(
  format($$select public.pos_record_payment(%L, 'QR', 250, %L, null, 0, null, 'p7-pay-000000000005')$$,
         pg_temp.j('iA') ->> 'invoice_id', pg_temp.j('chk1') ->> 'slip_check_id'),
  '23514', null, 'ยอดในสลิปไม่ตรงกับยอดรับรวมทิป');
select pg_temp.put('iA', public.pos_record_payment((pg_temp.j('iA') ->> 'invoice_id')::uuid, 'QR', 250,
  (pg_temp.j('chk1') ->> 'slip_check_id')::uuid, null, 10, '40000000-0000-4000-8000-000000000004', 'p7-pay-000000000006')::text);
select ok(pg_temp.j('iA') ->> 'status' = 'PAID' and pg_temp.j('iA') ->> 'receipt_number' ~ '^RCP-SKV-[0-9]{4}-000001$'
  and (select bool_or(p ->> 'verification' = 'AUTO') from jsonb_array_elements(pg_temp.j('iA') -> 'payments') p),
  'สลิป QR ผ่าน (250 + ทิป 10) = จ่ายครบ ออกเลขใบเสร็จ RCP');
reset role;

set local role service_role;
select is(public.record_payment_slip_check('10000000-0000-4000-8000-000000000002',
  (pg_temp.j('iA') ->> 'invoice_id')::uuid,
  '20000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000001/a/2.jpg', 260, 'VERIFIED', null, '✅',
  '{"trans_ref":"POSREF0001","amount":260}') ->> 'outcome', 'REJECTED', 'สลิปที่ใช้แล้วใช้ซ้ำไม่ได้');
reset role;

-- ออก Invoice แล้ว: ย้อนจบ/ย้อนเริ่มไม่ได้, เพิ่มบริการไป Order ใหม่
select pg_temp.as_user('10000000-0000-4000-8000-000000000002');
set local role authenticated;
select public.queue_complete(pg_temp.q('oA', 0));
select public.queue_complete(pg_temp.q('oA', 1));
select throws_ok(
  format($$select public.queue_undo_complete(%L, 'กดผิด')$$, pg_temp.q('oA', 0)),
  '23514', 'รายการนี้ออก Invoice แล้ว ต้อง Void Invoice ก่อน', 'ออก Invoice แล้วย้อนจบไม่ได้');
select pg_temp.put('oA2', public.pos_add_order_items((pg_temp.j('oA') ->> 'order_id')::uuid,
  (public.pos_available_starts('30000000-0000-4000-8000-000000000001', array[pg_temp.v('foot30')::uuid]) -> 0 ->> 'starts_at')::timestamptz,
  array[pg_temp.v('foot30')::uuid], 'p7-add-00000000000001')::text);
select ok(pg_temp.j('oA2') ->> 'order_id' <> pg_temp.j('oA') ->> 'order_id'
  and (select parent_order_id from public.service_orders where id = (pg_temp.j('oA2') ->> 'order_id')::uuid)
      = (pg_temp.j('oA') ->> 'order_id')::uuid,
  'เพิ่มบริการหลังออก Invoice = Order ใหม่ที่ต่อจาก Order เดิม');
select throws_ok(
  format($$select public.pos_void_invoice(%L, 'ลูกค้าขอ', 'p7-void-0000000000001')$$, pg_temp.j('iA') ->> 'invoice_id'),
  '42501', 'Invoice ที่รับเงินแล้ว ต้องให้เจ้าของร้านเป็นผู้ Void', 'Void Invoice ที่รับเงินแล้ว STAFF ทำไม่ได้');
select throws_ok(
  format($$select public.pos_refund_payment(%L, 50, 'CASH', null, 'ทดสอบ', 'p7-refund-000000000001')$$,
         (select p ->> 'payment_id' from jsonb_array_elements(pg_temp.j('iA') -> 'payments') p where p ->> 'method' = 'CASH')),
  '42501', null, 'STAFF คืนเงินไม่ได้');
reset role;

-- OWNER คืนเงินสด 50 บาท (บางส่วน)
select pg_temp.owner_step_up();
set local role authenticated;
select pg_temp.put('iA', public.pos_refund_payment(
  (select (p ->> 'payment_id')::uuid from jsonb_array_elements(pg_temp.j('iA') -> 'payments') p where p ->> 'method' = 'CASH'),
  50, 'CASH', null, 'นวดไม่ครบเวลา', 'p7-refund-000000000002')::text);
select ok((pg_temp.j('iA') ->> 'refunded_amount')::numeric = 50 and pg_temp.j('iA') ->> 'status' = 'PAID',
  'OWNER คืนเงินบางส่วนได้ Payment เดิมไม่ถูกแก้');
select throws_ok(
  format($$select public.pos_refund_payment(%L, 300, 'CASH', null, 'เกิน', 'p7-refund-000000000003')$$,
         (select p ->> 'payment_id' from jsonb_array_elements(pg_temp.j('iA') -> 'payments') p where p ->> 'method' = 'CASH')),
  '22023', null, 'คืนเกินยอดที่รับไม่ได้');
select throws_ok(
  format($$select public.pos_void_invoice(%L, 'ลูกค้าขอ', 'p7-void-0000000000002')$$, pg_temp.j('iA') ->> 'invoice_id'),
  '23514', null, 'Invoice ที่คืนเงินแล้ว Void ไม่ได้');
reset role;

-- ---------------------------------------------------------------------------
-- Void Invoice (ทิปและเงินในกะเปิดถูก Void ด้วย) แล้วออกใหม่ได้
-- ---------------------------------------------------------------------------
select pg_temp.as_user('10000000-0000-4000-8000-000000000002');
set local role authenticated;
select pg_temp.serve(pg_temp.q('oA2', 0), '40000000-0000-4000-8000-000000000002');
select pg_temp.put('iB', public.pos_issue_invoice(
  (public.pos_create_invoice((pg_temp.j('oA2') ->> 'order_id')::uuid) ->> 'invoice_id')::uuid)::text);
select public.pos_record_payment((pg_temp.j('iB') ->> 'invoice_id')::uuid, 'CASH', 200, null, null,
  20, '40000000-0000-4000-8000-000000000002', 'p7-pay-000000000007');
reset role;
select pg_temp.owner_step_up();
set local role authenticated;
select pg_temp.put('iB', public.pos_void_invoice((pg_temp.j('iB') ->> 'invoice_id')::uuid, 'คิดเงินผิดคน', 'p7-void-0000000000003')::text);
select ok(pg_temp.j('iB') ->> 'status' = 'VOID'
  and (select bool_and(p ->> 'status' = 'VOID') from jsonb_array_elements(pg_temp.j('iB') -> 'payments') p)
  and (select bool_and(x ->> 'status' = 'VOID') from jsonb_array_elements(pg_temp.j('iB') -> 'tips') x),
  'OWNER Void Invoice: การรับเงินและทิปถูก Void (ไม่ลบ)');
select ok(public.pos_create_invoice((pg_temp.j('oA2') ->> 'order_id')::uuid) ->> 'invoice_id' <> pg_temp.j('iB') ->> 'invoice_id',
  'Void แล้วออก Invoice ใหม่ได้');
reset role;

-- ---------------------------------------------------------------------------
-- สลิปตรวจอัตโนมัติไม่ได้ → พนักงานยืนยันเอง (ต้องมีเหตุผล)
-- ---------------------------------------------------------------------------
select pg_temp.as_user('10000000-0000-4000-8000-000000000002');
set local role authenticated;
select pg_temp.put('iC', public.pos_issue_invoice(
  (public.pos_create_invoice((pg_temp.j('oA2') ->> 'order_id')::uuid) ->> 'invoice_id')::uuid)::text);
reset role;
set local role service_role;
select pg_temp.put('chk2', public.record_payment_slip_check('10000000-0000-4000-8000-000000000002',
  (pg_temp.j('iC') ->> 'invoice_id')::uuid,
  '20000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000001/c/1.jpg', 200, 'REVIEW', null,
  'ระบบตรวจสลิปอัตโนมัติยังไม่ได้ตั้งค่า', '{}')::text);
reset role;
select pg_temp.as_user('10000000-0000-4000-8000-000000000002');
set local role authenticated;
select throws_ok(
  format($$select public.pos_record_payment(%L, 'BANK_TRANSFER', 200, %L, null, 0, null, 'p7-pay-000000000008')$$,
         pg_temp.j('iC') ->> 'invoice_id', pg_temp.j('chk2') ->> 'slip_check_id'),
  '22023', null, 'ตรวจอัตโนมัติไม่ได้ ต้องระบุเหตุผลเพื่อยืนยันเอง');
select ok(
  (public.pos_record_payment((pg_temp.j('iC') ->> 'invoice_id')::uuid, 'BANK_TRANSFER', 200,
     (pg_temp.j('chk2') ->> 'slip_check_id')::uuid, 'เช็กยอดเข้าในแอปธนาคารแล้ว', 0, null, 'p7-pay-000000000009')
     -> 'payments' -> 0 ->> 'verification') = 'MANUAL',
  'พนักงานยืนยันสลิปเองได้ (บันทึกเป็น MANUAL)');

-- ---------------------------------------------------------------------------
-- มัดจำการจองหักจาก Invoice อัตโนมัติ
-- ---------------------------------------------------------------------------
select pg_temp.put('b1', public.staff_create_booking('30000000-0000-4000-8000-000000000001',
  '60000000-0000-4000-8000-000000000001',
  (select (x ->> 'starts_at')::timestamptz
     from jsonb_array_elements(public.get_available_slots('30000000-0000-4000-8000-000000000001',
            pg_temp.v('bd')::date, array[pg_temp.v('foot30')::uuid])) x
    where (x ->> 'starts_at')::timestamptz > now() + interval '3 hours' limit 1),
  array[pg_temp.v('foot30')::uuid], null, true, 'p7-booking-0000000001')::text);
reset role;
set local role service_role;
select public.record_deposit_slip((pg_temp.j('b1') ->> 'booking_id')::uuid, 'x/dep.jpg', 'VERIFIED', null, '✅',
  '{"trans_ref":"DEPREF0001","amount":100}');
reset role;
select pg_temp.as_user('10000000-0000-4000-8000-000000000002');
set local role authenticated;
select pg_temp.put('oD', public.pos_check_in_booking((pg_temp.j('b1') ->> 'booking_id')::uuid)::text);
select pg_temp.serve(pg_temp.q('oD', 0), '40000000-0000-4000-8000-000000000004');
select pg_temp.put('iD', public.pos_issue_invoice(
  (public.pos_create_invoice((pg_temp.j('oD') ->> 'order_id')::uuid) ->> 'invoice_id')::uuid)::text);
select ok((pg_temp.j('iD') ->> 'paid_amount')::numeric = 100 and (pg_temp.j('iD') ->> 'balance')::numeric = 100
  and pg_temp.j('iD') -> 'payments' -> 0 ->> 'method' = 'DEPOSIT',
  'ออก Invoice ของการจอง = หักมัดจำ 100 บาทอัตโนมัติ');

-- ---------------------------------------------------------------------------
-- เงินเข้าออกลิ้นชัก / ทิป / รายจ่าย
-- ---------------------------------------------------------------------------
select ok(public.pos_cash_adjustment('30000000-0000-4000-8000-000000000001', 'CASH_IN', 100, 'แลกเหรียญเพิ่ม') is not null,
  'บันทึกเงินเข้าลิ้นชัก');
select is((public.pos_pay_out_tips('30000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000002') ->> 'amount')::numeric,
  40::numeric, 'จ่ายทิปเงินสดของนภา (ไม่รวมทิปที่ Void)');
select throws_ok(
  $$select public.pos_record_expense('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001',
      150, 'ซื้อน้ำมันนวด', '20000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000001/none.jpg', true, null)$$,
  '22023', 'กรุณาแนบรูปหลักฐาน', 'รายจ่ายต้องแนบรูป');
select pg_temp.put('e1', public.pos_record_expense('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001',
  150, 'ซื้อน้ำมันนวด', '20000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000001/bill1.jpg', true, null)::text);
select pg_temp.put('e2', public.pos_record_expense('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001',
  80, 'ค่าน้ำแข็ง', '20000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000001/bill2.jpg', true, null)::text);
select ok(exists (select 1 from public.pos_cash_movements where expense_id = pg_temp.v('e1')::uuid and category = 'EXPENSE'),
  'รายจ่ายจากลิ้นชัก = เงินออกจากลิ้นชักใน Transaction เดียวกัน');
select throws_ok(
  $$select public.pos_record_expense('20000000-0000-4000-8000-000000000001', null, 20000, 'ค่าเช่า',
      '20000000-0000-4000-8000-000000000001/hq/rent.jpg', false, null)$$,
  '42501', null, 'STAFF บันทึกรายจ่ายสำนักงานใหญ่ไม่ได้');
select is(public.pos_void_expense(pg_temp.v('e2')::uuid, 'บันทึกซ้ำ'), 'VOIDED',
  'STAFF ยกเลิกรายจ่ายในกะที่ยังเปิดได้ทันที (คืนเงินเข้าลิ้นชัก)');

-- ---------------------------------------------------------------------------
-- ปิดกะ (นับเงินโดยไม่เห็นยอดคาดการณ์)
-- ---------------------------------------------------------------------------
select throws_ok($$select expected_cash from public.pos_sessions$$, '42501', null,
  'STAFF อ่านยอดคาดการณ์ของกะตรงไม่ได้');
select ok(not (public.pos_sessions_list('30000000-0000-4000-8000-000000000001', pg_temp.v('bd')::date, pg_temp.v('bd')::date)
               -> 0 ? 'expected_cash'),
  'รายการกะไม่แสดงยอดคาดการณ์ให้ STAFF ก่อนปิดกะ');
reset role;
-- ยอดคาดการณ์ = 1000 + เงินสด 300 + ทิปเงินสด 40 (ทิปที่ Void ไม่นับ) + เงินเข้า 100 + คืนรายจ่าย 80
--               − รายจ่าย 150 − รายจ่าย 80 − จ่ายทิป 40 − คืนเงินสด 50 = 1200
select is((private.session_figures(pg_temp.v('sess')::uuid) ->> 'expected_cash')::numeric, 1200::numeric,
  'Expected Cash ตามสูตรสเปก (เงินที่ Void ไม่นับ)');
select pg_temp.as_user('10000000-0000-4000-8000-000000000002');
set local role authenticated;
select throws_ok(format($$select public.pos_close_session(%L, 1150, null)$$, pg_temp.v('sess')),
  '22023', null, 'นับเงินไม่ตรงต้องระบุเหตุผล');
select is((public.pos_close_session(pg_temp.v('sess')::uuid, 1150, 'เงินขาด ทอนผิด') ->> 'cash_difference')::numeric,
  -50::numeric, 'ปิดกะ: ผลต่าง = นับจริง − คาดการณ์');
select throws_ok(
  format($$select public.pos_record_payment(%L, 'CASH', 100, null, null, 0, null, 'p7-pay-000000000010')$$, pg_temp.j('iD') ->> 'invoice_id'),
  '23514', null, 'ปิดกะแล้วรับเงินในกะนั้นไม่ได้');
select is(public.pos_void_expense(pg_temp.v('e1')::uuid, 'ซื้อผิด'), 'REQUESTED',
  'กะปิดแล้ว STAFF ขอยกเลิกรายจ่าย = ส่งคำขอให้ OWNER');
select throws_ok(format($$select public.pos_review_session(%L, true, null)$$, pg_temp.v('sess')),
  '42501', null, 'STAFF อนุมัติกะไม่ได้');
reset role;

select pg_temp.as_user('10000000-0000-4000-8000-000000000001', 'aal2');   -- OWNER
set local role authenticated;
select throws_ok(format($$select public.pos_review_session(%L, false, '')$$, pg_temp.v('sess')),
  '22023', null, 'ปฏิเสธกะต้องมีเหตุผล');
select lives_ok(format($$select public.pos_review_session(%L, true, 'ตรวจแล้ว')$$, pg_temp.v('sess')), 'OWNER อนุมัติกะ');
select is(public.pos_void_expense(pg_temp.v('e1')::uuid, 'อนุมัติคำขอ'), 'VOIDED', 'OWNER อนุมัติยกเลิกรายจ่าย');
select pg_temp.put('e3', public.pos_record_expense('20000000-0000-4000-8000-000000000001', null, 20000, 'ค่าเช่า',
    '20000000-0000-4000-8000-000000000001/hq/rent.jpg', false, null)::text);
select ok((select is_large from public.expenses where id = pg_temp.v('e3')::uuid),
  'OWNER บันทึกรายจ่ายสำนักงานใหญ่ได้ (เกินเกณฑ์ = รายจ่ายสูง)');
reset role;

-- ---------------------------------------------------------------------------
-- สิทธิ์
-- ---------------------------------------------------------------------------
select pg_temp.as_user('10000000-0000-4000-8000-000000000003');   -- สมใจ (ARI)
set local role authenticated;
select is((select count(*)::int from public.invoices), 0, 'STAFF สาขาอื่นไม่เห็น Invoice ของ SKV');
select is((select count(*)::int from public.expenses), 0, 'STAFF สาขาอื่นไม่เห็นรายจ่ายของ SKV');
select throws_ok($$update public.payments set amount = 1$$, '42501', null, 'แก้ยอดรับเงินตรงไม่ได้');
reset role;

select * from finish();
rollback;
