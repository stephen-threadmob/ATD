# ATD Platform — Data Dictionary

Reference for the `atd` schema (94 base tables, 1 view) and the `audit` schema
(1 table). Derived from `supabase/migrations/0001_extensions_enums.sql` through
`supabase/migrations/0011_rbac_rls.sql` and verified against the live database.

Contents:

1. [Schema-wide conventions](#1-schema-wide-conventions)
2. [Enum types](#2-enum-types)
3. [Domains and extensions](#3-domains-and-extensions)
4. [Key mechanisms](#4-key-mechanisms)
5. [Context A — Identity, RBAC & Locations](#5-context-a--identity-rbac--locations)
6. [Context B — Resources, Coaches & Availability](#6-context-b--resources-coaches--availability)
7. [Context C — Service Catalogue, Requirements & Pricing](#7-context-c--service-catalogue-requirements--pricing)
8. [Context D — Bookings, Reservations & Blocks](#8-context-d--bookings-reservations--blocks)
9. [Context E — Programs, Registrations, Attendance & Waitlists](#9-context-e--programs-registrations-attendance--waitlists)
10. [Context F — Commerce](#10-context-f--commerce)
11. [Context G — Waivers, Notifications, Check-ins, Audit](#11-context-g--waivers-notifications-check-ins-audit)
12. [Scheduling engine functions](#12-scheduling-engine-functions)
13. [Row-level security](#13-row-level-security)

---

## 1. Schema-wide conventions

**Identifiers.** Every table uses a `uuid` primary key defaulting to
`gen_random_uuid()`, with two exceptions: `atd.stripe_events.id` is the Stripe event
id (`text`) so webhook replay is idempotent by primary key, and `audit.entries.id` is
a `bigint` identity column. Join tables use composite natural primary keys
(`role_permissions`, `coach_locations`, `coach_qualifications`, `organization_users`,
`household_tags`, `service_addon_links`, `program_staff`).

**Time.** All instants are `timestamptz`. Wall-clock intent is stored as local
`date`/`time` plus the location's IANA timezone (`locations.timezone`,
`users.timezone`, `recurring_series.timezone`), and resolved at materialisation time
with `timestamp AT TIME ZONE tz` so DST transitions come out correct rather than
drifting.

**Money.** All amounts are integer cents in `bigint` columns. Domains `atd.cents`
(non-negative) and `atd.signed_cents` are declared for this purpose. No floating point
is used anywhere for money.

**`updated_at`.** `atd.set_updated_at()` is a generic `BEFORE UPDATE` trigger
function; `atd.attach_touch(regclass)` attaches it as `trg_touch_<table>`. 51 tables
have an `updated_at` column; 48 of them carry a touch trigger. Two maintain
`updated_at` inside a more specific trigger instead — `resource_reservations`
(`trg_reservation_envelope`) and `bookings` (`trg_booking_envelope`) — and
`communication_preferences` has no trigger at all, so its `updated_at` is
application-maintained.

**Soft delete.** The convention is a nullable `deleted_at timestamptz`. It exists on
exactly ten tables — the long-lived entities that must not be hard-deleted because
history references them:

`users`, `locations`, `resources`, `coaches`, `households`, `participants`,
`customer_organizations`, `services`, `programs`, `bookings`.

Every other table uses either hard delete with `ON DELETE CASCADE`/`RESTRICT`, or a
status column (`revoked_at` on `user_roles` and `signed_waivers`, `released_at` on
`checkout_holds`, `cancelled_at` on `resource_blocks`, `retired_at` on
`waiver_versions`). Soft-deleted rows are excluded by partial indexes
(`... where deleted_at is null`) and by the engine functions
(`candidate_resources`, `plan_allocation`, `coach_is_available`, `my_coach_id`), and
by the `participants_safe` view.

**Arrays as soft references.** Several columns hold `uuid[]` without a foreign key,
deliberately, because they are filter lists rather than ownership edges:
`resources.implies_resource_ids`, `service_resource_requirements.allowed_/preferred_/
excluded_resource_ids` and `required_qualification_ids`,
`services.waiver_template_ids`, `programs.waiver_template_ids`,
`package_definitions.eligible_service_ids` / `eligible_category_ids` /
`eligible_coach_ids`, `promo_codes.applies_to_*_ids`, `notification_rules.service_ids`
/ `program_ids`, `conflict_overrides.conflicting_reservation_ids`.

**Partial unique indexes** are used pervasively to express "at most one live X",
e.g. `user_roles_unique_live`, `waiver_versions_one_current`,
`registrations_one_live_seat`, one default `saved_payment_methods` per household, one
primary `household_members` row per household.

---

## 2. Enum types

All enums live in the `atd` schema.

| Type | Values | Used by |
|---|---|---|
| `user_status` | `invited`, `active`, `suspended`, `deactivated` | `users.status` |
| `role_key` | `super_admin`, `location_admin`, `front_desk`, `coach`, `customer` | `roles.key` |
| `resource_kind` | `cage`, `hittrax_system`, `party_room`, `lobby`, `field_space`, `machine`, `radar`, `equipment`, `staff`, `event_host`, `facility`, `parking`, `custom` | `resource_types.kind` |
| `resource_status` | `active`, `maintenance`, `retired` | `resources.status` |
| `reservation_status` | `hold`, `tentative`, `confirmed`, `in_progress`, `completed`, `cancelled`, `released`, `no_show` | `resource_reservations.status`; the first four drive `is_blocking` |
| `booking_status` | `draft`, `hold`, `pending_payment`, `confirmed`, `checked_in`, `in_progress`, `completed`, `cancelled`, `no_show` | `bookings.status`, `booking_status_history.from_status`/`to_status` |
| `block_kind` | `maintenance`, `admin_hold`, `coach_time_off`, `closure`, `weather`, `private_event`, `buffer` | `resource_blocks.kind` |
| `assignment_mode` | `auto`, `customer_choice`, `admin_only`, `auto_with_choice` | `service_resource_requirements.assignment_mode` |
| `service_format` | `appointment`, `group_session`, `program`, `event`, `party`, `rental` | `services.format` |
| `pricing_model` | `fixed`, `per_minute`, `per_participant`, `per_resource`, `per_coach_rate`, `tiered`, `package_only`, `free` | `services.pricing_model` |
| `rate_scope` | `base`, `peak`, `off_peak`, `member`, `team`, `promo`, `custom` | `pricing_rules.scope` |
| `order_status` | `open`, `awaiting_payment`, `paid`, `partially_paid`, `refunded`, `partially_refunded`, `void` | `orders.status` |
| `payment_status` | `requires_action`, `processing`, `succeeded`, `failed`, `canceled`, `refunded`, `partially_refunded` | `payments.status` |
| `payment_method_kind` | `card`, `apple_pay`, `google_pay`, `cash`, `check`, `ach`, `account_credit`, `gift_card`, `comp`, `invoice` | `payments.method` |
| `credit_txn_kind` | `grant`, `purchase`, `redeem`, `refund`, `expire`, `adjust`, `transfer_in`, `transfer_out`, `forfeit` | all three ledgers |
| `membership_status` | `trialing`, `active`, `past_due`, `paused`, `canceled`, `expired` | `memberships.status` |
| `registration_status` | `registered`, `waitlisted`, `cancelled`, `attended`, `no_show`, `transferred` | `registrations.status` |
| `attendance_state` | `unknown`, `present`, `absent`, `late`, `excused` | `attendance_records.state`, `booking_participants.attendance` |
| `waitlist_status` | `waiting`, `offered`, `claimed`, `expired`, `declined`, `cancelled`, `converted` | `waitlist_entries.status` |
| `waiver_signer_relation` | `self`, `parent`, `guardian`, `other` | `signed_waivers.signer_relation` |
| `notification_channel` | `email`, `sms`, `push`, `in_app` | `notification_templates.channel`, `notification_rules.channel`, `notifications.channel` |
| `notification_state` | `queued`, `sending`, `sent`, `delivered`, `bounced`, `failed`, `suppressed`, `cancelled` | `notifications.state` |
| `recurrence_freq` | `daily`, `weekly`, `biweekly`, `monthly`, `custom` | `recurring_series.freq` |
| `throw_bat_hand` | `L`, `R`, `S` | `participants.bats`, `participants.throws` |
| `sport` | `baseball`, `softball`, `both` | `participants.sport`, `coaches.sports`, `services.allowed_sports`, `programs.sport` |
| `policy_outcome` | `full_refund`, `partial_refund`, `account_credit`, `package_credit_returned`, `credit_forfeited`, `reschedule_free`, `reschedule_fee`, `cancellation_fee`, `no_refund`, `requires_approval` | `policy_tiers.outcome` |
| `comp_basis` | `percent_revenue`, `flat_per_session`, `hourly`, `per_participant`, `custom` | `coach_compensation_rules.basis` |

---

## 3. Domains and extensions

| Object | Definition | Notes |
|---|---|---|
| `atd.cents` | `bigint CHECK (value >= 0)` | Non-negative money |
| `atd.signed_cents` | `bigint` | Money that may be negative (ledger deltas) |
| `atd.email` | `citext CHECK (value ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')` | Case-insensitive, format-validated |
| `atd.phone_e164` | `text CHECK (value ~ '^\+[1-9][0-9]{7,14}$')` | Strict E.164 |
| `btree_gist` | extension | **Mandatory.** Lets one GiST EXCLUDE constraint mix scalar equality (`resource_id`, `slot_index`) with range overlap (`blocking_span`) |
| `pgcrypto` | extension | `gen_random_uuid()`, `gen_random_bytes()` for confirmation codes and claim tokens |
| `citext` | extension | Backs `atd.email` and `promo_codes.code` |
| `pg_trgm` | extension | GIN trigram indexes for name search on `users`, `households`, `participants` |

Helper functions defined in `0001`/`0004`:

| Function | Purpose |
|---|---|
| `atd.set_updated_at()` | Generic `BEFORE UPDATE` trigger setting `updated_at := now()` |
| `atd.attach_touch(regclass)` | Attaches the above as `trg_touch_<table>` in one call |
| `atd.age_on(dob date, on date) -> int` | Immutable age calculation; used by age restrictions, `programs.age_as_of_date`, and `participants_safe.age` |

---

## 4. Key mechanisms

### 4.1 The occupancy table and the double-booking guarantee

`atd.resource_reservations` is the only table that represents occupancy. Bookings,
program sessions, parties, rentals, admin blocks, maintenance, coach time off,
whole-facility closures and transient checkout holds all materialise into it. Exactly
one owner is enforced:

```sql
check (num_nonnulls(booking_id, block_id, hold_id) = 1)
```

The guarantee itself is a single constraint:

```sql
constraint resource_reservations_no_overlap
  exclude using gist (
    resource_id   with =,
    slot_index    with =,
    blocking_span with &&
  ) where (is_blocking)
```

Two stored generated columns make it work:

| Column | Definition | Why |
|---|---|---|
| `is_blocking` | `boolean generated always as (status in ('hold','tentative','confirmed','in_progress')) stored` | The constraint's `WHERE` predicate must be immutable. Deriving "does this row occupy the facility?" from `status` means cancelled, released, completed and no-show rows drop out of the index automatically, with no reference to `now()` and no cleanup job. |
| `blocking_span` | `tstzrange generated always as (tstzrange(blocked_from, blocked_to, '[)')) stored` | The buffered envelope, half-open so back-to-back sessions that touch at the boundary do not conflict. Because buffers are folded into the span, a required transition gap is enforced by the same constraint that prevents overlap. |

`blocked_from` / `blocked_to` are not generated columns because `timestamptz +
interval` is `STABLE`, not `IMMUTABLE`. They are maintained by
`trg_reservation_envelope` (`BEFORE INSERT OR UPDATE OF starts_at, ends_at,
buffer_before_minutes, buffer_after_minutes`) calling
`atd.sync_reservation_envelope()`, which computes
`starts_at - buffer_before_minutes` and `ends_at + buffer_after_minutes`. A check
constraint (`blocked_from <= starts_at and blocked_to >= ends_at`) makes a bad
hand-written value impossible.

Because the guarantee lives in storage rather than in application code, two concurrent
checkouts racing for the same cage cannot both succeed. The loser gets SQLSTATE
`23P01` (`exclusion_violation`); `atd.create_hold` re-raises it with the hint
"Another customer may have just taken this slot."

Supporting index: `reservations_live_span`, a partial GiST index on
`(resource_id, blocking_span) where is_blocking`, which serves the availability probe
`atd.free_slot_index`.

### 4.2 `slot_index` — shared-capacity resources

`resource_types.allocation` is either `exclusive` or `shared`, and
`resources.capacity` (default 1, `CHECK capacity >= 1`) is the number of concurrent
occupants a resource supports — one for a cage, more for a lobby that can host
several simultaneous activities or a bucket of shared equipment.

`resource_reservations.slot_index` (`int not null default 0`, `CHECK >= 0`) is part of
the exclusion constraint's equality set. Two overlapping reservations on the same
resource conflict only if they also share a `slot_index`. Therefore a resource with
`capacity = N` can carry exactly N overlapping blocking reservations, using indices
`0 .. N-1`, and the N+1st insert has nowhere to go.

Allocation is done by `atd.free_slot_index(p_resource, p_from, p_to,
p_ignore_reservation)`, which reads `resources.capacity` and returns the lowest index
`i` in `0 .. capacity-1` with no blocking reservation whose `blocking_span` overlaps
the requested window, or `NULL` when the resource is full. `create_hold` calls it per
resource and aborts the entire hold if any resource returns `NULL` — there is no such
thing as a partial hold.

### 4.3 The three ledgers and their mirror balances

No mutable balance is authoritative. Every balance is the sum of an append-only
ledger; the denormalised columns exist only as fast-read mirrors and can be rebuilt
from the ledger at any time.

| Ledger table | Mirror column | Trigger | Trigger function |
|---|---|---|---|
| `package_credit_transactions` (`delta numeric(10,3)`, signed) | `package_purchases.credits_remaining` and `package_purchases.status` | `trg_package_balance` — `AFTER INSERT OR UPDATE OR DELETE FOR EACH ROW` | `atd.sync_package_balance()` recomputes `credits_remaining = greatest(0, sum(delta)::int)` and sets `status` to `exhausted` when the sum is `<= 0`, `active` otherwise — but never overrides a `refunded` or `frozen` status. |
| `account_credit_transactions` (`amount_cents bigint`, signed) | `households.account_credit_cents` | `trg_account_credit` — `AFTER INSERT OR UPDATE OR DELETE FOR EACH ROW` | `atd.sync_account_credit()` recomputes `sum(amount_cents)` for the household. |
| `gift_card_transactions` (`amount_cents bigint`, signed) | `gift_cards.balance_cents` and `gift_cards.status` | `trg_gift_card_balance` — `AFTER INSERT OR UPDATE OR DELETE FOR EACH ROW` | `atd.sync_gift_card_balance()` recomputes the balance and sets `status` to `depleted` at `<= 0`, `active` otherwise — but never overrides `void` or `expired`. |

All three triggers recompute from a full `SUM` over the ledger rather than applying a
delta, so a mirror can never drift; re-running any trigger converges. Each ledger row
carries `kind atd.credit_txn_kind` to explain the movement.

Guard index: `package_credit_one_redeem_per_booking`, a partial unique index on
`(package_purchase_id, booking_id) where kind = 'redeem' and booking_id is not null`,
so a double-clicked redeem cannot burn two credits.

Related non-ledger mirrors, also trigger-maintained:

- `programs.enrolled_count`, `programs.waitlist_count`, `program_sessions.enrolled_count`
  via `trg_registration_counts` on `registrations`
  (`AFTER INSERT OR UPDATE OF status OR DELETE`) calling
  `atd.sync_enrollment_counts()`. Note that the trigger is defined only on
  `registrations`, so `waitlist_count` refreshes when a registration changes, not when
  a `waitlist_entries` row changes on its own.
- `bookings.balance_due_cents` — a stored generated column,
  `total_cents - paid_cents`.
- `orders.balance_due_cents` — a stored generated column,
  `total_cents - paid_cents + refunded_cents`.
- `users.display_name` — a stored generated column, `first_name || ' ' || last_name`.

---

## 5. Context A — Identity, RBAC & Locations

| Table | Purpose | Key columns | Constraints, indexes, triggers |
|---|---|---|---|
| `organizations` | Top-level tenant that owns locations. | `name`, `legal_name`, `default_timezone`, `branding jsonb`, `support_email`, `support_phone` | `trg_touch_organizations` |
| `locations` | A physical facility; the scoping unit for nearly everything else. | `organization_id`; `slug` unique; `timezone` (IANA, drives all wall-clock resolution); `settings jsonb` holding `checkout_hold_minutes`, `min_booking_lead_minutes`, `max_booking_horizon_days`, `default_slot_granularity_minutes`, `allow_guest_checkout`, `require_waiver_before_participation`; `deleted_at` | FK to `organizations` `ON DELETE RESTRICT`; partial index on `organization_id where deleted_at is null`; `trg_touch_locations` |
| `operating_hour_sets` | Named weekly opening template, optionally seasonal. | `location_id`, `effective_from`/`effective_to`, `priority` (higher wins on overlap), `is_default` | `CHECK (effective_to >= effective_from)`; index `(location_id, priority desc)`; `trg_touch_operating_hour_sets` |
| `operating_hours` | One weekday row inside a set. | `hour_set_id`, `day_of_week` (0 = Sunday), `opens_at`, `closes_at`, `is_closed` | `CHECK (day_of_week between 0 and 6)`; `CHECK (is_closed or closes_at > opens_at)`; unique `(hour_set_id, day_of_week, opens_at)` |
| `date_overrides` | Single-date exception: holiday, early close, emergency closure. | `location_id`, `on_date`, `is_closed`, `opens_at`, `closes_at`, `label`, `created_by` | `CHECK (is_closed or (opens_at and closes_at present and closes_at > opens_at))`; unique `(location_id, on_date)`; read first by `atd.open_span()` so an override always beats the weekly template |
| `users` | Every human: customers, staff, coaches. Mirrors Supabase `auth.users` 1:1. | `auth_user_id` unique; `email` unique (`atd.email`); `phone` (`atd.phone_e164`); `display_name` generated; `status`; `timezone`; `sms_consent_at`/`sms_consent_source`/`sms_consent_ip` for TCPA provenance; `deleted_at` | Index on `lower(email::text)`; partial index on `phone where phone is not null`; GIN trigram index `users_name_trgm`; `trg_touch_users` |
| `permissions` | Catalogue of capability keys. | `key` PK, `category`, `description` | 41 rows seeded in `0011` across categories `booking`, `customer`, `money`, `ops`, `config`, `admin` |
| `roles` | Named bundles of permissions. | `key atd.role_key` unique, `name`, `is_system` | Five system roles seeded in `0011`; `trg_touch_roles` |
| `role_permissions` | Role-to-permission bundle. | `(role_id, permission_key)` PK | Both FKs `ON DELETE CASCADE` |
| `user_roles` | Grant of a role to a user, scoped to a location. | `user_id`, `role_id`, `location_id` (**null = all locations**, how `super_admin` is expressed), `granted_by`, `granted_at`, `revoked_at` | `user_roles_unique_live`: unique on `(user_id, role_id, coalesce(location_id, '000…0'))` `where revoked_at is null`; partial index on `user_id where revoked_at is null` |
| `user_permission_overrides` | Per-user grant or revoke of a single capability. | `user_id`, `location_id`, `permission_key`, `effect` (`allow`/`deny`), `reason` | `CHECK (effect in ('allow','deny'))`; unique `(user_id, permission_key, coalesce(location_id, '000…0'))`. **Deny wins**: `atd.has_permission()` evaluates the deny clause first |
| `households` | Billing and booking unit; the RLS ownership root for customers. | `primary_user_id`, `location_id`, `stripe_customer_id` unique, `account_credit_cents` (mirror of `account_credit_transactions`), `balance_due_cents`, `is_tax_exempt`, `source`/`referral_source`, `deleted_at` | Index on `primary_user_id`; GIN trigram `households_name_trgm`; `trg_touch_households`; RLS enabled |
| `household_members` | Adult users attached to a household with booking/paying rights. | `household_id`, `user_id`, `relationship`, `can_book`, `can_pay`, `is_primary` | Unique `(household_id, user_id)`; unique `(household_id) where is_primary` — at most one primary; drives `atd.my_household_ids()`; RLS enabled |
| `participants` | The athlete. Children, or adults booking for themselves. | `household_id`, `user_id` (set when the participant is also a user), `date_of_birth`, `sport`, `positions text[]`, `bats`/`throws`, `allergies`, `medical_notes`, `photo_consent`, `deleted_at` | Partial index on `household_id where deleted_at is null`; GIN trigram `participants_name_trgm`; `trg_touch_participants`; RLS enabled. `allergies`/`medical_notes` are sensitive and gated by `participant.read_medical` |
| `participants_safe` | View (`security_invoker = true`) over `participants` that redacts medical data unless the caller holds `participant.read_medical` or owns the household. Adds `age` via `atd.age_on`. Filters `deleted_at is null`. | — | Staff-facing lists read this, never the table |
| `emergency_contacts` | Emergency contacts for a household or a specific participant. | `household_id`, `participant_id`, `name`, `phone`, `alt_phone`, `priority` | Index on `household_id`; RLS enabled |
| `authorized_pickups` | People permitted to collect a child. | `household_id`, `participant_id`, `name`, `relationship`, `phone`, `photo_url` | Referenced by name in `booking_participants.checked_out_to` / `check_ins.released_to` |
| `customer_organizations` | Travel teams, schools, corporate accounts. | `name`, `kind`, `primary_contact_user_id`, `billing_email`, `billing_terms_days`, `is_tax_exempt`, `custom_rate_card_id`, `stripe_customer_id` unique, `deleted_at` | `customer_organizations_rate_card_fk` added in `0005` → `rate_cards`; `trg_touch_customer_organizations` |
| `organization_users` | Users who may act for an organisation. | `(organization_id, user_id)` PK, `role`, `can_book`, `can_invoice` | — |
| `teams` | A team within a customer organisation. | `organization_id`, `name`, `age_group`, `season`, `head_coach_name` | `trg_touch_teams` |
| `team_roster_entries` | Roster line; optionally linked to a real participant. | `team_id`, `participant_id` (nullable), `full_name`, `jersey_number`, `positions text[]` | Index on `team_id` |
| `tags` | CRM tag catalogue. | `key` unique, `label`, `color`, `category` | — |
| `household_tags` | Applied tags. | `(household_id, tag_id)` PK, `applied_by`, `applied_at` | — |
| `staff_notes` | Internal notes about a household, participant or booking. | `location_id`, `household_id`, `participant_id`, `booking_id` (FK added in `0006`), `body`, `visibility` (`staff`/`coach`/`admin_only`), `is_pinned`, `author_user_id` | Indexes on `household_id` and `participant_id`; `trg_touch_staff_notes`; RLS enabled — never customer-visible, `admin_only` requires `staff.manage` |

---

## 6. Context B — Resources, Coaches & Availability

| Table | Purpose | Key columns | Constraints, indexes, triggers |
|---|---|---|---|
| `resource_types` | Classification of bookable things, and their capacity semantics. | `location_id` (null = org-wide), `key`, `kind atd.resource_kind`, `allocation` (`exclusive` \| `shared`), `icon`, `color`, `sort_order` | `CHECK (allocation in ('exclusive','shared'))`; unique `(coalesce(location_id,'000…0'), key)`; `trg_touch_resource_types` |
| `resources` | Anything the facility can commit: cages, HitTrax units, rooms, machines, and coaches. | `location_id`, `resource_type_id`, `code` (e.g. `CAGE-1`), `status atd.resource_status`, `capacity` (concurrency; drives `slot_index`), `attributes jsonb` (matched by requirements with `@>`), `parent_resource_id` (physical containment), `implies_resource_ids uuid[]` (composite kit), `is_bookable_directly`, `online_bookable`, `deleted_at` | `CHECK (capacity >= 1)`; unique `(location_id, code) where deleted_at is null`; index `(location_id, resource_type_id) where deleted_at is null`; GIN `resources_attributes_gin` on `attributes jsonb_path_ops`; FK to `resource_types` `ON DELETE RESTRICT`; `trg_touch_resources` |
| `resource_availability_rules` | Weekly windows in which a resource may be used. Absence of rows means "available whenever the facility is open". | `resource_id`, `day_of_week`, `starts_at`, `ends_at`, `effective_from`/`effective_to`, `is_available` | `CHECK (ends_at > starts_at)`; `CHECK (day_of_week between 0 and 6)`; index `(resource_id, day_of_week)`. Read by `atd.candidate_resources` |
| `coaches` | Staff profile. A coach is a `users` row **plus** a dedicated `resources` row, which is what lets one exclusion constraint prevent both cage and coach double-booking. | `user_id` unique, `resource_id` unique, `display_name`, `employment_type`, `sports`, `is_active`, `accepts_online_booking`, `customer_selectable`, `auto_assignable`, `min_lead_time_minutes`, `max_sessions_per_day`, `max_consecutive_minutes`, `required_break_minutes`, `assignment_priority` (lower = preferred), `deleted_at` | `CHECK (employment_type in ('employee','contractor','volunteer'))`; FK to `resources` `ON DELETE RESTRICT`; `trg_touch_coaches` |
| `coach_locations` | Which locations a coach works at. | `(coach_id, location_id)` PK | — |
| `qualifications` | Admin-editable certification/skill catalogue. | `key` unique, `name`, `category` | Referenced by id from `service_resource_requirements.required_qualification_ids` |
| `coach_qualifications` | Certifications held. | `(coach_id, qualification_id)` PK, `level`, `certified_on`, `expires_on` | `candidate_resources` counts only rows where `expires_on is null or expires_on >= current_date` |
| `coach_age_ranges` | Age band a coach will take. | `coach_id`, `min_age`, `max_age` | `CHECK (max_age >= min_age)` |
| `coach_availability_rules` | Recurring weekly availability in location-local wall clock. | `coach_id`, `location_id`, `day_of_week`, `starts_at`, `ends_at`, `effective_from`/`effective_to`, `is_available` | `CHECK (ends_at > starts_at)`; index `(coach_id, day_of_week)`; `trg_touch_coach_availability_rules` |
| `coach_date_availability` | Single-date availability that supersedes the weekly rule outright. | `coach_id`, `on_date`, `starts_at`, `ends_at`, `is_available`, `note` | `CHECK (not is_available or (starts_at and ends_at present and ends_at > starts_at))`; unique `(coach_id, on_date, coalesce(starts_at,'00:00'))`; checked first by `atd.coach_is_available` |
| `time_off_requests` | Coach time-off workflow. | `coach_id`, `starts_at`, `ends_at`, `reason`, `status` (`pending`/`approved`/`denied`/`cancelled`), `decided_by`, `decided_at`, `reservation_id` — set once approved and materialised into a blocking reservation | `CHECK (ends_at > starts_at)`; index `(coach_id, status)`; `time_off_reservation_fk` added in `0006` → `resource_reservations` `ON DELETE SET NULL`; `trg_touch_time_off_requests` |

---

## 7. Context C — Service Catalogue, Requirements & Pricing

| Table | Purpose | Key columns | Constraints, indexes, triggers |
|---|---|---|---|
| `service_categories` | Grouping and public presentation of services. | `location_id` (null = org-wide), `key`, `name`, `color`, `icon`, `is_public`, `sort_order` | Unique `(coalesce(location_id,'000…0'), key)`; `trg_touch_service_categories` |
| `services` | The bookable product template: shape, eligibility, booking rules, deposit and base pricing. | `location_id`, `category_id`, `slug`, `format atd.service_format`; scheduling: `default_duration_minutes`, `min_/max_duration_minutes`, `duration_increment_minutes`, `setup_minutes`, `cleanup_minutes`, `buffer_before_minutes`, `buffer_after_minutes`, `slot_granularity_minutes`; capacity: `min_participants`, `max_participants`, `min_age`, `max_age`, `allowed_sports`, `skill_levels text[]`; rules: `is_online_bookable`, `is_public`, `requires_approval`, `allow_guest_checkout`, `min_lead_minutes`, `max_horizon_days`, `max_active_bookings_per_household`, `cancellation_policy_id`, `waiver_template_ids uuid[]`, `requires_deposit`, `deposit_cents`, `deposit_percent`, `balance_due_days_before`; pricing: `pricing_model`, `base_price_cents`, `tax_rate_id`, `is_taxable`; `deleted_at` | `CHECK`s: `default_duration_minutes > 0`, non-negative setup/cleanup/buffers, `max_participants >= min_participants`, `max_age >= min_age`, `min_duration <= default_duration`, `max_duration >= default_duration`. Unique `(location_id, slug) where deleted_at is null`; index `(location_id, category_id) where deleted_at is null and is_active`. FKs `services_policy_fk` → `policies` and `services_tax_rate_fk` → `tax_rates` added later in `0005`. `trg_touch_services`. `setup_minutes`/`cleanup_minutes` and the buffers are read by `atd.sync_booking_envelope()` to compute `bookings.blocked_from`/`blocked_to` |
| `service_resource_requirements` | One row per resource slot the service consumes. This is what the scheduling engine actually reads. | `service_id`, `label`, `resource_type_id`, `quantity`, `is_optional`, `required_attributes jsonb` (matched against `resources.attributes` with `@>`), `allowed_/preferred_/excluded_resource_ids uuid[]`, `required_qualification_ids uuid[]` (coach slots), `assignment_mode`, per-requirement `setup_minutes`/`cleanup_minutes`/`buffer_before_minutes`/`buffer_after_minutes` overrides, `offset_start_minutes`/`offset_end_minutes` (occupy only part of the window), `sort_order` | `CHECK (quantity >= 1)`; index `(service_id, sort_order)`; FK to `resource_types` `ON DELETE RESTRICT`; `trg_touch_service_resource_requirements`. Referenced by `resource_reservations.requirement_id` so each reservation records which slot it fills |
| `service_addons` | Purchasable extras, which may themselves pull resources or extend the window. | `location_id`, `key`, `price_cents`, `price_per` (`booking`/`participant`/`hour`), `max_quantity`, `is_taxable`, `adds_resource_type_id`, `adds_resource_quantity`, `adds_required_attributes jsonb`, `adds_minutes` | `CHECK (price_per in ('booking','participant','hour'))`; unique `(location_id, key)`; `trg_touch_service_addons` |
| `service_addon_links` | Which add-ons a service offers. | `(service_id, addon_id)` PK, `is_default`, `is_required`, `sort_order` | — |
| `service_questions` | Intake questions rendered at checkout. | `service_id`, `key`, `label`, `input_type`, `options jsonb`, `is_required`, `applies_to` (`booking`/`participant`), `is_sensitive` | `CHECK` on `input_type` (`text`, `textarea`, `number`, `select`, `multiselect`, `boolean`, `date`, `phone`, `email`); `CHECK (applies_to in ('booking','participant'))`; unique `(service_id, key)`. Answers land in `bookings.answers` / `booking_participants.answers` / `registrations.answers` |
| `rate_cards` | Named group of pricing rules, e.g. a negotiated team rate. | `location_id`, `name`, `is_default` | `trg_touch_rate_cards`; referenced by `customer_organizations.custom_rate_card_id` |
| `pricing_rules` | The pricing pipeline. All matching rules are collected and applied in ascending `priority`, so peak + member + promo compose predictably. | Targets: `rate_card_id`, `service_id`, `category_id`. Conditions (all nullable, null = "don't care"): `coach_id`, `resource_id`, `membership_plan_id`, `days_of_week int[]`, `starts_at_time`/`ends_at_time`, `effective_from`/`effective_to`, `min_/max_duration_minutes`, `min_/max_participants`, `min_days_before` (early bird), `max_days_before` (late registration). Effect: `effect`, `amount_cents`, `percent`. Also `scope atd.rate_scope`, `priority`, `is_active` | `CHECK` on `effect` (`set`, `add`, `multiply`, `percent_off`, `amount_off`, `set_per_minute`, `set_per_participant`); index `(location_id, service_id, priority) where is_active`; `pricing_rules_membership_fk` → `membership_plans` added in `0008`; `trg_touch_pricing_rules` |
| `tax_rates` | Tax percentages, optionally mirrored to Stripe. | `location_id`, `name`, `percent numeric(6,3)`, `stripe_tax_rate_id`, `is_active` | Referenced by `services.tax_rate_id` |
| `policies` | Cancellation / reschedule / no-show policy header. | `location_id`, `name`, `applies_to` (`booking`/`registration`/`membership`/`party`/`rental`), `is_default` | `trg_touch_policies` |
| `policy_tiers` | Ordered tiers within a policy; the first matching tier by hours-before descending wins. | `policy_id`, `min_hours_before numeric(8,2)`, `action` (`cancel`/`reschedule`/`no_show`), `outcome atd.policy_outcome`, `refund_percent`, `fee_cents`, `returns_package_credit`, `requires_approval` | `CHECK (action in ('cancel','reschedule','no_show'))`; index `(policy_id, action, min_hours_before desc)`. Referenced by `bookings.policy_tier_applied_id` and `refunds.policy_tier_id` for auditability |

---

## 8. Context D — Bookings, Reservations & Blocks

| Table | Purpose | Key columns | Constraints, indexes, triggers |
|---|---|---|---|
| `resource_reservations` | **The single occupancy table.** Nothing occupies the facility except a row here. | `location_id`, `resource_id`; exactly one of `booking_id` / `block_id` / `hold_id`; `requirement_id` + `requirement_label`; `status atd.reservation_status`; `starts_at`/`ends_at`; `buffer_before_minutes`/`buffer_after_minutes`; `blocked_from`/`blocked_to` (buffered envelope); `slot_index`; `expires_at` (holds only); `released_at`; `is_blocking` and `blocking_span` (generated) | **`resource_reservations_no_overlap`** — `EXCLUDE USING gist (resource_id WITH =, slot_index WITH =, blocking_span WITH &&) WHERE (is_blocking)`. Checks: `ends_at > starts_at`; `blocked_from <= starts_at and blocked_to >= ends_at`; `num_nonnulls(booking_id, block_id, hold_id) = 1`; `status <> 'hold' or expires_at is not null`; non-negative buffers; `slot_index >= 0`. Indexes: `(booking_id)`, `(block_id)`, `(hold_id)`, `(location_id, blocked_from)`, `reservations_expiry` on `expires_at where status='hold'`, `reservations_live_span` GiST `(resource_id, blocking_span) where is_blocking`. Trigger `trg_reservation_envelope` maintains the envelope and `updated_at`. FK to `resources` is `ON DELETE RESTRICT`; the three owner FKs are `ON DELETE CASCADE`. RLS enabled |
| `bookings` | A scheduled instance of a service for a household or organisation. Owns its reservations. | `location_id`, `service_id`, `household_id`, `organization_id`, `program_id`, `program_session_id`, `series_id`, `parent_booking_id`, `order_id`, `policy_tier_applied_id`; `confirmation_code` unique (random hex); `status atd.booking_status`; `starts_at`/`ends_at`/`timezone`; `blocked_from`/`blocked_to` (denormalised buffered envelope for calendar queries); `participant_count`; `answers jsonb`; `source`; money snapshot `subtotal_/discount_/addon_/tax_/total_/paid_cents` and generated `balance_due_cents`; lifecycle timestamps `checked_in_at`, `started_at`, `completed_at`, `cancelled_at`; `deleted_at` | Checks: `ends_at > starts_at`; `blocked_to >= ends_at and blocked_from <= starts_at`; `source in ('online','front_desk','admin','walk_in','import','api','kiosk')`. Indexes: `(location_id, starts_at)`, `(household_id, starts_at desc)`, `(status, starts_at)` — all `where deleted_at is null`; `(series_id) where series_id is not null`; `bookings_span_gist` GiST on `tstzrange(blocked_from, blocked_to, '[)')`. Triggers: `trg_booking_envelope` (recomputes the envelope from the service's setup/cleanup/buffer minutes), `trg_booking_status_history`. FKs to `locations`/`services` are `ON DELETE RESTRICT`. RLS enabled. The authoritative money ledger is in `orders`/`payments`; these columns are a snapshot |
| `checkout_holds` | Parent of transient hold reservations during checkout. | `location_id`, `household_id` (null for guest), `session_token`, `service_id`, `starts_at`/`ends_at`, `expires_at`, `released_at`, `converted_booking_id` (**no FK**, set by `confirm_hold`), `payload jsonb` | Index on `expires_at where released_at is null`; index on `session_token`. TTL comes from `locations.settings->>'checkout_hold_minutes'` (default 10). Swept by `atd.expire_stale_holds()` |
| `booking_participants` | Which participants are on a booking, and their attendance. | `booking_id`, `participant_id`, `registration_id`, `attendance atd.attendance_state`, `checked_in_at`, `checked_out_at`, `checked_out_to`, `answers jsonb`, `price_cents` | Unique `(booking_id, participant_id)` — used by `confirm_hold`'s `ON CONFLICT DO NOTHING`; FK to `participants` `ON DELETE RESTRICT`; `booking_participants_registration_fk` added in `0007`; `trg_touch_booking_participants`; RLS enabled |
| `booking_addons` | Add-ons purchased on a booking. | `booking_id`, `addon_id`, `quantity`, `unit_price_cents`, `total_cents` | `CHECK (quantity >= 1)`; FK to `service_addons` `ON DELETE RESTRICT` |
| `booking_status_history` | Append-only record of every booking status transition. | `booking_id`, `from_status`, `to_status`, `reason`, `actor_user_id` | Index `(booking_id, created_at)`. Written automatically by `trg_booking_status_history` → `atd.log_booking_status()` on insert and on any status change |
| `resource_blocks` | Non-booking occupancy: maintenance, closures, weather, private events, admin holds, coach time off. | `location_id`, `kind atd.block_kind`, `title`, `starts_at`/`ends_at`, `applies_to_whole_location`, `coach_id`, `time_off_request_id`, `series_id`, `cancelled_at` | `CHECK (ends_at > starts_at)`; index `(location_id, starts_at)`; `trg_touch_resource_blocks`. When `applies_to_whole_location` is true, `atd.location_is_blocked()` short-circuits availability without needing a reservation row per resource |
| `recurring_series` | Header for a repeating booking or block. | `location_id`, `service_id`, `freq atd.recurrence_freq`, `interval_count`, `by_weekday int[]`, `start_date`/`end_date`, `occurrence_count`, `start_time_local`, `duration_minutes`, `timezone`, `skip_dates date[]` | `CHECK (interval_count >= 1)`; `CHECK (end_date is not null or occurrence_count is not null)` — a series must terminate; `trg_touch_recurring_series`. Validated per-occurrence by `atd.validate_recurrence()` |

---

## 9. Context E — Programs, Registrations, Attendance & Waitlists

| Table | Purpose | Key columns | Constraints, indexes, triggers |
|---|---|---|---|
| `programs` | One customer-facing multi-session product: camp, clinic, arm-care series. | `location_id`, `service_id`, `slug`, `starts_on`/`ends_on`, `registration_opens_at`/`registration_closes_at`, `capacity`, `min_enrollment`, `enrolled_count`, `waitlist_count`, `min_age`/`max_age`/`age_as_of_date`, `sport`, `allow_drop_in`, `allow_partial_registration`, `prorate_late_enrollment`, `allow_waitlist`, `price_cents`, `drop_in_price_cents`, `deposit_cents`, `sibling_discount_percent`, logistics (`collects_shirt_size`, `collects_lunch_choice`, `check_in_window_minutes`, `pickup_window_minutes`, `late_pickup_fee_cents`), `status`, `cancellation_policy_id`, `waiver_template_ids uuid[]`, `deleted_at` | `CHECK (capacity >= 1)`; `CHECK (ends_on >= starts_on)`; `CHECK (max_age >= min_age)`; **`programs_capacity_not_exceeded CHECK (enrolled_count <= capacity)`** — the hard gate on the "two people buy the final spot" race; `CHECK` on `status` (`draft`, `published`, `full`, `closed`, `cancelled`, `completed`). Unique `(location_id, slug) where deleted_at is null`; index `(location_id, starts_on) where deleted_at is null`; `trg_touch_programs`. `age_as_of_date` exists so a participant who ages out between registration and the program date is evaluated on the right date |
| `program_sessions` | One occurrence of a program. Materialises **exactly one** booking, which owns the reservations — so a 40-child camp blocks its cages once per day, not forty times. | `program_id`, `booking_id`, `session_number`, `session_date`, `starts_at`/`ends_at`, `capacity` (null = inherit program), `enrolled_count`, `is_cancelled`, `cancellation_reason` | `CHECK (ends_at > starts_at)`; **`program_sessions_capacity_not_exceeded CHECK (capacity is null or enrolled_count <= capacity)`**; unique `(program_id, session_number)`; index `(program_id, session_date)`; `trg_touch_program_sessions` |
| `program_staff` | Coaches assigned to a program beyond the per-session reservation. | `(program_id, coach_id)` PK, `role` | — |
| `registrations` | A participant's seat in a program, or in a single session. | `program_id`, `program_session_id`, `household_id`, `participant_id`, `order_id`, `status atd.registration_status`, `registration_kind` (`full_series`/`single_session`/`drop_in`), `confirmation_code` unique, `price_cents`/`discount_cents`/`paid_cents`, `age_at_registration`, `shirt_size`, `lunch_choice`, `answers jsonb`, `cancelled_at` | **`registrations_one_live_seat`**: unique on `(program_id, participant_id, coalesce(program_session_id,'000…0'))` `where status in ('registered','attended')` — the second layer of the final-spot defence. Indexes `(household_id, registered_at desc)` and `(program_id, status)`. FKs to `households`/`participants` are `ON DELETE RESTRICT`. `registrations_order_fk` added in `0008`. Triggers: `trg_registration_counts` (recomputes enrolment mirrors), `trg_touch_registrations`. RLS enabled |
| `attendance_records` | Per-session roll call for a registration. | `program_session_id`, `registration_id`, `participant_id`, `state atd.attendance_state`, `checked_in_at`, `checked_out_at`, `released_to`, `marked_by`, `note` | Unique `(program_session_id, registration_id)`; `trg_touch_attendance_records` |
| `makeup_credits` | Credit issued when a participant misses a session, redeemable against a future booking. | `registration_id`, `participant_id`, `reason`, `issued_by`, `expires_on`, `redeemed_booking_id`, `redeemed_at` | — |
| `lesson_notes` | Coach-written progress notes, optionally shared with the family. | `booking_id`, `program_session_id`, `participant_id`, `coach_id`, `body`, `focus_areas text[]`, `metrics jsonb` (exit velo, spin, etc.), `shared_with_customer` | Index `(participant_id, created_at desc)`; `trg_touch_lesson_notes`; RLS enabled — coaches see their own, parents see only rows with `shared_with_customer` |
| `waitlist_entries` | A wait position against a program, session, service, coach, or arbitrary time window. | `location_id`, `program_id`, `program_session_id`, `service_id`, `coach_id`, `household_id`, `participant_id`, `desired_from`/`desired_to`, `desired_weekdays int[]`, `status atd.waitlist_status`, `priority`, `position`, `joined_at` | Indexes `(program_id, status, priority, joined_at)` and `(service_id, status, priority, joined_at)`; `trg_touch_waitlist_entries`; RLS enabled |
| `waitlist_offers` | A recorded offer of an opening, with a bounded claim window. | `waitlist_entry_id`, `hold_id` (the reservation-backed hold that prevents two people claiming the same opening), `offered_at`, `expires_at`, `responded_at`, `outcome`, `claim_token` unique, `offered_starts_at`/`offered_ends_at`, `resulting_booking_id`, `resulting_registration_id` | `CHECK (outcome in ('claimed','declined','expired','superseded'))`; index on `expires_at where outcome is null`; `claim_token` defaults to 18 random bytes hex |

---

## 10. Context F — Commerce

| Table | Purpose | Key columns | Constraints, indexes, triggers |
|---|---|---|---|
| `orders` | Commercial header for everything sold. | `location_id`, `household_id`, `organization_id`, `number` (bigint identity), `status atd.order_status`, `currency`, `subtotal_/discount_/tax_/total_/paid_/refunded_cents`, generated `balance_due_cents = total - paid + refunded`, `deposit_required_cents`, `balance_due_at`, `stripe_payment_intent_id`, `stripe_checkout_session_id`, `idempotency_key` unique, `placed_by_user_id`, `source` | `idempotency_key` unique makes a double-clicked Pay button reuse the same order and intent. Indexes `(household_id, created_at desc)` and `(location_id, status)`; FK to `locations` `ON DELETE RESTRICT`; `trg_touch_orders`; RLS enabled |
| `order_items` | Polymorphic line items. | `order_id`, `kind` (`booking`, `registration`, `package`, `membership`, `addon`, `gift_card`, `fee`, `deposit`, `custom`), plus the matching nullable FK (`booking_id`, `registration_id`, `package_purchase_id`, `membership_id`, `addon_id`), `description`, `quantity`, `unit_price_cents`, `subtotal_/discount_/tax_/total_cents`, `price_breakdown jsonb` | `CHECK` on `kind`; index `(order_id)`; `order_items_package_fk` and `order_items_membership_fk` added later in `0008`. `price_breakdown` stores the ordered list of pricing rules that produced `total_cents`, which is what makes a price explainable after the fact |
| `payments` | A settlement attempt or receipt. | `order_id`, `location_id`, `household_id`, `method atd.payment_method_kind`, `status atd.payment_status`, `amount_cents`, `fee_cents`, `stripe_payment_intent_id`, `stripe_charge_id`, `stripe_payment_method_id`, `last4`, `brand`, `received_at`, `failure_code`/`failure_message`, `taken_by_user_id` | `payments_intent_unique`: unique on `stripe_payment_intent_id where not null`; index `(order_id)`; FK to `locations` `ON DELETE RESTRICT`; `trg_touch_payments`; RLS enabled |
| `refunds` | A refund against a payment. | `payment_id`, `order_id`, `amount_cents`, `reason`, `policy_tier_id` (which policy tier authorised it), `stripe_refund_id` unique, `status`, `issued_by_user_id` | `CHECK (amount_cents > 0)`; `CHECK (status in ('pending','succeeded','failed','canceled'))`; FK to `payments` `ON DELETE RESTRICT`; `trg_touch_refunds` |
| `stripe_events` | Raw Stripe webhook events. | `id` PK = the Stripe `evt_…` id, `type`, `api_version`, `payload jsonb`, `received_at`, `processed_at`, `processing_error`, `attempts` | The primary key on the event id makes webhook replay a no-op; index on `processed_at where processed_at is null` for the worker queue |
| `invoices` | Term-billed invoices for organisations or households. | `order_id`, `organization_id`, `household_id`, `number` unique, `status`, `issued_on`, `due_on`, `total_cents`, `paid_cents`, `purchase_order_ref`, `terms`, `pdf_url` | `CHECK` on `status` (`draft`, `sent`, `partially_paid`, `paid`, `void`, `past_due`); `trg_touch_invoices` |
| `package_definitions` | The sellable package template. | `location_id`, `key`, `credit_count`, `credit_unit` (`session`/`hour`/`minute`/`day`), `price_cents`, `eligible_service_ids`/`eligible_category_ids`/`eligible_coach_ids uuid[]`, `restricted_to_off_peak`, `peak_window jsonb`, `valid_days`, `expires_on`, `is_transferable`, `household_shared`, `allow_partial_credit`, `min_lead_minutes` | `CHECK (credit_count > 0)`; `CHECK` on `credit_unit`; unique `(location_id, key)`; `trg_touch_package_definitions` |
| `package_purchases` | A household's purchased package. | `package_definition_id`, `household_id`, `participant_id` (null = household-wide), `order_id`, `purchased_at`, `expires_on`, `credits_granted`, **`credits_remaining` (mirror of the ledger)**, `status` | `CHECK` on `status` (`active`, `exhausted`, `expired`, `refunded`, `frozen`); index `(household_id, status)`; FK to `package_definitions` `ON DELETE RESTRICT`; `trg_touch_package_purchases`; RLS enabled |
| `package_credit_transactions` | **Append-only credit ledger.** | `package_purchase_id`, `kind atd.credit_txn_kind`, `delta numeric(10,3)` (+grant, −redeem, +refund), `booking_id`, `registration_id`, `participant_id`, `note`, `actor_user_id` | Index `(package_purchase_id, created_at)`; **`package_credit_one_redeem_per_booking`** unique on `(package_purchase_id, booking_id) where kind='redeem' and booking_id is not null`. Trigger `trg_package_balance` → `atd.sync_package_balance()` rebuilds `package_purchases.credits_remaining` and `status` from the full sum |
| `membership_plans` | Subscription product definition. | `location_id`, `key`, `billing_interval` (`month`/`year`), `price_cents`, `setup_fee_cents`, `trial_days`, `stripe_price_id`, `included_credits`, `included_credit_package_id`, `credits_roll_over`, `max_rollover_credits`, `member_discount_percent`, `priority_booking_hours`, `guest_passes_per_period`, `max_bookings_per_period`, `allows_freeze`, `max_freeze_days`, `min_commitment_months`, `cancellation_notice_days` | `CHECK (billing_interval in ('month','year'))`; unique `(location_id, key)`; `trg_touch_membership_plans`. Referenced by `pricing_rules.membership_plan_id` so member pricing is expressed as an ordinary rule |
| `memberships` | An active subscription held by a household. | `plan_id`, `household_id`, `participant_id`, `status atd.membership_status`, `stripe_subscription_id` unique, `current_period_start`/`current_period_end`, `started_on`, `cancel_at`/`canceled_at`/`cancel_reason`, `paused_from`/`paused_until`, `failed_payment_count`, `bookings_this_period` | Index `(household_id, status)`; FK to `membership_plans` `ON DELETE RESTRICT`; `trg_touch_memberships`; RLS enabled |
| `account_credit_transactions` | **Append-only store-credit ledger** (cancellation credit, goodwill, forfeits). | `household_id`, `kind atd.credit_txn_kind`, `amount_cents` (signed), `booking_id`, `order_id`, `reason`, `expires_on`, `actor_user_id` | Index `(household_id, created_at desc)`. Trigger `trg_account_credit` → `atd.sync_account_credit()` rebuilds `households.account_credit_cents` from the full sum |
| `gift_cards` | A gift card and its mirrored balance. | `location_id`, `code` unique, `initial_cents`, **`balance_cents` (mirror of the ledger)**, `purchaser_household_id`, `recipient_email`/`recipient_name`/`gift_message`, `deliver_at`/`delivered_at`, `expires_on`, `status`, `order_id` | `CHECK (initial_cents > 0)`; `CHECK` on `status` (`pending`, `active`, `depleted`, `expired`, `void`); `trg_touch_gift_cards` |
| `gift_card_transactions` | **Append-only gift-card ledger.** | `gift_card_id`, `kind atd.credit_txn_kind`, `amount_cents` (signed), `order_id`, `note` | Trigger `trg_gift_card_balance` → `atd.sync_gift_card_balance()` rebuilds `gift_cards.balance_cents` and `status` from the full sum |
| `promo_codes` | Discount codes, including referral codes. | `location_id`, `code citext`, `discount_kind` (`percent`/`amount`), `percent`, `amount_cents`, `applies_to_service_ids`/`applies_to_category_ids`/`applies_to_program_ids uuid[]`, `first_time_customers_only`, `min_order_cents`, `max_redemptions`, `max_per_household`, `redemption_count`, `starts_at`/`ends_at`, `restricted_to_household_id`, `is_referral`, `referring_household_id` | `CHECK (discount_kind in ('percent','amount'))`; unique `(location_id, code)` — `citext` makes it case-insensitive; `trg_touch_promo_codes` |
| `promo_redemptions` | Which order used which code. | `promo_code_id`, `order_id`, `household_id`, `amount_cents` | Unique `(promo_code_id, order_id)` — a code cannot be applied twice to one order |
| `saved_payment_methods` | Stored Stripe payment methods per household. | `household_id`, `stripe_payment_method_id` unique, `brand`, `last4`, `exp_month`, `exp_year`, `is_default` | Unique `(household_id) where is_default` — at most one default per household |
| `coach_compensation_rules` | How a coach is paid, by service or category. | `location_id`, `coach_id`, `service_id`, `category_id`, `basis atd.comp_basis`, `percent`, `amount_cents`, `hourly_cents`, `applies_to_group`, `applies_to_private`, `counts_no_show`, `net_of_discounts`, `priority`, `effective_from`/`effective_to`, `is_active` | `trg_touch_coach_compensation_rules` |
| `coach_earnings` | Accrued earnings, one row per coach per booking. | `coach_id`, `booking_id`, `program_session_id`, `rule_id`, `pay_period_id`, `occurred_on`, `gross_revenue_cents`, `eligible_revenue_cents`, `earning_cents`, `adjustment_cents`/`adjustment_reason`, `status` | `CHECK (status in ('accrued','approved','paid','void'))`; index `(coach_id, occurred_on)`; **`coach_earnings_one_per_booking`** unique on `(coach_id, booking_id) where booking_id is not null`; `coach_earnings_pay_period_fk` added at the end of `0008`; `trg_touch_coach_earnings` |
| `pay_periods` | Payroll batch window. | `location_id`, `starts_on`, `ends_on`, `status` (`open`/`locked`/`paid`), `paid_at` | `CHECK` on `status` |

---

## 11. Context G — Waivers, Notifications, Check-ins, Audit

| Table | Purpose | Key columns | Constraints, indexes, triggers |
|---|---|---|---|
| `waiver_templates` | Waiver identity and renewal policy. Holds no legal text. | `location_id`, `key`, `name`, `audience` (`participant`/`adult`/`guardian`/`spectator`/`staff`), `requires_guardian_if_under` (default 18), `renewal_months` (null = never expires), `is_required`, `is_active` | `CHECK` on `audience`; unique `(location_id, key)`; `trg_touch_waiver_templates`. Referenced by id from `services.waiver_template_ids` and `programs.waiver_template_ids` |
| `waiver_versions` | The legally binding body, versioned. | `template_id`, `version`, `body_markdown`, `summary_of_changes`, `requires_resignature` (material change vs typo fix), `effective_from`, `retired_at`, `published_by` | Unique `(template_id, version)`; **`waiver_versions_one_current`** unique on `(template_id) where retired_at is null` — exactly one live version per template |
| `signed_waivers` | A signature, always pointing at a **version** so "did they sign the current one?" is a join. | `waiver_version_id`, `household_id`, `participant_id`, `signer_user_id`, `signer_name`, `signer_email`, `signer_relation atd.waiver_signer_relation`, `signature_data`, `signature_kind` (`typed`/`drawn`/`click`), `photo_consent`, `medical_ack`, `signed_at`, `expires_on`, `ip_address`, `user_agent`, `document_url`, `revoked_at` | `CHECK` on `signature_kind`; partial indexes on `participant_id` and `household_id`, both `where revoked_at is null`; FK to `waiver_versions` `ON DELETE RESTRICT` so a signed version can never be deleted out from under the signature; RLS enabled |
| `waiver_overrides` | Audited exception letting a participant take part unsigned. | `participant_id`, `waiver_template_id`, `booking_id`, `reason` (NOT NULL), `approved_by` (NOT NULL), `expires_at` | Requires permission `waiver.override` at the application layer |
| `notification_templates` | Channel-specific message body with variable placeholders. | `location_id` (null = org-wide), `key`, `channel atd.notification_channel`, `subject`, `body`, `from_name`, `reply_to`, `is_transactional`, `available_variables text[]` | Unique `(coalesce(location_id,'000…0'), key, channel)`; `trg_touch_notification_templates` |
| `notification_rules` | Which template fires on which event, at what offset from what anchor. | `location_id`, `event_key` (e.g. `booking.confirmed`, `booking.reminder`), `template_id`, `channel`, `offset_minutes` (negative = before the anchor), `anchor` (`immediate`, `booking_start`, `booking_end`, `program_start`, `balance_due`, `period_end`), `service_ids`/`program_ids uuid[]`, `is_active` | `CHECK` on `anchor`; index `(location_id, event_key) where is_active`; `trg_touch_notification_rules` |
| `notifications` | A queued or delivered message instance. | `location_id`, `rule_id`, `template_id`, `channel`, `to_user_id`/`to_email`/`to_phone`, `subject`, `body`, `state atd.notification_state`, `scheduled_for`, `sent_at`, `delivered_at`, `failed_reason`, `provider`/`provider_message_id`, context FKs `booking_id`/`registration_id`/`order_id`/`household_id`, `dedupe_key`, `attempts` | **`dedupe_key` is UNIQUE** — a retried job cannot queue the same reminder twice. Index `notifications_due` on `scheduled_for where state='queued'`; index `(household_id, created_at desc)`; `trg_touch_notifications`; RLS enabled |
| `communication_preferences` | Per-user, per-category channel opt-ins. | `user_id`, `category` (`transactional`, `reminders`, `marketing`, `waitlist`), `email_enabled`, `sms_enabled`, `push_enabled` | Unique `(user_id, category)`. Complements `users.marketing_email_opt_in` and the TCPA SMS consent columns on `users` |
| `check_ins` | Front-desk and kiosk check-in/out for bookings and registrations. | `location_id`, `booking_id`, `registration_id`, `household_id`, `participant_id`, `method` (`staff`, `kiosk_phone`, `kiosk_qr`, `kiosk_code`, `self`), `checked_in_at`, `checked_out_at`, `released_to`, `staff_user_id` | `CHECK` on `method`; index `(location_id, checked_in_at desc)` |
| `files` | Storage object metadata. | `location_id`, `bucket`, `path`, `filename`, `mime_type`, `size_bytes`, `kind`, `is_sensitive`, `household_id`, `participant_id`, `booking_id`, `uploaded_by` | Unique `(bucket, path)` |
| `system_settings` | Typed key/value configuration with per-location override. | `location_id` (null = global), `key`, `value jsonb`, `value_type`, `category`, `label`, `description`, `is_secret`, `updated_by` | Unique `(coalesce(location_id,'000…0'), key)`; `trg_touch_system_settings` |
| `conflict_overrides` | First-class record of a deliberately overridden scheduling conflict, so operations can report on them. | `location_id`, `booking_id`, `block_id`, `resource_id`, `conflicting_reservation_ids uuid[]`, `conflict_summary jsonb`, `acknowledged`, `reason` (NOT NULL), `overridden_by` (NOT NULL) | Paired with an `audit.entries` row (`action = 'booking.override_conflict'`); requires permission `booking.override_conflict` |
| `audit.entries` | Append-only audit log across the whole platform. | `id bigint` identity, `occurred_at`, `actor_user_id`, `actor_email`, `actor_role`, `impersonated_by`, `location_id`, `action`, `entity_type`, `entity_id`, `summary`, `previous_value jsonb`, `new_value jsonb`, `reason`, `household_id`, `booking_id`, `payment_id`, `ip_address`, `user_agent`, `request_id` | **Immutable**: `trg_audit_immutable` (`BEFORE UPDATE OR DELETE FOR EACH ROW`) calls `audit.reject_mutation()`, which raises with errcode `restrict_violation` even for the table owner; `UPDATE`/`DELETE` are also revoked from `public`. **No foreign keys by design**, so audit history survives deletion of the entities it describes. Indexes: `(entity_type, entity_id, occurred_at desc)`, `(actor_user_id, occurred_at desc)`, `(location_id, occurred_at desc)`, `(action, occurred_at desc)` |

---

## 12. Scheduling engine functions

Migration `0010` puts availability calculation and reservation acquisition in the
database, so both observe the same snapshot and the same locks. Checking availability
on one connection and writing on another leaves a race window; this design does not.

| Function | Returns | Purpose |
|---|---|---|
| `atd.expire_stale_holds(p_location)` | `int` | Sweeps `resource_reservations` rows with `status='hold'` and `expires_at < now()` to `released`, and releases the matching `checkout_holds`. Called at the head of every allocation path, so an abandoned checkout never blocks a real customer beyond its TTL even if the background job is down |
| `atd.open_span(p_location, p_date)` | `tstzrange` | Resolves opening hours for one local date. `date_overrides` wins outright; otherwise the highest-priority effective `operating_hour_sets` row. Returns `NULL` when closed. Builds instants with `AT TIME ZONE` so DST resolves correctly |
| `atd.coach_is_available(p_coach, p_starts, p_ends, p_location)` | `boolean` | Composes `coach_date_availability` (supersedes), `coach_availability_rules`, `coaches.min_lead_time_minutes`, and daily workload caps |
| `atd.candidate_resources(p_requirement, p_starts, p_ends)` | `table(resource_id, is_preferred, priority)` | Resource matching for one requirement: type match, `excluded_`/`allowed_resource_ids`, `attributes @> required_attributes`, unexpired qualifications for coach slots, coach availability, and `resource_availability_rules`. Ordered preferred-first, then `assignment_priority`, then `sort_order`, then `code` |
| `atd.free_slot_index(p_resource, p_from, p_to, p_ignore_reservation)` | `int` | Lowest free `slot_index` in `0..capacity-1`, or `NULL` when full |
| `atd.location_is_blocked(p_location, p_from, p_to)` | `boolean` | True if a `resource_blocks` row with `applies_to_whole_location` and no `cancelled_at` overlaps the window |
| `atd.plan_allocation(p_service, p_starts, p_ends, p_pinned, p_ignore_booking)` | `jsonb` | Full allocation plan for a service at an instant, or `NULL` if unsatisfiable |
| `atd.find_slots(...)` | table | Availability search returning candidate windows with their assignments |
| `atd.create_hold(...)` | `table(hold_id, expires_at, plan)` | Atomically holds every required resource. Any exclusion violation aborts the whole hold — there is no partial hold. TTL from `locations.settings->>'checkout_hold_minutes'` |
| `atd.release_hold(p_hold)` | `void` | Explicit abandon |
| `atd.confirm_hold(...)` | `uuid` | Promotes a hold to a booking in one transaction by re-parenting the held reservation rows (`hold_id := null, booking_id := <new>, status := 'confirmed'`), so the rows never stop blocking during conversion. Idempotency is checked **first**: a hold with `converted_booking_id` set returns that booking instead of raising |
| `atd.create_booking(...)` | `uuid` | Front-desk / walk-in path: `create_hold` followed immediately by `confirm_hold` |
| `atd.reschedule_booking(...)` | — | Move or resize with full revalidation |
| `atd.cancel_booking(...)` | — | Cancel, releasing the occupancy by moving reservations out of the blocking statuses |
| `atd.validate_recurrence(...)` | table | Per-occurrence conflict report for a `recurring_series` |
| `atd.materialize_program_sessions(...)` | — | Creates `program_sessions` and their single owning bookings |
| `atd.register_participant(...)` | — | Creates a registration within the capacity constraints |

Auth helpers (migration `0011`): `atd.app_user_id()` resolves the Supabase JWT subject
(falling back to `app.user_id`) to an `atd.users.id`; `atd.has_permission(key,
location)` evaluates role bundles and overrides with **deny winning**;
`atd.is_staff(location)`; `atd.my_household_ids()`; `atd.my_coach_id()`.

---

## 13. Row-level security

RLS is the last line of defence, not the only one — the application also authorises
server-side. It exists because Supabase exposes PostgREST directly, so a leaked anon
key must not be able to enumerate other families' children.

RLS is enabled on 17 tables: `households`, `household_members`, `participants`,
`bookings`, `booking_participants`, `registrations`, `orders`, `payments`,
`package_purchases`, `memberships`, `signed_waivers`, `waitlist_entries`,
`lesson_notes`, `staff_notes`, `emergency_contacts`, `notifications`,
`resource_reservations`.

Notable policies:

- `bookings_self` — a household sees its own bookings, staff see their location's,
  and a coach sees any booking they are reserved on (joined through
  `resource_reservations` → `coaches.resource_id`).
- `lesson_notes_read` — coaches see their own notes; parents see only rows with
  `shared_with_customer = true` for participants in their household.
- `staff_notes_staff_only` — `admin_only` requires `staff.manage`, `coach` requires
  staff status, otherwise `customer.read`. Never customer-visible.
- `reservations_read` — staff see their location's reservations; customers see only
  those attached to their own bookings.
- `participants_safe` is a `security_invoker` view that additionally redacts
  `allergies` and `medical_notes` unless the caller holds `participant.read_medical`
  or owns the household.
