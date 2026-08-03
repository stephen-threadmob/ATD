-- =============================================================================
-- 0006 Bookings, resource reservations, holds, blocks, recurrence
-- -----------------------------------------------------------------------------
-- THE CENTRAL INVARIANT
--
--   Nothing occupies the facility except a row in atd.resource_reservations.
--   Bookings, camps, parties, admin blocks, coach time off, maintenance and
--   transient checkout holds ALL materialise into that one table. A single
--   GiST exclusion constraint therefore guarantees, at the storage layer, that
--   no resource is ever double-committed — including against a hold that
--   another customer's half-finished checkout is holding.
--
--   Because the guarantee lives in the constraint and not in application code,
--   a race between two concurrent checkouts cannot produce a double booking:
--   the loser gets SQLSTATE 23P01 (exclusion_violation) and is retried or
--   surfaced as "that slot was just taken".
-- =============================================================================
set search_path = atd, public;

-- ---------------------------------------------------------------------------
-- Recurring series header
-- ---------------------------------------------------------------------------
create table atd.recurring_series (
  id             uuid primary key default gen_random_uuid(),
  location_id    uuid not null references atd.locations(id) on delete cascade,
  service_id     uuid references atd.services(id) on delete set null,
  title          text,
  freq           atd.recurrence_freq not null,
  interval_count int not null default 1 check (interval_count >= 1),
  by_weekday     int[] not null default '{}',
  start_date     date not null,
  end_date       date,
  occurrence_count int,
  start_time_local time not null,
  duration_minutes int not null,
  timezone       text not null default 'America/New_York',
  skip_dates     date[] not null default '{}',
  created_by     uuid references atd.users(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (end_date is not null or occurrence_count is not null)
);

-- ---------------------------------------------------------------------------
-- Checkout holds: the parent of transient hold reservations.
-- ---------------------------------------------------------------------------
create table atd.checkout_holds (
  id            uuid primary key default gen_random_uuid(),
  location_id   uuid not null references atd.locations(id) on delete cascade,
  household_id  uuid references atd.households(id) on delete cascade,
  session_token text not null,                 -- anonymous/guest checkout key
  service_id    uuid references atd.services(id) on delete set null,
  starts_at     timestamptz,
  ends_at       timestamptz,
  expires_at    timestamptz not null,
  released_at   timestamptz,
  converted_booking_id uuid,
  payload       jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);
create index on atd.checkout_holds (expires_at) where released_at is null;
create index on atd.checkout_holds (session_token);

-- ---------------------------------------------------------------------------
-- Bookings
-- ---------------------------------------------------------------------------
create table atd.bookings (
  id                uuid primary key default gen_random_uuid(),
  location_id       uuid not null references atd.locations(id) on delete restrict,
  service_id        uuid not null references atd.services(id) on delete restrict,
  household_id      uuid references atd.households(id) on delete set null,
  organization_id   uuid references atd.customer_organizations(id) on delete set null,
  program_id        uuid,                       -- FK added in 0007
  program_session_id uuid,                      -- FK added in 0007
  series_id         uuid references atd.recurring_series(id) on delete set null,
  parent_booking_id uuid references atd.bookings(id) on delete set null,

  confirmation_code text not null unique default upper(substr(encode(gen_random_bytes(6),'hex'),1,8)),
  status            atd.booking_status not null default 'draft',
  starts_at         timestamptz not null,
  ends_at           timestamptz not null,
  timezone          text not null default 'America/New_York',
  -- Denormalised buffered envelope for fast calendar queries.
  blocked_from      timestamptz not null,
  blocked_to        timestamptz not null,

  participant_count int not null default 1,
  title             text,
  customer_note     text,
  internal_note     text,
  answers           jsonb not null default '{}'::jsonb,
  source            text not null default 'online'
                      check (source in ('online','front_desk','admin','walk_in','import','api','kiosk')),
  created_by_user_id uuid references atd.users(id),

  -- Money snapshot (authoritative ledger lives in orders/payments).
  subtotal_cents    bigint not null default 0,
  discount_cents    bigint not null default 0,
  addon_cents       bigint not null default 0,
  tax_cents         bigint not null default 0,
  total_cents       bigint not null default 0,
  paid_cents        bigint not null default 0,
  balance_due_cents bigint generated always as (total_cents - paid_cents) stored,
  order_id          uuid,                       -- FK added in 0008

  checked_in_at     timestamptz,
  started_at        timestamptz,
  completed_at      timestamptz,
  cancelled_at      timestamptz,
  cancelled_by_user_id uuid references atd.users(id),
  cancellation_reason  text,
  policy_tier_applied_id uuid references atd.policy_tiers(id),

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  check (ends_at > starts_at),
  check (blocked_to >= ends_at and blocked_from <= starts_at)
);
create index on atd.bookings (location_id, starts_at) where deleted_at is null;
create index on atd.bookings (household_id, starts_at desc) where deleted_at is null;
create index on atd.bookings (status, starts_at) where deleted_at is null;
create index on atd.bookings (series_id) where series_id is not null;
create index bookings_span_gist on atd.bookings using gist (tstzrange(blocked_from, blocked_to, '[)'));

alter table atd.staff_notes
  add constraint staff_notes_booking_fk foreign key (booking_id)
  references atd.bookings(id) on delete cascade;

create table atd.booking_participants (
  id             uuid primary key default gen_random_uuid(),
  booking_id     uuid not null references atd.bookings(id) on delete cascade,
  participant_id uuid not null references atd.participants(id) on delete restrict,
  registration_id uuid,                        -- FK added in 0007
  attendance     atd.attendance_state not null default 'unknown',
  checked_in_at  timestamptz,
  checked_out_at timestamptz,
  checked_out_to text,                          -- authorized pickup name
  answers        jsonb not null default '{}'::jsonb,
  price_cents    bigint not null default 0,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create unique index on atd.booking_participants (booking_id, participant_id);

create table atd.booking_addons (
  id          uuid primary key default gen_random_uuid(),
  booking_id  uuid not null references atd.bookings(id) on delete cascade,
  addon_id    uuid not null references atd.service_addons(id) on delete restrict,
  quantity    int not null default 1 check (quantity >= 1),
  unit_price_cents bigint not null default 0,
  total_cents bigint not null default 0,
  created_at  timestamptz not null default now()
);

create table atd.booking_status_history (
  id           uuid primary key default gen_random_uuid(),
  booking_id   uuid not null references atd.bookings(id) on delete cascade,
  from_status  atd.booking_status,
  to_status    atd.booking_status not null,
  reason       text,
  actor_user_id uuid references atd.users(id),
  created_at   timestamptz not null default now()
);
create index on atd.booking_status_history (booking_id, created_at);

-- ---------------------------------------------------------------------------
-- Facility blocks (maintenance, closure, admin hold, coach time off)
-- ---------------------------------------------------------------------------
create table atd.resource_blocks (
  id           uuid primary key default gen_random_uuid(),
  location_id  uuid not null references atd.locations(id) on delete cascade,
  kind         atd.block_kind not null,
  title        text not null,
  note         text,
  starts_at    timestamptz not null,
  ends_at      timestamptz not null,
  applies_to_whole_location boolean not null default false,
  coach_id     uuid references atd.coaches(id) on delete cascade,
  time_off_request_id uuid references atd.time_off_requests(id) on delete cascade,
  series_id    uuid references atd.recurring_series(id) on delete set null,
  created_by   uuid references atd.users(id),
  cancelled_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index on atd.resource_blocks (location_id, starts_at);

-- =============================================================================
-- resource_reservations — the single source of occupancy truth
-- =============================================================================
create table atd.resource_reservations (
  id             uuid primary key default gen_random_uuid(),
  location_id    uuid not null references atd.locations(id) on delete cascade,
  resource_id    uuid not null references atd.resources(id) on delete restrict,

  -- Exactly one owner.
  booking_id     uuid references atd.bookings(id) on delete cascade,
  block_id       uuid references atd.resource_blocks(id) on delete cascade,
  hold_id        uuid references atd.checkout_holds(id) on delete cascade,

  requirement_id uuid references atd.service_resource_requirements(id) on delete set null,
  requirement_label text,

  status         atd.reservation_status not null default 'confirmed',

  -- Activity window.
  starts_at      timestamptz not null,
  ends_at        timestamptz not null,
  -- Buffers pushed into the blocked envelope so a 5-minute transition gap is
  -- enforced by the same constraint that prevents overlap.
  buffer_before_minutes int not null default 0 check (buffer_before_minutes >= 0),
  buffer_after_minutes  int not null default 0 check (buffer_after_minutes >= 0),
  blocked_from   timestamptz not null,
  blocked_to     timestamptz not null,

  -- Shared-capacity resources hand out a distinct slot index per concurrent
  -- reservation, so capacity N is enforced by the same exclusion constraint.
  slot_index     int not null default 0 check (slot_index >= 0),

  expires_at     timestamptz,          -- holds only
  released_at    timestamptz,

  -- Stored generated columns: safe in an index predicate, and immutable.
  is_blocking    boolean generated always as (
                   status in ('hold','tentative','confirmed','in_progress')
                 ) stored,
  blocking_span  tstzrange generated always as (
                   tstzrange(blocked_from, blocked_to, '[)')
                 ) stored,

  created_by     uuid references atd.users(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  check (ends_at > starts_at),
  check (blocked_from <= starts_at and blocked_to >= ends_at),
  check (num_nonnulls(booking_id, block_id, hold_id) = 1),
  check (status <> 'hold' or expires_at is not null),

  -- ***** the guarantee *****
  constraint resource_reservations_no_overlap
    exclude using gist (
      resource_id  with =,
      slot_index   with =,
      blocking_span with &&
    ) where (is_blocking)
);

create index on atd.resource_reservations (booking_id);
create index on atd.resource_reservations (block_id);
create index on atd.resource_reservations (hold_id);
create index on atd.resource_reservations (location_id, blocked_from);
create index reservations_expiry on atd.resource_reservations (expires_at)
  where status = 'hold';
create index reservations_live_span on atd.resource_reservations
  using gist (resource_id, blocking_span) where is_blocking;

alter table atd.time_off_requests
  add constraint time_off_reservation_fk foreign key (reservation_id)
  references atd.resource_reservations(id) on delete set null;

-- ---------------------------------------------------------------------------
-- Buffer envelope maintenance. Kept in a trigger rather than a generated
-- column because timestamptz + interval is STABLE, not IMMUTABLE.
-- ---------------------------------------------------------------------------
create or replace function atd.sync_reservation_envelope() returns trigger
language plpgsql as $$
begin
  new.blocked_from := new.starts_at - make_interval(mins => new.buffer_before_minutes);
  new.blocked_to   := new.ends_at   + make_interval(mins => new.buffer_after_minutes);
  new.updated_at   := now();
  return new;
end $$;

create trigger trg_reservation_envelope
  before insert or update of starts_at, ends_at, buffer_before_minutes, buffer_after_minutes
  on atd.resource_reservations
  for each row execute function atd.sync_reservation_envelope();

create or replace function atd.sync_booking_envelope() returns trigger
language plpgsql as $$
declare
  v_before int; v_after int;
begin
  select coalesce(s.buffer_before_minutes,0) + coalesce(s.setup_minutes,0),
         coalesce(s.buffer_after_minutes,0)  + coalesce(s.cleanup_minutes,0)
    into v_before, v_after
    from atd.services s where s.id = new.service_id;
  new.blocked_from := new.starts_at - make_interval(mins => coalesce(v_before,0));
  new.blocked_to   := new.ends_at   + make_interval(mins => coalesce(v_after,0));
  new.updated_at   := now();
  return new;
end $$;

create trigger trg_booking_envelope
  before insert or update of starts_at, ends_at, service_id
  on atd.bookings
  for each row execute function atd.sync_booking_envelope();

-- Booking status transitions are recorded automatically.
create or replace function atd.log_booking_status() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    insert into atd.booking_status_history(booking_id, from_status, to_status, actor_user_id)
    values (new.id, null, new.status, new.created_by_user_id);
  elsif new.status is distinct from old.status then
    insert into atd.booking_status_history(booking_id, from_status, to_status, reason)
    values (new.id, old.status, new.status, new.cancellation_reason);
  end if;
  return null;
end $$;

create trigger trg_booking_status_history
  after insert or update of status on atd.bookings
  for each row execute function atd.log_booking_status();

select atd.attach_touch('atd.recurring_series');
select atd.attach_touch('atd.booking_participants');
select atd.attach_touch('atd.resource_blocks');
