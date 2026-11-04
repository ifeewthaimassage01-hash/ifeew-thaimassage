-- =============================================================================
-- Phase 7 / 022 — การเงินหน้าร้าน
--   invoices / invoice_items      Invoice 1 ใบหลักต่อ Order (DRAFT → ISSUED → PARTIALLY_PAID → PAID | VOID)
--   payment_slip_checks           ผลตรวจสลิป (เขียนโดย Edge Function เท่านั้น) — ข้อมูลที่ DB เชื่อถือได้
--   payments / payment_refunds    รับเงิน CASH / BANK_TRANSFER / QR / DEPOSIT, คืนเงินบางส่วนได้
--   pos_cash_movements            เงินเข้า/ออกลิ้นชัก (ปรับยอด, รายจ่าย, จ่ายทิป)
--   tips                          ทิปของหมอ (ไม่ใช่รายได้ร้าน)
--   expenses                      รายจ่าย (จำนวนเงิน + หมายเหตุ + รูป)
--   pos_sessions                  เพิ่มข้อมูลปิดกะ (นับเงินแบบไม่เห็นยอดคาดการณ์) + OWNER ตรวจ
-- QR หน้าร้าน: พนักงานถ่ายสลิป → Edge Function ตรวจกับ SlipOK → payment_slip_checks
--   ถ้าตรวจอัตโนมัติไม่ได้ พนักงานยืนยันเองพร้อมเหตุผล (verification = MANUAL)
--   (สเปกข้อ 13 กำหนด Webhook — ร้านไม่ใช้ Payment Gateway ตามที่ตกลงไว้)
-- ใบเสร็จ (RCP) ออกเมื่อจ่ายครบ เก็บในระบบเท่านั้น ไม่ออกให้ลูกค้า
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ค่าตั้งค่า
-- -----------------------------------------------------------------------------
alter table public.company_settings
  add column max_staff_discount_percent integer not null default 20 check (max_staff_discount_percent between 0 and 100);

grant update (max_staff_discount_percent) on public.company_settings to authenticated;

-- -----------------------------------------------------------------------------
-- service_orders: Order ต่อเนื่อง (เพิ่มบริการหลังออก Invoice = Order ใหม่ตามสเปกข้อ 13)
-- -----------------------------------------------------------------------------
alter table public.service_orders
  add column parent_order_id uuid,
  add constraint service_orders_parent_fk foreign key (company_id, branch_id, parent_order_id)
    references public.service_orders (company_id, branch_id, id) on delete restrict;

-- -----------------------------------------------------------------------------
-- invoices
-- -----------------------------------------------------------------------------
create table public.invoices (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null,
  branch_id         uuid not null,
  service_order_id  uuid not null,
  customer_id       uuid,
  business_date     date not null,
  invoice_number    text unique check (invoice_number is null or invoice_number ~ '^INV-[A-Z0-9]{2,10}-[0-9]{4}-[0-9]{6}$'),
  receipt_number    text unique check (receipt_number is null or receipt_number ~ '^RCP-[A-Z0-9]{2,10}-[0-9]{4}-[0-9]{6}$'),
  status            text not null default 'DRAFT'
                      check (status in ('DRAFT', 'ISSUED', 'PARTIALLY_PAID', 'PAID', 'VOID')),
  subtotal          numeric(12,2) not null default 0 check (subtotal >= 0),
  discount_total    numeric(12,2) not null default 0 check (discount_total >= 0),
  total             numeric(12,2) not null default 0 check (total >= 0),
  paid_amount       numeric(12,2) not null default 0 check (paid_amount >= 0),
  refunded_amount   numeric(12,2) not null default 0 check (refunded_amount >= 0),
  issued_at         timestamptz,
  issued_by         uuid references public.profiles (id),
  paid_at           timestamptz,
  void_reason       text check (void_reason is null or char_length(void_reason) <= 500),
  voided_at         timestamptz,
  voided_by         uuid references public.profiles (id),
  created_at        timestamptz not null default now(),
  created_by        uuid references public.profiles (id),
  updated_at        timestamptz not null default now(),
  constraint invoices_order_fk foreign key (company_id, branch_id, service_order_id)
    references public.service_orders (company_id, branch_id, id) on delete restrict,
  constraint invoices_customer_fk foreign key (company_id, customer_id)
    references public.customers (company_id, id) on delete restrict,
  constraint invoices_branch_id_key unique (company_id, branch_id, id),
  constraint invoices_total_chk check (total = subtotal - discount_total),
  constraint invoices_issued_chk check (status in ('DRAFT', 'VOID') or (invoice_number is not null and issued_at is not null)),
  constraint invoices_paid_chk check ((status = 'PAID') = (paid_at is not null and receipt_number is not null) or status = 'VOID'),
  constraint invoices_void_chk check ((status = 'VOID') = (voided_at is not null)),
  constraint invoices_paid_amount_chk check (paid_amount <= total)
);

comment on table public.invoices is 'Invoice ต่อ Order (ใบหลักได้ 1 ใบที่ไม่ VOID) ห้าม DELETE ยอดล็อกเมื่อ ISSUED';

create unique index invoices_one_per_order on public.invoices (service_order_id) where status <> 'VOID';
create index invoices_branch_date_idx on public.invoices (branch_id, business_date);
create index invoices_open_idx on public.invoices (branch_id) where status in ('ISSUED', 'PARTIALLY_PAID');

create table public.invoice_items (
  id                     uuid primary key default gen_random_uuid(),
  company_id             uuid not null,
  branch_id              uuid not null,
  invoice_id             uuid not null,
  service_order_item_id  uuid not null,
  description            text not null,
  duration_minutes       integer not null,
  unit_price             numeric(12,2) not null check (unit_price >= 0),
  discount_amount        numeric(12,2) not null default 0 check (discount_amount >= 0),
  discount_reason        text check (discount_reason is null or char_length(discount_reason) <= 300),
  line_total             numeric(12,2) not null check (line_total >= 0),
  created_at             timestamptz not null default now(),
  created_by             uuid references public.profiles (id),
  updated_at             timestamptz not null default now(),
  constraint invoice_items_invoice_fk foreign key (company_id, branch_id, invoice_id)
    references public.invoices (company_id, branch_id, id) on delete restrict,
  constraint invoice_items_order_item_fk foreign key (company_id, branch_id, service_order_item_id)
    references public.service_order_items (company_id, branch_id, id) on delete restrict,
  constraint invoice_items_key unique (invoice_id, service_order_item_id),
  constraint invoice_items_total_chk check (line_total = unit_price - discount_amount),
  constraint invoice_items_discount_chk check (discount_amount = 0 or discount_reason is not null)
);

create index invoice_items_order_item_idx on public.invoice_items (service_order_item_id);

-- -----------------------------------------------------------------------------
-- payment_slip_checks (เขียนโดย Edge Function pos-payment-slip ด้วย service role)
-- -----------------------------------------------------------------------------
create table public.payment_slip_checks (
  id                     uuid primary key default gen_random_uuid(),
  company_id             uuid not null,
  branch_id              uuid not null,
  invoice_id             uuid not null,
  slip_path              text not null check (char_length(slip_path) <= 300),
  requested_amount       numeric(12,2) not null check (requested_amount > 0),
  outcome                text not null check (outcome in ('VERIFIED', 'REJECTED', 'REVIEW')),
  provider               text not null default 'SLIPOK',
  provider_code          integer,
  provider_message       text check (provider_message is null or char_length(provider_message) <= 300),
  slip_trans_ref         text check (slip_trans_ref is null or char_length(slip_trans_ref) <= 40),
  slip_amount            numeric(12,2),
  slip_trans_at          timestamptz,
  slip_sender_name       text check (slip_sender_name is null or char_length(slip_sender_name) <= 100),
  slip_receiver_name     text check (slip_receiver_name is null or char_length(slip_receiver_name) <= 100),
  checked_by             uuid not null references public.profiles (id),
  created_at             timestamptz not null default now(),
  created_by             uuid references public.profiles (id),
  updated_at             timestamptz not null default now(),
  constraint payment_slip_checks_invoice_fk foreign key (company_id, branch_id, invoice_id)
    references public.invoices (company_id, branch_id, id) on delete restrict
);

comment on table public.payment_slip_checks is 'ผลตรวจสลิปรับเงินหน้าร้าน (append-only) ใช้อ้างอิงตอนบันทึก Payment';

create index payment_slip_checks_invoice_idx on public.payment_slip_checks (invoice_id);

-- -----------------------------------------------------------------------------
-- payments
-- -----------------------------------------------------------------------------
create table public.payments (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null,
  branch_id           uuid not null,
  invoice_id          uuid not null,
  pos_session_id      uuid,
  method              text not null check (method in ('CASH', 'BANK_TRANSFER', 'QR', 'DEPOSIT')),
  amount              numeric(12,2) not null check (amount > 0),
  status              text not null default 'SUCCESS' check (status in ('SUCCESS', 'VOID')),
  verification        text check (verification in ('AUTO', 'MANUAL')),
  slip_check_id       uuid references public.payment_slip_checks (id) on delete restrict,
  slip_trans_ref      text,
  manual_reason       text check (manual_reason is null or char_length(manual_reason) <= 300),
  booking_deposit_id  uuid references public.booking_deposits (id) on delete restrict,
  received_by         uuid references public.profiles (id),
  received_at         timestamptz not null default now(),
  voided_at           timestamptz,
  voided_by           uuid references public.profiles (id),
  void_reason         text check (void_reason is null or char_length(void_reason) <= 500),
  created_at          timestamptz not null default now(),
  created_by          uuid references public.profiles (id),
  updated_at          timestamptz not null default now(),
  constraint payments_invoice_fk foreign key (company_id, branch_id, invoice_id)
    references public.invoices (company_id, branch_id, id) on delete restrict,
  constraint payments_session_fk foreign key (company_id, pos_session_id)
    references public.pos_sessions (company_id, id) on delete restrict,
  constraint payments_branch_id_key unique (company_id, branch_id, id),
  constraint payments_session_chk check ((method = 'DEPOSIT') = (pos_session_id is null)),
  constraint payments_slip_chk check ((method in ('BANK_TRANSFER', 'QR')) = (slip_check_id is not null and verification is not null)),
  constraint payments_manual_chk check (verification is distinct from 'MANUAL' or manual_reason is not null),
  constraint payments_deposit_chk check ((method = 'DEPOSIT') = (booking_deposit_id is not null)),
  constraint payments_void_chk check ((status = 'VOID') = (voided_at is not null))
);

comment on table public.payments is 'การรับเงิน ห้าม DELETE/แก้ยอด ยกเลิกด้วย VOID (Source of Truth ของรายรับ)';

create unique index payments_slip_check_key on public.payments (slip_check_id) where status = 'SUCCESS';
create unique index payments_trans_ref_key on public.payments (slip_trans_ref) where status = 'SUCCESS' and slip_trans_ref is not null;
create unique index payments_deposit_key on public.payments (booking_deposit_id) where status = 'SUCCESS';
create index payments_invoice_idx on public.payments (invoice_id);
create index payments_session_idx on public.payments (pos_session_id);

-- -----------------------------------------------------------------------------
-- payment_refunds (คืนบางส่วนได้ ไม่แก้ Payment เดิม)
-- -----------------------------------------------------------------------------
create table public.payment_refunds (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null,
  branch_id        uuid not null,
  payment_id       uuid not null,
  invoice_id       uuid not null,
  pos_session_id   uuid,
  method           text not null check (method in ('CASH', 'BANK_TRANSFER')),
  amount           numeric(12,2) not null check (amount > 0),
  reference        text check (reference is null or char_length(reference) <= 100),
  reason           text not null check (char_length(trim(reason)) between 3 and 500),
  refunded_by      uuid references public.profiles (id),
  refunded_at      timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  created_by       uuid references public.profiles (id),
  updated_at       timestamptz not null default now(),
  constraint payment_refunds_payment_fk foreign key (company_id, branch_id, payment_id)
    references public.payments (company_id, branch_id, id) on delete restrict,
  constraint payment_refunds_invoice_fk foreign key (company_id, branch_id, invoice_id)
    references public.invoices (company_id, branch_id, id) on delete restrict,
  constraint payment_refunds_session_fk foreign key (company_id, pos_session_id)
    references public.pos_sessions (company_id, id) on delete restrict,
  constraint payment_refunds_cash_chk check ((method = 'CASH') = (pos_session_id is not null)),
  constraint payment_refunds_reference_chk check (method = 'CASH' or reference is not null)
);

comment on table public.payment_refunds is 'การคืนเงิน (append-only, Source of Truth)';

create index payment_refunds_payment_idx on public.payment_refunds (payment_id);
create index payment_refunds_session_idx on public.payment_refunds (pos_session_id);

-- -----------------------------------------------------------------------------
-- tips
-- -----------------------------------------------------------------------------
create table public.tips (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null,
  branch_id           uuid not null,
  invoice_id          uuid,
  payment_id          uuid,
  employee_id         uuid not null,
  pos_session_id      uuid not null,
  method              text not null check (method in ('CASH', 'BANK_TRANSFER', 'QR')),
  amount              numeric(12,2) not null check (amount > 0),
  status              text not null default 'RECORDED' check (status in ('RECORDED', 'PAID_OUT', 'VOID')),
  paid_out_at         timestamptz,
  paid_out_by         uuid references public.profiles (id),
  payout_movement_id  uuid,
  voided_at           timestamptz,
  void_reason         text check (void_reason is null or char_length(void_reason) <= 500),
  created_at          timestamptz not null default now(),
  created_by          uuid references public.profiles (id),
  updated_at          timestamptz not null default now(),
  constraint tips_invoice_fk foreign key (company_id, branch_id, invoice_id)
    references public.invoices (company_id, branch_id, id) on delete restrict,
  constraint tips_payment_fk foreign key (company_id, branch_id, payment_id)
    references public.payments (company_id, branch_id, id) on delete restrict,
  constraint tips_employee_fk foreign key (company_id, employee_id)
    references public.employees (company_id, id) on delete restrict,
  constraint tips_session_fk foreign key (company_id, pos_session_id)
    references public.pos_sessions (company_id, id) on delete restrict,
  constraint tips_paid_out_chk check ((status = 'PAID_OUT') = (paid_out_at is not null)),
  constraint tips_paid_out_cash_chk check (status <> 'PAID_OUT' or method = 'CASH'),
  constraint tips_void_chk check ((status = 'VOID') = (voided_at is not null))
);

comment on table public.tips is 'ทิปของหมอ ไม่ใช่รายได้ร้าน ไม่คิดค่ามือ; เงินสดนับรวมในลิ้นชัก (จ่ายให้หมอผ่าน TIP_PAYOUT)';

create index tips_employee_idx on public.tips (employee_id, status);
create index tips_session_idx on public.tips (pos_session_id);

-- -----------------------------------------------------------------------------
-- expenses (จำนวนเงิน + หมายเหตุ + รูปหลักฐาน)
-- -----------------------------------------------------------------------------
create table public.expenses (
  id                    uuid primary key default gen_random_uuid(),
  company_id            uuid not null references public.companies (id) on delete restrict,
  branch_id             uuid,
  expense_scope         text not null check (expense_scope in ('BRANCH', 'HQ')),
  amount                numeric(12,2) not null check (amount > 0 and amount <= 10000000),
  note                  text not null check (char_length(trim(note)) between 1 and 500),
  photo_path            text not null check (char_length(photo_path) <= 300),
  occurred_on           date not null,
  payment_source        text not null check (payment_source in ('CASH_DRAWER', 'OTHER')),
  pos_session_id        uuid,
  is_large              boolean not null default false,
  status                text not null default 'RECORDED' check (status in ('RECORDED', 'VOID')),
  recorded_by           uuid references public.profiles (id),
  void_requested_at     timestamptz,
  void_requested_by     uuid references public.profiles (id),
  void_request_reason   text check (void_request_reason is null or char_length(void_request_reason) <= 500),
  voided_at             timestamptz,
  voided_by             uuid references public.profiles (id),
  void_reason           text check (void_reason is null or char_length(void_reason) <= 500),
  created_at            timestamptz not null default now(),
  created_by            uuid references public.profiles (id),
  updated_at            timestamptz not null default now(),
  constraint expenses_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint expenses_session_fk foreign key (company_id, pos_session_id)
    references public.pos_sessions (company_id, id) on delete restrict,
  constraint expenses_company_id_id_key unique (company_id, id),
  constraint expenses_scope_chk check ((expense_scope = 'HQ') = (branch_id is null)),
  constraint expenses_drawer_chk check ((payment_source = 'CASH_DRAWER') = (pos_session_id is not null)),
  constraint expenses_hq_drawer_chk check (expense_scope = 'BRANCH' or payment_source = 'OTHER'),
  constraint expenses_void_chk check ((status = 'VOID') = (voided_at is not null))
);

comment on table public.expenses is 'รายจ่าย (RECORDED/VOID) ห้าม DELETE; จ่ายจากลิ้นชัก = CASH_OUT ใน Transaction เดียวกัน';

create index expenses_branch_date_idx on public.expenses (branch_id, occurred_on);
create index expenses_void_request_idx on public.expenses (company_id) where void_requested_at is not null and status = 'RECORDED';

-- -----------------------------------------------------------------------------
-- pos_cash_movements
-- -----------------------------------------------------------------------------
create table public.pos_cash_movements (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null,
  branch_id       uuid not null,
  pos_session_id  uuid not null,
  movement_type   text not null check (movement_type in ('CASH_IN', 'CASH_OUT')),
  category        text not null check (category in ('ADJUSTMENT', 'EXPENSE', 'EXPENSE_REVERSAL', 'TIP_PAYOUT')),
  amount          numeric(12,2) not null check (amount > 0),
  reason          text not null check (char_length(trim(reason)) between 1 and 500),
  expense_id      uuid,
  created_at      timestamptz not null default now(),
  created_by      uuid references public.profiles (id),
  updated_at      timestamptz not null default now(),
  constraint pos_cash_movements_session_fk foreign key (company_id, pos_session_id)
    references public.pos_sessions (company_id, id) on delete restrict,
  constraint pos_cash_movements_branch_fk foreign key (company_id, branch_id)
    references public.branches (company_id, id) on delete restrict,
  constraint pos_cash_movements_expense_fk foreign key (company_id, expense_id)
    references public.expenses (company_id, id) on delete restrict,
  constraint pos_cash_movements_category_chk check (
    (category = 'EXPENSE' and movement_type = 'CASH_OUT' and expense_id is not null)
    or (category = 'EXPENSE_REVERSAL' and movement_type = 'CASH_IN' and expense_id is not null)
    or (category = 'TIP_PAYOUT' and movement_type = 'CASH_OUT' and expense_id is null)
    or (category = 'ADJUSTMENT' and expense_id is null)
  )
);

comment on table public.pos_cash_movements is 'เงินเข้า/ออกลิ้นชักที่ไม่ใช่การขาย (append-only, Source of Truth)';

create index pos_cash_movements_session_idx on public.pos_cash_movements (pos_session_id);

alter table public.tips
  add constraint tips_payout_fk foreign key (payout_movement_id) references public.pos_cash_movements (id) on delete restrict;

-- -----------------------------------------------------------------------------
-- pos_sessions: ข้อมูลปิดกะ + การตรวจของ OWNER
-- -----------------------------------------------------------------------------
alter table public.pos_sessions
  add column cash_sales       numeric(12,2),
  add column transfer_sales   numeric(12,2),
  add column qr_sales         numeric(12,2),
  add column cash_tips        numeric(12,2),
  add column cash_in          numeric(12,2),
  add column cash_out         numeric(12,2),
  add column cash_refunds     numeric(12,2),
  add column expected_cash    numeric(12,2),
  add column actual_cash      numeric(12,2) check (actual_cash is null or actual_cash between 0 and 10000000),
  add column cash_difference  numeric(12,2),
  add column close_note       text check (close_note is null or char_length(close_note) <= 500),
  add column review_status    text check (review_status in ('PENDING', 'APPROVED', 'REJECTED')),
  add column reviewed_by      uuid references public.profiles (id),
  add column reviewed_at      timestamptz,
  add column review_note      text check (review_note is null or char_length(review_note) <= 500),
  add constraint pos_sessions_close_figures_chk check (
    status = 'OPEN' or (expected_cash is not null and actual_cash is not null and cash_difference is not null
                        and review_status is not null)),
  add constraint pos_sessions_difference_chk check (
    cash_difference is null or cash_difference = 0 or close_note is not null),
  add constraint pos_sessions_review_chk check (
    review_status is distinct from 'REJECTED' or review_note is not null);

create or replace function private.tg_pos_sessions_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.company_id <> old.company_id or new.branch_id <> old.branch_id or new.business_date <> old.business_date
     or new.opened_at <> old.opened_at or new.opened_by <> old.opened_by or new.opening_cash <> old.opening_cash then
    raise exception 'ห้ามแก้ข้อมูลการเปิดกะ' using errcode = 'check_violation';
  end if;
  if old.status = 'CLOSED' then
    if new.status <> 'CLOSED'
       or (new.cash_sales, new.transfer_sales, new.qr_sales, new.cash_tips, new.cash_in, new.cash_out,
           new.cash_refunds, new.expected_cash, new.actual_cash, new.cash_difference, new.close_note, new.closed_at)
          is distinct from
          (old.cash_sales, old.transfer_sales, old.qr_sales, old.cash_tips, old.cash_in, old.cash_out,
           old.cash_refunds, old.expected_cash, old.actual_cash, old.cash_difference, old.close_note, old.closed_at) then
      raise exception 'กะที่ปิดแล้วแก้ยอดไม่ได้' using errcode = 'check_violation';
    end if;
    if old.review_status <> 'PENDING' and new.review_status is distinct from old.review_status then
      raise exception 'กะนี้ตรวจแล้ว' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- stamp / audit / no delete / guards
-- -----------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['invoices', 'invoice_items', 'payment_slip_checks', 'payments', 'payment_refunds',
                           'tips', 'expenses', 'pos_cash_movements'] loop
    execute format('create trigger %I before insert or update on public.%I for each row execute function private.tg_stamp()',
                   t || '_stamp', t);
    execute format('create trigger %I before delete on public.%I for each row execute function private.tg_no_delete()',
                   t || '_no_delete', t);
  end loop;
end;
$$;

create trigger invoices_audit after insert or update or delete on public.invoices
  for each row execute function private.tg_audit();
create trigger invoice_items_audit after insert or update or delete on public.invoice_items
  for each row execute function private.tg_audit();
create trigger payments_audit after insert or update or delete on public.payments
  for each row execute function private.tg_audit();
create trigger payment_refunds_audit after insert or update or delete on public.payment_refunds
  for each row execute function private.tg_audit();
create trigger tips_audit after insert or update or delete on public.tips
  for each row execute function private.tg_audit();
create trigger expenses_audit after insert or update or delete on public.expenses
  for each row execute function private.tg_audit();
create trigger pos_cash_movements_audit after insert or update or delete on public.pos_cash_movements
  for each row execute function private.tg_audit();

-- append-only
create trigger payment_slip_checks_immutable before update on public.payment_slip_checks
  for each row execute function private.tg_immutable_row();
create trigger payment_refunds_immutable before update on public.payment_refunds
  for each row execute function private.tg_immutable_row();
create trigger pos_cash_movements_immutable before update on public.pos_cash_movements
  for each row execute function private.tg_immutable_row();

create or replace function private.tg_invoices_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.company_id <> old.company_id or new.branch_id <> old.branch_id
     or new.service_order_id <> old.service_order_id or new.business_date <> old.business_date then
    raise exception 'ห้ามแก้ข้อมูลหลักของ Invoice' using errcode = 'check_violation';
  end if;
  if old.status <> 'DRAFT' and (new.subtotal, new.discount_total, new.total) is distinct from (old.subtotal, old.discount_total, old.total) then
    raise exception 'Invoice ที่ออกแล้วแก้ยอดไม่ได้ (ต้อง Void แล้วออกใหม่)' using errcode = 'check_violation';
  end if;
  if old.invoice_number is not null and new.invoice_number is distinct from old.invoice_number
     or old.receipt_number is not null and new.receipt_number is distinct from old.receipt_number then
    raise exception 'ห้ามเปลี่ยนเลขเอกสาร' using errcode = 'check_violation';
  end if;
  if new.status <> old.status and not (
       (old.status = 'DRAFT' and new.status in ('ISSUED', 'PARTIALLY_PAID', 'PAID', 'VOID'))
    or (old.status = 'ISSUED' and new.status in ('PARTIALLY_PAID', 'PAID', 'VOID'))
    or (old.status = 'PARTIALLY_PAID' and new.status in ('ISSUED', 'PAID', 'VOID'))
    or (old.status = 'PAID' and new.status = 'VOID')
  ) then
    raise exception 'เปลี่ยนสถานะ Invoice จาก % เป็น % ไม่ได้', old.status, new.status using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger invoices_guard before update on public.invoices
  for each row execute function private.tg_invoices_guard();

-- รายการใน Invoice: แก้ได้เฉพาะส่วนลดตอน DRAFT
create or replace function private.tg_invoice_items_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select status from public.invoices where id = coalesce(new.invoice_id, old.invoice_id)) <> 'DRAFT' then
    raise exception 'แก้รายการได้เฉพาะ Invoice ที่ยังเป็นร่าง' using errcode = 'check_violation';
  end if;
  if tg_op = 'UPDATE' and (new.invoice_id, new.service_order_item_id, new.unit_price, new.description)
       is distinct from (old.invoice_id, old.service_order_item_id, old.unit_price, old.description) then
    raise exception 'แก้ได้เฉพาะส่วนลด' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger invoice_items_guard before insert or update on public.invoice_items
  for each row execute function private.tg_invoice_items_guard();

create or replace function private.tg_payments_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.company_id, new.branch_id, new.invoice_id, new.pos_session_id, new.method, new.amount, new.verification,
      new.slip_check_id, new.slip_trans_ref, new.booking_deposit_id, new.received_by, new.received_at)
     is distinct from
     (old.company_id, old.branch_id, old.invoice_id, old.pos_session_id, old.method, old.amount, old.verification,
      old.slip_check_id, old.slip_trans_ref, old.booking_deposit_id, old.received_by, old.received_at) then
    raise exception 'ห้ามแก้การรับเงิน (ใช้ Void/Refund)' using errcode = 'check_violation';
  end if;
  if old.status = 'VOID' and new.status <> 'VOID' then
    raise exception 'การรับเงินที่ Void แล้วกลับมาใช้ไม่ได้' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger payments_guard before update on public.payments
  for each row execute function private.tg_payments_guard();

create or replace function private.tg_tips_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.company_id, new.branch_id, new.invoice_id, new.payment_id, new.employee_id, new.pos_session_id, new.method, new.amount)
     is distinct from
     (old.company_id, old.branch_id, old.invoice_id, old.payment_id, old.employee_id, old.pos_session_id, old.method, old.amount) then
    raise exception 'ห้ามแก้ทิป (ใช้ Void)' using errcode = 'check_violation';
  end if;
  if old.status <> 'RECORDED' and new.status <> old.status then
    raise exception 'ทิปนี้จ่ายหรือยกเลิกแล้ว' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger tips_guard before update on public.tips
  for each row execute function private.tg_tips_guard();

create or replace function private.tg_expenses_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (new.company_id, new.branch_id, new.expense_scope, new.amount, new.note, new.photo_path, new.occurred_on,
      new.payment_source, new.pos_session_id, new.is_large, new.recorded_by)
     is distinct from
     (old.company_id, old.branch_id, old.expense_scope, old.amount, old.note, old.photo_path, old.occurred_on,
      old.payment_source, old.pos_session_id, old.is_large, old.recorded_by) then
    raise exception 'รายจ่ายที่บันทึกแล้วแก้ไขไม่ได้ (ให้ยกเลิกแล้วบันทึกใหม่)' using errcode = 'check_violation';
  end if;
  if old.status = 'VOID' and new.status <> 'VOID' then
    raise exception 'รายจ่ายที่ยกเลิกแล้วกลับมาใช้ไม่ได้' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger expenses_guard before update on public.expenses
  for each row execute function private.tg_expenses_guard();

-- ออก Invoice แล้ว ห้ามย้อน/ยกเลิกคิวของรายการในใบนั้น (ต้อง Void Invoice ก่อน) — ปิดช่องของ Phase 6
create or replace function private.tg_queue_items_invoice_lock()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status <> old.status
     and old.status in ('IN_SERVICE', 'COMPLETED')
     and not (old.status = 'IN_SERVICE' and new.status = 'COMPLETED')
     and exists (
       select 1 from public.invoice_items ii join public.invoices iv on iv.id = ii.invoice_id
        where ii.service_order_item_id = new.service_order_item_id and iv.status <> 'VOID') then
    raise exception 'รายการนี้ออก Invoice แล้ว ต้อง Void Invoice ก่อน' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger queue_items_invoice_lock before update of status on public.queue_items
  for each row execute function private.tg_queue_items_invoice_lock();

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function private.open_session_id(p_branch_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.pos_sessions where branch_id = p_branch_id and status = 'OPEN';
$$;

create or replace function private.require_open_session(p_branch_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select id into v_id from public.pos_sessions where branch_id = p_branch_id and status = 'OPEN' for share;
  if v_id is null then
    raise exception 'ยังไม่ได้เปิดกะ กรุณาเปิดกะก่อนรับ/จ่ายเงินสด' using errcode = 'check_violation', hint = 'NO_OPEN_SESSION';
  end if;
  return v_id;
end;
$$;

-- Order ที่ใช้รับรายการใหม่: ถ้า Order เดิมออก Invoice แล้ว → Order ต่อเนื่อง (สร้างครั้งแรกเมื่อจำเป็น)
create or replace function private.order_for_new_items(p_order_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  o     public.service_orders;
  v_id  uuid;
begin
  select * into o from public.service_orders where id = p_order_id;
  if not exists (select 1 from public.invoices where service_order_id = o.id and status <> 'VOID') then
    return o.id;
  end if;
  select c.id into v_id
    from public.service_orders c
   where c.parent_order_id = o.id and c.status <> 'CANCELLED'
     and not exists (select 1 from public.invoices i where i.service_order_id = c.id and i.status <> 'VOID')
   order by c.created_at desc
   limit 1;
  if v_id is null then
    insert into public.service_orders (company_id, branch_id, customer_id, channel, business_date, parent_order_id, note)
    values (o.company_id, o.branch_id, o.customer_id, 'WALK_IN', o.business_date, o.id, 'เพิ่มบริการหลังออก Invoice')
    returning id into v_id;
  end if;
  return v_id;
end;
$$;

-- อัปเดตยอดจ่าย/สถานะ Invoice จาก payments (ออกใบเสร็จเมื่อครบ)
create or replace function private.refresh_invoice(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  iv      public.invoices;
  v_paid  numeric(12,2);
  v_ref   numeric(12,2);
  v_new   text;
begin
  select * into iv from public.invoices where id = p_invoice_id for update;
  if iv.status in ('DRAFT', 'VOID') then
    return;
  end if;
  select coalesce(sum(amount), 0) into v_paid from public.payments where invoice_id = iv.id and status = 'SUCCESS';
  select coalesce(sum(amount), 0) into v_ref from public.payment_refunds where invoice_id = iv.id;
  v_new := case when v_paid >= iv.total then 'PAID' when v_paid > 0 then 'PARTIALLY_PAID' else 'ISSUED' end;

  update public.invoices
     set paid_amount = v_paid,
         refunded_amount = v_ref,
         status = v_new,
         paid_at = case when v_new = 'PAID' then coalesce(paid_at, now()) else null end,
         receipt_number = case when v_new = 'PAID'
                            then coalesce(receipt_number, private.next_document_number(iv.company_id, iv.branch_id, 'RCP', now()))
                            else receipt_number end
   where id = iv.id;
end;
$$;

create or replace function private.invoice_view(p_invoice_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'invoice_id', iv.id,
    'service_order_id', iv.service_order_id,
    'invoice_number', iv.invoice_number,
    'receipt_number', iv.receipt_number,
    'status', iv.status,
    'business_date', iv.business_date,
    'customer_name', case when c.id is null then null else trim(c.first_name || ' ' || c.last_name) end,
    'subtotal', iv.subtotal,
    'discount_total', iv.discount_total,
    'total', iv.total,
    'paid_amount', iv.paid_amount,
    'refunded_amount', iv.refunded_amount,
    'balance', iv.total - iv.paid_amount,
    'issued_at', iv.issued_at,
    'paid_at', iv.paid_at,
    'void_reason', iv.void_reason,
    'max_staff_discount_percent', s.max_staff_discount_percent,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'invoice_item_id', ii.id, 'description', ii.description, 'duration_minutes', ii.duration_minutes,
        'unit_price', ii.unit_price, 'discount_amount', ii.discount_amount, 'discount_reason', ii.discount_reason,
        'line_total', ii.line_total) order by ii.created_at, ii.id)
        from public.invoice_items ii where ii.invoice_id = iv.id), '[]'::jsonb),
    'payments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'payment_id', p.id, 'method', p.method, 'amount', p.amount, 'status', p.status,
        'verification', p.verification, 'slip_path', sc.slip_path, 'slip_trans_ref', p.slip_trans_ref,
        'manual_reason', p.manual_reason, 'received_at', p.received_at, 'received_by_name', pr.display_name,
        'refunded', coalesce((select sum(r.amount) from public.payment_refunds r where r.payment_id = p.id), 0),
        'void_reason', p.void_reason) order by p.received_at)
        from public.payments p
        left join public.payment_slip_checks sc on sc.id = p.slip_check_id
        left join public.profiles pr on pr.id = p.received_by
       where p.invoice_id = iv.id), '[]'::jsonb),
    'tips', coalesce((
      select jsonb_agg(jsonb_build_object('tip_id', t.id, 'nickname', e.nickname, 'method', t.method, 'amount', t.amount,
                                          'status', t.status) order by t.created_at)
        from public.tips t join public.employees e on e.id = t.employee_id
       where t.invoice_id = iv.id), '[]'::jsonb),
    'deposit_available', (
      select d.amount from public.service_orders o
        join public.booking_deposits d on d.booking_id = o.booking_id and d.status = 'VERIFIED' and d.refund_status = 'NONE'
       where o.id = iv.service_order_id
         and not exists (select 1 from public.payments x where x.booking_deposit_id = d.id and x.status = 'SUCCESS'))
  )
  from public.invoices iv
  join public.company_settings s on s.company_id = iv.company_id
  left join public.customers c on c.id = iv.customer_id
  where iv.id = p_invoice_id;
$$;

revoke all on function private.open_session_id(uuid) from public;
revoke all on function private.require_open_session(uuid) from public;
revoke all on function private.order_for_new_items(uuid) from public;
revoke all on function private.refresh_invoice(uuid) from public;
revoke all on function private.invoice_view(uuid) from public;

-- -----------------------------------------------------------------------------
-- Invoice
-- -----------------------------------------------------------------------------
-- สร้างร่าง (หรือคืนใบเดิมที่ยังไม่ VOID): คิดเฉพาะรายการที่กำลังทำหรือทำเสร็จ
create or replace function public.pos_create_invoice(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  o     public.service_orders;
  v_id  uuid;
begin
  select * into o from public.service_orders where id = p_order_id for update;
  if o.id is null then
    raise exception 'ไม่พบ Order' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(o.branch_id);

  select id into v_id from public.invoices where service_order_id = o.id and status <> 'VOID';
  if v_id is not null then
    return private.invoice_view(v_id);
  end if;
  if o.status = 'CANCELLED' then
    raise exception 'Order นี้ถูกยกเลิกแล้ว' using errcode = 'check_violation';
  end if;
  if exists (
    select 1 from public.service_order_items i join public.queue_items q on q.service_order_item_id = i.id
     where i.service_order_id = o.id and q.status in ('WAITING', 'CALLED', 'ACCEPTED')
  ) then
    raise exception 'มีรายการที่ยังไม่เริ่มบริการ กรุณายกเลิกหรือเริ่มบริการก่อนออก Invoice'
      using errcode = 'check_violation', hint = 'PENDING_ITEMS';
  end if;
  if not exists (
    select 1 from public.service_order_items i join public.queue_items q on q.service_order_item_id = i.id
     where i.service_order_id = o.id and q.status in ('IN_SERVICE', 'COMPLETED')
  ) then
    raise exception 'ยังไม่มีรายการที่ให้บริการ' using errcode = 'check_violation';
  end if;

  insert into public.invoices (company_id, branch_id, service_order_id, customer_id, business_date)
  values (o.company_id, o.branch_id, o.id, o.customer_id, o.business_date)
  returning id into v_id;

  insert into public.invoice_items (company_id, branch_id, invoice_id, service_order_item_id, description,
                                    duration_minutes, unit_price, line_total)
  select o.company_id, o.branch_id, v_id, i.id, i.service_name, i.duration_minutes, i.unit_price, i.unit_price
    from public.service_order_items i join public.queue_items q on q.service_order_item_id = i.id
   where i.service_order_id = o.id and q.status in ('IN_SERVICE', 'COMPLETED')
   order by q.queue_number;

  update public.invoices iv
     set subtotal = x.s, discount_total = 0, total = x.s
    from (select sum(unit_price) as s from public.invoice_items where invoice_id = v_id) x
   where iv.id = v_id;
  return private.invoice_view(v_id);
end;
$$;

-- ส่วนลดต่อรายการ (ร่างเท่านั้น, ต้องมีเหตุผล) เกินเพดาน STAFF ต้องเป็น OWNER + ยืนยัน TOTP
create or replace function public.pos_set_invoice_discount(p_invoice_item_id uuid, p_amount numeric, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  ii     public.invoice_items;
  iv     public.invoices;
  v_max  integer;
begin
  select * into ii from public.invoice_items where id = p_invoice_item_id;
  if ii.id is null then
    raise exception 'ไม่พบรายการ' using errcode = 'no_data_found';
  end if;
  select * into iv from public.invoices where id = ii.invoice_id for update;
  perform private.require_branch_access(iv.branch_id);
  if iv.status <> 'DRAFT' then
    raise exception 'ให้ส่วนลดได้เฉพาะ Invoice ที่ยังเป็นร่าง' using errcode = 'check_violation';
  end if;
  if p_amount is null or p_amount < 0 or p_amount > ii.unit_price then
    raise exception 'ส่วนลดต้องอยู่ระหว่าง 0 ถึงราคาของรายการ' using errcode = 'invalid_parameter_value';
  end if;
  if p_amount > 0 and (p_reason is null or char_length(trim(p_reason)) < 3) then
    raise exception 'กรุณาระบุเหตุผลของส่วนลด' using errcode = 'invalid_parameter_value';
  end if;
  select max_staff_discount_percent into v_max from public.company_settings where company_id = iv.company_id;
  if p_amount > round(ii.unit_price * v_max / 100.0, 2) then
    if not private.is_company_owner(iv.company_id) then
      raise exception '%', format('ส่วนลดเกิน %s%% ต้องให้เจ้าของร้านเป็นผู้ให้', v_max) using errcode = 'insufficient_privilege';
    end if;
    perform private.require_owner_step_up(iv.company_id);
  end if;

  update public.invoice_items
     set discount_amount = round(p_amount, 2),
         discount_reason = case when p_amount > 0 then left(trim(p_reason), 300) end,
         line_total = unit_price - round(p_amount, 2)
   where id = ii.id;
  update public.invoices v
     set discount_total = x.d, total = v.subtotal - x.d
    from (select coalesce(sum(discount_amount), 0) as d from public.invoice_items where invoice_id = iv.id) x
   where v.id = iv.id;
  return private.invoice_view(iv.id);
end;
$$;

-- ออก Invoice: ล็อกยอด, ออกเลข INV, หักมัดจำของการจองอัตโนมัติ
create or replace function public.pos_issue_invoice(p_invoice_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  iv      public.invoices;
  d       public.booking_deposits;
  v_apply numeric(12,2);
begin
  select * into iv from public.invoices where id = p_invoice_id for update;
  if iv.id is null then
    raise exception 'ไม่พบ Invoice' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(iv.branch_id);
  if iv.status <> 'DRAFT' then
    return private.invoice_view(iv.id);
  end if;

  update public.invoices
     set status = 'ISSUED', issued_at = now(), issued_by = auth.uid(),
         invoice_number = private.next_document_number(iv.company_id, iv.branch_id, 'INV', now())
   where id = iv.id;

  -- มัดจำการจอง (ยังไม่ถูกใช้/ไม่รอคืน) → Payment แบบ DEPOSIT (ไม่ใช่เงินในลิ้นชัก)
  select dep.* into d
    from public.service_orders o
    join public.booking_deposits dep on dep.booking_id = o.booking_id
   where o.id = iv.service_order_id and dep.status = 'VERIFIED' and dep.refund_status = 'NONE'
     and not exists (select 1 from public.payments x where x.booking_deposit_id = dep.id and x.status = 'SUCCESS')
   for update of dep;
  v_apply := least(coalesce(d.amount, 0), iv.total);
  if d.id is not null and v_apply > 0 then
    insert into public.payments (company_id, branch_id, invoice_id, method, amount, booking_deposit_id, received_by)
    values (iv.company_id, iv.branch_id, iv.id, 'DEPOSIT', v_apply, d.id, auth.uid());
  end if;

  perform private.refresh_invoice(iv.id);
  return private.invoice_view(iv.id);
end;
$$;

-- -----------------------------------------------------------------------------
-- รับเงิน (ต้องมีกะเปิดอยู่, Idempotent) + ทิป (ถ้ามี)
--   CASH: ไม่ต้องมีสลิป
--   BANK_TRANSFER / QR: ต้องอ้างผลตรวจสลิป (payment_slip_checks)
--     VERIFIED = AUTO (ยอดในสลิปต้องเท่ากับยอดรับ + ทิป), REVIEW = MANUAL (ต้องมีเหตุผล), REJECTED = ใช้ไม่ได้
-- -----------------------------------------------------------------------------
create or replace function public.pos_record_payment(
  p_invoice_id       uuid,
  p_method           text,
  p_amount           numeric,
  p_slip_check_id    uuid,
  p_manual_reason    text,
  p_tip_amount       numeric,
  p_tip_employee_id  uuid,
  p_idempotency_key  text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  iv         public.invoices;
  sc         public.payment_slip_checks;
  v_session  uuid;
  v_prev     jsonb;
  v_payment  uuid;
  v_verify   text;
  v_tip      numeric(12,2) := round(coalesce(p_tip_amount, 0), 2);
  v_result   jsonb;
  v_hash     text := private.request_hash(jsonb_build_object(
                       'i', p_invoice_id, 'm', p_method, 'a', p_amount, 's', p_slip_check_id,
                       't', p_tip_amount, 'e', p_tip_employee_id));
begin
  select * into iv from public.invoices where id = p_invoice_id for update;
  if iv.id is null then
    raise exception 'ไม่พบ Invoice' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(iv.branch_id);

  v_prev := private.idempotency_begin('pos_record_payment', p_idempotency_key, v_hash);
  if v_prev is not null then
    return v_prev -> 'body';
  end if;

  if iv.status not in ('ISSUED', 'PARTIALLY_PAID') then
    raise exception 'Invoice นี้รับเงินไม่ได้ (ต้องออก Invoice ก่อน หรือจ่ายครบแล้ว)' using errcode = 'check_violation';
  end if;
  if p_method not in ('CASH', 'BANK_TRANSFER', 'QR') then
    raise exception 'ช่องทางชำระไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  if p_amount is null or p_amount <= 0 or round(p_amount, 2) > iv.total - iv.paid_amount then
    raise exception 'ยอดรับต้องมากกว่า 0 และไม่เกินยอดค้าง % บาท', iv.total - iv.paid_amount
      using errcode = 'invalid_parameter_value';
  end if;
  if v_tip < 0 or (v_tip > 0 and p_tip_employee_id is null) then
    raise exception 'กรุณาเลือกหมอที่ได้รับทิป' using errcode = 'invalid_parameter_value';
  end if;
  v_session := private.require_open_session(iv.branch_id);

  if p_method in ('BANK_TRANSFER', 'QR') then
    select * into sc from public.payment_slip_checks where id = p_slip_check_id;
    if sc.id is null or sc.invoice_id <> iv.id then
      raise exception 'กรุณาถ่ายรูปสลิปของ Invoice นี้' using errcode = 'invalid_parameter_value';
    end if;
    if sc.outcome = 'REJECTED' then
      raise exception 'สลิปนี้ไม่ผ่านการตรวจ: %', coalesce(sc.provider_message, '-') using errcode = 'check_violation';
    end if;
    if sc.slip_trans_ref is not null and (
         exists (select 1 from public.payments where slip_trans_ref = sc.slip_trans_ref and status = 'SUCCESS')
      or exists (select 1 from public.booking_deposits where slip_trans_ref = sc.slip_trans_ref and status <> 'REJECTED')
    ) then
      raise exception 'สลิปนี้ถูกใช้แล้ว' using errcode = 'check_violation';
    end if;
    if sc.outcome = 'VERIFIED' then
      if sc.slip_amount is distinct from round(p_amount, 2) + v_tip then
        raise exception 'ยอดในสลิป (% บาท) ไม่ตรงกับยอดรับรวมทิป', sc.slip_amount using errcode = 'check_violation';
      end if;
      v_verify := 'AUTO';
    else
      if p_manual_reason is null or char_length(trim(p_manual_reason)) < 3 then
        raise exception 'ตรวจสลิปอัตโนมัติไม่ได้ กรุณาตรวจยอดเข้าบัญชีแล้วระบุเหตุผลเพื่อยืนยันเอง'
          using errcode = 'invalid_parameter_value', hint = 'MANUAL_REQUIRED';
      end if;
      v_verify := 'MANUAL';
    end if;
  elsif p_slip_check_id is not null then
    raise exception 'รับเงินสดไม่ต้องแนบสลิป' using errcode = 'invalid_parameter_value';
  end if;

  insert into public.payments (company_id, branch_id, invoice_id, pos_session_id, method, amount, verification,
                               slip_check_id, slip_trans_ref, manual_reason, received_by)
  values (iv.company_id, iv.branch_id, iv.id, v_session, p_method, round(p_amount, 2), v_verify,
          case when p_method = 'CASH' then null else sc.id end, sc.slip_trans_ref,
          case when v_verify = 'MANUAL' then left(trim(p_manual_reason), 300) end, auth.uid())
  returning id into v_payment;

  if v_tip > 0 then
    if not exists (
      select 1 from public.employees e
       where e.id = p_tip_employee_id and e.company_id = iv.company_id
         and private.is_active_staff_of_branch(e.user_id, iv.branch_id)
    ) then
      raise exception 'หมอที่ได้รับทิปไม่ได้อยู่สาขานี้' using errcode = 'invalid_parameter_value';
    end if;
    insert into public.tips (company_id, branch_id, invoice_id, payment_id, employee_id, pos_session_id, method, amount)
    values (iv.company_id, iv.branch_id, iv.id, v_payment, p_tip_employee_id, v_session, p_method, v_tip);
  end if;

  perform private.refresh_invoice(iv.id);
  v_result := private.invoice_view(iv.id);
  perform private.idempotency_complete('pos_record_payment', p_idempotency_key, 200, v_result);
  return v_result;
end;
$$;

-- -----------------------------------------------------------------------------
-- Void Invoice (ต้องมีเหตุผล)
--   ยังไม่รับเงิน (หรือมีแค่มัดจำ) = STAFF ได้; รับเงินแล้ว = OWNER + ยืนยัน TOTP
--   เงินที่รับต้องอยู่ในกะที่ยังเปิด (กะปิดแล้วต้องคืนเงินแทน), ทิปที่จ่ายให้หมอแล้วต้องจัดการก่อน
-- -----------------------------------------------------------------------------
create or replace function public.pos_void_invoice(p_invoice_id uuid, p_reason text, p_idempotency_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  iv      public.invoices;
  v_prev  jsonb;
  v_result jsonb;
begin
  select * into iv from public.invoices where id = p_invoice_id for update;
  if iv.id is null then
    raise exception 'ไม่พบ Invoice' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(iv.branch_id);

  v_prev := private.idempotency_begin('pos_void_invoice', p_idempotency_key,
                                      private.request_hash(jsonb_build_object('i', p_invoice_id)));
  if v_prev is not null then
    return v_prev -> 'body';
  end if;

  if iv.status = 'VOID' then
    raise exception 'Invoice นี้ถูก Void แล้ว' using errcode = 'check_violation';
  end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาระบุเหตุผล' using errcode = 'invalid_parameter_value';
  end if;
  if exists (select 1 from public.payments where invoice_id = iv.id and status = 'SUCCESS' and method <> 'DEPOSIT') then
    if not private.is_company_owner(iv.company_id) then
      raise exception 'Invoice ที่รับเงินแล้ว ต้องให้เจ้าของร้านเป็นผู้ Void' using errcode = 'insufficient_privilege';
    end if;
    perform private.require_owner_step_up(iv.company_id);
    if exists (
      select 1 from public.payments p join public.pos_sessions s on s.id = p.pos_session_id
       where p.invoice_id = iv.id and p.status = 'SUCCESS' and s.status <> 'OPEN'
    ) then
      raise exception 'มีเงินที่รับในกะที่ปิดแล้ว ต้องใช้การคืนเงินแทนการ Void' using errcode = 'check_violation';
    end if;
  end if;
  if exists (select 1 from public.payment_refunds where invoice_id = iv.id) then
    raise exception 'Invoice นี้มีการคืนเงินแล้ว Void ไม่ได้' using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.tips where invoice_id = iv.id and status = 'PAID_OUT') then
    raise exception 'ทิปของ Invoice นี้จ่ายให้หมอแล้ว Void ไม่ได้' using errcode = 'check_violation';
  end if;

  perform set_config('app.audit_reason', trim(p_reason), true);
  update public.tips set status = 'VOID', voided_at = now(), void_reason = 'Void Invoice'
   where invoice_id = iv.id and status = 'RECORDED';
  update public.payments set status = 'VOID', voided_at = now(), voided_by = auth.uid(), void_reason = left(trim(p_reason), 500)
   where invoice_id = iv.id and status = 'SUCCESS';
  update public.invoices
     set status = 'VOID', voided_at = now(), voided_by = auth.uid(), void_reason = left(trim(p_reason), 500)
   where id = iv.id;

  v_result := private.invoice_view(iv.id);
  perform private.idempotency_complete('pos_void_invoice', p_idempotency_key, 200, v_result);
  return v_result;
end;
$$;

-- -----------------------------------------------------------------------------
-- คืนเงิน (OWNER + ยืนยัน TOTP) บางส่วนได้; เงินสดต้องมีกะเปิด (หักจากลิ้นชักของกะนั้น)
-- -----------------------------------------------------------------------------
create or replace function public.pos_refund_payment(
  p_payment_id       uuid,
  p_amount           numeric,
  p_method           text,
  p_reference        text,
  p_reason           text,
  p_idempotency_key  text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  p          public.payments;
  v_prev     jsonb;
  v_left     numeric(12,2);
  v_session  uuid;
  v_result   jsonb;
begin
  select * into p from public.payments where id = p_payment_id for update;
  if p.id is null then
    raise exception 'ไม่พบการรับเงิน' using errcode = 'no_data_found';
  end if;
  perform private.require_owner_step_up(p.company_id);

  v_prev := private.idempotency_begin('pos_refund_payment', p_idempotency_key,
                                      private.request_hash(jsonb_build_object('p', p_payment_id, 'a', p_amount, 'm', p_method)));
  if v_prev is not null then
    return v_prev -> 'body';
  end if;

  if p.status <> 'SUCCESS' or p.method = 'DEPOSIT' then
    raise exception 'คืนเงินได้เฉพาะการรับเงินที่สำเร็จ (มัดจำคืนผ่านหน้าการจอง)' using errcode = 'check_violation';
  end if;
  if p_method not in ('CASH', 'BANK_TRANSFER') then
    raise exception 'ช่องทางคืนเงินไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาระบุเหตุผล' using errcode = 'invalid_parameter_value';
  end if;
  if p_method = 'BANK_TRANSFER' and (p_reference is null or char_length(trim(p_reference)) < 3) then
    raise exception 'กรุณาระบุเลขอ้างอิงการโอนคืน' using errcode = 'invalid_parameter_value';
  end if;
  select p.amount - coalesce(sum(r.amount), 0) into v_left from public.payment_refunds r where r.payment_id = p.id;
  if p_amount is null or p_amount <= 0 or round(p_amount, 2) > v_left then
    raise exception 'ยอดคืนต้องไม่เกิน % บาท', v_left using errcode = 'invalid_parameter_value';
  end if;
  if p_method = 'CASH' then
    v_session := private.require_open_session(p.branch_id);
  end if;

  insert into public.payment_refunds (company_id, branch_id, payment_id, invoice_id, pos_session_id, method, amount,
                                      reference, reason, refunded_by)
  values (p.company_id, p.branch_id, p.id, p.invoice_id, v_session, p_method, round(p_amount, 2),
          nullif(left(trim(coalesce(p_reference, '')), 100), ''), left(trim(p_reason), 500), auth.uid());

  perform private.refresh_invoice(p.invoice_id);
  v_result := private.invoice_view(p.invoice_id);
  perform private.idempotency_complete('pos_refund_payment', p_idempotency_key, 200, v_result);
  return v_result;
end;
$$;

-- -----------------------------------------------------------------------------
-- เงินเข้า/ออกลิ้นชัก (ปรับยอด) และจ่ายทิปเงินสดให้หมอ
-- -----------------------------------------------------------------------------
create or replace function public.pos_cash_adjustment(p_branch_id uuid, p_type text, p_amount numeric, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session uuid;
  v_company uuid;
  v_id      uuid;
begin
  perform private.require_branch_access(p_branch_id);
  if p_type not in ('CASH_IN', 'CASH_OUT') then
    raise exception 'ประเภทไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'จำนวนเงินต้องมากกว่า 0' using errcode = 'invalid_parameter_value';
  end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาระบุเหตุผล' using errcode = 'invalid_parameter_value';
  end if;
  v_session := private.require_open_session(p_branch_id);
  select company_id into v_company from public.branches where id = p_branch_id;
  insert into public.pos_cash_movements (company_id, branch_id, pos_session_id, movement_type, category, amount, reason)
  values (v_company, p_branch_id, v_session, p_type, 'ADJUSTMENT', round(p_amount, 2), left(trim(p_reason), 500))
  returning id into v_id;
  return v_id;
end;
$$;

-- จ่ายทิปเงินสดที่ยังไม่จ่ายทั้งหมดของหมอคนนั้นในสาขา (เงินออกจากลิ้นชักของกะปัจจุบัน)
create or replace function public.pos_pay_out_tips(p_branch_id uuid, p_employee_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session  uuid;
  v_company  uuid;
  v_total    numeric(12,2);
  v_count    integer;
  v_nick     text;
  v_move     uuid;
begin
  perform private.require_branch_access(p_branch_id);
  v_session := private.require_open_session(p_branch_id);
  select company_id into v_company from public.branches where id = p_branch_id;
  select nickname into v_nick from public.employees where id = p_employee_id and company_id = v_company;

  perform 1 from public.tips
   where branch_id = p_branch_id and employee_id = p_employee_id and method = 'CASH' and status = 'RECORDED' for update;
  select coalesce(sum(amount), 0), count(*) into v_total, v_count from public.tips
   where branch_id = p_branch_id and employee_id = p_employee_id and method = 'CASH' and status = 'RECORDED';
  if v_count = 0 then
    raise exception 'ไม่มีทิปเงินสดที่ต้องจ่าย' using errcode = 'check_violation';
  end if;

  insert into public.pos_cash_movements (company_id, branch_id, pos_session_id, movement_type, category, amount, reason)
  values (v_company, p_branch_id, v_session, 'CASH_OUT', 'TIP_PAYOUT', v_total, 'จ่ายทิปให้ ' || coalesce(v_nick, '-'))
  returning id into v_move;
  update public.tips
     set status = 'PAID_OUT', paid_out_at = now(), paid_out_by = auth.uid(), payout_movement_id = v_move
   where branch_id = p_branch_id and employee_id = p_employee_id and method = 'CASH' and status = 'RECORDED';

  return jsonb_build_object('amount', v_total, 'count', v_count, 'movement_id', v_move);
end;
$$;

-- -----------------------------------------------------------------------------
-- สรุปเงินของกะ (Expected Cash = เงินเริ่มต้น + รับเงินสด + ทิปเงินสด + เงินเข้า − เงินออก − คืนเงินสด)
-- -----------------------------------------------------------------------------
create or replace function private.session_figures(p_session_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with s as (select * from public.pos_sessions where id = p_session_id),
  pay as (
    select coalesce(sum(amount) filter (where method = 'CASH'), 0) as cash,
           coalesce(sum(amount) filter (where method = 'BANK_TRANSFER'), 0) as transfer,
           coalesce(sum(amount) filter (where method = 'QR'), 0) as qr
      from public.payments where pos_session_id = p_session_id and status = 'SUCCESS'),
  tip as (select coalesce(sum(amount), 0) as cash from public.tips
           where pos_session_id = p_session_id and method = 'CASH' and status <> 'VOID'),
  mv as (select coalesce(sum(amount) filter (where movement_type = 'CASH_IN'), 0) as cin,
                coalesce(sum(amount) filter (where movement_type = 'CASH_OUT'), 0) as cout
           from public.pos_cash_movements where pos_session_id = p_session_id),
  rf as (select coalesce(sum(amount), 0) as cash from public.payment_refunds
          where pos_session_id = p_session_id and method = 'CASH')
  select jsonb_build_object(
    'opening_cash', s.opening_cash,
    'cash_sales', pay.cash, 'transfer_sales', pay.transfer, 'qr_sales', pay.qr,
    'cash_tips', tip.cash, 'cash_in', mv.cin, 'cash_out', mv.cout, 'cash_refunds', rf.cash,
    'expected_cash', s.opening_cash + pay.cash + tip.cash + mv.cin - mv.cout - rf.cash)
  from s, pay, tip, mv, rf;
$$;

revoke all on function private.session_figures(uuid) from public;

-- ปิดกะ: พนักงานนับเงินโดยไม่เห็นยอดคาดการณ์ → ระบบคำนวณผลต่าง (ไม่ 0 ต้องมีเหตุผล)
create or replace function public.pos_close_session(p_session_id uuid, p_actual_cash numeric, p_note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s     public.pos_sessions;
  f     jsonb;
  v_diff numeric(12,2);
begin
  select * into s from public.pos_sessions where id = p_session_id for update;
  if s.id is null then
    raise exception 'ไม่พบกะ' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(s.branch_id);
  if s.status <> 'OPEN' then
    raise exception 'กะนี้ปิดแล้ว' using errcode = 'check_violation';
  end if;
  if p_actual_cash is null or p_actual_cash < 0 then
    raise exception 'กรุณากรอกเงินสดที่นับได้' using errcode = 'invalid_parameter_value';
  end if;

  f := private.session_figures(s.id);
  v_diff := round(p_actual_cash, 2) - (f ->> 'expected_cash')::numeric;
  if v_diff <> 0 and (p_note is null or char_length(trim(p_note)) < 3) then
    raise exception 'เงินที่นับได้ไม่ตรงกับยอดในระบบ กรุณาระบุเหตุผล' using errcode = 'invalid_parameter_value', hint = 'DIFFERENCE_NOTE';
  end if;

  update public.pos_sessions
     set status = 'CLOSED', closed_at = now(), closed_by = auth.uid(),
         cash_sales = (f ->> 'cash_sales')::numeric, transfer_sales = (f ->> 'transfer_sales')::numeric,
         qr_sales = (f ->> 'qr_sales')::numeric, cash_tips = (f ->> 'cash_tips')::numeric,
         cash_in = (f ->> 'cash_in')::numeric, cash_out = (f ->> 'cash_out')::numeric,
         cash_refunds = (f ->> 'cash_refunds')::numeric, expected_cash = (f ->> 'expected_cash')::numeric,
         actual_cash = round(p_actual_cash, 2), cash_difference = v_diff,
         close_note = nullif(left(trim(coalesce(p_note, '')), 500), ''), review_status = 'PENDING'
   where id = s.id;

  return f || jsonb_build_object('session_id', s.id, 'actual_cash', round(p_actual_cash, 2), 'cash_difference', v_diff);
end;
$$;

-- OWNER ตรวจกะ (อนุมัติ/ปฏิเสธพร้อมเหตุผล)
create or replace function public.pos_review_session(p_session_id uuid, p_approve boolean, p_note text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.pos_sessions;
begin
  select * into s from public.pos_sessions where id = p_session_id for update;
  if s.id is null or not private.is_company_owner(s.company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if s.status <> 'CLOSED' or s.review_status <> 'PENDING' then
    raise exception 'กะนี้ยังไม่ปิดหรือตรวจแล้ว' using errcode = 'check_violation';
  end if;
  if not p_approve and (p_note is null or char_length(trim(p_note)) < 3) then
    raise exception 'กรุณาระบุเหตุผลที่ปฏิเสธ' using errcode = 'invalid_parameter_value';
  end if;
  update public.pos_sessions
     set review_status = case when p_approve then 'APPROVED' else 'REJECTED' end,
         reviewed_by = auth.uid(), reviewed_at = now(), review_note = nullif(left(trim(coalesce(p_note, '')), 500), '')
   where id = s.id;
end;
$$;

-- รายการกะของสาขา: ยอดคาดการณ์แสดงเฉพาะกะที่ปิดแล้ว (นับเงินแบบไม่เห็นยอดก่อน) — OWNER เห็นทุกกะ
create or replace function public.pos_sessions_list(p_branch_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner boolean;
begin
  perform private.require_branch_access(p_branch_id);
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 92 then
    raise exception 'ช่วงวันที่ต้องไม่เกิน 92 วัน' using errcode = 'invalid_parameter_value';
  end if;
  select private.is_company_owner(company_id) into v_owner from public.branches where id = p_branch_id;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'session_id', s.id, 'status', s.status, 'business_date', s.business_date,
        'opened_at', s.opened_at, 'opened_by_name', po.display_name, 'opening_cash', s.opening_cash,
        'closed_at', s.closed_at, 'closed_by_name', pc.display_name,
        'actual_cash', s.actual_cash, 'cash_difference', s.cash_difference, 'close_note', s.close_note,
        'review_status', s.review_status, 'review_note', s.review_note)
      || case when s.status = 'CLOSED' then jsonb_build_object(
                'cash_sales', s.cash_sales, 'transfer_sales', s.transfer_sales, 'qr_sales', s.qr_sales,
                'cash_tips', s.cash_tips, 'cash_in', s.cash_in, 'cash_out', s.cash_out,
                'cash_refunds', s.cash_refunds, 'expected_cash', s.expected_cash)
              when v_owner then private.session_figures(s.id)
              else '{}'::jsonb end
      order by s.opened_at desc)
      from public.pos_sessions s
      left join public.profiles po on po.id = s.opened_by
      left join public.profiles pc on pc.id = s.closed_by
     where s.branch_id = p_branch_id and s.business_date between p_from and p_to
  ), '[]'::jsonb);
end;
$$;

-- -----------------------------------------------------------------------------
-- รายจ่าย (จำนวนเงิน + หมายเหตุ + รูป)
-- -----------------------------------------------------------------------------
create or replace function public.pos_record_expense(
  p_company_id    uuid,
  p_branch_id     uuid,          -- NULL = สำนักงานใหญ่ (OWNER เท่านั้น)
  p_amount        numeric,
  p_note          text,
  p_photo_path    text,
  p_from_drawer   boolean,
  p_occurred_on   date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session   uuid;
  v_threshold numeric;
  v_tz        text;
  v_id        uuid;
  v_folder    text := coalesce(p_branch_id::text, 'hq');
begin
  if p_branch_id is null then
    if not private.is_company_owner(p_company_id) then
      raise exception 'รายจ่ายสำนักงานใหญ่บันทึกได้เฉพาะเจ้าของร้าน' using errcode = 'insufficient_privilege';
    end if;
    if coalesce(p_from_drawer, false) then
      raise exception 'รายจ่ายสำนักงานใหญ่จ่ายจากลิ้นชักสาขาไม่ได้' using errcode = 'invalid_parameter_value';
    end if;
  else
    perform private.require_branch_access(p_branch_id);
    if (select company_id from public.branches where id = p_branch_id) <> p_company_id then
      raise exception 'สาขาไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
    end if;
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'จำนวนเงินต้องมากกว่า 0' using errcode = 'invalid_parameter_value';
  end if;
  if p_note is null or char_length(trim(p_note)) = 0 then
    raise exception 'กรุณาระบุหมายเหตุ' using errcode = 'invalid_parameter_value';
  end if;
  if p_photo_path is null
     or split_part(p_photo_path, '/', 1) <> p_company_id::text or split_part(p_photo_path, '/', 2) <> v_folder
     or not exists (select 1 from storage.objects where bucket_id = 'expense-photos' and name = p_photo_path) then
    raise exception 'กรุณาแนบรูปหลักฐาน' using errcode = 'invalid_parameter_value';
  end if;
  select large_expense_threshold, timezone into v_threshold, v_tz from public.company_settings where company_id = p_company_id;
  if p_occurred_on is not null and p_occurred_on > (now() at time zone v_tz)::date then
    raise exception 'วันที่จ่ายต้องไม่เป็นวันในอนาคต' using errcode = 'invalid_parameter_value';
  end if;
  if coalesce(p_from_drawer, false) then
    v_session := private.require_open_session(p_branch_id);
  end if;

  insert into public.expenses (company_id, branch_id, expense_scope, amount, note, photo_path, occurred_on,
                               payment_source, pos_session_id, is_large, recorded_by)
  values (p_company_id, p_branch_id, case when p_branch_id is null then 'HQ' else 'BRANCH' end, round(p_amount, 2),
          left(trim(p_note), 500), p_photo_path, coalesce(p_occurred_on, (now() at time zone v_tz)::date),
          case when v_session is null then 'OTHER' else 'CASH_DRAWER' end, v_session,
          round(p_amount, 2) > v_threshold, auth.uid())
  returning id into v_id;

  if v_session is not null then
    insert into public.pos_cash_movements (company_id, branch_id, pos_session_id, movement_type, category, amount, reason, expense_id)
    values (p_company_id, p_branch_id, v_session, 'CASH_OUT', 'EXPENSE', round(p_amount, 2), left(trim(p_note), 500), v_id);
  end if;
  return v_id;
end;
$$;

-- ยกเลิกรายจ่าย:
--   STAFF: ภายในกะเดียวกันที่ยังเปิด = ยกเลิกทันที (คืนเงินเข้าลิ้นชัก); นอกนั้น = ส่งคำขอให้ OWNER
--   OWNER: ยกเลิกได้เลย (ถ้ากะยังเปิดคืนเงินเข้าลิ้นชัก; กะปิดแล้วปรับในการปิดยอดรายวัน)
create or replace function public.pos_void_expense(p_expense_id uuid, p_reason text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  e        public.expenses;
  v_owner  boolean;
  v_open   boolean;
begin
  select * into e from public.expenses where id = p_expense_id for update;
  if e.id is null then
    raise exception 'ไม่พบรายจ่าย' using errcode = 'no_data_found';
  end if;
  v_owner := private.is_company_owner(e.company_id);
  if not v_owner and (e.branch_id is null or not private.has_branch_access(e.branch_id)) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if e.status = 'VOID' then
    raise exception 'รายจ่ายนี้ยกเลิกแล้ว' using errcode = 'check_violation';
  end if;
  if p_reason is null or char_length(trim(p_reason)) < 3 then
    raise exception 'กรุณาระบุเหตุผล' using errcode = 'invalid_parameter_value';
  end if;
  v_open := e.pos_session_id is not null
            and (select status from public.pos_sessions where id = e.pos_session_id) = 'OPEN';

  if not v_owner and not v_open then
    update public.expenses
       set void_requested_at = now(), void_requested_by = auth.uid(), void_request_reason = left(trim(p_reason), 500)
     where id = e.id;
    return 'REQUESTED';
  end if;

  perform set_config('app.audit_reason', trim(p_reason), true);
  if v_open then
    insert into public.pos_cash_movements (company_id, branch_id, pos_session_id, movement_type, category, amount, reason, expense_id)
    values (e.company_id, e.branch_id, e.pos_session_id, 'CASH_IN', 'EXPENSE_REVERSAL', e.amount,
            'ยกเลิกรายจ่าย: ' || left(trim(p_reason), 400), e.id);
  end if;
  update public.expenses
     set status = 'VOID', voided_at = now(), voided_by = auth.uid(), void_reason = left(trim(p_reason), 500)
   where id = e.id;
  return 'VOIDED';
end;
$$;

-- OWNER ปฏิเสธคำขอยกเลิกรายจ่าย
create or replace function public.pos_reject_expense_void(p_expense_id uuid, p_note text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  e public.expenses;
begin
  select * into e from public.expenses where id = p_expense_id for update;
  if e.id is null or not private.is_company_owner(e.company_id) then
    raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
  end if;
  if e.status <> 'RECORDED' or e.void_requested_at is null then
    raise exception 'ไม่มีคำขอยกเลิกที่รออยู่' using errcode = 'check_violation';
  end if;
  perform set_config('app.audit_reason', coalesce(nullif(trim(p_note), ''), 'ปฏิเสธคำขอยกเลิก'), true);
  update public.expenses set void_requested_at = null, void_requested_by = null, void_request_reason = null where id = e.id;
end;
$$;

-- รายการรายจ่าย (สาขา หรือ HQ สำหรับ OWNER)
create or replace function public.expenses_list(p_company_id uuid, p_branch_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_branch_id is null then
    if not private.is_company_owner(p_company_id) then
      raise exception 'ไม่มีสิทธิ์' using errcode = 'insufficient_privilege';
    end if;
  else
    perform private.require_branch_access(p_branch_id);
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 92 then
    raise exception 'ช่วงวันที่ต้องไม่เกิน 92 วัน' using errcode = 'invalid_parameter_value';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'expense_id', e.id, 'amount', e.amount, 'note', e.note, 'photo_path', e.photo_path, 'occurred_on', e.occurred_on,
      'payment_source', e.payment_source, 'is_large', e.is_large, 'status', e.status,
      'recorded_by_name', pr.display_name, 'created_at', e.created_at,
      'session_open', s.status = 'OPEN',
      'void_requested_at', e.void_requested_at, 'void_request_reason', e.void_request_reason,
      'void_reason', e.void_reason) order by e.created_at desc)
      from public.expenses e
      left join public.profiles pr on pr.id = e.recorded_by
      left join public.pos_sessions s on s.id = e.pos_session_id
     where e.company_id = p_company_id
       and (case when p_branch_id is null then e.branch_id is null else e.branch_id = p_branch_id end)
       and e.occurred_on between p_from and p_to
  ), '[]'::jsonb);
end;
$$;

-- -----------------------------------------------------------------------------
-- ข้อมูลประกอบการตรวจสลิป (Edge Function เรียกด้วย JWT ของพนักงาน) และบันทึกผลตรวจ (service role)
-- -----------------------------------------------------------------------------
create or replace function public.pos_invoice_slip_context(p_invoice_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  iv public.invoices;
begin
  select * into iv from public.invoices where id = p_invoice_id;
  if iv.id is null then
    raise exception 'ไม่พบ Invoice' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(iv.branch_id);
  if iv.status not in ('ISSUED', 'PARTIALLY_PAID') then
    raise exception 'Invoice นี้รับเงินไม่ได้' using errcode = 'check_violation';
  end if;
  return jsonb_build_object('invoice_id', iv.id, 'company_id', iv.company_id, 'branch_id', iv.branch_id,
                            'balance', iv.total - iv.paid_amount, 'user_id', auth.uid(),
                            'slipok_branch_id', (select slipok_branch_id from public.branch_payment_accounts
                                                  where branch_id = iv.branch_id and is_active));
end;
$$;

create or replace function public.record_payment_slip_check(
  p_user_id           uuid,
  p_invoice_id        uuid,
  p_slip_path         text,
  p_requested_amount  numeric,
  p_outcome           text,
  p_provider_code     integer,
  p_provider_message  text,
  p_slip              jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  iv        public.invoices;
  v_ref     text := nullif(p_slip ->> 'trans_ref', '');
  v_amount  numeric := (p_slip ->> 'amount')::numeric;
  v_outcome text := p_outcome;
  v_message text := p_provider_message;
  v_id      uuid;
begin
  select * into iv from public.invoices where id = p_invoice_id;
  if iv.id is null or p_outcome not in ('VERIFIED', 'REJECTED', 'REVIEW') then
    raise exception 'ข้อมูลไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  if split_part(p_slip_path, '/', 1) <> iv.company_id::text or split_part(p_slip_path, '/', 2) <> iv.branch_id::text then
    raise exception 'ตำแหน่งสลิปไม่ถูกต้อง' using errcode = 'invalid_parameter_value';
  end if;
  -- ตรวจซ้ำฝั่ง DB: สลิปที่ถูกใช้แล้ว (รับเงิน/มัดจำ) ใช้ไม่ได้
  if v_outcome = 'VERIFIED' and v_ref is not null and (
       exists (select 1 from public.payments where slip_trans_ref = v_ref and status = 'SUCCESS')
    or exists (select 1 from public.booking_deposits where slip_trans_ref = v_ref and status <> 'REJECTED')
  ) then
    v_outcome := 'REJECTED';
    v_message := 'สลิปนี้ถูกใช้แล้ว';
  elsif v_outcome = 'VERIFIED' and v_ref is null then
    v_outcome := 'REVIEW';
    v_message := 'ไม่พบเลขอ้างอิงสลิป';
  end if;

  insert into public.payment_slip_checks (company_id, branch_id, invoice_id, slip_path, requested_amount, outcome,
                                          provider_code, provider_message, slip_trans_ref, slip_amount, slip_trans_at,
                                          slip_sender_name, slip_receiver_name, checked_by)
  values (iv.company_id, iv.branch_id, iv.id, p_slip_path, p_requested_amount, v_outcome, p_provider_code,
          left(v_message, 300), case when v_outcome = 'VERIFIED' then v_ref end, v_amount,
          (p_slip ->> 'trans_at')::timestamptz, left(p_slip ->> 'sender_name', 100), left(p_slip ->> 'receiver_name', 100),
          p_user_id)
  returning id into v_id;

  return jsonb_build_object('slip_check_id', v_id, 'outcome', v_outcome, 'message', v_message,
                            'slip_amount', v_amount, 'slip_path', p_slip_path);
end;
$$;

-- -----------------------------------------------------------------------------
-- มุมมองการเงินหน้าร้าน (Invoice ของวันนี้ + ค้างชำระ + ทิปเงินสดที่ยังไม่จ่าย + กะเปิด)
-- -----------------------------------------------------------------------------
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
  perform private.require_branch_access(v_branch);
  return private.invoice_view(p_invoice_id);
end;
$$;

create or replace function public.pos_finance_board(p_branch_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_date date;
begin
  perform private.require_branch_access(p_branch_id);
  select business_date into v_date from private.branch_window_at(p_branch_id, now());
  return jsonb_build_object(
    'business_date', v_date,
    'session_id', private.open_session_id(p_branch_id),
    'invoices', coalesce((
      select jsonb_agg(jsonb_build_object(
        'invoice_id', iv.id, 'service_order_id', iv.service_order_id, 'invoice_number', iv.invoice_number,
        'status', iv.status, 'business_date', iv.business_date, 'total', iv.total, 'paid_amount', iv.paid_amount,
        'balance', iv.total - iv.paid_amount,
        'customer_name', case when c.id is null then null else trim(c.first_name || ' ' || c.last_name) end
      ) order by iv.created_at desc)
        from public.invoices iv left join public.customers c on c.id = iv.customer_id
       where iv.branch_id = p_branch_id
         and (iv.business_date = v_date or iv.status in ('ISSUED', 'PARTIALLY_PAID'))), '[]'::jsonb),
    'outstanding', coalesce((
      select sum(total - paid_amount) from public.invoices
       where branch_id = p_branch_id and status in ('ISSUED', 'PARTIALLY_PAID')), 0),
    'today_sales', coalesce((
      select sum(p.amount) from public.payments p join public.invoices iv on iv.id = p.invoice_id
       where p.branch_id = p_branch_id and p.status = 'SUCCESS' and iv.business_date = v_date), 0),
    'unpaid_cash_tips', coalesce((
      select jsonb_agg(jsonb_build_object('employee_id', x.employee_id, 'nickname', e.nickname, 'amount', x.amount))
        from (select employee_id, sum(amount) as amount from public.tips
               where branch_id = p_branch_id and method = 'CASH' and status = 'RECORDED' group by employee_id) x
        join public.employees e on e.id = x.employee_id), '[]'::jsonb)
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- (แทนที่ 020) เพิ่มบริการ — ถ้าออก Invoice แล้ว รายการใหม่ไปที่ Order ต่อเนื่อง
-- -----------------------------------------------------------------------------
create or replace function public.pos_add_order_items(
  p_order_id         uuid,
  p_starts_at        timestamptz,
  p_option_ids       uuid[],
  p_idempotency_key  text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  o         public.service_orders;
  v_target  uuid;
  v_date    date;
  v_prev    jsonb;
  v_opt     uuid;
  v_result  jsonb;
  v_hash    text := private.request_hash(jsonb_build_object('o', p_order_id, 's', p_starts_at, 'i', p_option_ids));
begin
  select * into o from public.service_orders where id = p_order_id for update;
  if o.id is null then
    raise exception 'ไม่พบ Order' using errcode = 'no_data_found';
  end if;
  perform private.require_branch_access(o.branch_id);
  if o.status not in ('OPEN', 'COMPLETED') then
    raise exception 'Order นี้ถูกยกเลิกแล้ว' using errcode = 'check_violation';
  end if;

  v_prev := private.idempotency_begin('pos_add_order_items', p_idempotency_key, v_hash);
  if v_prev is not null then
    return v_prev -> 'body';
  end if;

  perform private.expire_stale_bookings();
  v_date := private.reserve_walkin(o.branch_id, p_starts_at, p_option_ids);
  if v_date <> o.business_date then
    raise exception 'เพิ่มบริการได้เฉพาะ Order ของวันทำการนี้' using errcode = 'check_violation';
  end if;

  v_target := private.order_for_new_items(o.id);
  foreach v_opt in array p_option_ids loop
    perform private.add_order_item(v_target, v_opt, p_starts_at);
  end loop;
  perform private.refresh_order_status(v_target);

  v_result := private.pos_order_view(v_target);
  perform private.idempotency_complete('pos_add_order_items', p_idempotency_key, 200, v_result);
  return v_result;
end;
$$;

-- (แทนที่ 021) ต่อเวลา — ถ้าออก Invoice แล้ว รายการต่อเวลาไปที่ Order ต่อเนื่อง
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
  v_target uuid;
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
  update public.resource_allocations set ends_at = v_start
   where service_order_item_id = i.id and status <> 'RELEASED' and ends_at > v_start;
  v_date := private.reserve_walkin(q.branch_id, v_start, array[p_option_id]);
  if v_date <> o.business_date then
    raise exception 'ต่อเวลาได้เฉพาะภายในวันทำการนี้' using errcode = 'check_violation';
  end if;

  v_target := private.order_for_new_items(o.id);
  v_item := private.add_order_item(v_target, p_option_id, v_start);
  update public.queue_items set follows_queue_id = q.id where service_order_item_id = v_item;
  perform private.refresh_order_status(v_target);

  v_result := private.pos_order_view(v_target);
  perform private.idempotency_complete('queue_extend', p_idempotency_key, 200, v_result);
  return v_result;
end;
$$;

-- -----------------------------------------------------------------------------
-- (แทนที่ 021) แดชบอร์ด STAFF: เพิ่มยอดขายวันนี้และยอดค้างชำระของสาขา
-- -----------------------------------------------------------------------------
create or replace function public.staff_dashboard_finance(p_branch_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  f jsonb;
begin
  f := public.pos_finance_board(p_branch_id);
  return jsonb_build_object('today_sales', f -> 'today_sales', 'outstanding', f -> 'outstanding',
                            'pending_void_requests', (
                              select count(*) from public.expenses
                               where branch_id = p_branch_id and status = 'RECORDED' and void_requested_at is not null));
end;
$$;

-- -----------------------------------------------------------------------------
-- Storage
--   payment-slips  : {company}/{branch}/{invoice}/{file} เขียนโดย Edge Function, พนักงานสาขาอ่านได้
--   expense-photos : {company}/{branch|hq}/{file} พนักงานสาขาอัปโหลด/อ่านของสาขาตัวเอง, hq = OWNER
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('payment-slips', 'payment-slips', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
       ('expense-photos', 'expense-photos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy payment_slips_select_branch on storage.objects
  for select to authenticated
  using (bucket_id = 'payment-slips' and private.has_branch_access(private.try_uuid(split_part(name, '/', 2))));

create or replace function private.can_access_expense_folder(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when split_part(p_name, '/', 2) = 'hq' then private.is_company_owner(private.try_uuid(split_part(p_name, '/', 1)))
    else exists (
      select 1 from public.branches b
       where b.id = private.try_uuid(split_part(p_name, '/', 2))
         and b.company_id = private.try_uuid(split_part(p_name, '/', 1))
         and private.has_branch_access(b.id))
  end;
$$;

revoke all on function private.can_access_expense_folder(text) from public;
grant execute on function private.can_access_expense_folder(text) to authenticated;

create policy expense_photos_select on storage.objects
  for select to authenticated
  using (bucket_id = 'expense-photos' and private.can_access_expense_folder(name));
create policy expense_photos_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'expense-photos' and private.can_access_expense_folder(name));

-- -----------------------------------------------------------------------------
-- Grants + RLS
-- -----------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.pos_create_invoice(uuid)',
    'public.pos_set_invoice_discount(uuid, numeric, text)',
    'public.pos_issue_invoice(uuid)',
    'public.pos_record_payment(uuid, text, numeric, uuid, text, numeric, uuid, text)',
    'public.pos_void_invoice(uuid, text, text)',
    'public.pos_refund_payment(uuid, numeric, text, text, text, text)',
    'public.pos_cash_adjustment(uuid, text, numeric, text)',
    'public.pos_pay_out_tips(uuid, uuid)',
    'public.pos_close_session(uuid, numeric, text)',
    'public.pos_review_session(uuid, boolean, text)',
    'public.pos_sessions_list(uuid, date, date)',
    'public.pos_record_expense(uuid, uuid, numeric, text, text, boolean, date)',
    'public.pos_void_expense(uuid, text)',
    'public.pos_reject_expense_void(uuid, text)',
    'public.expenses_list(uuid, uuid, date, date)',
    'public.pos_invoice_slip_context(uuid)',
    'public.pos_invoice(uuid)',
    'public.pos_finance_board(uuid)',
    'public.staff_dashboard_finance(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  execute 'revoke all on function public.record_payment_slip_check(uuid, uuid, text, numeric, text, integer, text, jsonb) from public, anon, authenticated';
  execute 'grant execute on function public.record_payment_slip_check(uuid, uuid, text, numeric, text, integer, text, jsonb) to service_role';
end;
$$;

alter table public.invoices enable row level security;
alter table public.invoice_items enable row level security;
alter table public.payment_slip_checks enable row level security;
alter table public.payments enable row level security;
alter table public.payment_refunds enable row level security;
alter table public.tips enable row level security;
alter table public.expenses enable row level security;
alter table public.pos_cash_movements enable row level security;

revoke all on public.invoices, public.invoice_items, public.payment_slip_checks, public.payments,
              public.payment_refunds, public.tips, public.expenses, public.pos_cash_movements from anon, authenticated;
grant all on public.invoices, public.invoice_items, public.payment_slip_checks, public.payments,
             public.payment_refunds, public.tips, public.expenses, public.pos_cash_movements to service_role;
grant select on public.invoices, public.invoice_items, public.payment_slip_checks, public.payments,
               public.payment_refunds, public.tips, public.expenses, public.pos_cash_movements to authenticated;

-- ยอดปิดกะ (คาดการณ์) อ่านผ่าน pos_sessions_list เท่านั้น — ไม่ grant คอลัมน์ให้อ่านตรงก่อนปิดกะ
revoke select on public.pos_sessions from authenticated;
grant select (id, company_id, branch_id, status, business_date, opened_at, opened_by, opening_cash, opening_note,
              closed_at, closed_by, review_status, reviewed_by, reviewed_at, created_at, created_by, updated_at)
  on public.pos_sessions to authenticated;

create policy invoices_select_branch on public.invoices
  for select to authenticated using (private.has_branch_access(branch_id));
create policy invoice_items_select_branch on public.invoice_items
  for select to authenticated using (private.has_branch_access(branch_id));
create policy payment_slip_checks_select_branch on public.payment_slip_checks
  for select to authenticated using (private.has_branch_access(branch_id));
create policy payments_select_branch on public.payments
  for select to authenticated using (private.has_branch_access(branch_id));
create policy payment_refunds_select_branch on public.payment_refunds
  for select to authenticated using (private.has_branch_access(branch_id));
create policy tips_select_branch on public.tips
  for select to authenticated using (private.has_branch_access(branch_id));
create policy pos_cash_movements_select_branch on public.pos_cash_movements
  for select to authenticated using (private.has_branch_access(branch_id));
create policy expenses_select on public.expenses
  for select to authenticated
  using (private.is_company_owner(company_id) or (branch_id is not null and private.has_branch_access(branch_id)));

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.invoices;
    -- pos_sessions อ่านได้บางคอลัมน์ (ยอดคาดการณ์ซ่อนก่อนปิดกะ) จึงไม่ส่งผ่าน Realtime
    alter publication supabase_realtime drop table public.pos_sessions;
  end if;
end;
$$;
