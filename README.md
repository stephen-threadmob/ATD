# ATD Baseball Company — Booking & Facility Management Platform

A production-oriented booking, scheduling and facility-management system for an indoor
baseball and softball training facility: cage rentals, private and group instruction,
camps, clinics, arm-care programs, HitTrax sessions and events, birthday parties,
Parents' Night Out, team practices, memberships, packages and gift cards.

The hard part is not the calendar. It is that **one booking consumes several resources at
once** — a HitTrax lesson needs a certified coach, the 70 ft cage, and the HitTrax unit —
and all of them must be committed or none of them.

---

## The central design decision

> Nothing occupies the facility except a row in `atd.resource_reservations`.

Bookings, camp sessions, parties, admin blocks, maintenance, coach time off, weather
closures **and transient checkout holds** all materialise into that one table. It carries a
single GiST exclusion constraint:

```sql
constraint resource_reservations_no_overlap
  exclude using gist (
    resource_id   with =,
    slot_index    with =,
    blocking_span with &&
  ) where (is_blocking)
```

Consequences worth stating plainly:

- **Double-booking is not "checked", it is impossible.** Two concurrent checkouts cannot
  both win. The loser receives `SQLSTATE 23P01` and is told the slot was just taken.
- **Coaches are resources too.** A coach has a `resources` row, so "this coach is teaching
  two lessons at once" is prevented by the same constraint that prevents "this cage is
  double-booked". There is no second code path to keep in sync.
- **Buffers are enforced, not advisory.** `blocking_span` includes setup, cleanup and
  transition buffers, so a 5-minute gap between lessons is structural.
- **Holds block.** An abandoned checkout genuinely reserves the slot until its TTL expires,
  so the last cage on a Saturday cannot be sold twice while someone hunts for their card.
- **Shared-capacity resources work the same way.** A lobby with capacity 3 hands out
  `slot_index` 0–2; the fourth concurrent claim fails on the same constraint.

Availability calculation and reservation acquisition both run **inside the database**, on
the same connection and the same snapshot. Any design where the app checks availability
over one connection and writes over another has a race window. This one does not.

---

## What is here

| Area | Status |
|---|---|
| Database schema | 12 migrations, 96 tables/views, applied and verified from scratch |
| Scheduling engine | In-database: availability search, allocation planning, holds, atomic booking, reschedule, recurrence validation, program materialisation |
| Pricing engine | Ordered rule pipeline in TypeScript with a fully explainable breakdown |
| Policy engine | Tiered cancellation / reschedule / no-show, applied atomically with the cancellation |
| Payments | Stripe PaymentIntents, two independent idempotency layers, webhook replay safe |
| Public site | Services, coaches, camps, parties, memberships, facility, contact |
| Booking flow | Mobile-first 7 steps, live hold countdown, race-aware recovery |
| Customer portal | Bookings, household, packages, membership, waivers, payments, waitlists |
| Admin platform | Master resource-timeline calendar with drag/drop, service builder, resources, programs, customers, payments, reports, settings |
| Front desk | Today's operations board, walk-ins, customer search, payments, resource status |
| Coach portal | Today, calendar, session detail, attendance, notes, availability, earnings |
| Kiosk | Self check-in by phone, code or QR |
| Tests | 59 SQL tests + 6 true multi-connection concurrency tests, all passing |

---

## Quick start

```bash
cp .env.example .env.local          # fill in DATABASE_URL at minimum
npm install
./scripts/db-reset.sh               # migrations + seed
npm run dev
```

Then:

- Public site: <http://localhost:3000>
- Admin: `/admin` · Front desk: `/desk` · Coach: `/coach` · Kiosk: `/kiosk`

### Tests

```bash
npm run test:sql     # rebuilds the DB, runs 59 assertions
npm run test:race    # 12 parallel connections fighting over one slot
npm run typecheck
npm test             # all three
```

The concurrency suite is the one that matters. Its success criterion is not "no errors" —
it is **exactly one winner**.

---

## Repository layout

```
supabase/
  migrations/     0001–0012, ordered and idempotent to apply in sequence
    0006_bookings_reservations.sql   the exclusion constraint
    0010_scheduling_engine.sql       availability, holds, atomic booking, recurrence
    0011_rbac_rls.sql                permission catalogue + row-level security
    0012_addon_aware_allocation.sql  add-ons that add AND constrain requirements
  seed/           facility, staff, service catalogue, demo customers
src/
  server/         db, auth, availability, pricing, policy, waivers, stripe (server-only)
  app/
    (public)/     marketing site + booking flow
    (portal)/     customer account
    (admin)/      administrative platform
    (desk)/       front-desk operations
    (coach)/      coach portal
    kiosk/        self check-in
    api/          route handlers
  components/     UI primitives, calendar, booking, portal, admin
tests/
  sql/            assertion-based engine tests
  concurrency/    real parallel-connection race tests
docs/             PRD, ERD, data dictionary, roles, journeys, admin guide,
                  staff training, runbook, deployment
scripts/          db-reset, test runners
```

---

## Nothing about the facility is hard-coded

The seed describes today's building — one 50 ft cage, three 35 ft cages, one 70 ft HitTrax
cage, a party room, a lobby, machines, hosts, five coaches, 9:30 AM–8:30 PM. **All of it is
data.** An administrator adds a cage, a coach, a location or an entirely new kind of
service without a developer, because a service is a template that *declares* what it
consumes:

```
Private Hitting Lesson  →  coach (qualification: hitting) ×1
                           cage ×1
HitTrax Lesson          →  coach (qualification: hittrax) ×1
                           cage where attributes @> {"has_hittrax": true} ×1
                           hittrax unit ×1
Birthday Party          →  party room ×1 + cage ×2 + event host ×1
                           15 min setup, 30 min cleanup
```

The engine has no concept of "birthday party". It reads rows.

Multi-location is built in: every resource, service, program and booking is scoped to a
`location_id` with its own IANA timezone and operating hours, so a second site is
configuration rather than a migration.

---

## Documentation

| Document | For |
|---|---|
| [`docs/PRD.md`](docs/PRD.md) | Product requirements, service catalogue, business rules |
| [`docs/ERD.md`](docs/ERD.md) | Entity-relationship diagrams, seven bounded contexts |
| [`docs/DATA_DICTIONARY.md`](docs/DATA_DICTIONARY.md) | Every table, column, constraint and enum |
| [`docs/ROLES_AND_PERMISSIONS.md`](docs/ROLES_AND_PERMISSIONS.md) | Full permission matrix and RLS model |
| [`docs/USER_JOURNEYS.md`](docs/USER_JOURNEYS.md) | Ten end-to-end journeys with real system behaviour |
| [`docs/ADMIN_GUIDE.md`](docs/ADMIN_GUIDE.md) | Owner/manager handbook, including building a new service |
| [`docs/STAFF_TRAINING.md`](docs/STAFF_TRAINING.md) | Front-desk and coach training |
| [`docs/RUNBOOK.md`](docs/RUNBOOK.md) | Operations, incidents, background jobs |
| [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) | Production deployment, backups, monitoring |

---

## Security posture

- Authorisation is enforced **server-side on every mutation**; RLS is a second layer, not
  the only one. A client-side role check is a UI affordance.
- Row-level security on all 17 customer-reachable tables, so a leaked anon key cannot
  enumerate other families' children.
- Medical notes and allergies are gated behind `participant.read_medical` and surfaced to
  coaches as a flag rather than free text.
- Card data never touches the server — Stripe tokens and ids only.
- `audit.entries` is append-only, enforced by a trigger that refuses UPDATE and DELETE even
  for the table owner.
- Every conflict override requires an authenticated identity, an acknowledgement and a
  written reason, and writes both a first-class record and an audit row.

---

## Known limits

These are deliberate v1 boundaries, documented rather than hidden:

- HitTrax **scoring** software is not replaced. The platform handles registration,
  scheduling, resource blocking, payment and event operations around it.
- Stripe Terminal (card-present capture at the counter) is out of scope; counter card
  payments record a payment row.
- No coach payroll disbursement — earnings are computed and exported, not paid.
- `services.is_taxable` defaults to `false`, so nothing is taxed until an administrator
  enables it per service, even though a CT rate is seeded.
- Package and membership *purchase* endpoints are not yet wired to checkout; those CTAs
  route to the front desk rather than pretending to sell.
