-- 078 — สรุปประจำวัน: ยอดติดลบแสดงเป็น −฿270 (เดิม ฿-270) · "สรุป" ในแชทได้ลิงก์เปิดแดชบอร์ดด้วย

create or replace function private.line_baht(p numeric)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p < 0 then '−฿' else '฿' end || to_char(abs(coalesce(p, 0)), 'FM999,999,990');
$$;

create or replace function private.line_daily_summary_text(p jsonb, p_title text)
returns text
language sql
immutable
set search_path = ''
as $$
  select concat_ws(E'\n',
    '📊 ' || p_title,
    'ยอดสุทธิ ' || private.line_baht((p->'total'->>'net')::numeric),
    'รายได้ ' || private.line_baht((p->'total'->>'revenue')::numeric),
    'รายจ่าย ' || private.line_baht((p->'total'->>'expenses')::numeric),
    'ค่าแรงหมอ ' || private.line_baht((p->'total'->>'therapist_pay')::numeric),
    'ลูกค้า ' || (p->'total'->>'customers') || ' คน',
    case when (p->>'pending_slips')::int > 0 then 'สลิปรอตรวจ ' || (p->>'pending_slips') || ' รายการ' end,
    case when (p->>'unpaid_bills')::int > 0 then 'บิลค้างชำระ ' || (p->>'unpaid_bills') || ' บิล' end,
    'นัดพรุ่งนี้ ' || (p->>'tomorrow_bookings') || ' การจอง');
$$;

create or replace function public.line_owner_summary_now(p_company_id uuid, p_line_user_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tz  text;
  v_url text;
begin
  select ls.staff_url into v_url from private.line_settings ls
   where ls.company_id = p_company_id and ls.owner_line_user_id = p_line_user_id;
  if not found then
    return null;
  end if;
  select coalesce(s.timezone, 'Asia/Bangkok') into v_tz from public.company_settings s where s.company_id = p_company_id;
  return private.line_daily_summary_data(p_company_id, (now() at time zone coalesce(v_tz, 'Asia/Bangkok'))::date)
         || jsonb_build_object('company_name', (select name from public.companies where id = p_company_id), 'link', v_url);
end;
$$;
revoke all on function public.line_owner_summary_now(uuid, text) from public, anon, authenticated;
grant execute on function public.line_owner_summary_now(uuid, text) to service_role;
