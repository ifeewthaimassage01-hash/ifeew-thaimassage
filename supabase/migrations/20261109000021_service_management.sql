-- =============================================================================
-- Phase 6 / 021 — Service Management
--   เปลี่ยนหมอระหว่างให้บริการ (แบ่งค่ามือตามนาที), ต่อเวลา (เริ่มต่อทันทีหลังจบรายการเดิม),
--   ย้อน "เริ่ม/จบบริการ" ภายใน 15 นาที, หมอกดคิวด้วย PIN บนเครื่องสาขา,
--   ประวัติบริการ (ลูกค้า/หมอ/OWNER) และแดชบอร์ด STAFF
-- ค่ามือ = therapist_fee ที่ Snapshot ไว้ในรายการ (จำนวนคงที่ ไม่หักตามส่วนลด) — ยอดจริงคำนวณใน Phase 8
-- =============================================================================

-- -----------------------------------------------------------------------------
-- โครงสร้าง
-- -----------------------------------------------------------------------------
-- 1 คิวมีหมอที่ "กำลังรับผิดชอบ" ได้ 1 คน (คนก่อนหน้าที่ส่งต่อแล้วเป็น COMPLETED)
drop index public.service_assignments_one_per_queue;
create unique index service_assignments_one_active_per_queue
  on public.service_assignments (queue_item_id) where status in ('ASSIGNED', 'ACCEPTED', 'IN_SERVICE');

alter table public.service_assignments
  add column handover_reason text check (handover_reason is null or char_length(handover_reason) <= 500);

comment on column public.service_assignments.handover_reason is
  'เหตุผลที่ส่งต่อให้หมอคนอื่นระหว่างให้บริการ (แถวนี้ COMPLETED ณ เวลาส่งต่อ)';

-- ต่อเวลา: คิวใหม่ที่เริ่มต่อจากคิวเดิมทันที (หมอคนเดิม)
alter table public.queue_items
  add column follows_queue_id uuid,
  add constraint queue_items_follows_fk foreign key (company_id, branch_id, follows_queue_id)
    references public.queue_items (company_id, branch_id, id) on delete restrict,
  add constraint queue_items_follows_self_chk check (follows_queue_id is null or follows_queue_id <> id);

create index queue_items_follows_idx on public.queue_items (follows_queue_id) where follows_queue_id is not null;

-- -----------------------------------------------------------------------------
-- Guards (แทนที่ 020): เพิ่มการย้อนสถานะ IN_SERVICE → ACCEPTED, COMPLETED → IN_SERVICE
--   (เงื่อนไข 15 นาที/เหตุผล บังคับใน Function queue_undo_*)
-- -----------------------------------------------------------------------------
create or replace function private.tg_queue_items_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.company_id <> old.company_id or new.branch_id <> old.branch_id
     or new.service_order_item_id <> old.service_order_item_id
     or new.queue_date <> old.queue_date or new.queue_number <> old.queue_number
     or (old.follows_queue_id is not null and new.follows_queue_id is distinct from old.follows_queue_id) then
    raise exception 'ห้ามแก้เลขคิว/รายการของคิว' using errcode = 'check_violation';
  end if;
  if new.status <> old.status and not (
       (old.status = 'WAITING' and new.status in ('CALLED', 'CANCELLED'))
    or (old.status = 'CALLED' and new.status in ('ACCEPTED', 'CANCELLED'))
    or (old.status = 'ACCEPTED' and new.status in ('IN_SERVICE', 'CALLED', 'CANCELLED'))
    or (old.status = 'IN_SERVICE' and new.status in ('COMPLETED', 'ACCEPTED'))
    or (old.status = 'COMPLETED' and new.status = 'IN_SERVICE')
  ) then
    raise exception 'เปลี่ยนสถานะคิวจาก % เป็น % ไม่ได้', old.status, new.status using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create or replace function private.tg_service_assignments_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.company_id <> old.company_id or new.branch_id <> old.branch_id
     or new.queue_item_id <> old.queue_item_id or new.employee_id <> old.employee_id then
    raise exception 'ห้ามเปลี่ยนหมอ/คิวของการมอบหมาย (ให้ยกเลิกแล้วมอบหมายใหม่)' using errcode = 'check_violation';
  end if;
  if new.status <> old.status and not (
       (old.status = 'ASSIGNED' and new.status in ('ACCEPTED', 'CANCELLED'))
    or (old.status = 'ACCEPTED' and new.status in ('IN_SERVICE', 'CANCELLED'))
    or (old.status = 'IN_SERVICE' and new.status in ('COMPLETED', 'ACCEPTED'))
    or (old.status = 'COMPLETED' and new.status = 'IN_SERVICE')
  ) then
    raise exception 'เปลี่ยนสถานะการมอบหมายจาก % เป็น % ไม่ได้', old.status, new.status using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- ค่ามือประมาณการของการมอบหมาย (เฉพาะคิวที่จบแล้ว) แบ่งตามเวลาที่ทำจริง
-- -----------------------------------------------------------------------------
create or replace function private.assignment_fee(p_assignment_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  with a as (
    select sa.*, i.therapist_fee, q.status as queue_status
      from public.service_assignments sa
      join public.queue_items q on q.id = sa.queue_item_id
      join public.service_order_items i on i.id = q.service_order_item_id
     where sa.id = p_assignment_id
  ),
  peers as (
    select p.id, greatest(extract(epoch from (p.completed_at - p.started_at)), 0) as secs
      from public.service_assignments p, a
     where p.queue_item_id = a.queue_item_id and p.status = 'COMPLETED'
  ),
  tot as (select sum(secs) as total, count(*) as n from peers)
  select case
           when a.status <> 'COMPLETED' or a.queue_status <> 'COMPLETED' then null
           when tot.total > 0 then round(a.therapist_fee * (select secs from peers where id = a.id) / tot.total, 2)
           else round(a.therapist_fee / tot.n, 2)
         end
    from a, tot;
$$;

revoke all on function private.assignment_fee(uuid) from public;

-- ไม่ให้ไม่มีการแก้ไขที่หลุดรอด: Order view ใหม่ (หมอที่รับผิดชอบปัจจุบัน/ล่าสุด + ประวัติส่งต่อ + ต่อเวลา)
create or replace function private.pos_order_view(p_order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'order_id', o.id,
    'channel', o.channel,
    'status', o.status,
    'business_date', o.business_date,
    'booking_id', o.booking_id,
    'booking_code', b.booking_code,
    'customer_id', o.customer_id,
    'customer_name', case when c.id is null then null else trim(c.first_name || ' ' || c.last_name) end,
    'phone_masked', private.mask_phone(c.phone),
    'note', o.note,
    'cancel_reason', o.cancel_reason,
    'created_at', o.created_at,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'item_id', i.id,
        'service_name', i.service_name,
        'duration_minutes', i.duration_minutes,
        'unit_price', i.unit_price,
        'item_status', i.status,
        'queue_id', q.id,
        'queue_number', q.queue_number,
        'queue_status', q.status,
        'follows_queue_id', q.follows_queue_id,
        'planned_starts_at', q.planned_starts_at,
        'planned_ends_at', q.planned_ends_at,
        'called_at', q.called_at,
        'started_at', q.started_at,
        'completed_at', q.completed_at,
        'cancel_reason', coalesce(q.cancel_reason, i.cancel_reason),
        'therapist', (
          select jsonb_build_object('employee_id', e.id, 'nickname', e.nickname, 'user_id', e.user_id,
                                    'assignment_status', a.status, 'off_shift_confirmed', a.off_shift_confirmed,
                                    'started_at', a.started_at)
            from public.service_assignments a join public.employees e on e.id = a.employee_id
           where a.queue_item_id = q.id and a.status <> 'CANCELLED'
           order by (a.status in ('ASSIGNED', 'ACCEPTED', 'IN_SERVICE')) desc, a.completed_at desc nulls first
           limit 1),
        'handovers', coalesce((
          select jsonb_agg(jsonb_build_object('nickname', e.nickname, 'started_at', a.started_at,
                                              'ended_at', a.completed_at, 'reason', a.handover_reason)
                           order by a.started_at)
            from public.service_assignments a join public.employees e on e.id = a.employee_id
           where a.queue_item_id = q.id and a.handover_reason is not null), '[]'::jsonb)
      ) order by q.queue_number)
        from public.service_order_items i
        join public.queue_items q on q.service_order_item_id = i.id
       where i.service_order_id = o.id), '[]'::jsonb)
  )
  from public.service_orders o
  left join public.customers c on c.id = o.customer_id
  left join public.bookings b on b.id = o.booking_id
  where o.id = p_order_id;
$$;

-- เลื่อนช่วงจองทรัพยากรของรายการไปเริ่ม "ตอนนี้" (ใช้ตอนเริ่มบริการ/ต่อเวลาอัตโนมัติ)
create or replace function private.shift_item_allocations_to_now(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  i        public.service_order_items;
  v_buffer integer;
  v_hint   text;
begin
  select * into i from public.service_order_items where id = p_item_id;
  select booking_buffer_minutes into v_buffer from public.company_settings where company_id = i.company_id;
  begin
    update public.resource_allocations
       set status = 'IN_USE', expires_at = null,
           starts_at = now(), ends_at = now() + make_interval(mins => i.duration_minutes + v_buffer)
     where service_order_item_id = i.id and status <> 'RELEASED';
  exception when sqlstate 'P0001' then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint = 'CAPACITY_FULL' then
      raise exception 'เตียง/อุปกรณ์ไม่ว่างพอที่จะเริ่มตอนนี้ (ช่วงถัดไปมีคิวจองไว้) กรุณารอหรือเปลี่ยนบริการ'
        using errcode = 'P0001', hint = 'CAPACITY_FULL';
    end if;
    raise;
  end;
end;
$$;

revoke all on function private.shift_item_allocations_to_now(uuid) from public;

-- (แทนที่ 020) เริ่มบริการ — ใช้ helper เดียวกับต่อเวลา
create or replace function public.queue_start(p_queue_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  q       public.queue_items;
  v_order uuid;
begin
  select * into q from public.queue_items where id = p_queue_id for update;
  if q.id is null then
    raise exception 'ไม่พบคิว' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(q.branch_id);
  if q.status <> 'ACCEPTED' then
    raise exception 'เริ่มบริการได้เฉพาะคิวที่หมอรับแล้ว' using errcode = 'check_violation';
  end if;

  perform private.shift_item_allocations_to_now(q.service_order_item_id);
  update public.service_assignments set status = 'IN_SERVICE', started_at = now()
   where queue_item_id = q.id and status = 'ACCEPTED';
  update public.queue_items set status = 'IN_SERVICE', started_at = now(), started_by = auth.uid() where id = q.id;

  select i.service_order_id into v_order from public.service_order_items i where i.id = q.service_order_item_id;
  return private.pos_order_view(v_order);
end;
$$;

-- (แทนที่ 020) จบบริการ + เริ่มรายการต่อเวลาให้หมอคนเดิมทันที (ถ้าเตียงไม่พอ คิวต่อเวลารอหน้าร้านจัดการ)
create or replace function public.queue_complete(p_queue_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  q          public.queue_items;
  f          public.queue_items;
  v_employee uuid;
  v_order    uuid;
begin
  select * into q from public.queue_items where id = p_queue_id for update;
  if q.id is null then
    raise exception 'ไม่พบคิว' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(q.branch_id);
  if q.status <> 'IN_SERVICE' then
    raise exception 'จบบริการได้เฉพาะคิวที่กำลังให้บริการ' using errcode = 'check_violation';
  end if;

  update public.resource_allocations
     set status = 'RELEASED', released_at = now(), release_reason = 'จบบริการ', expires_at = null
   where service_order_item_id = q.service_order_item_id and status <> 'RELEASED';
  update public.service_assignments set status = 'COMPLETED', completed_at = now()
   where queue_item_id = q.id and status = 'IN_SERVICE'
  returning employee_id into v_employee;
  update public.queue_items set status = 'COMPLETED', completed_at = now(), completed_by = auth.uid() where id = q.id;

  -- ต่อเวลา: เริ่มคิวถัดไปทันทีด้วยหมอคนเดิม
  select * into f from public.queue_items where follows_queue_id = q.id and status = 'WAITING' for update;
  if f.id is not null and v_employee is not null then
    begin
      perform private.assert_therapist_available(f.company_id, f.branch_id, v_employee, true);
      perform private.shift_item_allocations_to_now(f.service_order_item_id);
      insert into public.service_assignments (company_id, branch_id, queue_item_id, employee_id, status,
                                              assigned_by, accepted_at, accepted_by, started_at)
      values (f.company_id, f.branch_id, f.id, v_employee, 'IN_SERVICE', auth.uid(), now(), auth.uid(), now());
      update public.queue_items set status = 'CALLED', called_at = now(), called_by = auth.uid() where id = f.id;
      update public.queue_items set status = 'ACCEPTED', accepted_at = now(), accepted_by = auth.uid() where id = f.id;
      update public.queue_items set status = 'IN_SERVICE', started_at = now(), started_by = auth.uid() where id = f.id;
    exception when sqlstate 'P0001' or sqlstate '23514' then
      null;   -- เริ่มต่ออัตโนมัติไม่ได้ (เช่นเตียงเต็ม) คิวต่อเวลายังรอเรียกตามปกติ
    end;
  end if;

  select i.service_order_id into v_order from public.service_order_items i where i.id = q.service_order_item_id;
  perform private.refresh_order_status(v_order);
  return private.pos_order_view(v_order);
end;
$$;

-- -----------------------------------------------------------------------------
-- ต่อเวลา: เพิ่มรายการต่อจากคิวที่กำลังให้บริการ (หมอคนเดิม เริ่มทันทีเมื่อจบรายการเดิม)
-- -----------------------------------------------------------------------------
create or replace function public.queue_extend(p_queue_id uuid, p_option_id uuid, p_idempotency_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  q        public.queue_items;
  i        public.service_order_items;
  o        public.service_orders;
  v_prev   jsonb;
  v_start  timestamptz;
  v_date   date;
  v_item   uuid;
  v_result jsonb;
  v_hash   text := private.request_hash(jsonb_build_object('q', p_queue_id, 'o', p_option_id));
begin
  select * into q from public.queue_items where id = p_queue_id for update;
  if q.id is null then
    raise exception 'ไม่พบคิว' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(q.branch_id);
  select * into i from public.service_order_items where id = q.service_order_item_id;
  select * into o from public.service_orders where id = i.service_order_id for update;

  v_prev := private.idempotency_begin('queue_extend', p_idempotency_key, v_hash);
  if v_prev is not null then
    return v_prev -> 'body';
  end if;

  if q.status <> 'IN_SERVICE' then
    raise exception 'ต่อเวลาได้เฉพาะคิวที่กำลังให้บริการ' using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.queue_items where follows_queue_id = q.id and status <> 'CANCELLED') then
    raise exception 'คิวนี้ต่อเวลาไว้แล้ว' using errcode = 'check_violation';
  end if;

  v_start := greatest(q.started_at + make_interval(mins => i.duration_minutes), now());
  -- ลูกค้าคนเดิมใช้เตียงเดิมต่อ: ย้ายเวลาเผื่อทำความสะอาดของรายการเดิมไปไว้หลังรายการต่อเวลา
  update public.resource_allocations set ends_at = v_start
   where service_order_item_id = i.id and status <> 'RELEASED' and ends_at > v_start;
  v_date := private.reserve_walkin(q.branch_id, v_start, array[p_option_id]);
  if v_date <> o.business_date then
    raise exception 'ต่อเวลาได้เฉพาะภายในวันทำการนี้' using errcode = 'check_violation';
  end if;

  v_item := private.add_order_item(o.id, p_option_id, v_start);
  update public.queue_items set follows_queue_id = q.id where service_order_item_id = v_item;

  v_result := private.pos_order_view(o.id);
  perform private.idempotency_complete('queue_extend', p_idempotency_key, 200, v_result);
  return v_result;
end;
$$;

-- -----------------------------------------------------------------------------
-- เปลี่ยนหมอระหว่างให้บริการ (ต้องมีเหตุผล) — ค่ามือแบ่งตามนาทีที่แต่ละคนทำ
-- -----------------------------------------------------------------------------
create or replace function public.queue_handover(
  p_queue_id           uuid,
  p_employee_id        uuid,
  p_reason             text,
  p_confirm_off_shift  boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  q          public.queue_items;
  a          public.service_assignments;
  v_on_shift boolean;
  v_order    uuid;
begin
  select * into q from public.queue_items where id = p_queue_id for update;
  if q.id is null then
    raise exception 'ไม่พบคิว' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(q.branch_id);
  if q.status <> 'IN_SERVICE' then
    raise exception 'เปลี่ยนหมอระหว่างบริการได้เฉพาะคิวที่กำลังให้บริการ' using errcode = 'check_violation';
  end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาระบุเหตุผลที่เปลี่ยนหมอ' using errcode = 'invalid_parameter_value';
  end if;
  select * into a from public.service_assignments where queue_item_id = q.id and status = 'IN_SERVICE' for update;
  if a.employee_id = p_employee_id then
    raise exception 'หมอคนนี้กำลังให้บริการคิวนี้อยู่แล้ว' using errcode = 'check_violation';
  end if;

  perform set_config('app.audit_reason', trim(p_reason), true);
  if a.id is not null then
    update public.service_assignments
       set status = 'COMPLETED', completed_at = now(), handover_reason = left(trim(p_reason), 500)
     where id = a.id;
  end if;

  v_on_shift := private.assert_therapist_available(q.company_id, q.branch_id, p_employee_id, p_confirm_off_shift);
  insert into public.service_assignments (company_id, branch_id, queue_item_id, employee_id, status, off_shift_confirmed,
                                          assigned_by, accepted_at, accepted_by, started_at)
  values (q.company_id, q.branch_id, q.id, p_employee_id, 'IN_SERVICE', not v_on_shift,
          auth.uid(), now(), auth.uid(), now());

  select i.service_order_id into v_order from public.service_order_items i where i.id = q.service_order_item_id;
  return private.pos_order_view(v_order);
end;
$$;

-- -----------------------------------------------------------------------------
-- ย้อน "เริ่มบริการ" (กดผิด) ภายใน 15 นาที — เตียงยังกันไว้ตามช่วงที่เริ่ม
-- -----------------------------------------------------------------------------
create or replace function public.queue_undo_start(p_queue_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  q       public.queue_items;
  v_order uuid;
begin
  select * into q from public.queue_items where id = p_queue_id for update;
  if q.id is null then
    raise exception 'ไม่พบคิว' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(q.branch_id);
  if q.status <> 'IN_SERVICE' or q.started_at < now() - interval '15 minutes' then
    raise exception 'ย้อนการเริ่มบริการได้ภายใน 15 นาทีเท่านั้น' using errcode = 'check_violation';
  end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาระบุเหตุผล' using errcode = 'invalid_parameter_value';
  end if;
  if (select count(*) from public.service_assignments where queue_item_id = q.id and status <> 'CANCELLED') > 1 then
    raise exception 'คิวนี้เปลี่ยนหมอระหว่างบริการแล้ว ย้อนไม่ได้' using errcode = 'check_violation';
  end if;

  perform set_config('app.audit_reason', trim(p_reason), true);
  update public.service_assignments set status = 'ACCEPTED', started_at = null
   where queue_item_id = q.id and status = 'IN_SERVICE';
  update public.queue_items set status = 'ACCEPTED', started_at = null, started_by = null where id = q.id;

  select i.service_order_id into v_order from public.service_order_items i where i.id = q.service_order_item_id;
  return private.pos_order_view(v_order);
end;
$$;

-- -----------------------------------------------------------------------------
-- ย้อน "จบบริการ" ภายใน 15 นาที (ก่อนออก Invoice — Phase 7 จะเพิ่มเงื่อนไข)
--   จองเตียงกลับ (ตอนนี้ → เวลาจบเดิม) ถ้าเตียงถูกใช้ไปแล้วย้อนไม่ได้
--   การจองที่ COMPLETED แล้วคงสถานะเดิม (สถานะสุดท้ายตามสเปกข้อ 9)
-- -----------------------------------------------------------------------------
create or replace function public.queue_undo_complete(p_queue_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  q        public.queue_items;
  i        public.service_order_items;
  a        public.service_assignments;
  r        record;
  v_buffer integer;
  v_end    timestamptz;
  v_hint   text;
begin
  select * into q from public.queue_items where id = p_queue_id for update;
  if q.id is null then
    raise exception 'ไม่พบคิว' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(q.branch_id);
  select * into i from public.service_order_items where id = q.service_order_item_id;
  perform 1 from public.service_orders where id = i.service_order_id for update;

  if q.status <> 'COMPLETED' or q.completed_at < now() - interval '15 minutes' then
    raise exception 'ย้อนการจบบริการได้ภายใน 15 นาทีเท่านั้น' using errcode = 'check_violation';
  end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาระบุเหตุผล' using errcode = 'invalid_parameter_value';
  end if;
  if exists (select 1 from public.queue_items
              where follows_queue_id = q.id and status not in ('WAITING', 'CANCELLED')) then
    raise exception 'รายการต่อเวลาเริ่มไปแล้ว ย้อนไม่ได้' using errcode = 'check_violation';
  end if;

  select * into a from public.service_assignments
   where queue_item_id = q.id and status = 'COMPLETED' and handover_reason is null
   order by completed_at desc limit 1 for update;
  if a.id is not null and exists (
    select 1 from public.service_assignments
     where employee_id = a.employee_id and status in ('ASSIGNED', 'ACCEPTED', 'IN_SERVICE')
  ) then
    raise exception 'หมอรับคิวอื่นไปแล้ว ย้อนไม่ได้' using errcode = 'check_violation';
  end if;

  perform set_config('app.audit_reason', trim(p_reason), true);

  -- จองเตียงกลับตามประเภทเดิมของรายการ
  select booking_buffer_minutes into v_buffer from public.company_settings where company_id = q.company_id;
  v_end := greatest(q.started_at + make_interval(mins => i.duration_minutes), now() + interval '5 minutes')
           + make_interval(mins => v_buffer);
  begin
    for r in
      select distinct on (resource_type_id) resource_type_id, quantity
        from public.resource_allocations
       where service_order_item_id = i.id
       order by resource_type_id, created_at desc
    loop
      insert into public.resource_allocations (company_id, branch_id, resource_type_id, service_order_item_id,
                                               quantity, starts_at, ends_at, status)
      values (q.company_id, q.branch_id, r.resource_type_id, i.id, r.quantity, now(), v_end, 'IN_USE');
    end loop;
  exception when sqlstate 'P0001' then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint = 'CAPACITY_FULL' then
      raise exception 'เตียง/อุปกรณ์ถูกใช้ต่อไปแล้ว ย้อนการจบบริการไม่ได้' using errcode = 'P0001', hint = 'CAPACITY_FULL';
    end if;
    raise;
  end;

  if a.id is not null then
    update public.service_assignments set status = 'IN_SERVICE', completed_at = null where id = a.id;
  end if;
  update public.queue_items set status = 'IN_SERVICE', completed_at = null, completed_by = null where id = q.id;
  perform private.refresh_order_status(i.service_order_id);
  return private.pos_order_view(i.service_order_id);
end;
$$;

-- -----------------------------------------------------------------------------
-- หมอกดคิวของตัวเองด้วย PIN บนเครื่องสาขา (เรียกจาก Edge Function queue-pin-action
-- หลังตรวจ PIN ด้วย device_verify_staff_pin แล้ว) — ทำในนามหมอคนนั้น
-- -----------------------------------------------------------------------------
create or replace function public.device_queue_action(
  p_device_token text,
  p_user_id      uuid,
  p_queue_id     uuid,
  p_action       text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  d          public.branch_devices;
  q          public.queue_items;
  v_sub      text := current_setting('request.jwt.claim.sub', true);
  v_claims   text := current_setting('request.jwt.claims', true);
  v_result   jsonb;
begin
  d := private.find_active_device(p_device_token);
  if d.id is null then
    raise exception 'เครื่องนี้ยังไม่ได้ผูกกับสาขา' using errcode = 'insufficient_privilege';
  end if;
  select * into q from public.queue_items where id = p_queue_id;
  if q.id is null or q.branch_id <> d.branch_id then
    raise exception 'ไม่พบคิวในสาขานี้' using errcode = 'insufficient_privilege';
  end if;
  if not exists (
    select 1 from public.service_assignments a join public.employees e on e.id = a.employee_id
     where a.queue_item_id = q.id and a.status in ('ASSIGNED', 'ACCEPTED', 'IN_SERVICE') and e.user_id = p_user_id
  ) then
    raise exception 'คิวนี้ไม่ใช่คิวของคุณ' using errcode = 'insufficient_privilege';
  end if;

  -- ทำงานในนามหมอ (auth.uid() = หมอ) เฉพาะใน Transaction นี้
  perform set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user_id, 'role', 'authenticated', 'aal', 'aal1')::text, true);

  if p_action = 'ACCEPT' then
    v_result := public.queue_accept(q.id);
  elsif p_action = 'START' then
    v_result := public.queue_start(q.id);
  elsif p_action = 'COMPLETE' then
    v_result := public.queue_complete(q.id);
  else
    raise exception 'คำสั่งไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;

  -- คืนตัวตนเดิมของ request
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  return v_result;
end;
$$;

-- -----------------------------------------------------------------------------
-- ประวัติบริการของลูกค้า (Customer App) — เฉพาะรายการที่ทำเสร็จ
-- -----------------------------------------------------------------------------
create or replace function private.customer_service_history(p_customer_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'business_date', o.business_date,
      'branch_name', br.name,
      'service_name', i.service_name,
      'service_name_en', i.service_name_en,
      'duration_minutes', i.duration_minutes,
      'unit_price', i.unit_price,
      'line_total', i.line_total,
      'started_at', q.started_at,
      'completed_at', q.completed_at,
      'therapists', (select coalesce(jsonb_agg(e.nickname order by a.started_at), '[]'::jsonb)
                       from public.service_assignments a join public.employees e on e.id = a.employee_id
                      where a.queue_item_id = q.id and a.status = 'COMPLETED')
    ) order by q.completed_at desc), '[]'::jsonb)
    from public.service_orders o
    join public.branches br on br.id = o.branch_id
    join public.service_order_items i on i.service_order_id = o.id
    join public.queue_items q on q.service_order_item_id = i.id
   where o.customer_id = p_customer_id and q.status = 'COMPLETED';
$$;

revoke all on function private.customer_service_history(uuid) from public;

create or replace function public.my_service_history(p_company_code text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select private.customer_service_history((private.my_customer_row(p_company_code)).id);
$$;

-- (แทนที่ 019) ส่งออกข้อมูล (PDPA) รวมประวัติการใช้บริการ
create or replace function public.export_my_data(p_company_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.customers := private.my_customer_row(p_company_code);
begin
  if c.id is null then
    raise exception 'ไม่พบข้อมูลลูกค้า' using errcode = 'no_data_found';
  end if;
  perform private.write_audit(p_action => 'CUSTOMER_DATA_EXPORTED', p_company_id => c.company_id,
                              p_table_name => 'customers', p_record_id => c.id);
  return jsonb_build_object(
    'exported_at', now(),
    'profile', (select jsonb_build_object('display_name', p.display_name, 'phone', p.phone) from public.profiles p where p.id = auth.uid()),
    'customer', jsonb_build_object(
      'first_name', c.first_name, 'last_name', c.last_name, 'phone', c.phone, 'email', c.email, 'created_at', c.created_at),
    'consents', coalesce((
      select jsonb_agg(jsonb_build_object('type', cc.consent_type, 'granted', cc.granted, 'channel', cc.channel,
                                          'version', p.version, 'recorded_at', cc.recorded_at) order by cc.recorded_at)
        from public.customer_consents cc join public.privacy_policy_versions p on p.id = cc.policy_version_id
       where cc.customer_id = c.id), '[]'::jsonb),
    'data_requests', coalesce((
      select jsonb_agg(jsonb_build_object('type', r.request_type, 'status', r.status, 'requested_at', r.requested_at,
                                          'processed_at', r.processed_at) order by r.requested_at)
        from public.customer_data_requests r where r.customer_id = c.id), '[]'::jsonb),
    'bookings', coalesce((
      select jsonb_agg(private.booking_customer_view(b.id) order by b.starts_at)
        from public.bookings b where b.customer_id = c.id), '[]'::jsonb),
    'service_history', private.customer_service_history(c.id)
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- งานของฉัน (หมอ): รายการที่ทำเสร็จในช่วงวันทำการ + ค่ามือประมาณการของตัวเอง
-- -----------------------------------------------------------------------------
create or replace function public.my_work_history(p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  if auth.uid() is null then
    raise exception 'กรุณาเข้าสู่ระบบ' using errcode = 'insufficient_privilege';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 62 then
    raise exception 'ช่วงวันที่ต้องไม่เกิน 62 วัน' using errcode = 'invalid_parameter_value';
  end if;

  select coalesce(jsonb_agg(x order by x ->> 'started_at' desc), '[]'::jsonb) into v_rows
    from (
      select jsonb_build_object(
        'assignment_id', a.id,
        'business_date', q.queue_date,
        'branch_name', br.name,
        'queue_number', q.queue_number,
        'service_name', i.service_name,
        'duration_minutes', i.duration_minutes,
        'started_at', a.started_at,
        'ended_at', a.completed_at,
        'worked_minutes', round(extract(epoch from (a.completed_at - a.started_at)) / 60)::int,
        'handover', a.handover_reason is not null,
        'off_shift', a.off_shift_confirmed,
        'fee_estimate', private.assignment_fee(a.id)
      ) as x
        from public.service_assignments a
        join public.employees e on e.id = a.employee_id
        join public.queue_items q on q.id = a.queue_item_id
        join public.service_order_items i on i.id = q.service_order_item_id
        join public.branches br on br.id = q.branch_id
       where e.user_id = auth.uid() and a.status = 'COMPLETED' and q.status = 'COMPLETED'
         and q.queue_date between p_from and p_to
    ) s;

  return jsonb_build_object(
    'rows', v_rows,
    'total_count', jsonb_array_length(v_rows),
    'total_minutes', coalesce((select sum((r ->> 'worked_minutes')::int) from jsonb_array_elements(v_rows) r), 0),
    'total_fee_estimate', coalesce((select sum((r ->> 'fee_estimate')::numeric) from jsonb_array_elements(v_rows) r), 0)
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- สรุปงานรายหมอ (OWNER)
-- -----------------------------------------------------------------------------
create or replace function public.therapist_work_summary(
  p_company_id uuid,
  p_branch_id  uuid,
  p_from       date,
  p_to         date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_company_owner(p_company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then
    raise exception 'ช่วงวันที่ต้องไม่เกิน 1 ปี' using errcode = 'invalid_parameter_value';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'employee_id', s.employee_id,
      'employee_code', e.employee_code,
      'nickname', e.nickname,
      'services', s.services,
      'worked_minutes', s.worked_minutes,
      'off_shift_count', s.off_shift_count,
      'handover_count', s.handover_count,
      'fee_estimate', s.fee_estimate
    ) order by s.fee_estimate desc, e.nickname)
    from (
      select a.employee_id,
             count(distinct a.queue_item_id) as services,
             coalesce(round(sum(extract(epoch from (a.completed_at - a.started_at))) / 60), 0)::int as worked_minutes,
             count(*) filter (where a.off_shift_confirmed) as off_shift_count,
             count(*) filter (where a.handover_reason is not null) as handover_count,
             coalesce(sum(private.assignment_fee(a.id)), 0) as fee_estimate
        from public.service_assignments a
        join public.queue_items q on q.id = a.queue_item_id
       where a.company_id = p_company_id
         and (p_branch_id is null or a.branch_id = p_branch_id)
         and a.status = 'COMPLETED' and q.status = 'COMPLETED'
         and q.queue_date between p_from and p_to
       group by a.employee_id
    ) s
    join public.employees e on e.id = s.employee_id
  ), '[]'::jsonb);
end;
$$;

-- -----------------------------------------------------------------------------
-- แดชบอร์ด STAFF (ส่วนที่ไม่ใช่เงิน — ยอดขาย/ค้างชำระเพิ่มใน Phase 7)
-- -----------------------------------------------------------------------------
create or replace function public.staff_dashboard(p_branch_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_date date;
  v_tz   text;
begin
  perform private.require_branch_access(p_branch_id);
  select business_date into v_date from private.branch_window_at(p_branch_id, now());
  select s.timezone into v_tz
    from public.branches b join public.company_settings s on s.company_id = b.company_id where b.id = p_branch_id;

  return jsonb_build_object(
    'business_date', v_date,
    'queue', (
      select jsonb_build_object(
        'waiting', count(*) filter (where q.status = 'WAITING'),
        'called', count(*) filter (where q.status in ('CALLED', 'ACCEPTED')),
        'in_service', count(*) filter (where q.status = 'IN_SERVICE'),
        'completed', count(*) filter (where q.status = 'COMPLETED'),
        'overdue', count(*) filter (where q.status = 'IN_SERVICE'
                     and q.started_at + make_interval(mins => i.duration_minutes + 10) < now()))
        from public.queue_items q join public.service_order_items i on i.id = q.service_order_item_id
       where q.branch_id = p_branch_id and q.queue_date = v_date),
    'bookings', (
      select jsonb_build_object(
        'total', count(*) filter (where status not in ('CANCELLED', 'EXPIRED')),
        'awaiting_check_in', count(*) filter (where status = 'CONFIRMED'),
        'checked_in', count(*) filter (where status in ('CHECKED_IN', 'COMPLETED')),
        'slip_review', count(*) filter (where deposit_status = 'PENDING_REVIEW'))
        from public.bookings b
       where b.branch_id = p_branch_id
         and b.starts_at between now() - interval '2 days' and now() + interval '2 days'
         and (select business_date from private.branch_window_at(p_branch_id, b.starts_at)) = v_date),
    'walk_in_orders', (
      select count(*) from public.service_orders
       where branch_id = p_branch_id and business_date = v_date and channel = 'WALK_IN' and status <> 'CANCELLED'),
    'resources', coalesce((
      select jsonb_agg(jsonb_build_object(
        'resource_type_id', t.id, 'name', t.name, 'status', r.status,
        'total', case when r.status = 'ACTIVE' then r.total_quantity else 0 end,
        'in_use', coalesce((
          select sum(a.quantity) from public.resource_allocations a
           where a.branch_id = p_branch_id and a.resource_type_id = t.id
             and a.starts_at <= now() and a.ends_at > now()
             and private.allocation_is_active(a.status, a.expires_at)), 0)
      ) order by t.name)
        from public.branch_resources r join public.resource_types t on t.id = r.resource_type_id
       where r.branch_id = p_branch_id and t.is_active), '[]'::jsonb),
    'session', (
      select jsonb_build_object('session_id', s.id, 'opened_at', s.opened_at, 'opening_cash', s.opening_cash)
        from public.pos_sessions s where s.branch_id = p_branch_id and s.status = 'OPEN'),
    'my_queue', coalesce((
      select jsonb_agg(jsonb_build_object('queue_id', q.id, 'queue_number', q.queue_number, 'status', q.status,
                                          'service_name', i.service_name, 'duration_minutes', i.duration_minutes)
                       order by q.queue_number)
        from public.service_assignments a
        join public.employees e on e.id = a.employee_id
        join public.queue_items q on q.id = a.queue_item_id
        join public.service_order_items i on i.id = q.service_order_item_id
       where e.user_id = auth.uid() and a.status in ('ASSIGNED', 'ACCEPTED', 'IN_SERVICE')), '[]'::jsonb)
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Grants
-- -----------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.queue_extend(uuid, uuid, text)',
    'public.queue_handover(uuid, uuid, text, boolean)',
    'public.queue_undo_start(uuid, text)',
    'public.queue_undo_complete(uuid, text)',
    'public.my_service_history(text)',
    'public.my_work_history(date, date)',
    'public.therapist_work_summary(uuid, uuid, date, date)',
    'public.staff_dashboard(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;

  execute 'revoke all on function public.device_queue_action(text, uuid, uuid, text) from public, anon, authenticated';
  execute 'grant execute on function public.device_queue_action(text, uuid, uuid, text) to service_role';
end;
$$;
