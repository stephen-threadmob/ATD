# ATD Baseball Company — Booking, Scheduling and Facility Management Platform
## Product Requirements Document (v1)

**Organisation:** ATD Baseball Company LLC
**Location (v1):** ATD Baseball — Training Center, 1200 Diamond Way, Wallingford, CT 06492
**Timezone:** `America/New_York`
**Operating hours:** 09:30–20:30, seven days a week (stored as an editable weekly template, not a constant)

Every rule stated in this document is implemented in `supabase/migrations/` and configured in
`supabase/seed/`. Where a statement describes data rather than code, it says so.

---

## 1. Problem statement

ATD runs a single indoor building whose revenue depends on how densely and how correctly its
physical inventory is scheduled. That inventory is not "a calendar". It is:

| Resource | Code | Notes |
| --- | --- | --- |
| 50 ft cage with mound | `CAGE-1` | `length_ft: 50`, `has_mound: true`, `supports_pitching: true`, pro turf |
| 35 ft cage | `CAGE-2` | `length_ft: 35`, no mound |
| 35 ft cage | `CAGE-3` | `length_ft: 35`, no mound |
| 35 ft cage | `CAGE-4` | `length_ft: 35`, no mound |
| 70 ft cage with HitTrax | `CAGE-5` | `length_ft: 70`, `has_hittrax: true`, `has_mound: true` |
| HitTrax unit | `HITTRAX-1` | child resource of `CAGE-5` |
| Party room | `PARTY-1` | 24 seats |
| Lobby / waiting area | `LOBBY` | shared allocation, **capacity 3** |
| Pitching machines | `MACHINE-1` (arm), `MACHINE-2` (wheel) | |
| Event hosts | `HOST-1`, `HOST-2` | |
| Coaches | `COACH-MR/TC/DN/JB/SV` | Marcus Reyes, Tyler Callahan, Dana Nakamura, Joe Brennan, Sofia Vargas |

A single sale consumes several of these at once, and which ones it consumes depends on the
*attributes* of the resource rather than its name. A pitching lesson needs a cage with a mound.
A HitTrax lesson needs a HitTrax-certified coach, a cage whose `has_hittrax` attribute is true,
and the HitTrax unit itself — three resources, one price, one confirmation email, and all three
must be committed or none of them.

### 1.1 Why a generic appointment calendar fails here

| Requirement | Generic appointment tool | This platform |
| --- | --- | --- |
| One booking consumes N heterogeneous resources atomically | Models one "staff member" per appointment; a party needing room + 2 cages + host is entered as three separate events that can drift apart | `atd.service_resource_requirements` declares N requirement rows; `atd.plan_allocation` satisfies all of them or returns `NULL`, and `atd.create_hold` writes every reservation in one transaction |
| Resource selection by physical attribute | Requires a hand-maintained list ("pitching lessons → Cage 1, Cage 5") that goes stale the day a cage is re-turfed | `required_attributes` is a JSONB predicate matched with `@>` against `resources.attributes`. No code and no list knows which cages have mounds |
| Staff selection by qualification | Any staff member can be assigned to any service | `required_qualification_ids` filters candidates against `coach_qualifications`, including expiry dates |
| A group class must block the cage **once**, not once per child | Blocks per attendee, or does not block at all | A program session materialises exactly one booking (`atd.materialize_program_sessions`); N registrations attach to that one booking. Verified: 6 registrations, still 4 reservations |
| A shared space used by several activities at once | Binary busy/free | `resources.capacity` plus `slot_index`; the lobby's capacity of 3 is enforced by the same exclusion constraint |
| Transition buffers that differ per resource within one service | Single global padding | Per-requirement `buffer_before_minutes` / `buffer_after_minutes`, folded into the blocked envelope so the constraint itself enforces them |
| Two customers checking out the same slot | Last write wins, or an optimistic check with a race window | Checkout holds are real blocking reservations. The loser receives SQLSTATE `23P01` and is told the slot was taken |
| DST | Stores an instant, so a 4:00 PM weekly series drifts to 3:00 PM in November | Recurrence stores local wall clock plus IANA zone and resolves at materialisation. Test 13 asserts the local time stays 16:00 while the UTC instant shifts |
| Emergency closure | Cancel each booking by hand | One `resource_blocks` row with `applies_to_whole_location = true`; `atd.location_is_blocked` makes every service unbookable for that window |
| Age gates that depend on the event date | Checks age today | `atd.register_participant` evaluates age on `programs.age_as_of_date` (falling back to `starts_on`), so a child with a birthday between registration and camp is judged correctly |

The unifying design decision: **nothing occupies the facility except a row in
`atd.resource_reservations`.** Bookings, camps, parties, admin blocks, coach time off,
maintenance and half-finished checkouts all materialise into that one table, which carries a
single GiST exclusion constraint:

```
exclude using gist (resource_id with =, slot_index with =, blocking_span with &&)
  where (is_blocking)
```

Double-booking is therefore impossible at the storage layer, not merely unlikely at the
application layer. Test 3 proves it: a raw `INSERT` that bypasses every function is still
rejected with `23P01`.

---

## 2. Goals

1. **Correctness of occupancy.** No resource is ever committed to two things at once, including
   against a competitor's in-flight checkout, under real concurrent load.
2. **Configuration over code.** A new service type, a new resource, a new price rule, a new
   intake question or a new add-on is a data change performed by an administrator. The
   scheduling engine has no knowledge of the concepts "birthday party" or "HitTrax lesson".
3. **Online self-service for parents.** Browse, choose a coach or accept first-available, book,
   sign a waiver and pay from a phone, without calling the desk.
4. **A front desk that can do anything the website can, faster.** Walk-ins, payment on the
   counter, household check-in, same-day changes, with policy outcomes computed rather than
   negotiated.
5. **Explainable money.** Every balance is the sum of an append-only ledger
   (`package_credit_transactions`, `account_credit_transactions`, `gift_card_transactions`,
   `payments`/`refunds`). Denormalised balances are trigger-maintained mirrors that can be
   rebuilt.
6. **Explainable pricing.** Each order line stores `price_breakdown` — the ordered list of
   pricing rules that produced its total.
7. **Least privilege by default.** Five roles, 41 permission keys, per-location grants,
   per-user overrides where deny wins, and RLS policies as the last line of defence.
8. **Auditability.** `audit.entries` is append-only and enforced by trigger; conflict overrides
   get first-class storage in `atd.conflict_overrides` as well as an audit row.

---

## 3. Non-goals (v1)

1. Replacing HitTrax's own software. The platform sells, schedules, reserves and bills HitTrax
   time and reserves the unit; it does not ingest ball-flight data, generate HitTrax reports, or
   run HitTrax sessions. `lesson_notes.metrics` is a free-form JSONB field a coach may type
   numbers into by hand.
2. Video capture, hosting or swing analysis. `atd.files` stores generic attachments only.
3. Payroll disbursement or tax filing. `coach_earnings` and `pay_periods` accrue, approve and
   mark paid; the actual payment runs elsewhere.
4. Accounting-system integration (general ledger export, invoice sync).
5. League, tournament, bracket or scorekeeping management.
6. Retail / pro-shop inventory and point-of-sale for merchandise. Gift cards are supported;
   bat sales are not.
7. Native iOS/Android applications. The customer surface is responsive web; kiosk mode is a web
   surface (`check_ins.method` includes `kiosk_phone`, `kiosk_qr`, `kiosk_code`).
8. Marketing automation, campaign management or drip sequences. Notifications are
   event-triggered and mostly transactional (`notification_rules.event_key` + `anchor`).
9. Demand-based or surge pricing. Pricing rules are declarative and deterministic: day-of-week,
   time-of-day, duration, participant count, lead time, coach, resource, membership plan.
10. Multi-location rollout. The schema is multi-location throughout (`location_id` on every
    operational table, `user_roles.location_id`, `resource_types.location_id` nullable for
    org-wide), but v1 ships one location.
11. Two-way calendar sync with Google/Apple/Outlook.
12. In-app messaging or chat between parents and coaches.
13. HR records, background checks or certification document storage beyond the
    `qualifications` / `coach_qualifications` key-and-expiry model.

---

## 4. Service catalogue (as seeded)

Sixteen services across eight categories. All values below are the seeded rows in
`supabase/seed/02_services.sql`; all are editable by an administrator holding `service.manage`.

### 4.1 Commercial terms

| # | Slug | Name | Category | Format | Duration (default / min / max, increment) | Participants | Ages | Pricing | Price | Deposit | Lead time | Horizon | Policy |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `private-hitting` | Private Hitting Lesson | Private Lessons | appointment | 60 / 30 / 90, 30 | 1 | 6–18 | fixed | $90.00 | — | 120 min | 120 d | Standard Lesson |
| 2 | `private-pitching` | Private Pitching Lesson | Private Lessons | appointment | 60 / 30 / 90, 30 | 1 | 8–18 | fixed | $95.00 | — | 120 min | 120 d | Standard Lesson |
| 3 | `private-catching` | Private Catching Lesson | Private Lessons | appointment | 60 / 30 / 60, 30 | 1 | 8–18 | fixed | $95.00 | — | 120 min | 120 d | Standard Lesson |
| 4 | `private-fielding` | Private Fielding Lesson | Private Lessons | appointment | 60 / 30 / 60, 30 | 1 | 7–18 | fixed | $90.00 | — | 120 min | 120 d | Standard Lesson |
| 5 | `hittrax-lesson` | HitTrax Hitting Lesson | HitTrax | appointment | 60 / 60 / 90, 30 | 1 | 8–18 | fixed | $120.00 | — | 180 min | 120 d | Standard Lesson |
| 6 | `semi-private` | Semi-Private Lesson (2–3) | Private Lessons | appointment | 60 / 60 / 90, 30 | 2–3 | 7–18 | per_participant | $60.00 each | — | 120 min | 120 d | Standard Lesson |
| 7 | `cage-rental-35` | Cage Rental — 35 ft | Cage Rentals | rental | 60 / 30 / 180, 30 | 1–6 | 0–99 | per_minute | $0.75/min ($45.00/hr) | — | 30 min | 120 d | Standard Lesson |
| 8 | `cage-rental-50` | Cage Rental — 50 ft w/ Mound | Cage Rentals | rental | 60 / 30 / 180, 30 | 1–8 | 0–99 | per_minute | $0.95/min ($57.00/hr) | — | 30 min | 120 d | Standard Lesson |
| 9 | `hittrax-rental` | HitTrax Rental | HitTrax | rental | 60 / 30 / 120, 30 | 1–8 | 0–99 | per_minute | $1.50/min ($90.00/hr) | — | 60 min | 120 d | Standard Lesson |
| 10 | `group-hitting-clinic` | Group Hitting Clinic | Group Training | group_session | 75 / 75 / 75, 15 | 4–12 | 9–14 | fixed | $45.00 | — | 120 min | 120 d | Program & Camp |
| 11 | `arm-care-program` | Arm Care Program | Programs | program | 60 / 60 / 60, 15 | 4–10 | 11–18 | fixed | $399.00 | — | 1440 min (24 h) | 120 d | Program & Camp |
| 12 | `summer-camp` | Summer Skills Camp | Camps & Clinics | program | 240 / 240 / 240, 30 | 8–40 | 7–13 | fixed | $299.00 | — | 1440 min (24 h) | 120 d | Program & Camp |
| 13 | `parents-night-out` | Parents' Night Out | Parties & Events | event | 180 / 180 / 180, 30 | 6–30 | 5–12 | fixed | $55.00 | — | 720 min (12 h) | 120 d | Program & Camp |
| 14 | `birthday-party` | Birthday Party — Grand Slam Package | Parties & Events | party | 135 / 135 / 180, 30 | 8–20 | 4–16 | fixed | $450.00 | **$150.00 flat** | 2880 min (48 h) | 120 d | Party |
| 15 | `team-practice` | Team Practice Rental | Team & Facility Rentals | rental | 120 / 60 / 240, 30 | 8–25 | 0–99 | per_minute | $3.00/min ($180.00/hr) | — | 720 min (12 h) | 120 d | Standard Lesson |
| 16 | `facility-buyout` | Full Facility Buyout | Team & Facility Rentals | rental | 180 / 120 / 360, 60 | 10–60 | 0–99 | per_minute | $6.00/min ($360.00/hr) | **25%** | 10080 min (7 d) | 120 d | Party |

Notes on the table:

- `facility-buyout` has `is_online_bookable = false`; it is quoted and booked by staff only.
- All other services default to `is_online_bookable = true`, `is_public = true`,
  `requires_approval = false`, `allow_guest_checkout = true`.
- `is_taxable` is `false` on every seeded service and `tax_rate_id` is unset, so no seeded
  service charges tax. The CT Sales Tax rate (6.350%) exists in `tax_rates` and can be attached
  to a service at any time.
- All 16 services carry the General Liability waiver. `summer-camp` and `parents-night-out`
  additionally require the Camp Medical Authorization & Pickup waiver.

### 4.2 Resource requirements

Each row below is a `service_resource_requirements` row. `assignment_mode` controls who picks:
`auto` (engine picks), `auto_with_choice` (customer may pin, otherwise engine picks),
`customer_choice` (customer picks), `admin_only` (staff picks).

| Service | Requirement | Type | Qty | Attribute predicate | Qualification filter | Assignment |
| --- | --- | --- | --- | --- | --- | --- |
| `private-hitting` | Coach | coach | 1 | — | `hitting` | auto_with_choice |
| | Cage | cage | 1 | — | — | auto |
| `private-pitching` | Coach | coach | 1 | — | `pitching` | auto_with_choice |
| | Mound Cage | cage | 1 | `{"has_mound": true}` | — | auto |
| `private-catching` | Coach | coach | 1 | — | `catching` | auto_with_choice |
| | Cage | cage | 1 | — | — | auto |
| `private-fielding` | Coach | coach | 1 | — | `fielding` | auto_with_choice |
| | Cage | cage | 1 | — | — | auto |
| `hittrax-lesson` | HitTrax Coach | coach | 1 | — | `hittrax` | auto_with_choice |
| | HitTrax Cage | cage | 1 | `{"has_hittrax": true}` | — | auto |
| | HitTrax Unit | hittrax | 1 | — | — | auto |
| `semi-private` | Coach | coach | 1 | — | — | auto_with_choice |
| | Cage | cage | 1 | — | — | auto |
| `cage-rental-35` | Cage | cage | 1 | `{"length_ft": 35}` | — | customer_choice |
| `cage-rental-50` | Cage | cage | 1 | `{"length_ft": 50}` | — | customer_choice |
| `hittrax-rental` | HitTrax Cage | cage | 1 | `{"has_hittrax": true}` | — | auto |
| | HitTrax Unit | hittrax | 1 | — | — | auto |
| `group-hitting-clinic` | Coaches | coach | 2 | — | — | admin_only |
| | Cages | cage | 2 | — | — | auto |
| `arm-care-program` | Coach | coach | 1 | — | — | admin_only |
| | Cage | cage | 1 | — | — | auto |
| `summer-camp` | Camp Coaches | coach | 3 | — | — | admin_only |
| | Camp Cages | cage | 4 | — | — | auto |
| | Check-in Space | lobby | 1 | — | — | auto |
| `parents-night-out` | Staff | event_host | 2 | — | — | admin_only |
| | Cages | cage | 2 | — | — | auto |
| | Party Room | party_room | 1 | — | — | auto |
| `birthday-party` | Party Room | party_room | 1 | — | — | auto |
| | Cages | cage | 2 | — | — | auto |
| | Party Host | event_host | 1 | — | — | admin_only |
| `team-practice` | Cages | cage | 3 | — | — | auto |
| | Lobby | lobby | 1 | — | — | auto |
| `facility-buyout` | All Cages | cage | 5 | — | — | auto |
| | Party Room | party_room | 1 | — | — | auto |

Consequences that fall out of the data with no code:

- `private-pitching` can only ever land on `CAGE-1` or `CAGE-5`, because those are the only
  resources whose `attributes` contain `has_mound: true`. Test 15 asserts this.
- `hittrax-lesson` can only be taught by Marcus Reyes or Dana Nakamura, the only coaches holding
  the `hittrax` qualification. Test 16 asserts this.
- `facility-buyout` requires all five cages, so it is unbookable if any single lesson exists in
  the window — the buyout does not silently displace anything.
- `parents-night-out` needs both event hosts, so it cannot run concurrently with a birthday
  party, which needs one.

### 4.3 Effective buffers

`atd.plan_allocation` computes each requirement's envelope as
`buffer_before = coalesce(req.buffer_before, service.buffer_before) + coalesce(req.setup, service.setup)` and
`buffer_after = coalesce(req.buffer_after, service.buffer_after) + coalesce(req.cleanup, service.cleanup)`.
With the seeded data that yields:

| Service | Effective lead-in | Effective trail-out |
| --- | --- | --- |
| `private-hitting`, `private-pitching`, `private-catching`, `private-fielding`, `semi-private` | 0 min | 5 min |
| `cage-rental-35`, `cage-rental-50` | 0 min | 5 min |
| `hittrax-lesson` | 10 min | 15 min |
| `hittrax-rental` | 10 min | 15 min |
| `group-hitting-clinic` | 5 min | 15 min |
| `arm-care-program` | 5 min | 5 min |
| `summer-camp` | 30 min | 45 min |
| `parents-night-out` | 30 min | 45 min |
| `birthday-party` | 30 min | 60 min |
| `team-practice` | 10 min | 25 min |
| `facility-buyout` | 45 min | 60 min |

Test 4 asserts the private-lesson case: a cage busy 18:00–19:00 rejects a 19:00 start and
accepts a 19:05 start.

### 4.4 Add-ons

| Key | Name | Price | Charged per | Max qty | Pulls extra resource | Attached to |
| --- | --- | --- | --- | --- | --- | --- |
| `hittrax_addon` | Add HitTrax | $30.00 | booking | 1 | HitTrax system ×1 | `private-hitting`, `birthday-party` |
| `pitching_machine` | Pitching Machine | $15.00 | booking | 1 | Pitching machine ×1 | `private-hitting`, `cage-rental-35`, `cage-rental-50` |
| `extra_guest` | Additional Party Guest | $20.00 | participant | 12 | — | `birthday-party` |
| `pizza_package` | Pizza & Drinks Package | $90.00 | booking | 3 | — | `birthday-party` (default-selected) |
| `decorations` | Decorations & Party Favors | $65.00 | booking | 1 | — | `birthday-party` |
| `extra_cage_time` | Extra 30 Minutes | $35.00 | booking | 4 | — | (available, not yet linked) |

An add-on that names `adds_resource_type_id` carries a requirement template
(`adds_resource_quantity`, `adds_required_attributes`, `adds_minutes`) that is applied when the
add-on is selected: choosing "Pitching Machine" on a cage rental makes the booking reserve a
machine as well, and the booking fails to hold if both machines are already out.
`atd.plan_allocation` itself reads only `service_resource_requirements`; expanding the
requirement set for selected add-ons is done by the server layer before it calls
`create_hold`, which is why add-on selection must precede the final hold.

### 4.5 Intake questions

| Service | Key | Label | Type | Required | Applies to |
| --- | --- | --- | --- | --- | --- |
| `private-hitting` | `focus` | What would you like to work on? | textarea | no | booking |
| `private-pitching` | `arm_status` | Any current arm soreness or injury? | textarea | no | participant |
| `summer-camp` | `shirt_size` | Camp shirt size | select (YS/YM/YL/AS/AM/AL) | yes | participant |
| `summer-camp` | `lunch` | Bringing lunch or purchasing? | select | yes | participant |
| `parents-night-out` | `dinner_pref` | Pizza preference | select | no | participant |
| `birthday-party` | `birthday_child` | Birthday child name and age | text | yes | booking |
| `birthday-party` | `guest_count` | Expected number of children | number | yes | booking |
| `birthday-party` | `special_requests` | Special requests | textarea | no | booking |

Answers land in `bookings.answers` (booking scope) or `booking_participants.answers` /
`registrations.answers` (participant scope). A question flagged `is_sensitive` is treated like
medical data by the read policies.

### 4.6 Packages and memberships

| Package | Credits | Unit | Price | Eligible services | Validity | Restriction |
| --- | --- | --- | --- | --- | --- | --- |
| `lessons-5` | 5 | session | $400.00 | the four private lessons | 365 days | household-shared |
| `lessons-10` | 10 | session | $750.00 | the four private lessons | 365 days | household-shared |
| `cage-10hr` | 10 | hour | $600.00 | 35 ft and 50 ft cage rentals | 365 days | **off-peak only** |
| `hittrax-5hr` | 5 | hour | $650.00 | HitTrax rental | 180 days | household-shared |

| Plan | Interval | Price | Included credits | Member discount | Priority booking | Rollover |
| --- | --- | --- | --- | --- | --- | --- |
| `cage-monthly` | month | $99.00 | 4 | 10% | 24 h | yes, max 8 |
| `training-monthly` | month | $249.00 | 6 | 15% | 48 h | yes, max 6 |
| `family-annual` | year | $1,499.00 | 60 | 20% | 72 h | no |

### 4.7 Pricing rules

Rules live in `atd.pricing_rules`, are scoped by rate card, and are evaluated in ascending
`priority` order as a pipeline so the resulting breakdown is explainable. Conditions left NULL
mean "do not care". The seeded rules:

| Priority | Name | Scope | Applies to | Condition | Effect |
| --- | --- | --- | --- | --- | --- |
| 10 | Peak cage rate | peak | `cage-rental-35` | Mon–Fri 16:00–20:30 | set $1.00/min |
| 10 | Off-peak cage rate | off_peak | `cage-rental-35` | Mon–Fri 09:30–16:00 | set $0.58/min |
| 10 | Peak 50ft cage rate | peak | `cage-rental-50` | Mon–Fri 16:00–20:30 | set $1.25/min |
| 20 | Travel team practice rate | team | `team-practice` (Travel Team rate card) | — | set $2.25/min |
| 30 | Director premium — Reyes | custom | `private-hitting` with coach Reyes | — | add $15.00 |
| 80 | Member discount | member | all services (Standard rate card) | — | 10% off |

The rule *catalogue* is data; the *evaluation pipeline* is server-side code that writes its
ordered result into `order_items.price_breakdown`. There is no pricing function in the database.

### 4.8 Cancellation, reschedule and no-show policies

Three policies are seeded. Tiers are ordered by `min_hours_before` descending; the first tier
whose threshold the request satisfies is the one that applies, and the tier used is recorded on
`bookings.policy_tier_applied_id` and `refunds.policy_tier_id`.

**Standard Lesson Policy** (`applies_to = booking`, default; used by all private lessons, all
cage rentals, HitTrax rental and team practice):

| Action | Hours before | Outcome | Refund | Fee | Package credit returned |
| --- | --- | --- | --- | --- | --- |
| cancel | ≥ 24 | full_refund | 100% | — | yes |
| cancel | ≥ 12 | partial_refund | 50% | — | yes |
| cancel | ≥ 0 | credit_forfeited | 0% | — | no |
| reschedule | ≥ 24 | reschedule_free | — | — | yes |
| reschedule | ≥ 2 | reschedule_fee | — | $15.00 | yes |
| no_show | ≥ 0 | credit_forfeited | 0% | — | no |

**Program & Camp Policy** (`applies_to = registration`; used by the clinic, arm-care program,
summer camp and Parents' Night Out):

| Action | Hours before | Outcome | Refund |
| --- | --- | --- | --- |
| cancel | ≥ 336 (14 days) | full_refund | 100% |
| cancel | ≥ 168 (7 days) | partial_refund | 75% |
| cancel | ≥ 48 (2 days) | account_credit | 100% as store credit |
| cancel | ≥ 0 | no_refund | 0% |

**Party Policy** (`applies_to = party`; used by birthday parties and facility buyouts):

| Action | Hours before | Outcome | Refund | Package credit returned |
| --- | --- | --- | --- | --- |
| cancel | ≥ 336 (14 days) | partial_refund | 100% | no |
| cancel | ≥ 0 | no_refund | 0% | no |

Combined with the party's $150 flat deposit, this is the "deposit non-refundable inside 14 days"
rule stated on the policy record.

---

## 5. Business rules

### 5.1 Operating hours and closures

- The weekly template lives in `operating_hour_sets` + `operating_hours`, stored as local
  `time` values and resolved against `locations.timezone`. Seeded: 09:30–20:30, all seven days.
- Multiple hour sets may coexist with `effective_from` / `effective_to` and a `priority`;
  the highest priority set that covers the date wins (`atd.open_span`).
- Single-date exceptions live in `date_overrides` (one row per location per date) and beat the
  weekly template outright. Seeded: Christmas Day 2026 and Thanksgiving 2026 closed.
- `atd.open_span` returns `NULL` on a closed day; `atd.find_slots` then produces nothing for
  that date, and `atd.validate_recurrence` reports the occurrence as `Facility closed`.
- An emergency closure is a `resource_blocks` row with `applies_to_whole_location = true`.
  `atd.location_is_blocked` causes `atd.plan_allocation` to return `NULL` for every service in
  that window. Setting `cancelled_at` lifts it immediately (test 11).

### 5.2 Lead time and horizon

- Per-service `min_lead_minutes` (30 min for cage rentals up to 7 days for a facility buyout)
  and `max_horizon_days` (120 for all seeded services) bound the availability search:
  `find_slots` only emits instants between `now() + min_lead` and `now() + horizon`.
- Coaches carry an independent `min_lead_time_minutes` (120 for Reyes and Callahan, 180 for
  Nakamura, Brennan and Vargas). `atd.coach_is_available` enforces it, so a service with a
  30-minute lead time still cannot book Sofia Vargas 45 minutes from now.
- Location-level defaults sit in `locations.settings`: `min_booking_lead_minutes` 60,
  `max_booking_horizon_days` 120, `default_slot_granularity_minutes` 15.

### 5.3 Slot granularity

The availability walk steps at `max(service.slot_granularity_minutes, 5)`. Seeded: 15 minutes
for lessons and clinics, 30 minutes for rentals, camps, parties and Parents' Night Out, 60
minutes for a buyout.

### 5.4 Buffers

- Buffers are not advisory. They are folded into `blocked_from` / `blocked_to` by the
  `trg_reservation_envelope` trigger, and the exclusion constraint compares those columns. A
  transition gap is therefore enforced by the same mechanism that prevents overlap.
- `bookings.blocked_from` / `blocked_to` are maintained in parallel by `trg_booking_envelope`
  for fast calendar range queries, using `buffer_before + setup` and `buffer_after + cleanup`.

### 5.5 Capacity

- `resource_types.allocation` is `exclusive` or `shared`. Only the lobby is shared, with
  `capacity = 3`.
- Concurrency on a shared resource is expressed as `slot_index`: `atd.free_slot_index` walks
  `0 .. capacity-1` and returns the first index with no overlapping blocking reservation. The
  same exclusion constraint then enforces the cap. Test 18 fills all three lobby slots and
  asserts the fourth request gets `NULL`.
- Program capacity is separate and belongs to the *seat*, not the room:
  `programs.capacity`, the trigger-maintained `programs.enrolled_count`, and the CHECK
  constraint `enrolled_count <= capacity`. `atd.register_participant` takes `FOR UPDATE` on the
  program row so concurrent claims on the last seat serialise; the CHECK is the backstop if
  anything bypasses the function (tests 7b/7c and concurrency race 2).
- A participant may hold at most one live seat per program, enforced by a partial unique index
  over `(program_id, participant_id, program_session_id)` where status is `registered` or
  `attended`.

### 5.6 Age gates

- Services carry `min_age` / `max_age` (see §4.1). Coaches carry their own `coach_age_ranges`.
- Programs carry `min_age`, `max_age` and `age_as_of_date`. `atd.register_participant` computes
  `atd.age_on(participant.date_of_birth, coalesce(age_as_of_date, starts_on))` and raises
  `23514` if the participant falls outside the band — evaluated against the program date, not
  today (test 7d).

### 5.7 Checkout holds

- Default hold TTL is 10 minutes, from `locations.settings.checkout_hold_minutes` and mirrored
  in `system_settings`. `atd.create_hold` accepts an override; internal front-desk bookings use
  5 minutes.
- A hold's reservations have `status = 'hold'`, which is inside the `is_blocking` set, so they
  block everyone else exactly like a confirmed booking.
- `atd.expire_stale_holds()` runs at the head of every allocation path (`find_slots`,
  `create_hold`), so an abandoned checkout frees its slot within one TTL even if the background
  sweeper is down.
- `atd.confirm_hold` checks idempotency **first**: a hold that already converted returns its
  existing booking id, so a double-clicked Pay button cannot produce two bookings (test 8b,
  concurrency race 3). Only after that does it reject a released or expired hold with `23P01`.

### 5.8 Deposits and balances

- `services.requires_deposit` with either `deposit_cents` (birthday party: $150 flat) or
  `deposit_percent` (facility buyout: 25%), plus `balance_due_days_before`.
- `orders.deposit_required_cents` and `orders.balance_due_at` carry it onto the order;
  `orders.balance_due_cents` is a generated column (`total - paid + refunded`).
- The `balance.due` notification rule fires an email 4320 minutes (3 days) before
  `balance_due_at`.
- `orders.idempotency_key` is unique, so a retried checkout reuses one order and one payment
  intent. `payments.stripe_payment_intent_id` is uniquely indexed, and `stripe_events` is keyed
  on the Stripe event id so webhook replay is a no-op (test 21).

### 5.9 Waivers

- `waiver_templates` hold identity (audience, `requires_guardian_if_under` default 18,
  `renewal_months`); `waiver_versions` hold the legally binding body. A signature always points
  at a *version*, so "did they sign the current text?" is a join, not a guess.
- A partial unique index guarantees exactly one non-retired version per template.
- `waiver_versions.requires_resignature` distinguishes a material change from a typo fix.
- Seeded templates: General Liability & Assumption of Risk (participant, 12-month renewal),
  Camp Medical Authorization & Pickup (guardian, 12-month), Photo & Video Consent (guardian,
  no expiry, no re-signature required).
- `locations.settings.require_waiver_before_participation` is `true`. Letting a participant play
  unsigned requires the `waiver.override` permission and writes an audited
  `waiver_overrides` row with a mandatory reason and approver.

### 5.10 Coach rules

| Coach | Employment | Sports | Qualifications | Assignment priority | Max sessions/day | Min lead |
| --- | --- | --- | --- | --- | --- | --- |
| Marcus Reyes | employee | both | hitting, hittrax, camp_lead | 10 | 8 | 120 min |
| Tyler Callahan | employee | baseball | pitching, arm_care, camp_lead | 20 | 7 | 120 min |
| Dana Nakamura | contractor | softball | hitting, fielding, softball, hittrax | 30 | 6 | 180 min |
| Joe Brennan | contractor | baseball | catching, fielding, hitting | 40 | 6 | 180 min |
| Sofia Vargas | contractor | both | arm_care, strength | 50 | 5 | 180 min |

- Weekly availability: all coaches Mon–Fri 15:00–20:30 and Sat–Sun 09:30–16:00. Marcus Reyes
  additionally works Mon–Fri 09:30–13:00. Consequence, asserted by test 17: there is no catching
  coach available on a weekday morning, so `private-catching` shows no morning slots.
- A `coach_date_availability` row for a given date overrides the weekly rule outright for that
  date, in both directions.
- Candidate ordering is: explicitly preferred resources first, then `assignment_priority`
  ascending, then `sort_order`, then code — so "first available" tends to offer Reyes, then
  Callahan, and so on, unless the requirement names preferences.
- A pinned choice that is not free is a **hard failure**, never a silent substitution. If a
  parent selected Marcus Reyes, the system shows no availability rather than quietly assigning
  Joe Brennan. Substitution is an explicit staff action via `reschedule_booking` with new pins.

### 5.11 Compensation

| Priority | Scope | Basis | Value |
| --- | --- | --- | --- |
| 40 | `summer-camp`, any coach | hourly | $45.00/hr |
| 50 | Marcus Reyes, any service | percent_revenue | 70% |
| 100 | any coach, any service | percent_revenue | 60% |

Lower priority number wins. `coach_earnings` carries one row per coach per booking (unique
index), moves through `accrued → approved → paid`, and attaches to a `pay_period`.

### 5.12 Notifications

| Event key | Template | Channel | Anchor | Offset |
| --- | --- | --- | --- | --- |
| `booking.confirmed` | Booking Confirmation | email | immediate | 0 |
| `booking.reminder` | 24-Hour Reminder | SMS | booking_start | −1440 min |
| `waiver.missing` | Waiver Required | email | booking_start | −2880 min |
| `waitlist.offer` | A Spot Opened Up | SMS | immediate | 0 |
| `balance.due` | Balance Due Reminder | email | balance_due | −4320 min |
| `location.closure` | Facility Closure | SMS | immediate | 0 |

- `notifications.dedupe_key` is unique, so a retried job cannot queue the same reminder twice.
- SMS consent is explicit and provenance-tracked on the user record (`sms_consent_at`,
  `sms_consent_source`, `sms_consent_ip`), and every seeded SMS body carries "Reply STOP to opt
  out". `communication_preferences` is per user per category.

### 5.13 Waitlists

- `waitlist_entries` can target a program, a session, a service, a coach, or an arbitrary time
  window (`desired_from` / `desired_to` / `desired_weekdays`), with `priority` and `position`.
- An opening produces a `waitlist_offers` row with a unique `claim_token`, an `expires_at`, and
  an optional `hold_id` pointing at a real checkout hold — so the offered slot is genuinely
  reserved for that family during the claim window and two offerees cannot claim the same
  opening.
- Claim window default: 120 minutes (`system_settings.waitlist_claim_minutes`).
- Outcomes recorded: `claimed`, `declined`, `expired`, `superseded`.

### 5.14 Operational settings

| Key | Seeded value | Meaning |
| --- | --- | --- |
| `checkout_hold_minutes` | 10 | Checkout hold TTL |
| `waitlist_claim_minutes` | 120 | Waitlist claim window |
| `no_show_fee_cents` | 2500 | No-show fee |
| `allow_front_desk_override` | false | Front desk may not override conflicts |
| `allow_front_desk_refund` | false | Front desk may not issue refunds |
| `sibling_discount_percent` | 10 | Default sibling discount |
| `reminder_hours_before` | 24 | Reminder lead time |
| `kiosk_enabled` | true | Kiosk check-in enabled |

---

## 6. Success metrics

All of these are computable from the schema without additional instrumentation.

| Metric | Target | Source |
| --- | --- | --- |
| Double-booked resource-minutes | 0, permanently | The exclusion constraint. Any non-zero value is a schema failure, not a metric drift |
| Concurrent-checkout winners per contested slot | exactly 1 | `tests/concurrency/race.sh` in CI |
| Over-sold program seats | 0 | `programs` where `enrolled_count > capacity` (CHECK-enforced) |
| Online share of bookings | ≥ 60% within two seasons | `bookings.source = 'online'` vs `front_desk` / `walk_in` |
| Checkout hold conversion rate | ≥ 70% | `checkout_holds` with `converted_booking_id` not null ÷ total holds |
| Median time from service selection to confirmation | ≤ 3 minutes | `checkout_holds.created_at` → `bookings.created_at` |
| Slot utilisation by resource and hour | trend up | `resource_reservations` blocking minutes ÷ `open_span` minutes |
| Cancellations inside the free window | trend down | `booking_status_history` joined to `policy_tier_applied_id` |
| No-show rate | ≤ 5% | `bookings.status = 'no_show'` and `attendance_records.state = 'absent'` |
| Waiver compliance at session start | ≥ 99% | Sessions starting with a current `signed_waivers` row per participant; `waiver_overrides` counts as a miss |
| Conflict overrides per month | ≤ 5 | `conflict_overrides` row count; each carries a mandatory reason |
| Waitlist offer claim rate | ≥ 50% | `waitlist_offers.outcome = 'claimed'` ÷ offers sent |
| Waitlist fill latency | ≤ 4 h median | `waitlist_offers.offered_at` → `responded_at` |
| Reminder delivery rate | ≥ 98% | `notifications.state` distribution |
| Ledger reconstructability | 100% | Every denormalised balance equals the sum of its ledger |
| Front-desk time per walk-in | ≤ 90 seconds | `bookings.created_at` for `source = 'walk_in'` vs the preceding `check_ins` row |
| Payment retry / duplicate charges | 0 | Duplicate `stripe_payment_intent_id` attempts rejected by unique index |

---

## 7. Out of scope for v1 — explicit list

Restating §3 as commitments, because these are the questions that get asked mid-build:

1. **HitTrax.** The platform sells HitTrax time, reserves `CAGE-5` and `HITTRAX-1` together,
   filters to HitTrax-certified coaches, prices the session and takes the money. It does **not**
   replace, embed, control or read from HitTrax scoring software. Exit velocity numbers appear
   in the product only if a coach types them into `lesson_notes.metrics`.
2. **Video.** No capture, no hosting, no side-by-side analysis.
3. **Payroll disbursement.** Earnings accrue and are approved in-platform; money leaves the
   business elsewhere.
4. **Accounting integration.** No QuickBooks/Xero sync.
5. **Leagues, tournaments, brackets, scorekeeping.**
6. **Retail POS and merchandise inventory.**
7. **Native mobile apps.** Responsive web plus a kiosk web surface.
8. **Marketing automation.** Transactional and operational notifications only.
9. **Dynamic/surge pricing.**
10. **Multi-location operations.** Schema-ready, not launched.
11. **External calendar sync.**
12. **Parent–coach messaging.**
13. **HR and background-check records.**
14. **Equipment-level inventory** beyond what is modelled as a bookable resource (the two
    pitching machines are resources; buckets of balls are not).

---

## 8. Acceptance requirements

The following are proven by `tests/sql/01_scheduling.sql` and
`tests/concurrency/race.sh` and must stay green:

1. A private lesson reserves both a coach and a cage.
2. A pinned but busy coach yields no plan.
3. A raw insert bypassing every function still cannot overlap (`23P01`).
4. A 5-minute trailing buffer blocks a back-to-back start; 19:05 is accepted.
5. A HitTrax lesson blocks exactly three resources including the unit; the HitTrax rental is
   then unavailable.
6. A birthday party reserves the party room, two cages and one host in one transaction.
7. A clinic session reserves 4 resources; six registrations do not add any. The seventh
   registration is waitlisted. The capacity CHECK rejects a manual over-sell. An under-age
   participant is refused.
8. An active hold blocks others; an expired hold releases the slot; confirming an expired hold
   fails loudly; double-confirm is idempotent.
9. Rescheduling onto a busy coach is rejected and rolls back; a legal reschedule moves every
   reservation together.
10. Cancelling frees the resources immediately.
11. A whole-location closure blocks every service; lifting it restores availability.
12. A holiday date override closes the day.
13. A weekly 16:00 series keeps 16:00 local across the DST change while its UTC instant shifts.
14. Recurrence validation returns a verdict per occurrence with a reason for closed days.
15. Attribute matching restricts pitching to mound cages.
16. Qualification filtering restricts HitTrax lessons to certified coaches.
17. Coach availability windows are honoured.
18. Lobby capacity of 3 is fully consumed by 3 concurrent holds.
19. Package credits are ledger-derived; a second redemption against the same booking is
    rejected; a refund restores the credit.
20. Account credit is the sum of its ledger.
21. Stripe event replay and duplicate payment intents are rejected.
22. Waiver versioning: publishing v2 makes a v1 signature stale; one current version per
    template.
23. The audit log cannot be updated or deleted.
24. Availability search never leaves operating hours.
25. Under concurrency: exactly one winner per contested slot, exactly one registration for the
    final seat, and one booking id from concurrent confirms of one hold.
