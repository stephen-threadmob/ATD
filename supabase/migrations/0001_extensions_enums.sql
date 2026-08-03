-- =============================================================================
-- ATD Baseball Platform — 0001 Extensions, enums, shared helpers
-- =============================================================================
-- Design notes
--  * btree_gist is mandatory: it lets a GiST EXCLUDE constraint mix scalar
--    equality (resource_id) with range overlap (tstzrange). That single
--    constraint is what makes double-booking physically impossible rather
--    than "unlikely".
--  * All instants are timestamptz. Wall-clock intent (operating hours, coach
--    availability, recurrence anchors) is stored as local date/time + the
--    location's IANA timezone so DST transitions resolve correctly at
--    materialisation time instead of drifting.
-- =============================================================================

create extension if not exists "btree_gist";
create extension if not exists "pgcrypto";
create extension if not exists "citext";
create extension if not exists "pg_trgm";

create schema if not exists atd;
create schema if not exists audit;

set search_path = atd, public;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type atd.user_status as enum ('invited','active','suspended','deactivated');

create type atd.role_key as enum (
  'super_admin','location_admin','front_desk','coach','customer'
);

create type atd.resource_kind as enum (
  'cage','hittrax_system','party_room','lobby','field_space','machine',
  'radar','equipment','staff','event_host','facility','parking','custom'
);

create type atd.resource_status as enum ('active','maintenance','retired');

-- Reservation status drives whether a row blocks the calendar. `is_blocking`
-- is a generated column derived from this, so the exclusion constraint can
-- ignore cancelled/released rows without ever needing now().
create type atd.reservation_status as enum (
  'hold',          -- transient checkout hold, has expires_at
  'tentative',     -- unpaid / pencilled-in event hold
  'confirmed',     -- live booking
  'in_progress',
  'completed',
  'cancelled',
  'released',      -- hold that expired or was abandoned
  'no_show'
);

create type atd.booking_status as enum (
  'draft','hold','pending_payment','confirmed','checked_in','in_progress',
  'completed','cancelled','no_show'
);

create type atd.block_kind as enum (
  'maintenance','admin_hold','coach_time_off','closure','weather','private_event','buffer'
);

create type atd.assignment_mode as enum ('auto','customer_choice','admin_only','auto_with_choice');

create type atd.service_format as enum (
  'appointment',   -- private lesson, cage rental: individually scheduled
  'group_session', -- semi-private / group class occurrence
  'program',       -- multi-session camp, clinic, arm-care series
  'event',         -- PNO, tournament, special event
  'party',         -- birthday party package
  'rental'         -- team practice / facility rental
);

create type atd.pricing_model as enum (
  'fixed','per_minute','per_participant','per_resource','per_coach_rate','tiered','package_only','free'
);

create type atd.rate_scope as enum ('base','peak','off_peak','member','team','promo','custom');

create type atd.order_status as enum ('open','awaiting_payment','paid','partially_paid','refunded','partially_refunded','void');

create type atd.payment_status as enum ('requires_action','processing','succeeded','failed','canceled','refunded','partially_refunded');

create type atd.payment_method_kind as enum ('card','apple_pay','google_pay','cash','check','ach','account_credit','gift_card','comp','invoice');

create type atd.credit_txn_kind as enum ('grant','purchase','redeem','refund','expire','adjust','transfer_in','transfer_out','forfeit');

create type atd.membership_status as enum ('trialing','active','past_due','paused','canceled','expired');

create type atd.registration_status as enum ('registered','waitlisted','cancelled','attended','no_show','transferred');

create type atd.attendance_state as enum ('unknown','present','absent','late','excused');

create type atd.waitlist_status as enum ('waiting','offered','claimed','expired','declined','cancelled','converted');

create type atd.waiver_signer_relation as enum ('self','parent','guardian','other');

create type atd.notification_channel as enum ('email','sms','push','in_app');

create type atd.notification_state as enum ('queued','sending','sent','delivered','bounced','failed','suppressed','cancelled');

create type atd.recurrence_freq as enum ('daily','weekly','biweekly','monthly','custom');

create type atd.throw_bat_hand as enum ('L','R','S');

create type atd.sport as enum ('baseball','softball','both');

create type atd.policy_outcome as enum (
  'full_refund','partial_refund','account_credit','package_credit_returned',
  'credit_forfeited','reschedule_free','reschedule_fee','cancellation_fee',
  'no_refund','requires_approval'
);

create type atd.comp_basis as enum ('percent_revenue','flat_per_session','hourly','per_participant','custom');

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------
create or replace function atd.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- Attach updated_at maintenance to a table in one call.
create or replace function atd.attach_touch(p_table regclass) returns void
language plpgsql as $$
declare
  t text := p_table::text;
  n text := replace(replace(t, 'atd.', ''), '"', '');
begin
  execute format(
    'create trigger %I before update on %s for each row execute function atd.set_updated_at()',
    'trg_touch_' || n, t);
end $$;

-- Deterministic money helper: everything is stored in integer cents.
create domain atd.cents as bigint check (value >= 0);
create domain atd.signed_cents as bigint;
create domain atd.email as citext check (value ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$');
create domain atd.phone_e164 as text check (value ~ '^\+[1-9][0-9]{7,14}$');

comment on schema atd is 'ATD Baseball booking + facility management platform';
