-- เก็บกวาดข้อมูลเดิม: Order ที่บิลถูก Void ไปก่อน migration 054 (ไม่มีบิลอื่นที่ยังใช้งาน และทุกคิวจบแล้ว)
-- → ยกเลิก Order ตามกติกาใหม่ ให้หายจาก "ยังไม่จ่าย"
do $$
begin
  perform set_config('app.void_order', 'on', true);
  perform set_config('app.audit_reason', 'ยกเลิกบิลก่อนปรับกติกา (migration 055)', true);
  update public.service_orders o
     set status = 'CANCELLED', cancelled_at = now(), cancel_reason = 'ยกเลิกบิล'
   where o.status in ('OPEN', 'COMPLETED')
     and exists (select 1 from public.invoices iv where iv.service_order_id = o.id and iv.status = 'VOID')
     and not exists (select 1 from public.invoices iv where iv.service_order_id = o.id and iv.status <> 'VOID')
     and not exists (
       select 1 from public.service_order_items i join public.queue_items q on q.service_order_item_id = i.id
        where i.service_order_id = o.id and q.status not in ('COMPLETED', 'CANCELLED'));
  perform set_config('app.void_order', 'off', true);
end;
$$;
