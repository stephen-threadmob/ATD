# ATD Baseball Platform — User Journeys

Each journey below states the real system behaviour at each step: which function runs, which
table receives the row, which constraint or permission decides the outcome, and what the user
sees when something goes wrong. Function and table names refer to
`supabase/migrations/0001`–`0011` and the seeded configuration in `supabase/seed/`.

Facility context used throughout: one location (Wallingford, CT), `America/New_York`, open
09:30–20:30 daily, five cages (`CAGE-1` 50 ft with mound, `CAGE-2/3/4` 35 ft, `CAGE-5` 70 ft with
HitTrax), one HitTrax unit, a party room, a lobby with capacity 3, two pitching machines, two
event hosts, five coaches.

---

## Journey 1 — A parent books a private hitting lesson on a phone

**Persona.** Erin, mother of Kai (11). She is standing in a supermarket queue at 8:40 PM on a
Tuesday and wants a lesson this week.

### Narrative

Erin opens the booking site on her phone, taps Private Lessons, picks Private Hitting Lesson,
picks Kai, decides she wants Marcus Reyes specifically, sees that his next opening is Thursday at
4:30 PM, adds a pitching machine, signs the waiver on the phone screen with her fingertip, pays
$120, and gets a confirmation email with the code `7F2A9C41`. Total elapsed time: under three
minutes. Behind that, the system held a coach, a cage and a machine for ten minutes while she
finished, and would have released all three automatically if she had abandoned the tab.

### Steps

| # | What Erin does | What the system does |
| --- | --- | --- |
| 1 | Opens the site, taps **Private Lessons** | Lists `services` for the location where `is_active`, `is_public`, `is_online_bookable`, `deleted_at is null`, joined to `service_categories`. Private Lessons contains hitting, pitching, catching, fielding and semi-private |
| 2 | Taps **Private Hitting Lesson** | Reads the service row: 60-minute default, selectable 30 / 60 / 90 in 30-minute increments, $90.00 fixed, ages 6–18, 120-minute minimum lead time, 120-day horizon, Standard Lesson Policy, General Liability waiver required |
| 3 | Chooses a duration (60 min) | Constrained by `min_duration_minutes` 30 and `max_duration_minutes` 90, stepped by `duration_increment_minutes` 30. The chosen duration is passed to the availability search as `p_duration_minutes` |
| 4 | Selects **Kai** from her household | Participants come from `atd.participants` filtered by `household_id in (select atd.my_household_ids())` — the `participants_self` RLS policy. Kai is 11, inside the service's 6–18 band. A child outside the band is shown as ineligible before any search runs. Erin has no account yet on a first visit: `allow_guest_checkout` is true on both the service and the location, so she can proceed and the household is created at confirmation |
| 5 | Coach step: **First available** or a named coach | The `Coach` requirement has `assignment_mode = 'auto_with_choice'` and `required_qualification_ids = [hitting]`. `atd.candidate_resources` returns only coaches holding a live `hitting` qualification — Marcus Reyes, Dana Nakamura and Joe Brennan. Tyler Callahan and Sofia Vargas are never offered for this service. Coaches also need `customer_selectable = true` to appear by name |
| 6 | Picks **Marcus Reyes** | The choice becomes a pin: `p_pinned = {"<coach requirement id>": ["<Reyes resource id>"]}`, carried into `atd.plan_allocation` |
| 7 | Sees a date/time grid | `atd.find_slots(service, from, to, 60, p_pinned)` runs. It first calls `atd.expire_stale_holds()` so abandoned checkouts do not suppress real availability. For each date it resolves `atd.open_span` (09:30–20:30, `NULL` on a closed day), then walks the window in 15-minute steps (`slot_granularity_minutes`), keeping only instants between `now() + 120 min` and `now() + 120 days`. Each candidate instant is tested by `plan_allocation`, which must satisfy **both** requirements — a qualified, available, free coach **and** a free cage — or the instant is not offered |
| 8 | Notices there are no weekday-morning slots for most coaches | Coach availability is Mon–Fri 15:00–20:30 and Sat–Sun 09:30–16:00. Marcus Reyes alone also works Mon–Fri 09:30–13:00, so with Reyes pinned, weekday mornings do appear. `atd.coach_is_available` also enforces his 120-minute personal lead time and his cap of 8 sessions per day |
| 9 | Picks **Thursday 4:30 PM** | The UI calls `atd.create_hold(service, starts, ends, session_token, household, p_pinned)`. This re-plans the allocation and, if it succeeds, writes one `checkout_holds` row plus one `resource_reservations` row **per resource** — Reyes and a cage — with `status = 'hold'` and `expires_at = now() + 10 minutes` (`locations.settings.checkout_hold_minutes`). Those rows are inside the `is_blocking` set, so from this instant nobody else can take that coach or that cage |
| 10 | Add-ons page | `service_addon_links` for private hitting offers **Add HitTrax** ($30.00) and **Pitching Machine** ($15.00). Erin adds the machine. `pitching_machine` carries `adds_resource_type_id = machine`, `adds_resource_quantity = 1`, so the requirement set is extended and a machine (`MACHINE-1` or `MACHINE-2`) is reserved alongside the coach and cage. `plan_allocation` reads only the service's own requirement rows, so this expansion is composed by the server layer and the hold is re-acquired to cover all three resources — which is why add-on selection has to complete before the final hold. If both machines were already out at 4:30, the add-on is shown unavailable rather than sold and then apologised for |
| 11 | Answers the intake question | `service_questions` for this service has one optional booking-scope textarea, `focus` — "What would you like to work on?". The answer lands in `bookings.answers` |
| 12 | Reviews the price | See the breakdown below |
| 13 | Signs the waiver | `services.waiver_template_ids` names General Liability & Assumption of Risk. The system finds the current `waiver_versions` row (the one with `retired_at is null`) and checks for a matching `signed_waivers` row for Kai that is not revoked and not expired (`renewal_months = 12`). Kai has none, so the waiver body renders. Kai is 11, under the template's `requires_guardian_if_under` of 18, so Erin signs as `guardian`. The signature stores `signature_kind`, `ip_address`, `user_agent` and `signed_at`, pointing at the **version** id — so if ATD later publishes v2 with `requires_resignature`, this signature is correctly recognised as stale |
| 14 | Pays | An `orders` row is created with a client-supplied `idempotency_key` (unique), plus `order_items` carrying `price_breakdown`. Stripe returns a payment intent; the `payments` row's `stripe_payment_intent_id` is uniquely indexed, so a retry cannot create a second payment |
| 15 | Payment succeeds | `atd.confirm_hold(hold_id, household, [Kai])` runs in one transaction: it locks the hold `FOR UPDATE`, inserts the `bookings` row, then **reassigns the existing hold reservations to the booking** (`hold_id = null, booking_id = ..., status = 'confirmed', expires_at = null`). The reservations never stop blocking during the handover, so there is no window in which someone else could slip in |
| 16 | Sees the confirmation screen | `bookings.confirmation_code` is an 8-character uppercase hex code generated by default. `trg_booking_status_history` has already written the `draft → confirmed` transition to `booking_status_history` |
| 17 | Receives email, then SMS | `notification_rules` fires `booking.confirmed` (email, immediate) with the participant, service, date, time, coach, resource, confirmation code and balance, and schedules `booking.reminder` (SMS) for `booking_start − 1440 minutes`. `notifications.dedupe_key` is unique, so a retried job cannot send the reminder twice. If Kai's waiver had been missing, `waiver.missing` would also be scheduled for `booking_start − 2880 minutes` |

### Price breakdown Erin sees

Pricing rules are applied as an ordered pipeline in ascending `priority`, and the ordered result
is persisted to `order_items.price_breakdown` so the number is explainable later.

| Line | Rule | Priority | Effect | Amount |
| --- | --- | ---: | --- | ---: |
| Private Hitting Lesson, 60 min | service `base_price_cents` | — | base | $90.00 |
| Director premium — Reyes | `custom` scope, coach = Reyes | 30 | add $15.00 | $105.00 |
| Pitching Machine add-on | `service_addons.price_cents`, per booking | — | add | $15.00 |
| **Subtotal** | | | | **$120.00** |
| Tax | service `is_taxable = false`, no `tax_rate_id` | — | none | $0.00 |
| **Total** | | | | **$120.00** |

If Erin held a membership, the `Member discount` rule (scope `member`, priority 80,
`percent_off` 10) would apply *after* the director premium because of its higher priority
number, taking the lesson line from $105.00 to $94.50. Ordering is why the breakdown is stored
rather than recomputed: the same rules in a different order would produce a different number,
and the customer is entitled to see which one was used.

### What happens if the slot is taken mid-checkout

There are three distinct failures and they are handled differently.

**(a) The slot goes while Erin is still on the time-picker.** She taps 4:30 PM, but another
parent's hold landed on Marcus Reyes two seconds earlier. `atd.create_hold` calls
`plan_allocation`, which returns `NULL` because the pinned coach is not free, and raises:

```
errcode 23P01 (exclusion_violation)
hint: 'Another customer may have just taken this slot.'
```

The UI catches `23P01`, shows "That time was just booked — here are the next openings", and
re-runs `find_slots`. Erin has lost nothing: no order, no payment, no partial reservation.
Note that because the coach was *pinned*, the engine refuses rather than substituting Joe
Brennan. That is deliberate and commented in `plan_allocation`: handing a customer a different
coach without saying so is worse than showing no availability.

**(b) Erin has the hold and someone else tries for the same slot.** They lose, not Erin. Her
hold reservations are `is_blocking`, so the competing `create_hold` fails with `23P01` at the
`free_slot_index` check. The concurrency suite proves the general case: twelve simultaneous
checkouts for one HitTrax slot produce exactly one winner and exactly one blocking reservation.

**(c) Erin takes longer than ten minutes.** Her hold's `expires_at` passes. The next call to
`expire_stale_holds()` — which runs at the head of every allocation path, not only on a
background timer — flips her reservations to `released` and frees the slot. When she finally
pays, `confirm_hold` finds `h.expires_at < now()`, calls `release_hold`, and raises `23P01`
`hold ... expired`. The UI must then re-search and re-hold before charging. If the charge already
succeeded, the payment stands as an unapplied credit on the order and staff resolve it; the
system will not manufacture a booking on a dead hold.

**(d) Erin double-taps Pay.** `confirm_hold` checks `converted_booking_id` **first**, before it
checks whether the hold was released, and returns the existing booking id. Two taps, one
booking, one confirmation code. Verified by test 8b and by concurrency race 3, where six
simultaneous confirms of one hold return a single distinct booking id.

---

## Journey 2 — A parent books a HitTrax lesson (three resources blocked)

**Persona.** Dev, father of Priya (14), who wants measured exit velocity numbers.

### Narrative

The HitTrax Hitting Lesson looks like any other lesson in the catalogue, and that is the point:
it is not a special code path. It is a service whose cage requirement carries the attribute
predicate `{"has_hittrax": true}`, whose coach requirement carries the `hittrax` qualification
filter, and which adds a third requirement for the unit itself. Dev sees far fewer available
times than for a standard hitting lesson, because all three scarce things must line up.

### Steps

| # | Step | Behaviour |
| --- | --- | --- |
| 1 | Dev picks **HitTrax Hitting Lesson** | $120.00 fixed, 60-minute default (60–90 available), ages 8–18, minimum lead time **180 minutes** — longer than a standard lesson because the room needs setting up |
| 2 | Coach step | The `HitTrax Coach` requirement filters on the `hittrax` qualification. Only **Marcus Reyes** and **Dana Nakamura** hold it, so only those two are offered. Test 16 asserts exactly this |
| 3 | Cage | The `HitTrax Cage` requirement carries `required_attributes = {"has_hittrax": true}`, matched with the `@>` containment operator against `resources.attributes`. Only `CAGE-5` qualifies. No code and no configuration list mentions "Cage 5" — re-tagging a different cage would move the service automatically |
| 4 | Unit | The `HitTrax Unit` requirement pulls `HITTRAX-1` from the `hittrax` resource type. The unit is also modelled as a child of `CAGE-5` via `parent_resource_id`, which keeps the physical relationship visible in the admin UI, but the *blocking* comes from the explicit requirement, not from the parent link |
| 5 | Availability is sparse | Three singletons must all be free, and the effective envelope is **10 minutes before and 15 minutes after** (service `buffer_before` 5 + `setup` 5; requirement `buffer_after` 10 + service `cleanup` 5). A 4:00 PM lesson blocks `CAGE-5` and `HITTRAX-1` from 3:50 PM to 5:15 PM |
| 6 | Dev holds and pays | `create_hold` writes **three** `resource_reservations` rows in one transaction. If any one of the three cannot be secured, the whole hold aborts — there is no partial hold. Test 5 asserts the count is exactly 3 and that `HITTRAX-1` is among them |
| 7 | Side effect Dev never sees | While his lesson is held, the self-guided **HitTrax Rental** service is unbookable for the same window, because it requires the same cage and the same unit. Test 5 asserts that `plan_allocation` for the rental returns `NULL` 15 minutes into the lesson. One customer cannot be sold the machine that another customer is already using |
| 8 | Cancellation | `atd.cancel_booking` sets the reservations to `cancelled` with `released_at`, which drops them out of `is_blocking` immediately. The HitTrax rental becomes bookable again in the same transaction (test 10) |

### The equivalent lesson for administrators

Adding a second HitTrax unit and a second HitTrax-capable cage requires: two `resources` rows,
`{"has_hittrax": true}` on the new cage's attributes, and a `hittrax` qualification row for
whichever coaches are trained. The service, its price, its buffers and its booking flow are
untouched, and capacity doubles.

---

## Journey 3 — A parent registers two siblings for summer camp

**Persona.** Marisol, mother of Diego (12) and Luz (9). Summer Skills Camp, five days,
9:00 AM–1:00 PM, $299.00 per child, capacity 40, ages 7–13.

### Narrative

Marisol registers both children in one pass. The system charges the second child a sibling
discount, collects shirt sizes and lunch choices per child, takes medical information and an
authorised-pickup list once for the household, and requires two waivers rather than one. The
camp's four cages, three coaches and lobby check-in space are blocked **once per camp day**,
not once per child.

### Steps

| # | Step | Behaviour |
| --- | --- | --- |
| 1 | Marisol opens the camp page | A `programs` row built on the `summer-camp` service. It carries its own `capacity`, `min_age` / `max_age`, `age_as_of_date`, `registration_opens_at` / `registration_closes_at`, `price_cents`, `sibling_discount_percent`, `collects_shirt_size`, `collects_lunch_choice`, `check_in_window_minutes` (default 15), `pickup_window_minutes` (default 15) and `late_pickup_fee_cents`. `enrolled_count` and `waitlist_count` are trigger-maintained, so "6 spots left" is accurate at read time |
| 2 | She selects **Diego and Luz** | One `registrations` row per child. Each row records `age_at_registration`, `registration_kind` (`full_series`), a unique `confirmation_code`, and `price_cents` |
| 3 | Age is checked against the **camp date** | `atd.register_participant` computes `atd.age_on(dob, coalesce(age_as_of_date, starts_on))`. Luz turns 10 in July; if the camp runs in August the system judges her as 10, not as 9. A participant outside the band is refused with SQLSTATE `23514` and a message naming the age, the as-of date and the limit. Test 7d asserts a 6-year-old is refused from a 9–14 program |
| 4 | Capacity is claimed safely | `register_participant` takes `SELECT ... FOR UPDATE` on the program row, so two families racing for the last two seats serialise. The `programs_capacity_not_exceeded` CHECK constraint is the backstop if anything ever bypasses the function (test 7c). Concurrency race 2 confirms that twelve simultaneous registrations for a single remaining seat produce exactly one `registered` |
| 5 | Sibling discount | `programs.sibling_discount_percent` (facility default 10%, from `system_settings.sibling_discount_percent`) is applied by the pricing pipeline to the second and subsequent children in the same household on the same program, and lands in `registrations.discount_cents` and the order line's `price_breakdown` |
| 6 | Shirt sizes | The camp's `shirt_size` question is `applies_to = 'participant'`, required, a select of `YS / YM / YL / AS / AM / AL`. Answers write to both `registrations.shirt_size` (first-class, so the order form is one query) and `registrations.answers` |
| 7 | Lunch | The `lunch` question is required, participant-scoped, "Bringing lunch" or "Purchase lunch ($10/day)". It writes to `registrations.lunch_choice`. The program also carries `includes_lunch` for camps where lunch is bundled |
| 8 | Medical | Allergies and medical notes live on `atd.participants`, not on the registration, because they follow the child across every booking. They are readable only by the household and by holders of `participant.read_medical` — the redacting view `atd.participants_safe` returns `NULL` for both columns to front desk and coaches. `emergency_contacts` rows are per household with an optional `participant_id` and a `priority` ordering |
| 9 | Pickup list | `authorized_pickups` rows, per household with an optional per-child scope, carrying name, relationship, phone, an optional photo and notes. At the end of a camp day, `attendance_records.released_to` and `check_ins.released_to` record who actually collected the child |
| 10 | Two waivers | `summer-camp` has `waiver_template_ids = [general-liability, camp-medical]`. Camp Medical Authorization & Pickup has `audience = 'guardian'` and a 12-month renewal, so Marisol signs it as guardian for each child. `locations.settings.require_waiver_before_participation` is `true`; a child arriving unsigned cannot be checked in without a `waiver.override`, which only admins hold and which writes an audited `waiver_overrides` row with a mandatory reason |
| 11 | Deposit and balance | If the program sets `deposit_cents` and `balance_due_days_before`, the order records `deposit_required_cents` and `balance_due_at`, and the `balance.due` email fires 4320 minutes (3 days) before |
| 12 | The camp's resources | Separately, an admin runs `atd.materialize_program_sessions(program_id)`. For each `program_sessions` row it creates **one booking** and reserves 3 coaches, 4 cages and 1 lobby slot for that day, with a 30-minute lead-in and 45-minute trail-out. Forty registrations attach to those same bookings. Test 7 asserts the invariant directly: a clinic session reserves 4 resources, and after six registrations it still reserves 4 |
| 13 | Day one | Front desk or a coach checks each child in within the `check_in_window_minutes`. `attendance_records` carries one row per session per registration (unique index), with `state`, `checked_in_at`, `checked_out_at`, `released_to`, `marked_by` and a note. A missed day can be compensated with a `makeup_credits` row, redeemable against a later booking |

---

## Journey 4 — A parent joins a waitlist and is later offered a spot

**Persona.** Tom, father of Ada (10). The camp is full.

### Narrative

Tom asks for a seat, is told the camp is full, and joins the waitlist rather than being turned
away. Nine days later a family withdraws. Tom gets an SMS with a link, a two-hour window, and a
seat that is genuinely reserved for him while he decides — not a race against the other eleven
people on the list.

### Steps

| # | Step | Behaviour |
| --- | --- | --- |
| 1 | Tom registers Ada for a full camp | `atd.register_participant` computes `v_seats = capacity - enrolled_count`. It is zero, and `allow_waitlist` is true on the program, so instead of raising it writes **two** rows: a `waitlist_entries` row with `status = 'waiting'`, and a `registrations` row with `status = 'waitlisted'`. Test 7b asserts the seventh registration into a capacity-6 clinic comes back `waitlisted` and that `enrolled_count` stays at 6 |
| 2 | The counters update | The `trg_registration_counts` trigger recomputes `enrolled_count` from registrations in `registered`/`attended`, and `waitlist_count` from entries in `waiting`/`offered`. A waitlisted registration therefore never consumes a seat |
| 3 | Tom's position | `waitlist_entries` carries `priority` (default 100, lower is better) and `position`, plus `joined_at`. Waitlists can also target a service, a coach, a specific session, or an arbitrary window via `desired_from` / `desired_to` / `desired_weekdays` — so "any Saturday morning with Coach Nakamura" is a first-class waitlist, not just "this camp" |
| 4 | A seat opens | A family cancels; their registration moves out of `registered`, the trigger drops `enrolled_count`, and staff (or an automated sweep) run the offer for the highest-priority `waiting` entry |
| 5 | The offer is made | A `waitlist_offers` row is written with a unique `claim_token` (18 random bytes, hex), `offered_at`, `expires_at` — `now() + 120 minutes` by default from `system_settings.waitlist_claim_minutes` — and `offered_starts_at` / `offered_ends_at`. Crucially it may carry a `hold_id` pointing at a real `checkout_holds` row, which means the offered slot's resources are blocked for the duration of the claim window. Two offerees cannot claim the same opening, because the second one's allocation fails at the constraint |
| 6 | Tom is notified | The `waitlist.offer` rule sends the SMS template immediately: "a spot opened for {{program_name}} on {{date}}. Claim within {{claim_window}}: {{claim_link}}". Delivery respects the user's `communication_preferences` for the `waitlist` category and requires SMS consent recorded on the user row |
| 7 | Tom claims within the window | The claim link carries the `claim_token`. The offer is marked `outcome = 'claimed'` with `responded_at`; the waitlist entry moves to `claimed`/`converted`; Ada's registration flips from `waitlisted` to `registered`; the resulting registration or booking id is recorded on the offer (`resulting_registration_id` / `resulting_booking_id`); payment is taken against the order |
| 8 | Tom does not respond | At `expires_at` the offer is marked `expired`, any attached hold expires through the ordinary `expire_stale_holds()` path and frees the resources, and the next entry on the list is offered. Tom stays on the list unless he declined |
| 9 | Tom declines | `outcome = 'declined'`, the entry moves to `declined`, and the offer passes on. If the seat is filled another way first, the outstanding offer is closed as `superseded` — a distinct outcome, so reporting can tell "we were too slow" apart from "they said no" |

Because every offer is a row rather than an email side effect, the claim rate and the median
time-to-claim are directly reportable, and any dispute ("I never got the text") is answerable
from `waitlist_offers` joined to `notifications`.

---

## Journey 5 — Front desk handles a walk-in, takes payment, and checks in a household

**Persona.** Jamie Whitfield, front desk. It is 4:12 PM on a Saturday. A family walks in wanting
a cage for an hour, and a second family arrives for the 4:15 lesson they booked last week.

### Narrative

Jamie does the walk-in in one action rather than three, takes cash, and checks in both families
from the same screen. The system does not make her check availability separately from booking
it, because that gap is where double-bookings come from.

### Part A — The walk-in

| # | Step | Behaviour |
| --- | --- | --- |
| 1 | Jamie searches for the family | Trigram indexes on `users` and `households` names make partial-name lookup fast. No match, so she creates a `households` row with a `household_members` row marked `is_primary`, plus a `participants` row per child. She holds `customer.write` |
| 2 | She picks **Cage Rental — 35 ft**, 60 minutes | The service's `min_lead_minutes` is 30, but a walk-in is happening now. Front desk booking goes through `atd.create_booking(...)`, which does not consult `find_slots` and its lead-time window — it plans the allocation directly for the requested instant. This is intentional: the lead time exists to protect the online funnel, not to stop a paying customer standing at the counter |
| 3 | She picks the cage | The rental's single requirement is `{"length_ft": 35}` with `assignment_mode = 'customer_choice'`, so `CAGE-2`, `CAGE-3` and `CAGE-4` are the candidates and Jamie picks whichever is visibly free. She can pin it; if her pin is not actually free the booking is refused rather than silently moved |
| 4 | She books | `atd.create_booking` internally calls `create_hold` with a **5-minute** TTL and an internal session token, then immediately `confirm_hold`. Both run in one transaction, so the booking either exists complete with its reservations or does not exist at all. `source` is recorded as `walk_in`, and `created_by_user_id` is Jamie |
| 5 | The cage is not free | `plan_allocation` returns `NULL` and the call raises `23P01`. Jamie sees "CAGE-3 is not available 4:15–5:15" and the conflicting reservation. She holds `booking.reassign_resource`, so she can pick another cage. She does **not** hold `booking.override_conflict`, and the seeded setting `allow_front_desk_override` is `false` — forcing an overlap requires an admin, and it writes a `conflict_overrides` row with a mandatory reason plus an audit entry |
| 6 | She takes payment | Jamie holds `payment.collect` and `payment.discount`. A `payments` row is written with `method` (`cash`, `check`, `card`, `apple_pay`, …), `amount_cents`, `received_at`, and `taken_by_user_id = Jamie`. She does **not** hold `payment.refund` or `payment.price_override`; the seeded `allow_front_desk_refund` is `false` and agrees with the role bundle |
| 7 | Waiver | The rental requires the General Liability waiver. Jamie holds `waiver.send` and texts or emails the link, or hands over the counter tablet. She cannot bypass it — `waiver.override` is an admin key |
| 8 | Buffer | The rental's 5-minute trail-out means the cage is blocked until 5:20, so the next customer cannot be sold a 5:15 start. Test 4 asserts exactly this behaviour on a 60-minute booking |

### Part B — Checking in the booked household

| # | Step | Behaviour |
| --- | --- | --- |
| 1 | Jamie opens the arrivals list | Bookings for the location in a window around now. She is staff at this location, so the `bookings_self` policy admits her |
| 2 | She finds the household | She holds `checkin.manage` and `customer.read` |
| 3 | Waiver status shows per child | A green state means a current, unrevoked `signed_waivers` row exists against the **current** waiver version. If ATD published a new version requiring re-signature, previously-signed children show as needing signature — the check is a join on version id, not a boolean on the participant |
| 4 | Medical flags | Jamie's screen reads `atd.participants_safe`. She holds neither `participant.read_medical` nor the household relationship, so `allergies` and `medical_notes` come back `NULL`. She sees that a note exists and who to ask, not the note |
| 5 | She checks in the whole household in one action | A `check_ins` row per participant with `method = 'staff'`, `staff_user_id = Jamie`, `checked_in_at`; `booking_participants.checked_in_at` and `attendance`; and the booking moves to `checked_in`, which `trg_booking_status_history` records automatically. Self-service is available too — `check_ins.method` supports `kiosk_phone`, `kiosk_qr`, `kiosk_code` and `self`, and `system_settings.kiosk_enabled` is `true` |
| 6 | Later, the family wants 30 more minutes | Jamie holds `booking.extend`. Extending is `atd.reschedule_booking` with a later end time: it deletes the old reservations, re-plans, and inserts new ones — all in one transaction. If the cage is taken at 5:15 the extension is refused with `23P01` and the original booking survives untouched |
| 7 | Checkout | `check_ins.checked_out_at` and, for children, `released_to` matched against `authorized_pickups` |

---

## Journey 6 — Front desk handles a same-day cancellation and the policy engine's decision

**Persona.** Jamie again. It is 11:05 AM. A parent calls: their 5:00 PM hitting lesson has to be
cancelled because of a school event.

### Narrative

The outcome is not negotiated at the counter. The policy engine reads the booking's policy, finds
the tier that matches the hours remaining, and states the result. Jamie's job is to communicate
it, and if the family deserves an exception, to escalate to someone whose permissions allow it —
which leaves a record.

### Steps

| # | Step | Behaviour |
| --- | --- | --- |
| 1 | Jamie opens the booking | Private Hitting Lesson, today at 5:00 PM, $90.00 paid by card, Standard Lesson Policy (`services.cancellation_policy_id`) |
| 2 | The engine computes hours remaining | 5:00 PM minus 11:05 AM is **5.9 hours** |
| 3 | It selects the tier | Tiers for `action = 'cancel'` are evaluated by `min_hours_before` descending. 24 does not match (5.9 < 24). 12 does not match. **0 matches**: outcome `credit_forfeited`, `refund_percent` 0, `fee_cents` 0, `returns_package_credit` **false** |
| 4 | Jamie sees the decision, not a form | "Inside 12 hours — no refund, no package credit returned." Had the call come at 3:00 PM yesterday (26 hours), the 24-hour tier would have matched: `full_refund`, 100%, package credit returned. Between 12 and 24 hours: `partial_refund` at 50% |
| 5 | The alternative is offered | Reschedule tiers are separate. At 5.9 hours the ≥ 2 tier matches: `reschedule_fee`, **$15.00**, and the package credit **is** returned. So the parent's cheaper option is to move the lesson for $15 rather than cancel for $90. The UI surfaces both outcomes side by side, because a policy engine that only says "no" costs the business the rebooking |
| 6 | The parent chooses to cancel | Jamie holds `booking.cancel` — but **not** `booking.cancel_paid`. This booking has a payment against it, so cancelling it is an admin action. She escalates to Renee (location admin) or applies the cancellation as a no-refund cancel if the policy produces no money movement, per ATD's counter procedure |
| 7 | The cancellation executes | `atd.cancel_booking(booking, reason, actor)` sets every reservation in `confirmed`/`hold`/`tentative`/`in_progress` to `cancelled` with `released_at`, which removes them from `is_blocking` **immediately** — the coach and cage are back on sale in the same transaction (test 10). The booking moves to `cancelled` with `cancelled_at`, `cancelled_by_user_id` and `cancellation_reason`, and `trg_booking_status_history` records the transition |
| 8 | The applied tier is recorded | `bookings.policy_tier_applied_id` names the exact tier row used. Any refund written later carries `refunds.policy_tier_id` too. Six months on, "why did this family get 50%?" is answerable from data |
| 9 | Money movement | With `credit_forfeited` there is none: no `refunds` row, and no `package_credit_transactions` refund because `returns_package_credit` is false. Had it been the 24-hour tier and the lesson been paid from a package, a `+1` `refund` transaction would restore the credit and the trigger would rebuild `credits_remaining` from the ledger (test 19) |
| 10 | The goodwill exception | If Renee decides to credit the family anyway, she holds `payment.credit` and writes an `account_credit_transactions` grant with a reason. `households.account_credit_cents` is recomputed by trigger as the sum of the ledger (test 20). The exception is a ledger row with an actor and a reason, not an untracked adjustment |
| 11 | No-show instead | If the family simply does not arrive, staff mark the booking `no_show`. The `no_show` tier at ≥ 0 hours yields `credit_forfeited`, and `system_settings.no_show_fee_cents` ($25.00) is the configured fee |

---

## Journey 7 — A coach's week

**Persona.** Dana Nakamura, contractor, softball hitting and fielding, also HitTrax-certified.
Assignment priority 30, maximum 6 sessions per day, 180-minute personal lead time.

### 7.1 Sets availability

| # | Step | Behaviour |
| --- | --- | --- |
| 1 | Dana opens her availability | She holds `coach.availability_self` — the only config key a coach has |
| 2 | Her weekly pattern | `coach_availability_rules`: Mon–Fri 15:00–20:30, Sat–Sun 09:30–16:00, matching the seeded default for all coaches. Rules carry `effective_from` / `effective_to`, so a seasonal change is a new dated rule rather than an edit that rewrites history |
| 3 | She adds Tuesday mornings for the spring | A new rule with `day_of_week = 2`, 09:30–13:00, `effective_from` March 1 and `effective_to` June 15 |
| 4 | She is unavailable next Thursday afternoon | A `coach_date_availability` row for that date. `atd.coach_is_available` checks for **any** date row first, and if one exists the weekly rules are ignored entirely for that date. A date row therefore overrides in both directions — it can add availability on a normally-off day, or remove it |
| 5 | Effect on the customer | `atd.candidate_resources` calls `coach_is_available` for every coach slot, so Dana simply stops appearing in search results for those hours. There is no separate "publish" step, and no cached calendar to go stale |
| 6 | Her caps | `max_sessions_per_day = 6` and her 180-minute `min_lead_time_minutes` are enforced in the same function. Once she has six blocking reservations on a local date, she is unavailable for a seventh regardless of gaps in her schedule. A parent at 2:00 PM cannot book her for 4:00 PM |
| 7 | What she cannot do | Existing bookings are not affected by an availability change. Availability governs future *search*; it does not retroactively unschedule a committed lesson. Clearing an already-booked window is a time-off request or a staff reschedule |

### 7.2 Requests time off

| # | Step | Behaviour |
| --- | --- | --- |
| 1 | Dana requests June 10–17 | A `time_off_requests` row: `coach_id`, `starts_at`, `ends_at`, `reason`, `status = 'pending'` |
| 2 | Nothing is blocked yet | A pending request has no `reservation_id` and reserves nothing. She can still be booked during the request window until it is approved |
| 3 | Renee approves | She holds `coach.approve_time_off`. The request records `decided_by`, `decided_at`, `decision_note` and `status = 'approved'` |
| 4 | Approval materialises a block | A `resource_blocks` row with `kind = 'coach_time_off'`, `coach_id`, and a link back via `time_off_request_id`; and a `resource_reservations` row on **Dana's coach resource** for the window. The request's `reservation_id` points at it. Because a coach is a resource, her time off blocks her using exactly the same constraint that stops a cage being double-booked |
| 5 | Existing bookings in that window | The approval will fail with `23P01` if Dana already has confirmed lessons in the window — the exclusion constraint refuses to let a block overlap a booking. That is the correct order of operations: those lessons must be rescheduled or reassigned first, and the failure makes them visible rather than letting the block silently coexist with the commitments it contradicts |

### 7.3 Teaches, marks attendance, writes notes

| # | Step | Behaviour |
| --- | --- | --- |
| 1 | Dana opens her day | The `bookings_self` policy has a coach clause: she can read any booking that has a `resource_reservations` row on her coach resource. No separate assignment table exists — being reserved *is* being assigned |
| 2 | She sees the participant | Through `atd.participants_safe`. She does not hold `participant.read_medical`, so `allergies` and `medical_notes` are `NULL` on her screen. She sees that information exists; the director or the guardian supplies it |
| 3 | She reads the context | Staff notes with `visibility = 'coach'` or `'staff'` are visible to her; `admin_only` notes are not. She also sees the parent's answer to the `focus` intake question in `bookings.answers` |
| 4 | She checks the player in | She holds `checkin.manage`. `check_ins` row, `booking_participants.checked_in_at`, booking → `checked_in` → `in_progress` |
| 5 | She marks attendance | For a private lesson: `booking_participants.attendance` (`present`, `absent`, `late`, `excused`). For a program session: an `attendance_records` row, unique per `(program_session_id, registration_id)`, with `marked_by` |
| 6 | She writes a lesson note | `lesson_notes` with `body`, `focus_areas[]`, `metrics` (free-form JSONB — exit velocity, launch angle, whatever she chooses to type; the platform does not read these from HitTrax), and `shared_with_customer` |
| 7 | Sharing decides visibility | `lesson_notes_read` lets the authoring coach see her own notes always, lets `customer.read` holders see all notes, and lets the participant's household see a note **only** when `shared_with_customer` is true. So she can keep a candid coaching observation private and share the constructive summary |

### 7.4 Checks earnings

| # | Step | Behaviour |
| --- | --- | --- |
| 1 | Dana opens Earnings | She holds `comp.read_self`, the single money key a coach has |
| 2 | What she sees | `coach_earnings` rows scoped to her: per booking or program session, with `occurred_on`, `gross_revenue_cents`, `eligible_revenue_cents`, `earning_cents`, any `adjustment_cents` with a reason, and a status of `accrued` / `approved` / `paid` |
| 3 | Which rule applied | Compensation rules are matched by ascending `priority`. Her sessions fall to the facility default at priority 100: **60% of revenue**, `net_of_discounts = true`, `counts_no_show = false`. (Marcus Reyes has a coach-specific rule at priority 50 for 70%; camp work is an hourly rule at priority 40 for $45.00/hr.) The rule id is recorded on each earning row, so the arithmetic is checkable |
| 4 | Pay periods | Earnings attach to a `pay_periods` row which moves `open → locked → paid`. Once locked, the period is a stable statement |
| 5 | What she cannot see | She holds no `finance.reports`, no `payment.collect`, and no `comp.manage`. The `payments_self` policy therefore excludes her from the payments table entirely. She cannot see another coach's earnings, the compensation rules themselves, the household's card, or facility revenue. She can see a booking's `paid_cents` and `balance_due_cents`, because a coach should know whether the lesson in front of them is paid |

---

## Journey 8 — An administrator builds a brand new service type without a developer

**Persona.** Renee Okafor, location admin. She wants to launch a "Velocity Lab" — a 45-minute
pitching session on a mound cage with the wheel machine, taught by an arm-care or pitching coach,
priced at $110, with a required arm-health question and an optional video-review add-on.

This is the design goal of the whole platform, so it is worth stating plainly: **nothing in the
scheduling engine knows what a Velocity Lab is.** `atd.plan_allocation` reads
`service_resource_requirements` rows and matches attributes and qualifications. It contains no
reference to "party", "camp", "HitTrax" or "lesson". A new service is therefore rows, not code,
and requires no deployment.

### Step 1 — Category

Reuse `private_lessons`, or insert a `service_categories` row (`location_id`, `key`, `name`,
`color`, `sort_order`, `is_public`). Renee holds `service.manage`.

### Step 2 — The service row

| Field | Value | Why |
| --- | --- | --- |
| `slug`, `name` | `velocity-lab`, "Velocity Lab" | Slug is unique per location |
| `format` | `appointment` | Individually scheduled, as opposed to `group_session`, `program`, `event`, `party`, `rental` |
| `default_duration_minutes` | 45 | |
| `min_duration_minutes` / `max_duration_minutes` | 45 / 90 | CHECK constraints require min ≤ default ≤ max |
| `duration_increment_minutes` | 15 | Customer-selectable steps |
| `slot_granularity_minutes` | 15 | How finely the availability walk steps |
| `setup_minutes` / `cleanup_minutes` | 5 / 5 | Machine set-up and tear-down |
| `buffer_before_minutes` / `buffer_after_minutes` | 0 / 10 | Transition gap |
| `min_participants` / `max_participants` | 1 / 1 | |
| `min_age` / `max_age` | 11 / 18 | Age gate |
| `min_lead_minutes` | 180 | Machine needs staging |
| `max_horizon_days` | 120 | |
| `pricing_model` / `base_price_cents` | `fixed` / 11000 | Alternatives: `per_minute`, `per_participant`, `per_resource`, `per_coach_rate`, `tiered`, `package_only`, `free` |
| `cancellation_policy_id` | Standard Lesson Policy | |
| `waiver_template_ids` | `[general-liability]` | Array of template ids |
| `is_online_bookable` / `is_public` | false initially | Build it invisible, publish when verified |
| `requires_approval` | false | Set true if every booking should be staff-confirmed |
| `max_active_bookings_per_household` | (optional) | Throttle a scarce new offering |

The effective envelope this produces: lead-in `0 + 5 = 5` minutes, trail-out `10 + 5 = 15`
minutes, unless a requirement overrides them.

### Step 3 — Resource requirements, with attribute predicates and qualification filters

Three rows in `service_resource_requirements`. This is where the service acquires its physical
meaning.

| Label | `resource_type_id` | Qty | `required_attributes` | `required_qualification_ids` | `assignment_mode` | Resolves to |
| --- | --- | ---: | --- | --- | --- | --- |
| Coach | coach | 1 | `{}` | `[pitching, arm_care]` | `auto_with_choice` | Tyler Callahan only — he is the sole coach holding **both**; Sofia Vargas has `arm_care` but not `pitching` |
| Mound Cage | cage | 1 | `{"has_mound": true}` | — | `auto` | `CAGE-1` and `CAGE-5` |
| Wheel Machine | machine | 1 | `{"type": "wheel"}` | — | `auto` | `MACHINE-2` only |

Notes Renee needs to understand:

- **Attribute predicates are containment, not equality.** `required_attributes` is matched with
  `resources.attributes @> required_attributes`. `{"has_mound": true}` matches any resource whose
  attribute JSON contains that pair, regardless of what else it contains. An empty `{}` matches
  everything of that type.
- **Qualification filters are conjunctive.** `candidate_resources` requires the count of the
  coach's matching, unexpired qualifications to equal the length of
  `required_qualification_ids`. Listing two qualifications means "holds both", not "holds
  either". If Renee wants "pitching **or** arm care", she lists neither and instead uses
  `allowed_resource_ids` to name the two coaches, or she creates a new qualification key such as
  `velocity` and grants it to both.
- **Expiry is honoured.** A `coach_qualifications` row with `expires_on` in the past does not
  count, so a lapsed certification silently removes the coach from candidacy.
- **Allow / prefer / exclude lists override attributes.** A non-empty `allowed_resource_ids`
  restricts candidacy to that list; `preferred_resource_ids` sorts those first;
  `excluded_resource_ids` removes them. Useful for "always try Cage 5 first, never use Cage 2".
- **`assignment_mode` decides the UI.** `auto` (engine picks silently), `auto_with_choice`
  (customer may pin a coach), `customer_choice` (customer must pick, as on cage rentals),
  `admin_only` (staff assign, as on camps, clinics and party hosts).
- **Per-requirement buffers override the service.** Setting `buffer_after_minutes = 20` on the
  machine row alone means the machine stays blocked 20 minutes after the session while the coach
  is released after 10.
- **Offsets carve a sub-window.** `offset_start_minutes` and `offset_end_minutes` let a
  requirement occupy only part of the booking — a host who arrives 15 minutes in, or a machine
  needed only for the second half. The engine reserves `starts_at + offset_start` to
  `ends_at − offset_end` for that requirement alone.
- **`is_optional`.** An optional requirement that cannot be filled is skipped rather than
  failing the slot; a non-optional one that cannot be filled means no availability at that time.
- **Quantity above 1 draws distinct resources.** `plan_allocation` tracks what it has already
  taken within the plan, so `quantity = 2` never returns the same cage twice.

### Step 4 — Pricing rules

Insert `pricing_rules` rows against the standard rate card. Conditions left NULL mean "do not
care"; available conditions are day-of-week, time-of-day window, effective date range, coach,
resource, membership plan, duration range, participant range, and days-before (for early-bird or
late-registration pricing).

| Name | Scope | Priority | Condition | Effect |
| --- | --- | ---: | --- | --- |
| Velocity Lab off-peak | `off_peak` | 10 | Mon–Fri 09:30–16:00 | `set` 9500 |
| Velocity Lab early bird | `promo` | 40 | `min_days_before = 14` | `percent_off` 10 |
| Member discount | `member` | 80 | (already exists, `service_id` NULL so it applies to everything) | `percent_off` 10 |

Effects available: `set`, `add`, `multiply`, `percent_off`, `amount_off`, `set_per_minute`,
`set_per_participant`. Rules compose in ascending priority order and the ordered result is
written to `order_items.price_breakdown`, so a customer question about a price is answered from
the order, not reconstructed.

### Step 5 — Intake questions

Insert `service_questions` rows. Each has a `key` (unique per service), a `label`, optional
`help_text`, an `input_type` from `text / textarea / number / select / multiselect / boolean /
date / phone / email`, an `options` JSONB array for select types, `is_required`, a `sort_order`,
`is_sensitive`, and `applies_to` — `booking` (asked once, stored in `bookings.answers`) or
`participant` (asked per person, stored in `booking_participants.answers`).

For the Velocity Lab: a required participant-scoped textarea `arm_status`, "Current arm soreness
or injury?", marked `is_sensitive` so it is treated like medical data by read policies.

### Step 6 — Add-ons

Either link an existing `service_addons` row via `service_addon_links`, or create a new one.
An add-on has a `price_cents` charged `per booking / participant / hour`, a `max_quantity`, and
optionally extends the booking: `adds_resource_type_id` + `adds_resource_quantity` +
`adds_required_attributes` pull additional resources when selected, and `adds_minutes` extends
the duration.

For "Video Review" — a $25.00 per-booking add-on with no resource impact. Link it with
`is_default = false`, `is_required = false`, `sort_order = 1`.

One caveat worth knowing, visible in the seeded data: the **Add HitTrax** add-on on the private
hitting lesson adds a HitTrax *unit* requirement but does not narrow the lesson's cage
requirement to a HitTrax-capable cage. If an add-on's resource is only usable in a specific room,
either set `adds_required_attributes` accordingly on the add-on or model the combination as its
own service — which is what `hittrax-lesson` does.

### Step 7 — Verify before publishing

Renee does not deploy anything; she tests with the same functions the customer flow uses.

1. `select * from atd.candidate_resources('<coach requirement id>', <start>, <end>);`
   — confirms only Tyler Callahan is offered, and only inside his availability.
2. `select atd.plan_allocation('<service id>', <start>, <end>);`
   — returns the JSONB plan (`requirement_id`, `label`, `resource_ids`, buffers, offsets), or
   `NULL` if the combination is unsatisfiable.
3. `select * from atd.find_slots('<service id>', <from date>, <to date>);`
   — confirms real availability appears, sits inside 09:30–20:30, and respects the 180-minute
   lead time.

If step 2 returns `NULL` everywhere, the usual causes are: a qualification list that no single
coach satisfies, an attribute predicate that matches no resource, a quantity larger than the
number of matching resources, or a coach availability window that never covers the requested
hours.

### Step 8 — Publish

Set `is_active = true`, `is_public = true`, `is_online_bookable = true`. The service appears in
the catalogue immediately. No release, no migration, no engineer.

### Step 9 — Retire, later

Set `is_active = false` to remove it from sale while keeping history intact, or set `deleted_at`
for a soft delete. Existing bookings keep working — `bookings.service_id` is `on delete restrict`
specifically so a live service cannot be erased out from under them.

---

## Journey 9 — An administrator creates a recurring team practice series and resolves a conflict

**Persona.** Renee. The Wallingford Wolves 12U travel team wants Tuesdays, 6:00–8:00 PM, from
March 3 to June 16.

### Narrative

Renee defines the pattern, and the system tells her — before writing anything — exactly which of
the sixteen Tuesdays will work and why the others will not. She resolves the two problem dates
and then commits the series.

### Steps

| # | Step | Behaviour |
| --- | --- | --- |
| 1 | She picks **Team Practice Rental** | 3 cages + the lobby, 120-minute default (60–240 available), `per_minute` at $3.00/min (the Travel Team rate card overrides to $2.25/min via the priority-20 rule), 720-minute lead time, 30-minute granularity, Standard Lesson Policy. Effective envelope: 10 minutes before, 25 minutes after |
| 2 | She enters the pattern | Weekly, Tuesdays, 18:00 local, 120 minutes, March 3 → June 16 |
| 3 | She previews | `atd.validate_recurrence(service, start_date, end_date, weekdays, start_time, duration, interval, pinned, skip_dates)` returns **one row per occurrence** with `occurrence_date`, `starts_at`, `ends_at`, `is_valid`, `reason` and `plan`. Nothing is written. This is what the admin screen renders |
| 4 | Local time is preserved across DST | Occurrences are built as `(date + local_time) at time zone 'America/New_York'`, so every Tuesday is 6:00 PM local even though the underlying UTC instant shifts in March. Test 13 asserts both halves: the local time stays constant, and the UTC instant genuinely moves — proving the system is not storing a fixed offset |
| 5 | The preview shows three problems | The three possible `reason` values are `Facility closed` (the date resolves to no open span — a holiday or a `date_overrides` closure), `Outside operating hours` (the requested window does not fit inside 09:30–20:30), and `Required resources unavailable` (`plan_allocation` returned `NULL`) |
| 6 | April 14 says **Required resources unavailable** | The team needs 3 of 5 cages. That evening a birthday party holds 2 cages and two private lessons hold 2 more, so only one is free. The preview names the conflicting reservations |
| 7 | Options for April 14 | (a) **Skip it** — add the date to `skip_dates` on the `recurring_series` row; the series simply has no occurrence that week. (b) **Move it** — create a one-off booking at a different time or on a different day, linked to the series via `bookings.series_id`. (c) **Clear it** — reschedule the two private lessons with `atd.reschedule_booking`, which revalidates and rolls back cleanly if the new times do not work, then re-run the preview. (d) **Override** — force it, which requires `booking.override_conflict` (admins only), writes a `conflict_overrides` row with `conflicting_reservation_ids`, a `conflict_summary` and a mandatory `reason`, plus an audit entry. Overrides are a reportable metric with a target of ≤ 5/month |
| 8 | May 26 says **Facility closed** | A `date_overrides` row. Renee either accepts the skip or, if the closure was provisional, edits the override — she holds neither `location.manage` nor `settings.manage`, so changing the standing operating-hours template is a `super_admin` action, but single-date overrides sit under `schedule.block` which she does hold |
| 9 | She commits | A `recurring_series` header stores `freq = 'weekly'`, `interval_count`, `by_weekday`, `start_date` / `end_date`, `start_time_local`, `duration_minutes`, `timezone` and `skip_dates`. Each valid occurrence becomes a booking (via `create_booking` or the program materialisation path) carrying `series_id`, and each booking's reservations are written under the exclusion constraint. If any occurrence fails at write time — because the world changed between preview and commit — that occurrence fails loudly rather than being silently dropped |
| 10 | One week changes later | A single occurrence is an ordinary booking. `reschedule_booking` moves just that week; `cancel_booking` cancels just that week; the rest of the series is untouched because there is no shared row to corrupt |
| 11 | Billing | `per_minute` at the travel-team rate, invoiced rather than card-charged: the team is a `customer_organizations` row with `billing_terms_days`, an optional `purchase_order_ref`, `is_tax_exempt`, and `custom_rate_card_id` pointing at the Travel Team rate card. `invoices` rows carry `number`, `due_on`, `terms` and a status of `draft / sent / partially_paid / paid / void / past_due` |

---

## Journey 10 — An administrator handles an emergency closure

**Persona.** Renee, 6:40 AM on a Thursday in February. Fifteen inches of snow. The facility will
not open today.

### Narrative

She closes the building in one action, which makes the entire day unbookable for every service.
She then works the affected bookings — the system does not cancel them for her, deliberately, so
that every customer contact is a decision someone made.

### Steps

| # | Step | Behaviour |
| --- | --- | --- |
| 1 | She declares the closure | She holds `schedule.block`. A `resource_blocks` row with `kind = 'closure'`, `applies_to_whole_location = true`, `title` "Snow closure", `starts_at` and `ends_at` covering the whole day, and `created_by` |
| 2 | Everything becomes unbookable instantly | `atd.location_is_blocked` is the **first** test inside `atd.plan_allocation`. When it returns true, the function returns `NULL` before evaluating a single requirement, so every service — lessons, rentals, parties, camps — reports no availability for that window. One row, not one row per resource. Test 11 asserts both the block and its removal |
| 3 | Alternative for a planned closure | For a known future closure (a holiday, a floor refinish), a `date_overrides` row with `is_closed = true` is the better instrument: `atd.open_span` returns `NULL` for that date, `find_slots` produces nothing, and `validate_recurrence` reports `Facility closed` with that exact reason. The seeded overrides are Christmas Day and Thanksgiving 2026. `date_overrides` can also shorten a day rather than close it, by setting `opens_at` / `closes_at` |
| 4 | Existing bookings are **not** auto-cancelled | This is by design and worth stating explicitly: `location_is_blocked` prevents *new* allocations; it does not touch reservations that already exist. Today's bookings still hold their resources until someone acts on them. The alternative — cascading automatic cancellation with automatic refunds triggered by an operational mistake — is a worse failure mode than a short list of bookings to work through |
| 5 | She works the list | The affected bookings are those whose window overlaps the block. For each, `atd.cancel_booking(booking, 'Snow closure — facility closed', actor)` releases the reservations immediately and records the reason. `trg_booking_status_history` logs every transition with its reason |
| 6 | Money | A closure is the facility's fault, so the policy tiers are not the right answer — they would forfeit credit for a same-day cancellation. Renee holds `payment.credit` and `payment.refund`, and issues either an `account_credit_transactions` grant (the seeded closure SMS promises credit: "Your {{service_name}} at {{time}} is cancelled and credited") or a `refunds` row against the original payment. Package-paid lessons get a `+1` `package_credit_transactions` refund, and the trigger rebuilds `credits_remaining` from the ledger. Every one of these is a ledger row with an actor and a reason |
| 7 | Customers are told | The `location.closure` notification rule fires the SMS template immediately: "ATD Baseball is closed {{date}} ({{reason}}). Your {{service_name}} at {{time}} is cancelled and credited." Delivery honours `communication_preferences` and requires recorded SMS consent; families without SMS consent get the email path |
| 8 | Camps and programs | A camp day inside the closure is a `program_sessions` row: set `is_cancelled = true` with a `cancellation_reason`, cancel the session's booking to free the four cages and three coaches, and issue `makeup_credits` rows to each affected registration rather than refunding a multi-day program |
| 9 | Coaches | Coach earnings for cancelled sessions do not accrue: the default compensation rule has `counts_no_show = false`, and a cancelled booking produces no `coach_earnings` row. Salaried arrangements are handled with an `adjustment_cents` entry carrying an `adjustment_reason` |
| 10 | The roads clear at 3 PM | Renee sets `cancelled_at` on the `resource_blocks` row. `location_is_blocked` filters on `cancelled_at is null`, so availability returns instantly for the remaining hours (test 11 asserts this). If she had used a `date_overrides` row instead, she would edit or delete that row, or change it from `is_closed` to a shortened `opens_at` / `closes_at` |
| 11 | Afterwards | The block row, the cancellations with reasons, the credits with actors and the notifications all remain queryable. `audit.entries` is append-only and enforced by trigger (test 23), so the record of what was decided at 6:40 AM cannot be edited later |

### Adjacent case: a single cage goes down

The same mechanism at smaller scope. A torn net in `CAGE-3` is a `resource_blocks` row with
`kind = 'maintenance'` and a `resource_reservations` row on that cage alone. Everything that
requires a 35 ft cage now has three candidates instead of four; the Full Facility Buyout, which
requires all five, becomes unbookable for the window; nothing else changes. Alternatively, setting
`resources.status = 'maintenance'` removes the cage from `candidate_resources` entirely for an
open-ended repair, without needing a time-bounded block.
