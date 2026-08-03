-- =============================================================================
-- 0002 Identity, RBAC, organisations, locations, operating hours
-- =============================================================================
set search_path = atd, public;

-- ---------------------------------------------------------------------------
-- Users. Mirrors auth.users (Supabase) 1:1 via id; we never duplicate secrets.
-- ---------------------------------------------------------------------------
create table atd.users (
  id                uuid primary key default gen_random_uuid(),
  auth_user_id      uuid unique,                      -- supabase auth.users.id
  email             atd.email not null unique,
  phone             atd.phone_e164,
  first_name        text not null,
  last_name         text not null,
  display_name      text generated always as (first_name || ' ' || last_name) stored,
  avatar_url        text,
  status            atd.user_status not null default 'active',
  last_login_at     timestamptz,
  timezone          text not null default 'America/New_York',
  marketing_email_opt_in boolean not null default false,
  -- TCPA: SMS consent must be explicit, timestamped, and provenance-tracked.
  sms_consent_at    timestamptz,
  sms_consent_source text,
  sms_consent_ip    inet,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);
create index on atd.users (lower(email::text));
create index on atd.users (phone) where phone is not null;
create index users_name_trgm on atd.users using gin ((first_name || ' ' || last_name) gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- Permissions are string keys; roles bundle them; grants are per-location.
-- ---------------------------------------------------------------------------
create table atd.permissions (
  key         text primary key,
  category    text not null,
  description text not null
);

create table atd.roles (
  id          uuid primary key default gen_random_uuid(),
  key         atd.role_key not null unique,
  name        text not null,
  description text,
  is_system   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table atd.role_permissions (
  role_id        uuid not null references atd.roles(id) on delete cascade,
  permission_key text not null references atd.permissions(key) on delete cascade,
  primary key (role_id, permission_key)
);

create table atd.organizations (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  legal_name   text,
  support_email atd.email,
  support_phone atd.phone_e164,
  default_timezone text not null default 'America/New_York',
  branding     jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table atd.locations (
  id            uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atd.organizations(id) on delete restrict,
  slug          text not null unique,
  name          text not null,
  timezone      text not null default 'America/New_York',
  address_line1 text, address_line2 text, city text, region text,
  postal_code   text, country text not null default 'US',
  phone         atd.phone_e164,
  email         atd.email,
  is_active     boolean not null default true,
  -- Booking guardrails, all admin-editable.
  settings      jsonb not null default jsonb_build_object(
                  'checkout_hold_minutes', 10,
                  'min_booking_lead_minutes', 60,
                  'max_booking_horizon_days', 120,
                  'default_slot_granularity_minutes', 15,
                  'allow_guest_checkout', true,
                  'require_waiver_before_participation', true
                ),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index on atd.locations (organization_id) where deleted_at is null;

-- Per-location role grants. A super_admin row has location_id null.
create table atd.user_roles (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references atd.users(id) on delete cascade,
  role_id     uuid not null references atd.roles(id) on delete restrict,
  location_id uuid references atd.locations(id) on delete cascade,
  granted_by  uuid references atd.users(id),
  granted_at  timestamptz not null default now(),
  revoked_at  timestamptz
);
create unique index user_roles_unique_live
  on atd.user_roles (user_id, role_id, coalesce(location_id, '00000000-0000-0000-0000-000000000000'::uuid))
  where revoked_at is null;
create index on atd.user_roles (user_id) where revoked_at is null;

-- Per-user permission overrides (grant or revoke a single capability).
create table atd.user_permission_overrides (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references atd.users(id) on delete cascade,
  location_id    uuid references atd.locations(id) on delete cascade,
  permission_key text not null references atd.permissions(key) on delete cascade,
  effect         text not null check (effect in ('allow','deny')),
  reason         text,
  created_by     uuid references atd.users(id),
  created_at     timestamptz not null default now()
);
create unique index on atd.user_permission_overrides
  (user_id, permission_key, coalesce(location_id,'00000000-0000-0000-0000-000000000000'::uuid));

-- ---------------------------------------------------------------------------
-- Operating hours: weekly template + season overrides + single-date overrides.
-- Stored as local time; resolved against location.timezone.
-- ---------------------------------------------------------------------------
create table atd.operating_hour_sets (
  id          uuid primary key default gen_random_uuid(),
  location_id uuid not null references atd.locations(id) on delete cascade,
  name        text not null,
  effective_from date,
  effective_to   date,
  priority    int not null default 0,        -- higher wins on overlap
  is_default  boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  check (effective_to is null or effective_from is null or effective_to >= effective_from)
);
create index on atd.operating_hour_sets (location_id, priority desc);

create table atd.operating_hours (
  id            uuid primary key default gen_random_uuid(),
  hour_set_id   uuid not null references atd.operating_hour_sets(id) on delete cascade,
  day_of_week   int not null check (day_of_week between 0 and 6),   -- 0 = Sunday
  opens_at      time not null,
  closes_at     time not null,
  is_closed     boolean not null default false,
  check (is_closed or closes_at > opens_at)
);
create unique index on atd.operating_hours (hour_set_id, day_of_week, opens_at);

-- Explicit single-date overrides: holidays, early closes, emergency closures.
create table atd.date_overrides (
  id          uuid primary key default gen_random_uuid(),
  location_id uuid not null references atd.locations(id) on delete cascade,
  on_date     date not null,
  is_closed   boolean not null default false,
  opens_at    time,
  closes_at   time,
  label       text,
  note        text,
  created_by  uuid references atd.users(id),
  created_at  timestamptz not null default now(),
  check (is_closed or (opens_at is not null and closes_at is not null and closes_at > opens_at))
);
create unique index on atd.date_overrides (location_id, on_date);

select atd.attach_touch('atd.users');
select atd.attach_touch('atd.roles');
select atd.attach_touch('atd.organizations');
select atd.attach_touch('atd.locations');
select atd.attach_touch('atd.operating_hour_sets');
