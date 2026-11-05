-- =============================================================================
-- 032 — เปลี่ยนราคา/ค่าแรงเดิมไม่ต้องระบุเหตุผล (ตามที่ผู้ใช้ขอ)
--   แทนที่ save_branch_service_pricing (016): ยังต้องเป็น OWNER เหมือนเดิม
--   ไม่กรอกเหตุผล → บันทึกใน price_history ว่า “เปลี่ยนราคา” (ประวัติราคา + audit ยังครบ)
-- =============================================================================

create or replace function public.save_branch_service_pricing(
  p_branch_ids      uuid[],
  p_service_id      uuid,
  p_options         jsonb,
  p_effective_from  timestamptz,
  p_reason          text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company   uuid;
  v_eff       timestamptz := coalesce(p_effective_from, now());
  v_editing   boolean;
  v_reason    text;
  v_branch    uuid;
  v_bs        uuid;
  v_opt       public.branch_service_options;
  v_item      jsonb;
  v_duration  integer;
  v_price     numeric;
  v_fee       numeric;
  v_durations integer[] := '{}';
  v_changed   integer := 0;
begin
  select company_id into v_company from public.services where id = p_service_id and is_active;
  if v_company is null or not private.is_company_owner(v_company) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if p_branch_ids is null or cardinality(p_branch_ids) = 0 then
    raise exception 'กรุณาเลือกสาขา' using errcode = 'invalid_parameter_value';
  end if;
  if exists (
    select 1 from unnest(p_branch_ids) b(id)
     where not exists (select 1 from public.branches x where x.id = b.id and x.company_id = v_company)
  ) then
    raise exception 'สาขาไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;

  -- ตรวจรายการช่วงเวลา
  if jsonb_typeof(p_options) <> 'array' or jsonb_array_length(p_options) = 0 then
    raise exception 'กรุณาเพิ่มช่วงเวลาอย่างน้อย 1 ช่วง' using errcode = 'invalid_parameter_value';
  end if;
  for v_item in select * from jsonb_array_elements(p_options) loop
    v_duration := (v_item ->> 'duration_minutes')::integer;
    v_price := (v_item ->> 'price')::numeric;
    v_fee := coalesce((v_item ->> 'therapist_fee')::numeric, 0);
    if v_duration is null or v_duration not between 5 and 600 then
      raise exception 'ช่วงเวลาต้องอยู่ระหว่าง 5-600 นาที' using errcode = 'invalid_parameter_value';
    end if;
    if v_price is null or v_price < 0 or v_fee < 0 or v_price <> round(v_price, 2) or v_fee <> round(v_fee, 2) then
      raise exception 'ราคา/ค่าแรงของช่วง % นาทีไม่ถูกต้อง', v_duration using errcode = 'invalid_parameter_value';
    end if;
    if v_fee > v_price then
      raise exception 'ค่าแรงของช่วง % นาทีมากกว่าราคา', v_duration using errcode = 'invalid_parameter_value';
    end if;
    if v_duration = any (v_durations) then
      raise exception 'ช่วงเวลา % นาทีซ้ำ', v_duration using errcode = 'invalid_parameter_value';
    end if;
    v_durations := v_durations || v_duration;
  end loop;

  if v_eff < now() - interval '1 minute' then
    raise exception 'ห้ามเปลี่ยนราคาย้อนหลัง' using errcode = 'invalid_parameter_value';
  end if;
  if v_eff < now() then
    v_eff := now();
  end if;

  -- แก้ของเดิม = มีช่วงเวลาที่มีราคาอยู่แล้วในสาขาใดสาขาหนึ่ง
  v_editing := exists (
    select 1
      from public.branch_services bs
      join public.branch_service_options o on o.branch_service_id = bs.id
      join public.service_price_histories p on p.branch_service_option_id = o.id and p.status = 'ACTIVE'
     where bs.service_id = p_service_id and bs.branch_id = any (p_branch_ids)
  );
  if v_editing then
    perform private.require_owner_step_up(v_company);
    -- (032) ไม่บังคับเหตุผล — ไม่กรอกใช้ข้อความมาตรฐาน (price_history.reason ต้องยาว 3-500 ตัวอักษร)
    v_reason := left(coalesce(nullif(trim(p_reason), ''), 'เปลี่ยนราคา'), 500);
    if char_length(v_reason) < 3 then
      v_reason := 'เปลี่ยนราคา';
    end if;
  else
    v_reason := coalesce(nullif(trim(p_reason), ''), 'ราคาเริ่มต้น');
    if char_length(v_reason) < 3 then
      v_reason := 'ราคาเริ่มต้น';
    end if;
  end if;

  foreach v_branch in array p_branch_ids loop
    -- เปิดบริการที่สาขา (หรือเปิดกลับ)
    insert into public.branch_services (company_id, branch_id, service_id)
    values (v_company, v_branch, p_service_id)
    on conflict (branch_id, service_id) do update set is_active = true
    returning id into v_bs;

    -- ปิดช่วงเวลาที่ไม่อยู่ในรายการ
    update public.branch_service_options
       set is_active = false
     where branch_service_id = v_bs and is_active and not (duration_minutes = any (v_durations));
    v_changed := v_changed + (case when found then 1 else 0 end);

    for v_item in select * from jsonb_array_elements(p_options) loop
      v_duration := (v_item ->> 'duration_minutes')::integer;
      v_price := (v_item ->> 'price')::numeric;
      v_fee := coalesce((v_item ->> 'therapist_fee')::numeric, 0);

      insert into public.branch_service_options (company_id, branch_service_id, duration_minutes)
      values (v_company, v_bs, v_duration)
      on conflict (branch_service_id, duration_minutes) do update set is_active = true
      returning * into v_opt;

      if private.set_option_price(v_opt.id, v_price, v_fee, v_eff, v_reason) then
        v_changed := v_changed + 1;
      end if;
    end loop;
  end loop;

  return jsonb_build_object('changed', v_changed, 'effective_from', v_eff, 'step_up_required', v_editing);
end;
$$;

revoke all on function public.save_branch_service_pricing(uuid[], uuid, jsonb, timestamptz, text) from public, anon;
grant execute on function public.save_branch_service_pricing(uuid[], uuid, jsonb, timestamptz, text) to authenticated;
