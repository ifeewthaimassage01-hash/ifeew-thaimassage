-- แก้ "invalid regular expression: invalid repetition count(s)" ตอนบันทึกการตั้งค่า LINE
--   Postgres จำกัดตัวนับซ้ำใน regex ไม่เกิน 255 แต่ 059 ใช้ {4,300} (ลิงก์เพิ่มเพื่อน) และ {20,1000} (Channel access token)
--   → ตรวจตัวอักษรด้วย regex และตรวจความยาวด้วย char_length แทน (กติกาเท่าเดิม)

alter table private.line_settings drop constraint if exists line_settings_add_friend_url_check;
alter table private.line_settings add constraint line_settings_add_friend_url_check
  check (add_friend_url is null or (add_friend_url ~ '^https://[^\s]+$' and char_length(add_friend_url) between 12 and 308));

create or replace function public.line_set_credentials(p_company_id uuid, p_access_token text, p_channel_secret text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  s private.line_settings;
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'เฉพาะเจ้าของร้าน' using errcode = 'insufficient_privilege';
  end if;
  p_access_token := trim(p_access_token);
  p_channel_secret := trim(p_channel_secret);
  if p_access_token <> '' and (p_access_token !~ '^[A-Za-z0-9+/=._-]+$' or char_length(p_access_token) not between 20 and 1000) then
    raise exception 'Channel access token ไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  if p_channel_secret <> '' and p_channel_secret !~ '^[0-9a-f]{32}$' then
    raise exception 'Channel secret ต้องเป็นตัวอักษร 0-9 a-f 32 ตัว' using errcode = 'invalid_parameter_value';
  end if;

  insert into private.line_settings (company_id) values (p_company_id) on conflict do nothing;
  select * into s from private.line_settings where company_id = p_company_id for update;

  if p_access_token is not null then
    if p_access_token = '' then
      delete from vault.secrets where id = s.access_token_secret_id;
      s.access_token_secret_id := null;
      s.access_token_hint := null;
      s.bot_name := null;
      s.bot_basic_id := null;
    elsif s.access_token_secret_id is null then
      s.access_token_secret_id := vault.create_secret(p_access_token, 'line_access_token_' || p_company_id, 'LINE Messaging API channel access token');
      s.access_token_hint := right(p_access_token, 4);
    else
      perform vault.update_secret(s.access_token_secret_id, p_access_token);
      s.access_token_hint := right(p_access_token, 4);
    end if;
  end if;

  if p_channel_secret is not null then
    if p_channel_secret = '' then
      delete from vault.secrets where id = s.channel_secret_secret_id;
      s.channel_secret_secret_id := null;
    elsif s.channel_secret_secret_id is null then
      s.channel_secret_secret_id := vault.create_secret(p_channel_secret, 'line_channel_secret_' || p_company_id, 'LINE Messaging API channel secret');
    else
      perform vault.update_secret(s.channel_secret_secret_id, p_channel_secret);
    end if;
  end if;

  update private.line_settings
     set access_token_secret_id = s.access_token_secret_id, access_token_hint = s.access_token_hint,
         channel_secret_secret_id = s.channel_secret_secret_id, bot_name = s.bot_name, bot_basic_id = s.bot_basic_id,
         updated_at = now(), updated_by = auth.uid()
   where company_id = p_company_id;
end;
$$;
