# Deployment

Production deployment, backup and monitoring for the ATD Baseball platform.

---

## 1. Architecture

| Layer | Service | Notes |
|---|---|---|
| Web / API | Vercel | Next.js 15 App Router, Node runtime for API routes |
| Database | Supabase Postgres 16 | Requires `btree_gist`, `pgcrypto`, `citext`, `pg_trgm` |
| Auth | Supabase Auth | Email/password + magic link |
| Storage | Supabase Storage | Signed waiver PDFs, coach photos, camp rosters |
| Payments | Stripe | PaymentIntents, Subscriptions, Refunds |
| Email | Resend or Postmark | Transactional only; marketing respects opt-in |
| SMS | Twilio | Messaging Service with opt-out keywords enabled |
| Errors | Sentry | Server + client |
| Jobs | Vercel Cron or Supabase pg_cron | See §6 |

---

## 2. Database connection — read this before configuring `DATABASE_URL`

Use the Supabase **session pooler (port 5432)** or a direct connection.

**Do not use the transaction pooler (port 6543) for `DATABASE_URL`.** The booking engine
depends on transaction-scoped session state:

- `tx()` sets `app.user_id` with `set_config(..., true)` so RLS helpers and audit rows can
  attribute the actor.
- `atd.register_participant` holds a `SELECT ... FOR UPDATE` row lock across statements.
- `create_hold` → `confirm_hold` must observe the same snapshot and locks.

PgBouncer in transaction mode may hand consecutive statements to different backends, which
silently breaks all three. There is no error — just wrong behaviour under load, which is
the worst failure mode available.

```
DATABASE_URL=postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres
PGSSL=require
PGPOOL_MAX=10
```

Size `PGPOOL_MAX` against your Postgres `max_connections` and the number of serverless
instances. Vercel functions each hold their own pool; start conservative.

---

## 3. First deploy

### 3.1 Provision the database

```bash
psql "$DATABASE_URL" -c "create extension if not exists btree_gist;"
psql "$DATABASE_URL" -c "create extension if not exists pgcrypto;"
psql "$DATABASE_URL" -c "create extension if not exists citext;"
psql "$DATABASE_URL" -c "create extension if not exists pg_trgm;"

for f in supabase/migrations/*.sql; do
  echo "applying $f"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$f"
done
```

Migrations are ordered and must be applied in sequence. Verify:

```bash
psql "$DATABASE_URL" -tAc \
  "select count(*) from information_schema.tables where table_schema in ('atd','audit');"
# expect 96

psql "$DATABASE_URL" -tAc \
  "select conname from pg_constraint where conname = 'resource_reservations_no_overlap';"
# must return a row — this constraint IS the double-booking guarantee
```

If that constraint is missing, **stop**. Do not take bookings.

### 3.2 Seed

Seed `01_facility.sql` and `02_services.sql` on a new location. They contain the facility
layout, staff, service catalogue, packages, memberships, policies, waivers and notification
templates — all of which are editable in the admin UI afterwards.

Do **not** load the demo customer/booking seed into production.

### 3.3 Link staff accounts to auth

`atd.users.auth_user_id` must point at the Supabase `auth.users.id`. Create each staff
member in Supabase Auth, then:

```sql
update atd.users u
   set auth_user_id = a.id
  from auth.users a
 where a.email = u.email::text
   and u.auth_user_id is null;
```

Confirm the owner has the `super_admin` role before signing out of any break-glass access.

### 3.4 Configure Stripe

1. Create the webhook endpoint: `https://<domain>/api/webhooks/stripe`
2. Subscribe to: `payment_intent.succeeded`, `payment_intent.payment_failed`,
   `charge.refunded`, `invoice.payment_failed`, `customer.subscription.updated`,
   `customer.subscription.deleted`
3. Copy the signing secret into `STRIPE_WEBHOOK_SECRET`
4. Verify locally first: `stripe listen --forward-to localhost:3000/api/webhooks/stripe`

The webhook returns **200 for duplicates** (so Stripe stops retrying an event already
recorded) and **400 only for signature failures**. If you ever see it return 500 for a
recorded event, that is a bug worth paging on — the event is durably stored and should be
retried by the job runner, not by Stripe.

### 3.5 Deploy the app

```bash
vercel --prod
```

Set every variable from `.env.example` in the Vercel project. `SUPABASE_SERVICE_ROLE_KEY`,
`STRIPE_SECRET_KEY`, `TWILIO_AUTH_TOKEN` and `JOB_RUNNER_SECRET` must be server-only —
never prefixed `NEXT_PUBLIC_`.

---

## 4. Post-deploy verification

Run these against production before announcing it. Each maps to a guarantee.

| # | Check | Expected |
|---|---|---|
| 1 | `GET /api/availability?serviceId=<hittrax>&from=&to=` | Slots resolve a certified coach, the 70 ft cage and the HitTrax unit |
| 2 | Book a private lesson end to end | Coach and cage both blocked; confirmation email received |
| 3 | Attempt the same slot in a second browser | Rejected with "someone just booked that time" |
| 4 | Abandon a checkout, wait for the TTL | Slot returns to sale automatically |
| 5 | Double-click Pay | Exactly one booking, exactly one charge |
| 6 | Replay a Stripe event from the dashboard | 200, no duplicate payment row |
| 7 | Admin drag a booking onto a busy cage | Refused with a clear reason; booking unmoved |
| 8 | Register past a camp's capacity | Waitlisted, `enrolled_count` never exceeds `capacity` |
| 9 | Front-desk check-in with a missing waiver | Blocked, with a sign-now path |
| 10 | Coach signs in | Sees own schedule only; no facility financials |

---

## 5. Backups

Supabase takes automated daily backups; PITR is available on paid plans. **Turn PITR on.**
A booking system's worst day is one where a bad bulk edit is discovered six hours later.

Additionally, take an independent nightly logical dump so recovery does not depend on a
single vendor:

```bash
pg_dump "$DATABASE_URL" --format=custom --no-owner --no-acl \
  --file="atd-$(date +%F).dump"
```

Retention: 30 daily, 12 monthly. Store off-platform with server-side encryption.

**Restore drill — do this quarterly, not just in an incident.** Restore last night's dump
into a scratch database and run:

```bash
PGDATABASE=atd_restore_test ./scripts/test-sql.sh
PGDATABASE=atd_restore_test ./tests/concurrency/race.sh
```

A backup you have never restored is a hypothesis, not a backup.

---

## 6. Background jobs

| Job | Schedule | If it stops |
|---|---|---|
| Expire stale holds | every 2 min | Self-healing — every allocation path calls `atd.expire_stale_holds()` first. Slots free late, never never. |
| Send queued notifications | every 1 min | **Not self-healing.** Confirmations and reminders silently stop. Alert on queue depth. |
| Waitlist offer expiry | every 5 min | Offers stay open past their window; the next person is not called. |
| Package expiry | daily 02:00 ET | Expired credits remain spendable. |
| Membership renewal reconciliation | daily 03:00 ET | Stripe and local subscription status drift. |
| Stripe event retry (unprocessed rows) | every 10 min | Payments recorded but not applied to bookings. |
| Nightly reporting rollups | daily 04:00 ET | Dashboards go stale; no correctness impact. |

Jobs are triggered over HTTP and must present `JOB_RUNNER_SECRET`. Example Vercel cron:

```json
{
  "crons": [
    { "path": "/api/jobs/expire-holds",   "schedule": "*/2 * * * *" },
    { "path": "/api/jobs/notifications",  "schedule": "* * * * *" },
    { "path": "/api/jobs/waitlist",       "schedule": "*/5 * * * *" },
    { "path": "/api/jobs/stripe-retry",   "schedule": "*/10 * * * *" },
    { "path": "/api/jobs/nightly",        "schedule": "0 7 * * *" }
  ]
}
```

Cron schedules on Vercel are UTC. `0 7 * * *` is 03:00 ET in daylight time and 02:00 ET in
standard time — if a job must land at a fixed *local* hour, have the job itself check the
local time and no-op outside its window rather than trusting the scheduler.

---

## 7. Monitoring

Alert on these, in priority order:

1. **Exclusion-constraint violations outside checkout.** `23P01` during a hold is normal —
   it is the system working. `23P01` from an admin path or a job means something is
   fighting the engine.
2. **Unprocessed Stripe events** older than 15 minutes:
   `select count(*) from atd.stripe_events where processed_at is null and received_at < now() - interval '15 min'`
3. **Notification queue depth** > 200 or oldest queued > 10 minutes.
4. **Hold conversion rate** falling sharply — usually a payment or availability regression.
5. **Database connection saturation** — pool exhaustion presents as slow availability
   search long before it presents as an error.
6. **p95 latency of `/api/availability`.** It walks the open window at slot granularity;
   if someone widens a search horizon it degrades before anything breaks.

Useful operational query — how busy is the building right now:

```sql
select r.code, b.confirmation_code, rr.starts_at, rr.ends_at
  from atd.resource_reservations rr
  join atd.resources r on r.id = rr.resource_id
  left join atd.bookings b on b.id = rr.booking_id
 where rr.is_blocking and rr.blocking_span @> now()
 order by r.sort_order;
```

---

## 8. Rollback

The app rolls back via Vercel's instant rollback. **The database does not.**

Migrations `0001`–`0012` are additive. Before any future migration that drops or rewrites a
column:

1. Take a fresh dump and confirm it restores.
2. Deploy the schema change and the code that tolerates both shapes, in that order.
3. Only remove the old shape a release later.

Never roll a migration back under load by dropping a column. Ship a forward fix.

---

## 9. Scaling notes

- Availability search is the hot path. It is `O(days × slots × requirements × candidate
  resources)`. For a five-cage facility over a two-week horizon this is trivial; if a
  future location has 40 resources and a 6-month horizon, cache per (service, date) with a
  short TTL and invalidate on any reservation write for that location.
- `reservations_live_span` is the index that matters — a partial GiST on
  `(resource_id, blocking_span) where is_blocking`. Watch it in `pg_stat_user_indexes`.
- Multi-location is already modelled. Adding a second site is configuration: new
  `locations` row with its own timezone and operating hours, its own resources and
  services. No migration required.
