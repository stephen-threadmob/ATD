# ATD Baseball Platform — Roles and Permissions

Source of truth: `supabase/migrations/0002_identity_locations.sql` (tables) and
`supabase/migrations/0011_rbac_rls.sql` (permission catalogue, role bundles, auth helpers,
row-level security). Every permission key and every grant listed here is a row inserted by
migration 0011.

---

## 1. The five roles

`atd.role_key` is a Postgres enum with exactly five values. Roles are system roles
(`roles.is_system = true`); custom roles are not part of v1. Capability is adjusted through
per-user overrides rather than by inventing new roles.

| Role key | Name | Description (as seeded) | Typical holder |
| --- | --- | --- | --- |
| `super_admin` | Super Administrator | Full control across all locations | Anthony Delgado (owner) |
| `location_admin` | Location Administrator | Full control of an assigned location | Renee Okafor (manager) |
| `front_desk` | Front Desk | Day-to-day counter operations | Jamie Whitfield |
| `coach` | Coach / Instructor | Teaching, availability, own earnings | Reyes, Callahan, Nakamura, Brennan, Vargas |
| `customer` | Customer | Household self-service | Parents and adult athletes |

The `customer` role deliberately holds **zero** rows in `role_permissions`. Customers are not
granted staff capabilities that are then filtered down; they get no staff capability at all, and
their access to their own data comes exclusively from row-level security matching their
household membership. This is why a leaked customer token cannot read another family's
children — there is no permission to narrow, only a household predicate to satisfy.

---

## 2. Permission matrix

41 permission keys. `Yes` = granted by the role bundle in migration 0011; `—` = not granted.

### 2.1 Booking (category `booking`)

| Permission key | Description | super_admin | location_admin | front_desk | coach | customer |
| --- | --- | :---: | :---: | :---: | :---: | :---: |
| `booking.read` | View bookings | Yes | Yes | Yes | Yes | — |
| `booking.create` | Create bookings | Yes | Yes | Yes | — | — |
| `booking.update` | Move, resize, or edit bookings | Yes | Yes | Yes | — | — |
| `booking.cancel` | Cancel bookings | Yes | Yes | Yes | — | — |
| `booking.cancel_paid` | Cancel bookings that have payments | Yes | Yes | — | — | — |
| `booking.override_conflict` | Override a scheduling conflict | Yes | Yes | — | — | — |
| `booking.reassign_resource` | Reassign cages, coaches or equipment | Yes | Yes | Yes | — | — |
| `booking.walk_in` | Create walk-in bookings | Yes | Yes | Yes | — | — |
| `booking.extend` | Extend an in-progress rental | Yes | Yes | Yes | — | — |

### 2.2 Customer data (category `customer`)

| Permission key | Description | super_admin | location_admin | front_desk | coach | customer |
| --- | --- | :---: | :---: | :---: | :---: | :---: |
| `customer.read` | View customer accounts | Yes | Yes | Yes | Yes | — |
| `customer.write` | Edit customer accounts | Yes | Yes | Yes | — | — |
| `customer.delete` | Delete or anonymise customer data | Yes | — | — | — | — |
| `customer.export` | Export customer data | Yes | Yes | — | — | — |
| `participant.read_medical` | View allergies and medical notes | Yes | Yes | — | — | — |

### 2.3 Money (category `money`)

| Permission key | Description | super_admin | location_admin | front_desk | coach | customer |
| --- | --- | :---: | :---: | :---: | :---: | :---: |
| `payment.collect` | Collect payments | Yes | Yes | Yes | — | — |
| `payment.refund` | Issue refunds | Yes | Yes | — | — | — |
| `payment.discount` | Apply discounts | Yes | Yes | Yes | — | — |
| `payment.price_override` | Override prices | Yes | Yes | — | — | — |
| `payment.credit` | Grant account credit | Yes | Yes | — | — | — |
| `payment.comp` | Create complimentary bookings | Yes | Yes | — | — | — |
| `finance.reports` | View financial reports | Yes | Yes | — | — | — |
| `package.sell` | Sell packages and memberships | Yes | Yes | Yes | — | — |
| `package.adjust` | Adjust package credits | Yes | Yes | — | — | — |
| `comp.read_self` | View own compensation | Yes | Yes | — | Yes | — |
| `comp.manage` | Manage compensation rules and payroll | Yes | Yes | — | — | — |

### 2.4 Operations (category `ops`)

| Permission key | Description | super_admin | location_admin | front_desk | coach | customer |
| --- | --- | :---: | :---: | :---: | :---: | :---: |
| `waiver.send` | Send and resend waivers | Yes | Yes | Yes | — | — |
| `waiver.override` | Allow participation without a waiver | Yes | Yes | — | — | — |
| `checkin.manage` | Check customers in and out | Yes | Yes | Yes | Yes | — |
| `waitlist.manage` | Manage waitlists and offers | Yes | Yes | Yes | — | — |
| `schedule.block` | Create maintenance blocks and closures | Yes | Yes | — | — | — |

### 2.5 Configuration (category `config`)

| Permission key | Description | super_admin | location_admin | front_desk | coach | customer |
| --- | --- | :---: | :---: | :---: | :---: | :---: |
| `resource.manage` | Create and edit resources | Yes | Yes | — | — | — |
| `service.manage` | Create and edit services and pricing | Yes | Yes | — | — | — |
| `program.manage` | Create and edit programs, camps, events | Yes | Yes | — | — | — |
| `coach.manage` | Manage coach profiles and qualifications | Yes | Yes | — | — | — |
| `coach.availability_self` | Edit own availability | Yes | Yes | — | Yes | — |
| `coach.approve_time_off` | Approve coach time off | Yes | Yes | — | — | — |

### 2.6 Administration (category `admin`)

| Permission key | Description | super_admin | location_admin | front_desk | coach | customer |
| --- | --- | :---: | :---: | :---: | :---: | :---: |
| `staff.manage` | Manage staff and permissions | Yes | Yes | — | — | — |
| `location.manage` | Manage locations and operating hours | Yes | — | — | — | — |
| `settings.manage` | Manage system settings and integrations | Yes | — | — | — | — |
| `audit.read` | View audit logs | Yes | Yes | — | — | — |
| `report.operational` | View operational reports | Yes | Yes | Yes | — | — |

### 2.7 Totals

| Role | Permissions granted | How the bundle is defined in 0011 |
| --- | ---: | --- |
| `super_admin` | 41 of 41 | `roles CROSS JOIN permissions` — every key, unconditionally |
| `location_admin` | 38 of 41 | every key **except** `location.manage`, `settings.manage`, `customer.delete` |
| `front_desk` | 16 of 41 | an explicit `unnest(array[...])` list |
| `coach` | 5 of 41 | an explicit `unnest(array[...])` list |
| `customer` | 0 of 41 | no rows inserted |

The three keys withheld from `location_admin` are precisely the irreversible or
cross-location ones: changing operating hours and location records, changing integration and
system settings, and destroying customer data. A location administrator can run the business
completely but cannot silently redefine the business or erase its history.

---

## 3. The grant model

### 3.1 Roles are granted per location

`atd.user_roles` is the grant table:

| Column | Meaning |
| --- | --- |
| `user_id` | who |
| `role_id` | which role |
| `location_id` | **where — `NULL` means all locations** |
| `granted_by`, `granted_at` | provenance |
| `revoked_at` | soft revocation; `NULL` means live |

A partial unique index (`user_roles_unique_live`) prevents duplicate live grants of the same
role to the same user at the same location, coalescing `NULL` location to the zero UUID so that
"all locations" is itself a distinct, single grant.

As seeded, the owner's `super_admin` grant carries `location_id = NULL`; every other staff grant
names the Wallingford location explicitly. That is the whole of the multi-location story: adding
a second building means new `locations` and `resources` rows plus new `user_roles` rows, not new
code.

Revocation is `revoked_at`, never a delete. Every permission check filters on
`revoked_at is null`, so history stays intact for audit while access stops immediately.

### 3.2 Per-user overrides, deny wins

`atd.user_permission_overrides` adjusts a single capability for a single user, optionally scoped
to one location:

| Column | Meaning |
| --- | --- |
| `user_id`, `permission_key` | the capability being adjusted |
| `location_id` | scope; `NULL` = everywhere |
| `effect` | `'allow'` or `'deny'` (CHECK-constrained) |
| `reason` | free text, for the person reading it a year later |
| `created_by`, `created_at` | provenance |

A unique index over `(user_id, permission_key, coalesce(location_id, zero-uuid))` means a user
has at most one override per key per scope — there is no ambiguity about which override applies.

The resolution order is implemented in `atd.has_permission(p_key, p_location)`:

```sql
select
  -- explicit deny wins
  not exists (deny override matching key and scope)
  and (
    exists (role grant that includes the key, matching scope)
    or exists (allow override matching key and scope)
  )
```

Read plainly:

1. **Deny is checked first and short-circuits everything.** A deny override beats a role grant,
   beats an allow override, and beats `super_admin`. There is no escalation path around it.
2. If no deny applies, the permission is held if **either** a live role grant supplies it **or**
   an allow override supplies it.
3. Scope matching is deliberately permissive in one direction: a grant with `location_id = NULL`
   satisfies any location, and a check with `p_location = NULL` is satisfied by a grant at any
   location. A grant at location A does not satisfy a check at location B.

Worked examples:

| Situation | Configuration | Result |
| --- | --- | --- |
| Front desk lead may issue refunds at Wallingford only | allow `payment.refund`, `location_id` = Wallingford | `has_permission('payment.refund', wallingford)` true; elsewhere false |
| A contractor coach is suspended from viewing customer records during an investigation | deny `customer.read`, `location_id` = NULL | false everywhere, even though the `coach` bundle grants it |
| An admin is temporarily barred from refunds after an incident | deny `payment.refund` on a `location_admin` | false, despite the role bundle granting it |
| Owner sanity check | deny `settings.manage` on the `super_admin` | false — deny genuinely wins over everything |

Because deny outranks `super_admin`, removing a deny is itself a `staff.manage` action and
leaves an audit trail. That is the intended property: capability reduction should be as
deliberate as capability grant.

### 3.3 Staff identity helpers

Three helpers sit between the grant model and the policies:

| Function | Returns | Used for |
| --- | --- | --- |
| `atd.app_user_id()` | the `atd.users.id` for the current JWT subject, falling back to the `app.user_id` GUC for server-side and test contexts | every policy |
| `atd.is_staff(p_location)` | true if the caller holds any of `super_admin`, `location_admin`, `front_desk`, `coach` at that location (or unscoped) | coarse staff-vs-customer gates |
| `atd.my_household_ids()` | the set of households the caller belongs to via `household_members` | every customer-facing policy |
| `atd.my_coach_id()` | the caller's coach id, if any | coach-scoped reads |

`atd.is_staff()` is intentionally coarse. It answers "is this person behind the counter" and is
used only where the distinction between staff roles does not matter. Anywhere the distinction
does matter, the policy calls `atd.has_permission()` with a specific key.

---

## 4. How row-level security backs this up

The comment at the head of migration 0011 states the posture: RLS is the *last* line of defence,
not the only one. The application performs server-side authorisation as well. RLS exists because
Supabase exposes PostgREST directly, so every customer-reachable table must be safe even if an
anon or customer key is used to query it directly.

### 4.1 Tables with RLS enabled

`households`, `household_members`, `participants`, `bookings`, `booking_participants`,
`registrations`, `orders`, `payments`, `package_purchases`, `memberships`, `signed_waivers`,
`waitlist_entries`, `lesson_notes`, `staff_notes`, `emergency_contacts`, `notifications`,
`resource_reservations`.

Trusted server code connects with the service role, which bypasses RLS entirely; that is the
only path that writes reservations, orders and payments.

### 4.2 Policy summary

| Table | Policy | Who can read | Who can write |
| --- | --- | --- | --- |
| `households` | `households_self`, `households_update` | own household, or any staff at that location | own household, or `customer.write` |
| `household_members` | `household_members_self` | own household, or any staff | (server only) |
| `participants` | `participants_self`, `participants_write` | own household, or any staff | own household, or `customer.write` |
| `bookings` | `bookings_self`, `bookings_staff_write` | own household; staff at that location; **or a coach who is reserved on that booking** | `booking.update` to modify, `booking.create` to insert |
| `booking_participants` | `booking_participants_self` | via the parent booking's household, or staff at its location | (server only) |
| `registrations` | `registrations_self` | own household, or any staff | (server only) |
| `orders` | `orders_self` | own household, or staff at that location | (server only) |
| `payments` | `payments_self` | own household, or `finance.reports`, or `payment.collect` | (server only) |
| `package_purchases` | `packages_self` | own household, or any staff | (server only) |
| `memberships` | `memberships_self` | own household, or any staff | (server only) |
| `signed_waivers` | `waivers_self` | own household, or any staff | (server only) |
| `waitlist_entries` | `waitlist_self` | own household, or staff at that location | (server only) |
| `lesson_notes` | `lesson_notes_read` | the authoring coach; `customer.read` holders; the participant's household **only if `shared_with_customer`** | (server only) |
| `staff_notes` | `staff_notes_staff_only` | tiered by `visibility` — see §5.2 | (server only) |
| `emergency_contacts` | `emergency_contacts_read` | own household, or any staff | (server only) |
| `notifications` | `notifications_self` | own household, the addressed user, or staff at that location | (server only) |
| `resource_reservations` | `reservations_read` | staff at that location, or a customer whose booking owns the reservation | (server only) |

### 4.3 Two policies worth reading closely

**Coaches see the bookings they teach.** `bookings_self` includes a clause that joins through
`resource_reservations` to `coaches` on `resource_id`. Because a coach *is* a resource, "the
bookings assigned to me" needs no separate assignment table — a coach can read exactly the
bookings that reserve their coach resource, plus anything else their staff role allows.

**Payments are gated by capability, not by staff status.** `payments_self` does not use
`atd.is_staff()`. It requires `finance.reports` or `payment.collect`. A coach is staff, holds
neither key, and therefore cannot read the payments table at all — see §5.3.

### 4.4 What RLS does not do

RLS governs `select` (and, where a policy exists, `update`/`insert`). Writes to the occupancy
and money tables go through `SECURITY INVOKER` functions called by the service role. The
correctness guarantees those writes rely on are constraints, not policies:

- the GiST exclusion constraint on `resource_reservations`,
- `programs_capacity_not_exceeded`,
- the partial unique index on live registrations,
- unique indexes on `stripe_events.id`, `payments.stripe_payment_intent_id`,
  `orders.idempotency_key`, `notifications.dedupe_key`,
- the append-only trigger on `audit.entries`.

Permissions decide who may *ask*; constraints decide what is *possible*.

---

## 5. Sensitive data gating

### 5.1 Participant medical information

`participants.allergies` and `participants.medical_notes` are commented in migration 0004 as
"exposed only to users holding `participant.read_medical`". That is enforced by a redacting
view, `atd.participants_safe`, declared `security_invoker = true` so it evaluates the caller's
own permissions rather than the view owner's:

```sql
case when atd.has_permission('participant.read_medical')
          or p.household_id in (select atd.my_household_ids())
     then p.allergies else null end as allergies
```

with the same expression for `medical_notes`. The view also exposes a computed `age` and omits
`internal_notes`, `gender` and `photo_consent` entirely.

| Caller | Sees allergies / medical notes |
| --- | --- |
| The child's own parent or guardian | Yes — it is their own child's data |
| `super_admin` | Yes |
| `location_admin` | Yes |
| `front_desk` | **No** — redacted to `NULL` |
| `coach` | **No** — redacted to `NULL` |

The intent: the front desk does not need a child's medical history to take a payment, and a
contractor coach does not need it to run a hitting lesson. The people who need it during a camp
are the ones administering the Camp Medical Authorization waiver, and they hold
`participant.read_medical` or are handed the information operationally.

Two consequences to design around in the UI:

1. **Staff-facing lists read `participants_safe`, never `participants`.** The policy on the base
   table (`participants_self`) permits any staff member to select it, so reading the table
   directly would leak the columns the view redacts. The redaction lives in the view, so the
   view is the only correct staff-facing source.
2. A camp roster printed for coaches shows "medical note on file — see the director" rather than
   the note itself, unless the printing user holds the key.

### 5.2 Staff notes visibility levels

`atd.staff_notes.visibility` is CHECK-constrained to three values, and `staff_notes_staff_only`
maps each to a different test:

| `visibility` | Policy test | Who can read | Intended use |
| --- | --- | --- | --- |
| `admin_only` | `has_permission('staff.manage', location_id)` | `super_admin`, `location_admin` | Payment disputes, behavioural incidents, custody and legal matters, staff concerns about a family |
| `coach` | `is_staff(location_id)` | any staff at the location, including coaches | Coaching context: "works better with a shorter bat", "gets discouraged after three bad swings" |
| `staff` (default) | `has_permission('customer.read', location_id)` | roles holding `customer.read` — `super_admin`, `location_admin`, `front_desk`, `coach` | Counter context: "always pays by check", "arrives 15 minutes early" |

No value of `visibility` is customer-readable. The policy has no household branch at all, which
is the point: staff notes are internal by construction, and there is no configuration mistake
that can expose them to a parent.

Note the near-equivalence of `coach` and `staff` under the seeded bundles — both `is_staff()` and
`customer.read` currently resolve to the same four roles. They diverge the moment a deny
override removes `customer.read` from an individual, or a future staff role is added that is
`is_staff()` but not granted `customer.read`. The three levels exist so that the *intent* is
recorded on each note rather than inferred later.

### 5.3 Coach access to financials

Coaches are staff, but the money surface is closed to them:

| Capability | Coach holds it? | Effect |
| --- | :---: | --- |
| `finance.reports` | No | Cannot open revenue reporting |
| `payment.collect` | No | Cannot take a payment; combined with the above, `payments_self` denies the payments table entirely |
| `payment.refund`, `payment.discount`, `payment.price_override`, `payment.credit`, `payment.comp` | No | No ability to move money or change a price |
| `package.sell`, `package.adjust` | No | Cannot sell or adjust packages |
| `comp.manage` | No | Cannot see or edit compensation rules, other coaches' earnings, or pay periods |
| `comp.read_self` | **Yes** | Can see their own earnings |

`comp.read_self` is the only money key a coach holds, and its name is the contract: **own**
compensation. `coach_earnings` does not have RLS enabled, so the scoping to
`coach_id = atd.my_coach_id()` is applied by the server-side query layer that the permission
gates, not by a policy. Two implications:

1. The coach earnings endpoint must filter on `my_coach_id()` server-side; the permission check
   alone is not sufficient isolation.
2. Direct PostgREST access to `atd.coach_earnings` should not be exposed. Financial ledger
   tables (`orders` aside) are reached only through the service role.

A coach reading a booking they teach sees the booking row, which carries denormalised money
columns (`total_cents`, `paid_cents`, `balance_due_cents`). That is intentional — a coach should
know whether a lesson is paid — but it is the boundary. They cannot see the order, the payment,
the card, the household's account credit, or anyone else's session revenue.

### 5.4 Other gated surfaces

| Surface | Gate |
| --- | --- |
| Lesson notes | A parent sees a note only when the coach set `shared_with_customer = true`; the coach always sees their own; `customer.read` holders see all |
| Customer export | `customer.export` — held by admins only, not by the front desk |
| Customer deletion / anonymisation | `customer.delete` — `super_admin` only |
| Audit log | `audit.read` for viewing; `update` and `delete` are revoked from `public` and additionally rejected by the `trg_audit_immutable` trigger, so even the table owner cannot rewrite history |
| Conflict overrides | `booking.override_conflict` — admins only, not the front desk; the seeded setting `allow_front_desk_override` is `false`, matching the role bundle |
| Refunds at the counter | `payment.refund` — admins only; the seeded setting `allow_front_desk_refund` is `false`, matching the role bundle |
| Waiver bypass | `waiver.override` — admins only; every use writes a `waiver_overrides` row with a mandatory reason and an approver |
| System settings marked `is_secret` | `settings.manage` — `super_admin` only |

---

## 6. Operating guidance

1. **Grant the role, then subtract.** Start staff on the standard bundle and use deny overrides
   with a written `reason` for the exceptions. Do not invent a role.
2. **Add capability with allow overrides, scoped to a location.** A senior front-desk lead who
   should be able to refund gets `allow payment.refund` at Wallingford, not `location_admin`.
3. **Revoke, do not delete.** Set `user_roles.revoked_at`. Access stops on the next permission
   check; the record of who had what, and when, survives.
4. **Read `participants_safe` in every staff-facing view.** Reading `atd.participants` directly
   from a staff surface bypasses medical redaction.
5. **Choose a staff-note visibility on purpose.** `admin_only` for anything a coach should not
   read; `coach` for anything that helps at the cage; `staff` for counter logistics.
6. **Keep the seeded settings and the role bundles aligned.** `allow_front_desk_override` and
   `allow_front_desk_refund` are both `false` and both agree with the front-desk bundle. If one
   is changed, change the other, or the UI and the authorisation layer will disagree.
