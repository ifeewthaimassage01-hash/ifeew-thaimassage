-- 079 — แก้สรุปประจำวัน (077)
--   1) push_outbox: DAILY_SUMMARY เป็นของทั้งร้าน ไม่มีสาขา/รายการอ้างอิง → ให้ branch_id/ref_id ว่างได้เฉพาะเหตุการณ์นี้
--      (เดิม NOT NULL → "null value in column branch_id of relation push_outbox")
--   2) tick: บันทึกว่าส่งแล้ว (summary_last_date) หลังเข้าคิวส่งสำเร็จเท่านั้น — เดิมบันทึกก่อน ถ้าส่งพลาดวันนั้นจะไม่ส่งอีก

alter table private.push_outbox alter column branch_id drop not null;
alter table private.push_outbox alter column ref_id drop not null;
alter table private.push_outbox add constraint push_outbox_refs_chk
  check (event = 'DAILY_SUMMARY' or (branch_id is not null and ref_id is not null));

create or replace function private.line_daily_summary_tick()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r        record;
  v_now    timestamp;
  v_target date;
begin
  for r in
    select ls.company_id, ls.summary_time, ls.summary_last_date, coalesce(s.timezone, 'Asia/Bangkok') as tz
      from private.line_settings ls
      left join public.company_settings s on s.company_id = ls.company_id
     where ls.summary_enabled and ls.owner_line_user_id is not null and ls.access_token_secret_id is not null
     for update of ls skip locked
  loop
    v_now := now() at time zone r.tz;
    if v_now::time < r.summary_time then
      continue;
    end if;
    -- ส่งก่อนเที่ยงวัน = สรุปของเมื่อวาน
    v_target := case when r.summary_time < '12:00' then v_now::date - 1 else v_now::date end;
    if r.summary_last_date is not null and r.summary_last_date >= v_target then
      continue;
    end if;
    begin
      perform private.line_daily_summary_enqueue(r.company_id, v_target);
      update private.line_settings set summary_last_date = v_target where company_id = r.company_id;
    exception when others then
      -- ไม่บันทึกว่าส่งแล้ว → รอบถัดไป (5 นาที) ลองใหม่
      raise warning 'line_daily_summary_tick %: %', r.company_id, sqlerrm;
    end;
  end loop;
end;
$$;

-- tick ที่รันก่อนแก้อาจบันทึกว่าส่งแล้วทั้งที่ส่งไม่สำเร็จ → ตั้งเป็น "เมื่อวานผ่านไปแล้ว"
--   (ไม่ล้างเป็นว่าง เพราะจะส่งสรุปของเมื่อวานทันทีตอน deploy) · ครั้งแรกที่ส่งจริง = รอบเวลาที่ตั้งไว้ครั้งถัดไป
update private.line_settings ls
   set summary_last_date = (now() at time zone 'Asia/Bangkok')::date - 1
 where ls.owner_line_user_id is not null
   and not exists (select 1 from private.push_outbox o where o.company_id = ls.company_id and o.event = 'DAILY_SUMMARY');
