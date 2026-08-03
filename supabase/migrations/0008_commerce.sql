-- =============================================================================
-- 0008 Orders, payments, refunds, invoices, packages, memberships,
--      gift cards, promo codes, account credit — all ledger-first
-- -----------------------------------------------------------------------------
-- Money rule: no mutable balance is authoritative. Every balance is the SUM of
-- an append-only ledger. Denormalised balances exist only as fast-read mirrors
-- maintained by trigger, and can always be rebuilt from the ledger.
-- =============================================================================
set search_path = atd, public;

create table atd.orders (
  id              uuid primary key default gen_random_uuid(),
  location_id     uuid not null references atd.locations(id) on delete restrict,
  household_id    uuid references atd.households(id) on delete set null,
  organization_id uuid references atd.customer_organizations(id) on delete set null,
  number          bigint generated always as identity,
  status          atd.order_status not null default 'open',
  currency        text not null default 'usd',

  subtotal_cents  bigint not null default 0,
  discount_cents  bigint not null default 0,
  tax_cents       bigint not null default 0,
  total_cents     bigint not null default 0,
  paid_cents      bigint not null default 0,
  refunded_cents  bigint not null default 0,
  balance_due_cents bigint generated always as (total_cents - paid_cents + refunded_cents) stored,

  deposit_required_cents bigint not null default 0,
  balance_due_at  timestamptz,

  stripe_payment_intent_id text,
  stripe_checkout_session_id text,
  -- Client-supplied idempotency key: a double-clicked Pay button reuses the
  -- same order + intent instead of charging twice.
  idempotency_key text unique,

  placed_by_user_id uuid references atd.users(id),
  source          text not null default 'online',
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index on atd.orders (household_id, created_at desc);
create index on atd.orders (location_id, status);

alter table atd.bookings
  add constraint bookings_order_fk foreign key (order_id)
  references atd.orders(id) on delete set null;
alter table atd.registrations
  add constraint registrations_order_fk foreign key (order_id)
  references atd.orders(id) on delete set null;

create table atd.order_items (
  id              uuid primary key default gen_random_uuid(),
  order_id        uuid not null references atd.orders(id) on delete cascade,
  kind            text not null check (kind in
                    ('booking','registration','package','membership','addon','gift_card','fee','deposit','custom')),
  booking_id      uuid references atd.bookings(id) on delete set null,
  registration_id uuid references atd.registrations(id) on delete set null,
  package_purchase_id uuid,
  membership_id   uuid,
  addon_id        uuid references atd.service_addons(id) on delete set null,
  description     text not null,
  quantity        int not null default 1,
  unit_price_cents bigint not null default 0,
  subtotal_cents  bigint not null default 0,
  discount_cents  bigint not null default 0,
  tax_cents       bigint not null default 0,
  total_cents     bigint not null default 0,
  -- Explainable pricing: the ordered list of rules that produced total_cents.
  price_breakdown jsonb not null default '[]'::jsonb,
  created_at      timestamptz not null default now()
);
create index on atd.order_items (order_id);

create table atd.payments (
  id              uuid primary key default gen_random_uuid(),
  order_id        uuid references atd.orders(id) on delete set null,
  location_id     uuid not null references atd.locations(id) on delete restrict,
  household_id    uuid references atd.households(id) on delete set null,
  method          atd.payment_method_kind not null default 'card',
  status          atd.payment_status not null default 'processing',
  amount_cents    bigint not null,
  fee_cents       bigint not null default 0,
  currency        text not null default 'usd',
  stripe_payment_intent_id text,
  stripe_charge_id text,
  stripe_payment_method_id text,
  last4           text,
  brand           text,
  received_at     timestamptz,
  failure_code    text,
  failure_message text,
  taken_by_user_id uuid references atd.users(id),
  note            text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create unique index payments_intent_unique on atd.payments (stripe_payment_intent_id)
  where stripe_payment_intent_id is not null;
create index on atd.payments (order_id);

create table atd.refunds (
  id            uuid primary key default gen_random_uuid(),
  payment_id    uuid not null references atd.payments(id) on delete restrict,
  order_id      uuid references atd.orders(id) on delete set null,
  amount_cents  bigint not null check (amount_cents > 0),
  reason        text,
  policy_tier_id uuid references atd.policy_tiers(id),
  stripe_refund_id text unique,
  status        text not null default 'pending'
                  check (status in ('pending','succeeded','failed','canceled')),
  issued_by_user_id uuid references atd.users(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Stripe webhook dedupe: PK on the event id makes replay a no-op.
create table atd.stripe_events (
  id             text primary key,               -- evt_...
  type           text not null,
  api_version    text,
  payload        jsonb not null,
  received_at    timestamptz not null default now(),
  processed_at   timestamptz,
  processing_error text,
  attempts       int not null default 0
);
create index on atd.stripe_events (processed_at) where processed_at is null;

create table atd.invoices (
  id              uuid primary key default gen_random_uuid(),
  order_id        uuid references atd.orders(id) on delete set null,
  organization_id uuid references atd.customer_organizations(id) on delete set null,
  household_id    uuid references atd.households(id) on delete set null,
  number          text not null unique,
  status          text not null default 'draft'
                    check (status in ('draft','sent','partially_paid','paid','void','past_due')),
  issued_on       date,
  due_on          date,
  total_cents     bigint not null default 0,
  paid_cents      bigint not null default 0,
  purchase_order_ref text,
  terms           text,
  pdf_url         text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Packages: prepaid credits, tracked by ledger not by a mutable integer.
-- ---------------------------------------------------------------------------
create table atd.package_definitions (
  id                uuid primary key default gen_random_uuid(),
  location_id       uuid not null references atd.locations(id) on delete cascade,
  key               text not null,
  name              text not null,
  description       text,
  credit_count      int not null check (credit_count > 0),
  credit_unit       text not null default 'session'
                      check (credit_unit in ('session','hour','minute','day')),
  price_cents       bigint not null,
  eligible_service_ids uuid[] not null default '{}',
  eligible_category_ids uuid[] not null default '{}',
  eligible_coach_ids   uuid[] not null default '{}',
  restricted_to_off_peak boolean not null default false,
  peak_window       jsonb not null default '{}'::jsonb,
  valid_days        int not null default 365,
  expires_on        date,
  is_transferable   boolean not null default false,
  household_shared  boolean not null default true,
  allow_partial_credit boolean not null default false,
  min_lead_minutes  int not null default 0,
  is_active         boolean not null default true,
  sort_order        int not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create unique index on atd.package_definitions (location_id, key);

create table atd.package_purchases (
  id             uuid primary key default gen_random_uuid(),
  package_definition_id uuid not null references atd.package_definitions(id) on delete restrict,
  household_id   uuid not null references atd.households(id) on delete cascade,
  participant_id uuid references atd.participants(id) on delete set null,  -- null = household-wide
  order_id       uuid references atd.orders(id) on delete set null,
  purchased_at   timestamptz not null default now(),
  expires_on     date,
  credits_granted int not null,
  -- Mirror of the ledger; rebuilt by trigger.
  credits_remaining int not null default 0,
  status         text not null default 'active'
                   check (status in ('active','exhausted','expired','refunded','frozen')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index on atd.package_purchases (household_id, status);
alter table atd.order_items
  add constraint order_items_package_fk foreign key (package_purchase_id)
  references atd.package_purchases(id) on delete set null;

create table atd.package_credit_transactions (
  id              uuid primary key default gen_random_uuid(),
  package_purchase_id uuid not null references atd.package_purchases(id) on delete cascade,
  kind            atd.credit_txn_kind not null,
  delta           numeric(10,3) not null,      -- +grant, -redeem, +refund
  booking_id      uuid references atd.bookings(id) on delete set null,
  registration_id uuid references atd.registrations(id) on delete set null,
  participant_id  uuid references atd.participants(id) on delete set null,
  note            text,
  actor_user_id   uuid references atd.users(id),
  created_at      timestamptz not null default now()
);
create index on atd.package_credit_transactions (package_purchase_id, created_at);
-- One redemption row per booking per package: guards the double-click case.
create unique index package_credit_one_redeem_per_booking
  on atd.package_credit_transactions (package_purchase_id, booking_id)
  where kind = 'redeem' and booking_id is not null;

create or replace function atd.sync_package_balance() returns trigger
language plpgsql as $$
declare v_pp uuid;
begin
  v_pp := coalesce(new.package_purchase_id, old.package_purchase_id);
  update atd.package_purchases pp
     set credits_remaining = greatest(0, (
           select coalesce(sum(t.delta),0)::int
             from atd.package_credit_transactions t
            where t.package_purchase_id = pp.id)),
         status = case
           when pp.status in ('refunded','frozen') then pp.status
           when (select coalesce(sum(t.delta),0) from atd.package_credit_transactions t
                  where t.package_purchase_id = pp.id) <= 0 then 'exhausted'
           else 'active' end
   where pp.id = v_pp;
  return null;
end $$;

create trigger trg_package_balance
  after insert or update or delete on atd.package_credit_transactions
  for each row execute function atd.sync_package_balance();

-- ---------------------------------------------------------------------------
-- Memberships
-- ---------------------------------------------------------------------------
create table atd.membership_plans (
  id                uuid primary key default gen_random_uuid(),
  location_id       uuid not null references atd.locations(id) on delete cascade,
  key               text not null,
  name              text not null,
  description       text,
  billing_interval  text not null default 'month' check (billing_interval in ('month','year')),
  price_cents       bigint not null,
  setup_fee_cents   bigint not null default 0,
  trial_days        int not null default 0,
  stripe_price_id   text,
  included_credits  int not null default 0,
  included_credit_package_id uuid references atd.package_definitions(id) on delete set null,
  credits_roll_over boolean not null default false,
  max_rollover_credits int,
  member_discount_percent numeric(5,2) not null default 0,
  priority_booking_hours int not null default 0,
  guest_passes_per_period int not null default 0,
  max_bookings_per_period int,
  allows_freeze     boolean not null default true,
  max_freeze_days   int not null default 60,
  min_commitment_months int not null default 0,
  cancellation_notice_days int not null default 0,
  is_active         boolean not null default true,
  sort_order        int not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create unique index on atd.membership_plans (location_id, key);
alter table atd.pricing_rules
  add constraint pricing_rules_membership_fk foreign key (membership_plan_id)
  references atd.membership_plans(id) on delete cascade;

create table atd.memberships (
  id               uuid primary key default gen_random_uuid(),
  plan_id          uuid not null references atd.membership_plans(id) on delete restrict,
  household_id     uuid not null references atd.households(id) on delete cascade,
  participant_id   uuid references atd.participants(id) on delete set null,
  status           atd.membership_status not null default 'active',
  stripe_subscription_id text unique,
  current_period_start timestamptz,
  current_period_end   timestamptz,
  started_on       date not null default current_date,
  cancel_at        timestamptz,
  canceled_at      timestamptz,
  cancel_reason    text,
  paused_from      date,
  paused_until     date,
  failed_payment_count int not null default 0,
  bookings_this_period int not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index on atd.memberships (household_id, status);
alter table atd.order_items
  add constraint order_items_membership_fk foreign key (membership_id)
  references atd.memberships(id) on delete set null;

-- ---------------------------------------------------------------------------
-- Account credit ledger (store credit from cancellations, goodwill, etc.)
-- ---------------------------------------------------------------------------
create table atd.account_credit_transactions (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references atd.households(id) on delete cascade,
  kind          atd.credit_txn_kind not null,
  amount_cents  bigint not null,               -- signed
  booking_id    uuid references atd.bookings(id) on delete set null,
  order_id      uuid references atd.orders(id) on delete set null,
  reason        text,
  expires_on    date,
  actor_user_id uuid references atd.users(id),
  created_at    timestamptz not null default now()
);
create index on atd.account_credit_transactions (household_id, created_at desc);

create or replace function atd.sync_account_credit() returns trigger
language plpgsql as $$
declare v_h uuid;
begin
  v_h := coalesce(new.household_id, old.household_id);
  update atd.households h
     set account_credit_cents = (
       select coalesce(sum(t.amount_cents),0)
         from atd.account_credit_transactions t where t.household_id = h.id)
   where h.id = v_h;
  return null;
end $$;

create trigger trg_account_credit
  after insert or update or delete on atd.account_credit_transactions
  for each row execute function atd.sync_account_credit();

-- ---------------------------------------------------------------------------
-- Gift cards & promo codes
-- ---------------------------------------------------------------------------
create table atd.gift_cards (
  id              uuid primary key default gen_random_uuid(),
  location_id     uuid not null references atd.locations(id) on delete cascade,
  code            text not null unique,
  initial_cents   bigint not null check (initial_cents > 0),
  balance_cents   bigint not null default 0,
  purchaser_household_id uuid references atd.households(id) on delete set null,
  recipient_email atd.email,
  recipient_name  text,
  gift_message    text,
  deliver_at      timestamptz,
  delivered_at    timestamptz,
  expires_on      date,
  status          text not null default 'active'
                    check (status in ('pending','active','depleted','expired','void')),
  order_id        uuid references atd.orders(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table atd.gift_card_transactions (
  id           uuid primary key default gen_random_uuid(),
  gift_card_id uuid not null references atd.gift_cards(id) on delete cascade,
  kind         atd.credit_txn_kind not null,
  amount_cents bigint not null,
  order_id     uuid references atd.orders(id) on delete set null,
  note         text,
  created_at   timestamptz not null default now()
);

create or replace function atd.sync_gift_card_balance() returns trigger
language plpgsql as $$
declare v_g uuid;
begin
  v_g := coalesce(new.gift_card_id, old.gift_card_id);
  update atd.gift_cards g
     set balance_cents = (select coalesce(sum(t.amount_cents),0)
                            from atd.gift_card_transactions t where t.gift_card_id = g.id),
         status = case when g.status in ('void','expired') then g.status
                       when (select coalesce(sum(t.amount_cents),0)
                               from atd.gift_card_transactions t where t.gift_card_id = g.id) <= 0
                       then 'depleted' else 'active' end
   where g.id = v_g;
  return null;
end $$;

create trigger trg_gift_card_balance
  after insert or update or delete on atd.gift_card_transactions
  for each row execute function atd.sync_gift_card_balance();

create table atd.promo_codes (
  id              uuid primary key default gen_random_uuid(),
  location_id     uuid not null references atd.locations(id) on delete cascade,
  code            citext not null,
  description     text,
  discount_kind   text not null default 'percent' check (discount_kind in ('percent','amount')),
  percent         numeric(5,2),
  amount_cents    bigint,
  applies_to_service_ids uuid[] not null default '{}',
  applies_to_category_ids uuid[] not null default '{}',
  applies_to_program_ids uuid[] not null default '{}',
  first_time_customers_only boolean not null default false,
  min_order_cents bigint not null default 0,
  max_redemptions int,
  max_per_household int not null default 1,
  redemption_count int not null default 0,
  starts_at       timestamptz,
  ends_at         timestamptz,
  restricted_to_household_id uuid references atd.households(id) on delete cascade,
  is_referral     boolean not null default false,
  referring_household_id uuid references atd.households(id) on delete set null,
  is_active       boolean not null default true,
  created_by      uuid references atd.users(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create unique index on atd.promo_codes (location_id, code);

create table atd.promo_redemptions (
  id            uuid primary key default gen_random_uuid(),
  promo_code_id uuid not null references atd.promo_codes(id) on delete cascade,
  order_id      uuid not null references atd.orders(id) on delete cascade,
  household_id  uuid references atd.households(id) on delete set null,
  amount_cents  bigint not null default 0,
  created_at    timestamptz not null default now()
);
create unique index on atd.promo_redemptions (promo_code_id, order_id);

create table atd.saved_payment_methods (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references atd.households(id) on delete cascade,
  stripe_payment_method_id text not null unique,
  brand         text, last4 text, exp_month int, exp_year int,
  is_default    boolean not null default false,
  created_at    timestamptz not null default now()
);
create unique index on atd.saved_payment_methods (household_id) where is_default;

-- ---------------------------------------------------------------------------
-- Coach compensation
-- ---------------------------------------------------------------------------
create table atd.coach_compensation_rules (
  id            uuid primary key default gen_random_uuid(),
  location_id   uuid not null references atd.locations(id) on delete cascade,
  coach_id      uuid references atd.coaches(id) on delete cascade,
  service_id    uuid references atd.services(id) on delete cascade,
  category_id   uuid references atd.service_categories(id) on delete cascade,
  basis         atd.comp_basis not null,
  percent       numeric(6,3),
  amount_cents  bigint,
  hourly_cents  bigint,
  applies_to_group boolean not null default true,
  applies_to_private boolean not null default true,
  counts_no_show boolean not null default false,
  net_of_discounts boolean not null default true,
  priority      int not null default 100,
  effective_from date,
  effective_to   date,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table atd.coach_earnings (
  id            uuid primary key default gen_random_uuid(),
  coach_id      uuid not null references atd.coaches(id) on delete cascade,
  booking_id    uuid references atd.bookings(id) on delete set null,
  program_session_id uuid references atd.program_sessions(id) on delete set null,
  rule_id       uuid references atd.coach_compensation_rules(id) on delete set null,
  occurred_on   date not null,
  gross_revenue_cents   bigint not null default 0,
  eligible_revenue_cents bigint not null default 0,
  earning_cents bigint not null default 0,
  adjustment_cents bigint not null default 0,
  adjustment_reason text,
  pay_period_id uuid,
  status        text not null default 'accrued'
                  check (status in ('accrued','approved','paid','void')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index on atd.coach_earnings (coach_id, occurred_on);
create unique index coach_earnings_one_per_booking
  on atd.coach_earnings (coach_id, booking_id) where booking_id is not null;

create table atd.pay_periods (
  id          uuid primary key default gen_random_uuid(),
  location_id uuid not null references atd.locations(id) on delete cascade,
  starts_on   date not null,
  ends_on     date not null,
  status      text not null default 'open' check (status in ('open','locked','paid')),
  paid_at     timestamptz,
  created_at  timestamptz not null default now()
);
alter table atd.coach_earnings
  add constraint coach_earnings_pay_period_fk foreign key (pay_period_id)
  references atd.pay_periods(id) on delete set null;

select atd.attach_touch('atd.orders');
select atd.attach_touch('atd.payments');
select atd.attach_touch('atd.refunds');
select atd.attach_touch('atd.invoices');
select atd.attach_touch('atd.package_definitions');
select atd.attach_touch('atd.package_purchases');
select atd.attach_touch('atd.membership_plans');
select atd.attach_touch('atd.memberships');
select atd.attach_touch('atd.gift_cards');
select atd.attach_touch('atd.promo_codes');
select atd.attach_touch('atd.coach_compensation_rules');
select atd.attach_touch('atd.coach_earnings');
