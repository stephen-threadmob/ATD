-- =============================================================================
-- 0003 Resources, resource attributes, coaches, availability, time off
-- =============================================================================
set search_path = atd, public;

create table atd.resource_types (
  id            uuid primary key default gen_random_uuid(),
  location_id   uuid references atd.locations(id) on delete cascade, -- null = org-wide
  key           text not null,
  name          text not null,
  kind          atd.resource_kind not null,
  -- Capacity semantics: 'exclusive' resources allow one blocking reservation at
  -- a time; 'shared' resources allow up to capacity concurrent reservations.
  allocation    text not null default 'exclusive' check (allocation in ('exclusive','shared')),
  icon          text,
  color         text,
  sort_order    int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create unique index on atd.resource_types (coalesce(location_id,'00000000-0000-0000-0000-000000000000'::uuid), key);

create table atd.resources (
  id               uuid primary key default gen_random_uuid(),
  location_id      uuid not null references atd.locations(id) on delete cascade,
  resource_type_id uuid not null references atd.resource_types(id) on delete restrict,
  code             text not null,                 -- 'CAGE-1', 'HITTRAX-A'
  name             text not null,
  description      text,
  status           atd.resource_status not null default 'active',
  -- Concurrency capacity. 1 for a cage. >1 for e.g. a lobby that can hold
  -- several simultaneous activities, or a bucket of shared helmets.
  capacity         int not null default 1 check (capacity >= 1),
  -- Free-form searchable attributes the requirement matcher filters on:
  --   {"length_ft":70,"has_hittrax":true,"has_mound":true,"turf":"pro"}
  attributes       jsonb not null default '{}'::jsonb,
  -- Resources that are physically contained by another (HitTrax lives in a
  -- cage). Blocking a child does NOT auto-block the parent; service
  -- requirements express that explicitly. But `implies_resource_ids` does.
  parent_resource_id uuid references atd.resources(id) on delete set null,
  -- Reserving this resource automatically reserves these too (composite kit).
  implies_resource_ids uuid[] not null default '{}',
  is_bookable_directly boolean not null default true,
  online_bookable  boolean not null default true,
  color            text,
  sort_order       int not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz
);
create unique index on atd.resources (location_id, code) where deleted_at is null;
create index on atd.resources (location_id, resource_type_id) where deleted_at is null;
create index resources_attributes_gin on atd.resources using gin (attributes jsonb_path_ops);

-- Weekly availability template per resource (e.g. HitTrax only after 3pm).
-- Absence of rows == available whenever the facility is open.
create table atd.resource_availability_rules (
  id           uuid primary key default gen_random_uuid(),
  resource_id  uuid not null references atd.resources(id) on delete cascade,
  day_of_week  int not null check (day_of_week between 0 and 6),
  starts_at    time not null,
  ends_at      time not null,
  effective_from date,
  effective_to   date,
  is_available boolean not null default true,
  check (ends_at > starts_at)
);
create index on atd.resource_availability_rules (resource_id, day_of_week);

-- ---------------------------------------------------------------------------
-- Coaches. A coach is a user + a staff profile + a schedulable resource.
-- Modelling the coach as a resource is what lets one exclusion constraint
-- cover "cage double-booked" and "coach double-booked" identically.
-- ---------------------------------------------------------------------------
create table atd.coaches (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null unique references atd.users(id) on delete cascade,
  resource_id         uuid not null unique references atd.resources(id) on delete restrict,
  display_name        text not null,
  headline            text,
  bio                 text,
  public_description  text,
  internal_notes      text,
  photo_url           text,
  employment_type     text not null default 'contractor'
                        check (employment_type in ('employee','contractor','volunteer')),
  sports              atd.sport not null default 'both',
  is_active           boolean not null default true,
  accepts_online_booking boolean not null default true,
  customer_selectable boolean not null default true,
  auto_assignable     boolean not null default true,
  min_lead_time_minutes int not null default 120,
  max_sessions_per_day  int,
  max_consecutive_minutes int,
  required_break_minutes  int not null default 0,
  assignment_priority int not null default 100,   -- lower = preferred
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz
);

create table atd.coach_locations (
  coach_id    uuid not null references atd.coaches(id) on delete cascade,
  location_id uuid not null references atd.locations(id) on delete cascade,
  primary key (coach_id, location_id)
);

-- Qualification catalogue is data, not code: admins add new ones freely.
create table atd.qualifications (
  id          uuid primary key default gen_random_uuid(),
  key         text not null unique,
  name        text not null,
  category    text not null default 'skill',
  description text
);

create table atd.coach_qualifications (
  coach_id         uuid not null references atd.coaches(id) on delete cascade,
  qualification_id uuid not null references atd.qualifications(id) on delete cascade,
  level            int not null default 1,
  certified_on     date,
  expires_on       date,
  primary key (coach_id, qualification_id)
);

-- Age range a coach will take, per qualification-free general rule.
create table atd.coach_age_ranges (
  id        uuid primary key default gen_random_uuid(),
  coach_id  uuid not null references atd.coaches(id) on delete cascade,
  min_age   int not null default 0,
  max_age   int not null default 99,
  check (max_age >= min_age)
);

-- Recurring weekly availability (local wall-clock, location timezone).
create table atd.coach_availability_rules (
  id            uuid primary key default gen_random_uuid(),
  coach_id      uuid not null references atd.coaches(id) on delete cascade,
  location_id   uuid references atd.locations(id) on delete cascade,
  day_of_week   int not null check (day_of_week between 0 and 6),
  starts_at     time not null,
  ends_at       time not null,
  effective_from date,
  effective_to   date,
  is_available  boolean not null default true,
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index on atd.coach_availability_rules (coach_id, day_of_week);

-- Date-specific availability that supersedes the weekly rule for one day.
create table atd.coach_date_availability (
  id          uuid primary key default gen_random_uuid(),
  coach_id    uuid not null references atd.coaches(id) on delete cascade,
  on_date     date not null,
  starts_at   time,
  ends_at     time,
  is_available boolean not null default true,
  note        text,
  created_at  timestamptz not null default now(),
  check (not is_available or (starts_at is not null and ends_at is not null and ends_at > starts_at))
);
create unique index on atd.coach_date_availability (coach_id, on_date, coalesce(starts_at, '00:00'::time));

create table atd.time_off_requests (
  id          uuid primary key default gen_random_uuid(),
  coach_id    uuid not null references atd.coaches(id) on delete cascade,
  starts_at   timestamptz not null,
  ends_at     timestamptz not null,
  reason      text,
  status      text not null default 'pending' check (status in ('pending','approved','denied','cancelled')),
  decided_by  uuid references atd.users(id),
  decided_at  timestamptz,
  decision_note text,
  -- Set once approved and materialised into a blocking reservation.
  reservation_id uuid,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index on atd.time_off_requests (coach_id, status);

select atd.attach_touch('atd.resource_types');
select atd.attach_touch('atd.resources');
select atd.attach_touch('atd.coaches');
select atd.attach_touch('atd.coach_availability_rules');
select atd.attach_touch('atd.time_off_requests');
