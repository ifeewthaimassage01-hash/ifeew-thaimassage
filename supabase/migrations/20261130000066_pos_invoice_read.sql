-- pos_invoice (อ่านบิลอย่างเดียว) มีอยู่แล้วตั้งแต่ 022 — ไฟล์นี้แทนที่ด้วยเวอร์ชันเดิม + แจ้ง "ไม่พบบิล" ชัดเจน
-- ใช้ในหน้า checkout ตอนโหลดใหม่จาก Realtime (pos_create_invoice สร้างบิลใหม่ถ้าบิลเดิมถูกยกเลิก จึงใช้โหลดซ้ำไม่ได้)
create or replace function public.pos_invoice(p_invoice_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_branch uuid;
begin
  select branch_id into v_branch from public.invoices where id = p_invoice_id;
  if v_branch is null then
    raise exception 'ไม่พบบิล' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(v_branch);
  return private.invoice_view(p_invoice_id);
end;
$$;

revoke all on function public.pos_invoice(uuid) from public, anon;
grant execute on function public.pos_invoice(uuid) to authenticated;
