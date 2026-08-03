-- =============================================================================
-- 0007 Programs (camps, clinics, arm-care, group series), registrations,
--      capacity control, attendance, waitlists
-- -----------------------------------------------------------------------------
-- A program is ONE customer-facing product that owns N sessions. Each session
-- materialises exactly one booking, which owns the resource reservations. So a
-- 40-child camp blocks four cages ONCE per day, not forty times — while forty
-- registrations attach to the same session. That is the "group lesson must not
-- double-block the cage" acceptance requirement, structurally.
-- =============================================================================
set search_path = atd, public;

create table atd.programs (
  id                uuid primary key default gen_random_uuid(),
  location_id       uuid not null references atd.locations(id) on delete cascade,
  service_id        uuid not null references atd.services(id) on delete restrict,
  slug              text not null,
  name              text not null,
  summary           text,
  description       text,
  image_url         text,

  starts_on         date not null,
  ends_on           date not null,
  registration_opens_at  timestamptz,
  registration_closes_at timestamptz,

  capacity          int not null check (capacity >= 1),
  min_enrollment    int not null default 0,
  -- Maintained transactionally by trigger; the check below is the hard gate on
  -- the "two people buy the final spot" race.
  enrolled_count    int not null default 0,
  waitlist_count    int not null default 0,

  min_age           int,
  max_age           int,
  age_as_of_date    date,           -- age computed on this date, not on booking date
  skill_levels      text[] not null default '{}',
  sport             atd.sport not null default 'both',

  allow_drop_in     boolean not null default false,
  allow_partial_registration boolean not null default false,   -- single-day camp days
  prorate_late_enrollment boolean not null default false,
  allow_waitlist    boolean not null default true,

  price_cents       bigint not null default 0,
  drop_in_price_cents bigint,
  deposit_cents     bigint not null default 0,
  balance_due_days_before int,
  sibling_discount_percent numeric(5,2) not null default 0,

  collects_shirt_size boolean not null default false,
  collects_lunch_choice boolean not null default false,
  includes_lunch    boolean not null default false,
  parent_instructions text,
  check_in_window_minutes int not null default 15,
  pickup_window_minutes   int not null default 15,
  late_pickup_fee_cents   bigint not null default 0,

  status            text not null default 'draft'
                      check (status in ('draft','published','full','closed','cancelled','completed')),
  cancellation_policy_id uuid references atd.policies(id) on delete set null,
  waiver_template_ids uuid[] not null default '{}',
  created_by        uuid references atd.users(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  check (ends_on >= starts_on),
  check (max_age is null or min_age is null or max_age >= min_age),
  constraint programs_capacity_not_exceeded check (enrolled_count <= capacity)
);
create unique index on atd.programs (location_id, slug) where deleted_at is null;
create index on atd.programs (location_id, starts_on) where deleted_at is null;

create table atd.program_sessions (
  id            uuid primary key default gen_random_uuid(),
  program_id    uuid not null references atd.programs(id) on delete cascade,
  booking_id    uuid references atd.bookings(id) on delete set null,
  session_number int not null,
  title         text,
  session_date  date not null,
  starts_at     timestamptz not null,
  ends_at       timestamptz not null,
  -- Per-session capacity for drop-in style group classes; null = inherit.
  capacity      int,
  enrolled_count int not null default 0,
  is_cancelled  boolean not null default false,
  cancellation_reason text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (ends_at > starts_at),
  constraint program_sessions_capacity_not_exceeded
    check (capacity is null or enrolled_count <= capacity)
);
create unique index on atd.program_sessions (program_id, session_number);
create index on atd.program_sessions (program_id, session_date);

alter table atd.bookings
  add constraint bookings_program_fk foreign key (program_id)
    references atd.programs(id) on delete set null,
  add constraint bookings_program_session_fk foreign key (program_session_id)
    references atd.program_sessions(id) on delete set null;

-- Coaches assigned to a program (beyond the per-session reservation).
create table atd.program_staff (
  program_id uuid not null references atd.programs(id) on delete cascade,
  coach_id   uuid not null references atd.coaches(id) on delete cascade,
  role       text not null default 'instructor',
  primary key (program_id, coach_id)
);

-- ---------------------------------------------------------------------------
-- Registrations: a participant's seat in a program (or a single session).
-- ---------------------------------------------------------------------------
create table atd.registrations (
  id                uuid primary key default gen_random_uuid(),
  program_id        uuid not null references atd.programs(id) on delete cascade,
  program_session_id uuid references atd.program_sessions(id) on delete cascade,
  household_id      uuid not null references atd.households(id) on delete restrict,
  participant_id    uuid not null references atd.participants(id) on delete restrict,
  order_id          uuid,                      -- FK added in 0008
  status            atd.registration_status not null default 'registered',
  registration_kind text not null default 'full_series'
                      check (registration_kind in ('full_series','single_session','drop_in')),
  confirmation_code text not null unique default upper(substr(encode(gen_random_bytes(6),'hex'),1,8)),

  price_cents       bigint not null default 0,
  discount_cents    bigint not null default 0,
  paid_cents        bigint not null default 0,

  age_at_registration int,
  shirt_size        text,
  lunch_choice      text,
  answers           jsonb not null default '{}'::jsonb,
  notes             text,

  registered_at     timestamptz not null default now(),
  cancelled_at      timestamptz,
  cancelled_by_user_id uuid references atd.users(id),
  cancellation_reason text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
-- A participant holds at most one live seat per program (or per session for
-- drop-in style). This is the second layer of the "final spot" defence.
create unique index registrations_one_live_seat
  on atd.registrations (program_id, participant_id,
                        coalesce(program_session_id,'00000000-0000-0000-0000-000000000000'::uuid))
  where status in ('registered','attended');
create index on atd.registrations (household_id, registered_at desc);
create index on atd.registrations (program_id, status);

alter table atd.booking_participants
  add constraint booking_participants_registration_fk foreign key (registration_id)
  references atd.registrations(id) on delete set null;

create table atd.attendance_records (
  id             uuid primary key default gen_random_uuid(),
  program_session_id uuid not null references atd.program_sessions(id) on delete cascade,
  registration_id uuid not null references atd.registrations(id) on delete cascade,
  participant_id uuid not null references atd.participants(id) on delete cascade,
  state          atd.attendance_state not null default 'unknown',
  checked_in_at  timestamptz,
  checked_out_at timestamptz,
  released_to    text,
  marked_by      uuid references atd.users(id),
  note           text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create unique index on atd.attendance_records (program_session_id, registration_id);

create table atd.makeup_credits (
  id             uuid primary key default gen_random_uuid(),
  registration_id uuid not null references atd.registrations(id) on delete cascade,
  participant_id uuid not null references atd.participants(id) on delete cascade,
  reason         text,
  issued_by      uuid references atd.users(id),
  expires_on     date,
  redeemed_booking_id uuid references atd.bookings(id) on delete set null,
  redeemed_at    timestamptz,
  created_at     timestamptz not null default now()
);

-- Progress / lesson notes written by coaches.
create table atd.lesson_notes (
  id             uuid primary key default gen_random_uuid(),
  booking_id     uuid references atd.bookings(id) on delete cascade,
  program_session_id uuid references atd.program_sessions(id) on delete cascade,
  participant_id uuid not null references atd.participants(id) on delete cascade,
  coach_id       uuid references atd.coaches(id) on delete set null,
  body           text not null,
  focus_areas    text[] not null default '{}',
  metrics        jsonb not null default '{}'::jsonb,   -- exit velo, spin, etc.
  shared_with_customer boolean not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index on atd.lesson_notes (participant_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Waitlists — for programs, sessions, coaches, or arbitrary time windows.
-- ---------------------------------------------------------------------------
create table atd.waitlist_entries (
  id              uuid primary key default gen_random_uuid(),
  location_id     uuid not null references atd.locations(id) on delete cascade,
  program_id      uuid references atd.programs(id) on delete cascade,
  program_session_id uuid references atd.program_sessions(id) on delete cascade,
  service_id      uuid references atd.services(id) on delete cascade,
  coach_id        uuid references atd.coaches(id) on delete set null,
  household_id    uuid not null references atd.households(id) on delete cascade,
  participant_id  uuid references atd.participants(id) on delete cascade,
  desired_from    timestamptz,
  desired_to      timestamptz,
  desired_weekdays int[] not null default '{}',
  status          atd.waitlist_status not null default 'waiting',
  priority        int not null default 100,
  position        int,
  note            text,
  joined_at       timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index on atd.waitlist_entries (program_id, status, priority, joined_at);
create index on atd.waitlist_entries (service_id, status, priority, joined_at);

-- Every offer is recorded; the claim window is enforced by expires_at plus a
-- reservation-backed hold so two people cannot claim the same opening.
create table atd.waitlist_offers (
  id             uuid primary key default gen_random_uuid(),
  waitlist_entry_id uuid not null references atd.waitlist_entries(id) on delete cascade,
  hold_id        uuid references atd.checkout_holds(id) on delete set null,
  offered_at     timestamptz not null default now(),
  expires_at     timestamptz not null,
  responded_at   timestamptz,
  outcome        text check (outcome in ('claimed','declined','expired','superseded')),
  claim_token    text not null unique default encode(gen_random_bytes(18),'hex'),
  offered_starts_at timestamptz,
  offered_ends_at   timestamptz,
  resulting_booking_id uuid references atd.bookings(id) on delete set null,
  resulting_registration_id uuid references atd.registrations(id) on delete set null,
  created_at     timestamptz not null default now()
);
create index on atd.waitlist_offers (expires_at) where outcome is null;

-- ---------------------------------------------------------------------------
-- Enrollment counters maintained inside the same transaction as the seat.
-- Combined with `programs_capacity_not_exceeded`, an over-sell is impossible.
-- ---------------------------------------------------------------------------
create or replace function atd.sync_enrollment_counts() returns trigger
language plpgsql as $$
declare
  v_prog uuid;
  v_sess uuid;
begin
  v_prog := coalesce(new.program_id, old.program_id);
  v_sess := coalesce(new.program_session_id, old.program_session_id);

  update atd.programs p
     set enrolled_count = (
           select count(*) from atd.registrations r
            where r.program_id = p.id
              and r.program_session_id is null
              and r.status in ('registered','attended')),
         waitlist_count = (
           select count(*) from atd.waitlist_entries w
            where w.program_id = p.id and w.status in ('waiting','offered'))
   where p.id = v_prog;

  if v_sess is not null then
    update atd.program_sessions s
       set enrolled_count = (
             select count(*) from atd.registrations r
              where r.program_session_id = s.id
                and r.status in ('registered','attended'))
     where s.id = v_sess;
  end if;
  return null;
end $$;

create trigger trg_registration_counts
  after insert or update of status or delete on atd.registrations
  for each row execute function atd.sync_enrollment_counts();

select atd.attach_touch('atd.programs');
select atd.attach_touch('atd.program_sessions');
select atd.attach_touch('atd.registrations');
select atd.attach_touch('atd.attendance_records');
select atd.attach_touch('atd.lesson_notes');
select atd.attach_touch('atd.waitlist_entries');
