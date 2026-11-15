-- แถบ "มีสลิปมัดจำรอตรวจ" ในหน้า POS อัปเดตทันทีเมื่อลูกค้าส่งสลิป (bookings.deposit_status → PENDING_REVIEW)
-- Realtime ส่งแถวให้เฉพาะผู้ที่ RLS อนุญาต (bookings_select_branch: พนักงานที่มีสิทธิ์สาขานั้น)
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'bookings'
  ) then
    alter publication supabase_realtime add table public.bookings;
  end if;
end;
$$;
