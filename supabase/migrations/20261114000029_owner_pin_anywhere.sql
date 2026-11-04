-- =============================================================================
-- 029 — เจ้าของร้าน login ด้วย PIN อย่างเดียว (ไม่ต้องใช้เครื่องที่ผูก / อีเมล) ตามที่ผู้ใช้ขอ
--   เรียกจาก Edge Function owner-pin-login (service role) หลัง rate limit ต่อ IP/บริษัท
--   กฎ PIN และการล็อกเหมือนพนักงาน (staff_pins.failed_attempts / locked_until)
-- ความเสี่ยงที่ยอมรับ: ใครรู้ URL ของระบบลองเดา PIN จากที่ไหนก็ได้ (ป้องกันด้วยการล็อก + rate limit)
-- =============================================================================

create or replace function public.owner_verify_pin(p_company_code text, p_pin text, p_client_ip text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid := private.company_id_by_code(p_company_code);
  v_owner   uuid;
  sp        public.staff_pins;
  s         public.company_settings;
  v_meta    jsonb := jsonb_build_object('client_ip', p_client_ip, 'channel', 'OWNER_PIN');
begin
  if v_company is null then
    return jsonb_build_object('ok', false, 'error_code', 'INVALID_CREDENTIALS');
  end if;
  select cm.user_id into v_owner from public.company_memberships cm
   where cm.company_id = v_company and cm.role = 'OWNER' and cm.status = 'ACTIVE'
     and cm.effective_from <= now() and (cm.effective_to is null or cm.effective_to > now());

  select * into sp from public.staff_pins where company_id = v_company and user_id = v_owner for update;
  if v_owner is null or sp.user_id is null then
    return jsonb_build_object('ok', false, 'error_code', 'INVALID_CREDENTIALS');
  end if;
  if sp.locked_until is not null and sp.locked_until > now() then
    return jsonb_build_object('ok', false, 'error_code', 'PIN_LOCKED', 'locked_until', sp.locked_until);
  end if;

  select * into s from public.company_settings where company_id = v_company;

  if sp.pin_hash <> extensions.crypt(coalesce(p_pin, ''), sp.pin_hash) then
    if sp.failed_attempts + 1 >= s.staff_pin_max_attempts then
      update public.staff_pins
         set failed_attempts = 0, locked_until = now() + make_interval(mins => s.staff_pin_lockout_minutes)
       where company_id = sp.company_id and user_id = sp.user_id
      returning * into sp;
      perform private.write_audit(p_action => 'STAFF_PIN_LOCKED', p_company_id => v_company,
                                  p_actor => v_owner, p_metadata => v_meta);
      return jsonb_build_object('ok', false, 'error_code', 'PIN_LOCKED', 'locked_until', sp.locked_until);
    end if;
    update public.staff_pins set failed_attempts = failed_attempts + 1
     where company_id = sp.company_id and user_id = sp.user_id;
    perform private.write_audit(p_action => 'STAFF_PIN_LOGIN_FAILED', p_company_id => v_company,
                                p_actor => v_owner, p_metadata => v_meta);
    return jsonb_build_object('ok', false, 'error_code', 'INVALID_CREDENTIALS',
                              'attempts_left', s.staff_pin_max_attempts - (sp.failed_attempts + 1));
  end if;

  update public.staff_pins set failed_attempts = 0, locked_until = null
   where company_id = sp.company_id and user_id = sp.user_id and (failed_attempts <> 0 or locked_until is not null);
  perform private.write_audit(p_action => 'STAFF_PIN_LOGIN_SUCCESS', p_company_id => v_company,
                              p_actor => v_owner, p_metadata => v_meta);
  return jsonb_build_object('ok', true, 'user_id', v_owner, 'company_id', v_company,
                            'idle_lock_minutes', s.staff_idle_lock_minutes);
end;
$$;

revoke all on function public.owner_verify_pin(text, text, text) from public, anon, authenticated;
grant execute on function public.owner_verify_pin(text, text, text) to service_role;
