-- =============================================================================
-- 0009 Waivers (versioned), notifications, check-in, files, settings, audit
-- =============================================================================
set search_path = atd, public;

-- ---------------------------------------------------------------------------
-- Waivers. Templates hold identity; versions hold the legally binding body.
-- A signature always points at a VERSION, so "did they sign the current one?"
-- is a join, not a guess.
-- ---------------------------------------------------------------------------
create table atd.waiver_templates (
  id            uuid primary key default gen_random_uuid(),
  location_id   uuid not null references atd.locations(id) on delete cascade,
  key           text not null,
  name          text not null,
  audience      text not null default 'participant'
                  check (audience in ('participant','adult','guardian','spectator','staff')),
  requires_guardian_if_under int not null default 18,
  renewal_months int,                         -- null = never expires
  is_required   boolean not null default true,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create unique index on atd.waiver_templates (location_id, key);

create table atd.waiver_versions (
  id            uuid primary key default gen_random_uuid(),
  template_id   uuid not null references atd.waiver_templates(id) on delete cascade,
  version       int not null,
  body_markdown text not null,
  summary_of_changes text,
  -- Material changes force re-signature; typo fixes do not.
  requires_resignature boolean not null default true,
  effective_from timestamptz not null default now(),
  retired_at    timestamptz,
  published_by  uuid references atd.users(id),
  created_at    timestamptz not null default now()
);
create unique index on atd.waiver_versions (template_id, version);
create unique index waiver_versions_one_current on atd.waiver_versions (template_id)
  where retired_at is null;

create table atd.signed_waivers (
  id              uuid primary key default gen_random_uuid(),
  waiver_version_id uuid not null references atd.waiver_versions(id) on delete restrict,
  household_id    uuid references atd.households(id) on delete cascade,
  participant_id  uuid references atd.participants(id) on delete cascade,
  signer_user_id  uuid references atd.users(id) on delete set null,
  signer_name     text not null,
  signer_email    atd.email,
  signer_relation atd.waiver_signer_relation not null default 'self',
  signature_data  text,                       -- base64 PNG or typed name
  signature_kind  text not null default 'typed' check (signature_kind in ('typed','drawn','click')),
  photo_consent   boolean,
  medical_ack     boolean,
  signed_at       timestamptz not null default now(),
  expires_on      date,
  ip_address      inet,
  user_agent      text,
  document_url    text,
  revoked_at      timestamptz,
  created_at      timestamptz not null default now()
);
create index on atd.signed_waivers (participant_id) where revoked_at is null;
create index on atd.signed_waivers (household_id) where revoked_at is null;

-- Explicit, audited exceptions when staff let a participant play unsigned.
create table atd.waiver_overrides (
  id             uuid primary key default gen_random_uuid(),
  participant_id uuid not null references atd.participants(id) on delete cascade,
  waiver_template_id uuid not null references atd.waiver_templates(id) on delete cascade,
  booking_id     uuid references atd.bookings(id) on delete set null,
  reason         text not null,
  approved_by    uuid not null references atd.users(id),
  expires_at     timestamptz,
  created_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------------
create table atd.notification_templates (
  id            uuid primary key default gen_random_uuid(),
  location_id   uuid references atd.locations(id) on delete cascade,
  key           text not null,
  name          text not null,
  channel       atd.notification_channel not null,
  subject       text,
  body          text not null,               -- Handlebars-ish {{variables}}
  from_name     text,
  reply_to      atd.email,
  is_transactional boolean not null default true,
  is_active     boolean not null default true,
  available_variables text[] not null default '{}',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create unique index on atd.notification_templates
  (coalesce(location_id,'00000000-0000-0000-0000-000000000000'::uuid), key, channel);

-- Trigger definitions: which template fires on which event, with what offset.
create table atd.notification_rules (
  id            uuid primary key default gen_random_uuid(),
  location_id   uuid not null references atd.locations(id) on delete cascade,
  event_key     text not null,               -- 'booking.confirmed', 'booking.reminder'
  template_id   uuid not null references atd.notification_templates(id) on delete cascade,
  channel       atd.notification_channel not null,
  offset_minutes int not null default 0,      -- negative = before the anchor
  anchor        text not null default 'immediate'
                  check (anchor in ('immediate','booking_start','booking_end','program_start','balance_due','period_end')),
  service_ids   uuid[] not null default '{}',
  program_ids   uuid[] not null default '{}',
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index on atd.notification_rules (location_id, event_key) where is_active;

create table atd.notifications (
  id            uuid primary key default gen_random_uuid(),
  location_id   uuid references atd.locations(id) on delete cascade,
  rule_id       uuid references atd.notification_rules(id) on delete set null,
  template_id   uuid references atd.notification_templates(id) on delete set null,
  channel       atd.notification_channel not null,
  to_user_id    uuid references atd.users(id) on delete set null,
  to_email      atd.email,
  to_phone      atd.phone_e164,
  subject       text,
  body          text not null,
  state         atd.notification_state not null default 'queued',
  scheduled_for timestamptz not null default now(),
  sent_at       timestamptz,
  delivered_at  timestamptz,
  failed_reason text,
  provider      text,
  provider_message_id text,
  booking_id    uuid references atd.bookings(id) on delete cascade,
  registration_id uuid references atd.registrations(id) on delete cascade,
  order_id      uuid references atd.orders(id) on delete set null,
  household_id  uuid references atd.households(id) on delete cascade,
  -- Prevents the same reminder being queued twice by a retried job.
  dedupe_key    text unique,
  attempts      int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index notifications_due on atd.notifications (scheduled_for)
  where state = 'queued';
create index on atd.notifications (household_id, created_at desc);

create table atd.communication_preferences (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references atd.users(id) on delete cascade,
  category      text not null,        -- 'transactional','reminders','marketing','waitlist'
  email_enabled boolean not null default true,
  sms_enabled   boolean not null default false,
  push_enabled  boolean not null default false,
  updated_at    timestamptz not null default now()
);
create unique index on atd.communication_preferences (user_id, category);

-- ---------------------------------------------------------------------------
-- Check-in
-- ---------------------------------------------------------------------------
create table atd.check_ins (
  id             uuid primary key default gen_random_uuid(),
  location_id    uuid not null references atd.locations(id) on delete cascade,
  booking_id     uuid references atd.bookings(id) on delete cascade,
  registration_id uuid references atd.registrations(id) on delete cascade,
  household_id   uuid references atd.households(id) on delete set null,
  participant_id uuid references atd.participants(id) on delete set null,
  method         text not null default 'staff'
                   check (method in ('staff','kiosk_phone','kiosk_qr','kiosk_code','self')),
  checked_in_at  timestamptz not null default now(),
  checked_out_at timestamptz,
  released_to    text,
  staff_user_id  uuid references atd.users(id),
  note           text,
  created_at     timestamptz not null default now()
);
create index on atd.check_ins (location_id, checked_in_at desc);

-- ---------------------------------------------------------------------------
-- Files
-- ---------------------------------------------------------------------------
create table atd.files (
  id            uuid primary key default gen_random_uuid(),
  location_id   uuid references atd.locations(id) on delete cascade,
  bucket        text not null default 'atd',
  path          text not null,
  filename      text not null,
  mime_type     text,
  size_bytes    bigint,
  kind          text not null default 'attachment',
  is_sensitive  boolean not null default false,
  household_id  uuid references atd.households(id) on delete cascade,
  participant_id uuid references atd.participants(id) on delete cascade,
  booking_id    uuid references atd.bookings(id) on delete cascade,
  uploaded_by   uuid references atd.users(id),
  created_at    timestamptz not null default now()
);
create unique index on atd.files (bucket, path);

-- ---------------------------------------------------------------------------
-- System settings (typed key/value, per-location override)
-- ---------------------------------------------------------------------------
create table atd.system_settings (
  id          uuid primary key default gen_random_uuid(),
  location_id uuid references atd.locations(id) on delete cascade,
  key         text not null,
  value       jsonb not null,
  value_type  text not null default 'json',
  category    text not null default 'general',
  label       text,
  description text,
  is_secret   boolean not null default false,
  updated_by  uuid references atd.users(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index on atd.system_settings
  (coalesce(location_id,'00000000-0000-0000-0000-000000000000'::uuid), key);

-- ---------------------------------------------------------------------------
-- Audit log — append-only. Revoking UPDATE/DELETE happens in 0012 (RLS/grants);
-- the trigger below refuses mutation even for the table owner.
-- ---------------------------------------------------------------------------
create table audit.entries (
  id              bigint generated always as identity primary key,
  occurred_at     timestamptz not null default now(),
  actor_user_id   uuid,
  actor_email     text,
  actor_role      text,
  impersonated_by uuid,
  location_id     uuid,
  action          text not null,            -- 'booking.override_conflict'
  entity_type     text not null,
  entity_id       uuid,
  summary         text,
  previous_value  jsonb,
  new_value       jsonb,
  reason          text,
  household_id    uuid,
  booking_id      uuid,
  payment_id      uuid,
  ip_address      inet,
  user_agent      text,
  request_id      text
);
create index on audit.entries (entity_type, entity_id, occurred_at desc);
create index on audit.entries (actor_user_id, occurred_at desc);
create index on audit.entries (location_id, occurred_at desc);
create index on audit.entries (action, occurred_at desc);

create or replace function audit.reject_mutation() returns trigger
language plpgsql as $$
begin
  raise exception 'audit.entries is append-only (attempted %)', tg_op
    using errcode = 'restrict_violation';
end $$;

create trigger trg_audit_immutable
  before update or delete on audit.entries
  for each row execute function audit.reject_mutation();

-- Conflict overrides get first-class storage as well as an audit row, because
-- operations needs to report on them.
create table atd.conflict_overrides (
  id              uuid primary key default gen_random_uuid(),
  location_id     uuid not null references atd.locations(id) on delete cascade,
  booking_id      uuid references atd.bookings(id) on delete cascade,
  block_id        uuid references atd.resource_blocks(id) on delete cascade,
  resource_id     uuid references atd.resources(id) on delete set null,
  conflicting_reservation_ids uuid[] not null default '{}',
  conflict_summary jsonb not null default '[]'::jsonb,
  acknowledged    boolean not null default false,
  reason          text not null,
  overridden_by   uuid not null references atd.users(id),
  created_at      timestamptz not null default now()
);

select atd.attach_touch('atd.waiver_templates');
select atd.attach_touch('atd.notification_templates');
select atd.attach_touch('atd.notification_rules');
select atd.attach_touch('atd.notifications');
select atd.attach_touch('atd.system_settings');
