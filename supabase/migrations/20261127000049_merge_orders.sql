-- =============================================================================
-- 049 — รวมกลุ่มลูกค้า: ย้ายคิวทั้งหมดของออเดอร์หนึ่งไปรวมกับอีกออเดอร์ (มาทีหลังแต่มาด้วยกัน)
--   pos_merge_orders(source, target):
--     - สาขาเดียวกัน วันทำการเดียวกัน ทั้งสองออเดอร์ยังเปิดอยู่ (OPEN)
--     - ทั้งสองฝั่งยังไม่ออกบิล (ไม่มี Invoice ที่ไม่ถูก Void) — กันยอดเงิน/ใบเสร็จไม่ตรง
--     - ฝั่งที่ย้าย (source) ต้องไม่ใช่ออเดอร์จากการจอง (มัดจำผูกกับการจองนั้น)
--     - ย้ายรายการบริการ (และคิวที่ผูกอยู่) ไปออเดอร์ปลายทาง · เลขคิวไม่เปลี่ยน
--     - ออเดอร์ต้นทางที่ว่างแล้ว → ยกเลิก (เหตุผล "รวมกับกลุ่มคิว …")
--     - ปลายทางยังไม่มีลูกค้า แต่ต้นทางมี → ใช้ลูกค้าของต้นทาง
--   guard ของรายการบริการ: ยอมให้เปลี่ยน service_order_id เฉพาะใน transaction ที่ตั้ง app.merge_order = on
-- =============================================================================

create or replace function private.tg_service_order_items_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_merge boolean := coalesce(current_setting('app.merge_order', true), '') = 'on';
begin
  if (new.company_id, new.branch_id, new.booking_item_id, new.branch_service_option_id,
      new.service_id, new.service_name, new.service_name_en, new.duration_minutes, new.unit_price,
      new.therapist_fee, new.quantity, new.discount_amount, new.line_total)
     is distinct from
     (old.company_id, old.branch_id, old.booking_item_id, old.branch_service_option_id,
      old.service_id, old.service_name, old.service_name_en, old.duration_minutes, old.unit_price,
      old.therapist_fee, old.quantity, old.discount_amount, old.line_total)
     or (new.service_order_id <> old.service_order_id and not v_merge) then
    raise exception 'ห้ามแก้ Snapshot ของรายการบริการ' using errcode = 'check_violation';
  end if;
  if old.status = 'CANCELLED' and new.status <> 'CANCELLED' then
    raise exception 'รายการที่ยกเลิกแล้วกลับมาใช้ไม่ได้' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create or replace function public.pos_merge_orders(p_source_order_id uuid, p_target_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s     public.service_orders;
  t     public.service_orders;
  v_min integer;
  v_max integer;
begin
  if p_source_order_id = p_target_order_id then
    raise exception 'เลือกกลุ่มอื่นที่ไม่ใช่กลุ่มเดิม' using errcode = 'invalid_parameter_value';
  end if;
  -- ล็อกทั้งสองออเดอร์ตามลำดับ id กัน deadlock
  perform 1 from public.service_orders where id in (p_source_order_id, p_target_order_id) order by id for update;
  select * into s from public.service_orders where id = p_source_order_id;
  select * into t from public.service_orders where id = p_target_order_id;
  if s.id is null or t.id is null then
    raise exception 'ไม่พบออเดอร์' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(s.branch_id);

  if s.branch_id <> t.branch_id or s.business_date <> t.business_date then
    raise exception 'รวมได้เฉพาะลูกค้าสาขาเดียวกันในวันเดียวกัน' using errcode = 'check_violation';
  end if;
  if s.status <> 'OPEN' or t.status <> 'OPEN' then
    raise exception 'รวมได้เฉพาะกลุ่มที่ยังให้บริการไม่เสร็จ' using errcode = 'check_violation';
  end if;
  if s.booking_id is not null then
    raise exception 'คิวนี้มาจากการจอง (มีมัดจำผูกอยู่) ย้ายไม่ได้ — ให้ย้ายกลุ่มอื่นมารวมกับคิวนี้แทน'
      using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.invoices where service_order_id in (s.id, t.id) and status <> 'VOID') then
    raise exception 'กลุ่มนี้ออกบิลแล้ว รวมไม่ได้' using errcode = 'check_violation';
  end if;

  select min(q.queue_number), max(q.queue_number) into v_min, v_max
    from public.service_order_items i join public.queue_items q on q.service_order_item_id = i.id
   where i.service_order_id = t.id;

  perform set_config('app.merge_order', 'on', true);
  update public.service_order_items set service_order_id = t.id where service_order_id = s.id;
  perform set_config('app.merge_order', 'off', true);

  if t.customer_id is null and s.customer_id is not null then
    update public.service_orders set customer_id = s.customer_id where id = t.id;
  end if;
  update public.service_orders
     set status = 'CANCELLED', cancelled_at = now(), cancelled_by = auth.uid(),
         cancel_reason = left(format('รวมกับกลุ่มคิว %s–%s', lpad(v_min::text, 3, '0'), lpad(v_max::text, 3, '0')), 500)
   where id = s.id;

  return private.pos_order_view(t.id);
end;
$$;

revoke all on function public.pos_merge_orders(uuid, uuid) from public, anon;
grant execute on function public.pos_merge_orders(uuid, uuid) to authenticated;
