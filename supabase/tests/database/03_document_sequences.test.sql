-- ตรวจเลขรันเอกสารและ audit append-only (รันในฐานะ postgres)
begin;
create extension if not exists pgtap with schema extensions;

select plan(10);

select is(
  private.next_document_number('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001',
                               'INV', '2026-11-04 10:00+07'),
  'INV-SKV-2026-000001', 'INV ใบแรกของปี');

select is(
  private.next_document_number('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001',
                               'INV', '2026-12-31 23:59+07'),
  'INV-SKV-2026-000002', 'INV ใบที่สองต่อเนื่อง');

select is(
  private.next_document_number('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001',
                               'INV', '2026-12-31 17:30+00'),
  'INV-SKV-2027-000001', 'ขึ้นปีใหม่ตามเวลา Asia/Bangkok (00:30 ของ 1 ม.ค.)');

select is(
  private.next_document_number('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000002',
                               'INV', '2026-11-04 10:00+07'),
  'INV-ARI-2026-000001', 'แต่ละสาขานับแยกกัน');

select is(
  private.next_document_number('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001',
                               'BKG', '2026-11-04 23:30+07'),
  'BKG-SKV-20261104-0001', 'BKG รายวัน');

select is(
  private.next_document_number('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001',
                               'BKG', '2026-11-04 17:30+00'),
  'BKG-SKV-20261105-0001', 'BKG เปลี่ยนวันตามเวลาไทย');

select throws_ok(
  $$select private.next_document_number('99999999-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000001', 'INV', now())$$,
  '23503', null, 'สาขาไม่ตรงบริษัทออกเลขไม่ได้');

select throws_ok(
  $$update public.branches set code = 'SKX' where code = 'SKV'$$,
  '23514', null, 'เปลี่ยนรหัสสาขาที่ออกเอกสารแล้วไม่ได้');

select throws_ok(
  $$update public.document_sequences set last_number = 0 where doc_type = 'INV'$$,
  '23514', null, 'ลดเลขรันไม่ได้');

select throws_ok(
  $$delete from public.audit_logs$$,
  '42501', null, 'audit_logs ลบไม่ได้แม้เป็น postgres');

select * from finish();
rollback;
