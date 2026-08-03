-- =============================================================================
-- 0004 Households, customers, participants, organisations/teams, CRM
-- =============================================================================
set search_path = atd, public;

-- A household is the billing + booking unit. One or more adult users may be
-- attached to it (both parents), plus N participants (children).
create table atd.households (
  id                uuid primary key default gen_random_uuid(),
  location_id       uuid references atd.locations(id) on delete set null, -- home location
  name              text not null,
  primary_user_id   uuid references atd.users(id) on delete set null,
  stripe_customer_id text unique,
  account_credit_cents bigint not null default 0,   -- denormalised mirror of ledger
  balance_due_cents  bigint not null default 0,
  source            text,
  referral_source   text,
  notes             text,
  is_tax_exempt     boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);
create index on atd.households (primary_user_id);
create index households_name_trgm on atd.households using gin (name gin_trgm_ops);

create table atd.household_members (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references atd.households(id) on delete cascade,
  user_id      uuid not null references atd.users(id) on delete cascade,
  relationship text not null default 'guardian',
  can_book     boolean not null default true,
  can_pay      boolean not null default true,
  is_primary   boolean not null default false,
  created_at   timestamptz not null default now()
);
create unique index on atd.household_members (household_id, user_id);
create unique index on atd.household_members (household_id) where is_primary;

create table atd.participants (
  id              uuid primary key default gen_random_uuid(),
  household_id    uuid not null references atd.households(id) on delete cascade,
  -- Adults booking for themselves get a participant row linked to their user.
  user_id         uuid references atd.users(id) on delete set null,
  first_name      text not null,
  last_name       text not null,
  preferred_name  text,
  date_of_birth   date,
  gender          text,
  sport           atd.sport not null default 'baseball',
  school          text,
  team_name       text,
  skill_level     text,
  positions       text[] not null default '{}',
  bats            atd.throw_bat_hand,
  throws          atd.throw_bat_hand,
  shirt_size      text,
  -- Sensitive: exposed only to users holding participant.read_medical.
  allergies       text,
  medical_notes   text,
  photo_consent   boolean,
  internal_notes  text,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);
create index on atd.participants (household_id) where deleted_at is null;
create index participants_name_trgm on atd.participants
  using gin ((first_name || ' ' || last_name) gin_trgm_ops);

-- Age at an arbitrary date — used by age-restriction checks and the
-- "participant ages out between registration and program date" edge case.
create or replace function atd.age_on(p_dob date, p_on date)
returns int language sql immutable as $$
  select case when p_dob is null then null
              else extract(year from age(p_on, p_dob))::int end
$$;

create table atd.emergency_contacts (
  id             uuid primary key default gen_random_uuid(),
  household_id   uuid not null references atd.households(id) on delete cascade,
  participant_id uuid references atd.participants(id) on delete cascade,
  name           text not null,
  relationship   text,
  phone          atd.phone_e164 not null,
  alt_phone      atd.phone_e164,
  email          atd.email,
  priority       int not null default 1,
  created_at     timestamptz not null default now()
);
create index on atd.emergency_contacts (household_id);

create table atd.authorized_pickups (
  id             uuid primary key default gen_random_uuid(),
  household_id   uuid not null references atd.households(id) on delete cascade,
  participant_id uuid references atd.participants(id) on delete cascade,
  name           text not null,
  relationship   text,
  phone          atd.phone_e164,
  photo_url      text,
  notes          text,
  created_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Organisations (travel teams, schools, corporate) and their rosters.
-- ---------------------------------------------------------------------------
create table atd.customer_organizations (
  id                uuid primary key default gen_random_uuid(),
  location_id       uuid references atd.locations(id) on delete set null,
  name              text not null,
  kind              text not null default 'travel_team',
  primary_contact_user_id uuid references atd.users(id) on delete set null,
  billing_email     atd.email,
  billing_terms_days int not null default 0,
  is_tax_exempt     boolean not null default false,
  tax_exempt_id     text,
  purchase_order_ref text,
  custom_rate_card_id uuid,           -- FK added in 0005
  stripe_customer_id text unique,
  contract_url      text,
  notes             text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);

create table atd.organization_users (
  organization_id uuid not null references atd.customer_organizations(id) on delete cascade,
  user_id         uuid not null references atd.users(id) on delete cascade,
  role            text not null default 'member',
  can_book        boolean not null default true,
  can_invoice     boolean not null default false,
  primary key (organization_id, user_id)
);

create table atd.teams (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atd.customer_organizations(id) on delete cascade,
  name            text not null,
  age_group       text,
  season          text,
  head_coach_name text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table atd.team_roster_entries (
  id             uuid primary key default gen_random_uuid(),
  team_id        uuid not null references atd.teams(id) on delete cascade,
  participant_id uuid references atd.participants(id) on delete set null,
  full_name      text not null,
  jersey_number  text,
  positions      text[] not null default '{}',
  date_of_birth  date,
  created_at     timestamptz not null default now()
);
create index on atd.team_roster_entries (team_id);

-- ---------------------------------------------------------------------------
-- CRM tagging + staff notes
-- ---------------------------------------------------------------------------
create table atd.tags (
  id       uuid primary key default gen_random_uuid(),
  key      text not null unique,
  label    text not null,
  color    text,
  category text not null default 'general'
);

create table atd.household_tags (
  household_id uuid not null references atd.households(id) on delete cascade,
  tag_id       uuid not null references atd.tags(id) on delete cascade,
  applied_by   uuid references atd.users(id),
  applied_at   timestamptz not null default now(),
  primary key (household_id, tag_id)
);

create table atd.staff_notes (
  id            uuid primary key default gen_random_uuid(),
  location_id   uuid references atd.locations(id) on delete cascade,
  household_id  uuid references atd.households(id) on delete cascade,
  participant_id uuid references atd.participants(id) on delete cascade,
  booking_id    uuid,                      -- FK added in 0006
  body          text not null,
  visibility    text not null default 'staff'
                  check (visibility in ('staff','coach','admin_only')),
  is_pinned     boolean not null default false,
  author_user_id uuid references atd.users(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index on atd.staff_notes (household_id);
create index on atd.staff_notes (participant_id);

select atd.attach_touch('atd.households');
select atd.attach_touch('atd.participants');
select atd.attach_touch('atd.customer_organizations');
select atd.attach_touch('atd.teams');
select atd.attach_touch('atd.staff_notes');
