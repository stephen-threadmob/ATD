# ATD Baseball Company — Administrator Guide

For the owner (Anthony Delgado, super administrator) and the location administrator
(Renee Okafor). This is the "how do I run it" companion to the design documents.

**Read these first, once:**

| Document | What it gives you |
| --- | --- |
| [`PRD.md`](./PRD.md) | Why the platform works the way it does, and every business rule in one place |
| [`ROLES_AND_PERMISSIONS.md`](./ROLES_AND_PERMISSIONS.md) | Who can do what, and why the front desk cannot refund |
| [`USER_JOURNEYS.md`](./USER_JOURNEYS.md) | Ten end-to-end walkthroughs, customer and staff |
| [`DATA_DICTIONARY.md`](./DATA_DICTIONARY.md) / [`ERD.md`](./ERD.md) | Every table and column, for when you need the exact field name |

This guide does not repeat those. It tells you which screen to open, in what order, and
what will happen when you press the button.

**Your facility, as configured today**

| | |
| --- | --- |
| Organisation | ATD Baseball Company LLC |
| Location | ATD Baseball — Training Center, 1200 Diamond Way, Wallingford, CT 06492 |
| Time zone | America/New_York (all times you see are Wallingford local time) |
| Hours | 9:30 AM – 8:30 PM, seven days a week |
| Cages | CAGE-1 (50 ft, mound), CAGE-2 / CAGE-3 / CAGE-4 (35 ft), CAGE-5 (70 ft, HitTrax, mound) |
| Other spaces | PARTY-1 (party room, seats 24), LOBBY (holds 3 activities at once) |
| Equipment | HITTRAX-1 (lives in Cage 5), MACHINE-1 Iron Mike (arm), MACHINE-2 Hack Attack (wheel) |
| Event hosts | HOST-1, HOST-2 |
| Coaches | Marcus Reyes, Tyler Callahan, Dana Nakamura, Joe Brennan, Sofia Vargas |

---

## Contents

1. [Routines: daily, weekly, seasonal](#1-routines-daily-weekly-seasonal)
2. [Hours, holidays, early closes and emergency closures](#2-hours-holidays-early-closes-and-emergency-closures)
3. [Resources and what attributes mean](#3-resources-and-what-attributes-mean)
4. [Adding and managing a coach](#4-adding-and-managing-a-coach)
5. [Creating a new service with no developer](#5-creating-a-new-service-with-no-developer)
6. [Camps, clinics and programs](#6-camps-clinics-and-programs)
7. [Pricing: how the rule pipeline composes](#7-pricing-how-the-rule-pipeline-composes)
8. [Packages, memberships and the credit ledger](#8-packages-memberships-and-the-credit-ledger)
9. [Cancellation policy tiers](#9-cancellation-policy-tiers)
10. [Waivers](#10-waivers)
11. [Reports](#11-reports)
12. [The audit log](#12-the-audit-log)

---

## 1. Routines: daily, weekly, seasonal

### 1.1 Every morning (5 minutes)

1. Open **Dashboard** at `/admin`. Read the four tiles across the top: revenue today,
   bookings today, outstanding balances, no-show rate over the last 30 days.
2. Look at **Utilisation today**. The two bars are cage-minutes and coach-minutes
   committed against the minutes actually available inside opening hours. A cage bar
   under about 30 percent on a weekday evening is worth a conversation; a coach bar
   near 100 percent means you are about to start turning people away.
3. Open **Master calendar** at `/admin/calendar`. Scan the day for red or amber blocks —
   maintenance, coach time off, closures. Confirm nothing unexpected has appeared.
4. Glance at the front-desk board at `/desk`. If **Missing waivers** or **Unpaid balances**
   is not zero, the desk has work to do before those families arrive.

### 1.2 Every evening (2 minutes)

1. `/desk` — confirm **Not checked in** is empty or explained. Anything still sitting
   there at close is either a no-show that was never marked or a data problem.
2. `/admin/payments` — check today's takings against the till. Every payment row shows
   who took it (`taken_by`), the method, and the last four digits for cards.

### 1.3 Every week

| Day | Task | Screen |
| --- | --- | --- |
| Monday | Review last week's no-shows and cancellations; decide whether any need a goodwill credit | `/admin/reports`, `/admin/bookings?status=no_show` |
| Monday | Check coach load for the coming week — nobody should be at their daily cap every day | `/admin/coaches` |
| Wednesday | Review programs filling below 50 percent with under two weeks to start; decide to promote or cancel | `/admin/programs` |
| Friday | Confirm next week's holidays or early closes are entered as date overrides | `/admin/settings` |
| Friday | Review packages expiring in the next 60 days (dashboard card) and have the desk call those households | `/admin` |

### 1.4 Every month

1. Reconcile payments and refunds for the month at `/admin/payments`.
2. Review the resource load chart at `/admin/reports`. If one 35 ft cage is consistently
   at half the load of the others, check its attributes — a missing or mistyped attribute
   quietly removes a cage from candidacy for services that filter on it.
3. Review coach compensation and close the pay period.
4. Skim the audit log for overrides (see [§12](#12-the-audit-log)).

### 1.5 Seasonal

| When | Task |
| --- | --- |
| 8–10 weeks before a school break | Build the camp or clinic as a program, publish it, materialise sessions ([§6](#6-camps-clinics-and-programs)) |
| Start of a season | Review coach weekly availability; contractors' hours usually change |
| Start of a season | Review peak / off-peak pricing windows against actual demand ([§7](#7-pricing-how-the-rule-pipeline-composes)) |
| Annually | Review waiver wording with counsel; publish a new version if it changed ([§10](#10-waivers)) |
| Annually | Retire services nobody books — set **Active** off rather than deleting them |

---

## 2. Hours, holidays, early closes and emergency closures

Everything about when the building is open lives in one place and every other screen
obeys it. If the facility is not open, the availability engine returns no times at all —
there is no way for a customer to book into a closed day.

### 2.1 Viewing what is configured

Open **Settings** at `/admin/settings`. Four cards:

- **Location** — name, time zone, address, contact details.
- **Booking guardrails** — the operational settings listed in [§2.5](#25-the-guardrail-settings).
- **Operating hours** — the standard weekly pattern (currently 9:30 AM – 8:30 PM, every day).
- **Date overrides** — holidays, early closes and special hours for specific dates.

### 2.2 Changing the standard weekly hours

Standard hours are stored as an **hours set** — a named group of seven day rows. The one
in use is called "Standard Hours" and is marked as the default.

1. Decide whether the change is permanent or seasonal.
2. For a permanent change, edit the day rows in the existing "Standard Hours" set.
3. For a seasonal change (say, summer hours from 8:00 AM), create a **second hours set**
   with an effective-from and effective-to date and a higher priority number. Between
   those dates the higher-priority set wins; outside them the default applies again.
   You never have to remember to change it back.

**What happens to bookings already in the closed part of the day?** Nothing automatically.
Shrinking your hours does not cancel anything. The engine will stop offering *new* times
outside the new window, but an existing 8:00 PM lesson on a day you just moved close to
7:30 PM stays on the calendar. Find those bookings at `/admin/bookings` and move or cancel
them deliberately.

### 2.3 Adding a holiday or an early close

A **date override** replaces the weekly pattern for one calendar date.

| Field | For a full closure | For an early close |
| --- | --- | --- |
| Date | The date | The date |
| Closed | Yes | No |
| Opens at | (ignored) | e.g. 9:30 AM |
| Closes at | (ignored) | e.g. 2:00 PM |
| Label | e.g. "Christmas Day" | e.g. "Christmas Eve — early close" |

Two are already seeded: 25 December 2026 (Christmas Day) and 26 November 2026
(Thanksgiving), both full closures.

**Do this weeks ahead.** A date override entered in advance means the day never becomes
bookable in the first place, and you never have to phone anyone.

### 2.4 Emergency closure (snow, burst pipe, power cut)

This is different from a date override because there are already families booked. Use a
**whole-facility block**, which is created from the calendar or the resources screen and
recorded as kind `closure` or `weather`.

1. Open `/admin/calendar` and choose the affected day.
2. Create a block covering the affected window. Set it to apply to the **whole facility**
   rather than picking resources one at a time — a whole-facility block covers everything
   including resources added later, without needing a row per cage.
3. The system checks who is already inside that window. If anyone is, it **refuses and
   shows you the list**: confirmation code, service, household name, time, cage. Nothing
   is blocked yet.
4. To proceed you must (a) hold the conflict-override permission and (b) type a written
   reason of at least five characters. Both are required. The reason is stored.
5. On confirmation the block is created, an override record is written per affected
   resource, and an audit entry with action `booking.override_conflict` records who did
   it, when, why, and the full list of affected bookings.

**What happens to the affected bookings?** They are **not cancelled automatically**, and
that is deliberate — a closure records your intent, and a human decides what each family
gets. Your follow-up:

1. Open `/admin/bookings` filtered to that date.
2. For each booking, decide: move it, cancel it with a full refund, or convert it to
   account credit. See [§9](#9-cancellation-policy-tiers) for what the policy would do by
   default and how to override it.
3. Cancelling from `/admin/bookings` frees the cage and coach immediately and offers the
   slot to up to three people on the waitlist.
4. Send the closure notice. The `Facility Closure` SMS template already exists and reads:
   *"ATD Baseball is closed {date} ({reason}). Your {service} at {time} is cancelled and
   credited."*

**A note on the mechanics, because it explains an oddity you may see.** Blocks become
reservations in the same table bookings use, so "cage under repair" and "cage booked" are
the same kind of thing to the scheduler and cannot overlap. When you override a conflict,
the block is recorded but the system cannot *also* hold a cage that a live booking is
still sitting in. Those cages come back in the response as "covered on paper but not
held". Once you cancel or move the conflicting booking, the cage is genuinely free.

### 2.5 The guardrail settings

These live in Settings and change behaviour everywhere.

| Setting | Seeded value | What it controls |
| --- | --- | --- |
| `checkout_hold_minutes` | 10 | How long a slot is held while a customer is on the payment screen |
| `waitlist_claim_minutes` | 120 | How long a waitlist offer stays claimable |
| `no_show_fee_cents` | 2500 | The default no-show fee ($25.00) |
| `allow_front_desk_override` | false | Whether front desk may override a price or a conflict |
| `allow_front_desk_refund` | false | Whether front desk may issue refunds |
| `sibling_discount_percent` | 10 | Automatic discount when siblings are booked together |
| `reminder_hours_before` | 24 | How far ahead the reminder message goes out |
| `kiosk_enabled` | true | Whether the lobby check-in screen at `/kiosk` is live |

Raising `checkout_hold_minutes` reduces "the slot vanished while I was typing my card
number" complaints but takes popular evening slots off the market for longer. Ten minutes
is a sensible balance; go to fifteen only if you see real drop-off at checkout.

---

## 3. Resources and what attributes mean

A **resource** is anything the facility can commit to one booking at a time: a cage, the
party room, a machine, an event host, and — importantly — a coach. Coaches are resources
too, which is why one rule ("nothing can be in two places at once") covers people and
places alike.

Open **Resources** at `/admin/resources`.

### 3.1 Adding a cage, room, machine or other resource

1. Press **New resource**.
2. Fill in:

| Field | Guidance |
| --- | --- |
| Code | Short and unique, in capitals: `CAGE-6`, `MACHINE-3`. This is what staff see on the board. |
| Name | What a human calls it: "Cage 6 — 35 ft" |
| Type | Batting Cage, HitTrax System, Party / Event Space, Lobby, Pitching Machine, Event Host, Coach, Whole Facility |
| Status | Active, or Maintenance / Retired to take it out of service without deleting it |
| Capacity | How many bookings can occupy it at once. **1** for a cage. The lobby is **3**. |
| Sort order | Lower numbers appear first on the calendar and the board |
| Physically inside | Optional. The HitTrax unit is set to sit inside Cage 5, which keeps the relationship visible |
| Reserving this also reserves | Optional "kit" list. Booking this resource commits the ones you name here too |

3. Fill in the **Attributes** — see below. This is the part that matters.
4. Save. The resource appears on `/admin/calendar` and `/desk/resources` immediately.

### 3.2 What attributes are

Attributes are a small list of labelled facts about a resource. They are the only thing
that tells the system a 70 ft cage is different from a 35 ft cage. Services do not name
cages; they describe the cage they need, and the system finds one.

The attributes in use at ATD today:

| Attribute | Type | Meaning | Values in use |
| --- | --- | --- | --- |
| `length_ft` | number | Cage length in feet | 35, 50, 70 |
| `has_hittrax` | true/false | The HitTrax simulator is installed here | true on CAGE-5 only |
| `has_mound` | true/false | There is a pitching mound | true on CAGE-1 and CAGE-5 |
| `turf` | text | Surface grade | `pro`, `standard` |
| `supports_pitching` | true/false | Safe for live pitching | true on CAGE-1 and CAGE-5 |
| `seats` | number | Seating capacity (party room) | 24 |
| `type` | text | Machine style | `arm` (Iron Mike), `wheel` (Hack Attack) |

Current values:

| Resource | length_ft | has_hittrax | has_mound | turf | supports_pitching |
| --- | ---: | --- | --- | --- | --- |
| CAGE-1 — 50 ft | 50 | false | **true** | pro | true |
| CAGE-2 — 35 ft | 35 | false | false | standard | false |
| CAGE-3 — 35 ft | 35 | false | false | standard | false |
| CAGE-4 — 35 ft | 35 | false | false | standard | false |
| CAGE-5 — 70 ft | 70 | **true** | **true** | pro | true |

### 3.3 Three rules about attributes you must know

**Rule 1 — the type must match exactly.** The attribute editor makes you choose whether a
value is a number, a true/false, or text. This is not cosmetic. A cage saved with
`length_ft` as the *text* "50" will never match a service asking for the *number* 50. The
symptom is silent: the service simply shows no availability. If a new cage never gets
booked, check its attribute types first.

**Rule 2 — matching is "contains", not "equals".** A service asking for
`has_mound: true` matches any cage whose attributes *include* that fact, no matter what
else the cage has. It does not have to be an exact list. That is why a request for a
mound cage picks up both CAGE-1 and CAGE-5 even though they differ in every other respect.

**Rule 3 — an empty attribute list matches everything of that type.** A requirement for
"a cage" with no attributes will happily take any of the five.

### 3.4 Worked examples: how attributes decide which cage gets used

| Service | The cage requirement says | Cages that qualify | Why |
| --- | --- | --- | --- |
| Private Hitting Lesson | (nothing) | CAGE-1 … CAGE-5 | Any cage will do; the engine spreads load |
| Private Pitching Lesson | `has_mound: true` | CAGE-1, CAGE-5 | Only those two have a mound |
| HitTrax Hitting Lesson | `has_hittrax: true` | CAGE-5 | Only Cage 5 has the simulator |
| Cage Rental — 35 ft | `length_ft: 35` | CAGE-2, CAGE-3, CAGE-4 | The number must match exactly |
| Cage Rental — 50 ft w/ Mound | `length_ft: 50` | CAGE-1 | Only one 50 ft cage exists |

Notice what this buys you. Nothing in the software knows that Cage 5 is the HitTrax cage.
If you move the HitTrax unit into Cage 1 tomorrow, you change two attribute values and
every HitTrax service follows it — no developer, no release.

**A worked change.** Suppose you turf CAGE-4 to pro grade and add a mound.

1. Open `/admin/resources`, edit CAGE-4.
2. Change `turf` from `standard` to `pro`; change `has_mound` from false to true; change
   `supports_pitching` to true.
3. Save.
4. Private Pitching Lesson now has three candidate cages instead of two. Evening
   availability for pitching roughly increases by half, immediately, with no other change.

### 3.5 Taking a resource out of service

Two different tools, for two different situations:

| Situation | Tool | Effect |
| --- | --- | --- |
| Netting torn, back Thursday | **Block** the resource for a window | The cage vanishes from availability for exactly that window; existing bookings inside it are flagged as conflicts before the block is created |
| Cage permanently removed | Set **Status** to Retired | Never offered again; history and past bookings stay intact |

To block: open `/admin/resources`, find the resource, choose **Block**, give it a title,
a start and an end, and an optional note. A block becomes a real reservation, so the
resource disappears from availability everywhere at once — the calendar, the public
booking page, the walk-in screen and the recurrence preview all agree instantly.

---

## 4. Adding and managing a coach

Open **Coaches** at `/admin/coaches` to see the roster with each coach's qualifications
and their booked load for the next seven days.

### 4.1 Adding a coach — the order matters

A coach is three linked things: a staff **user account** (so they can sign in), a
**resource row** (so the calendar can reserve them), and a **coach profile** (so the
public site can show them). Create them in this order.

1. **Create the staff user.** Name, email, phone. Grant them the **Coach** role at this
   location. See `ROLES_AND_PERMISSIONS.md` §3 for what that role includes.
2. **Create the coach resource.** Type: Coach. Code in the house style: `COACH-XX` using
   initials. Capacity 1. Set **bookable directly** to off — customers book a *lesson*,
   never a coach on their own.
3. **Create the coach profile** and link it to both. Fields:

| Field | Guidance |
| --- | --- |
| Display name | As it appears to customers |
| Headline | One line: "Pitching Coordinator", "Softball Hitting & Fielding" |
| Bio | Two or three sentences for the public coach page at `/coaches` |
| Sports | Baseball, Softball, or Both |
| Employment type | Employee, Contractor, or Volunteer |

### 4.2 Qualifications

Qualifications are the skills gate. A service can insist a coach holds one or more before
the system will ever offer them. Current catalogue:

| Key | Name | Held by |
| --- | --- | --- |
| `hitting` | Hitting Instruction | Reyes, Nakamura, Brennan |
| `pitching` | Pitching Instruction | Callahan |
| `catching` | Catching Instruction | Brennan |
| `fielding` | Infield / Outfield | Nakamura, Brennan |
| `arm_care` | Arm Care Program | Callahan, Vargas |
| `strength` | Strength & Conditioning | Vargas |
| `hittrax` | HitTrax Certified | Reyes, Nakamura |
| `softball` | Softball Specialist | Nakamura |
| `camp_lead` | Camp Lead Instructor | Reyes, Callahan |

Each grant can carry a **certified on** and an **expires on** date. An expired
qualification stops counting the day it lapses, and the coach silently drops out of
candidacy for services that require it. This is a feature — but it means a coach
"disappearing" from availability is worth checking here first.

You can add new qualification keys freely. They are data, not code.

### 4.3 Availability

Two layers, and the second always wins.

**Weekly pattern.** Day of week plus a from/to time. Current roster:

| Coach | Weekdays | Weekends |
| --- | --- | --- |
| Marcus Reyes | 9:30 AM – 1:00 PM **and** 3:00 – 8:30 PM | 9:30 AM – 4:00 PM |
| All other coaches | 3:00 – 8:30 PM | 9:30 AM – 4:00 PM |

**Specific dates.** A single-date entry overrides the weekly pattern for that day
completely — either different hours, or unavailable altogether.

Coaches maintain both themselves at `/coach/availability`. You can edit on their behalf.
When hours are removed that already contain booked lessons, the editor shows the affected
lessons before saving rather than after.

**Important:** the requested lesson must fit *entirely* inside an availability window. A
60-minute lesson at 8:00 PM does not fit a window ending at 8:30 PM once the 5-minute
after-buffer is counted, so it will not be offered.

### 4.4 Workload caps and lead time

| Field | What it does | Current values |
| --- | --- | --- |
| Minimum lead time | How far ahead of *now* a booking with this coach must be | Reyes 120 min, Callahan 120, Nakamura 180, Brennan 180, Vargas 180 |
| Max sessions per day | Hard cap on reservations in one local day | Reyes 8, Callahan 7, Nakamura 6, Brennan 6, Vargas 5 |
| Max consecutive minutes | Hard cap on total minutes in one local day | Not set — set it if a coach is doing six straight hours |
| Required break minutes | Minimum gap between sessions | 0 |

Caps are enforced when availability is calculated, not when someone complains. A coach at
their cap stops appearing for the rest of that day, and the slot is simply offered with a
different coach or not offered at all.

### 4.5 Whether customers may pick them, and auto-assignment order

| Field | Meaning |
| --- | --- |
| **Accepts online booking** | Off means this coach never appears in the public booking flow at all |
| **Customer selectable** | Off means the coach can be auto-assigned but never chosen by name |
| **Auto assignable** | Off means only staff may assign this coach |
| **Assignment priority** | **Lower number wins.** The engine tries coaches in this order |

Current priorities: Reyes 10, Callahan 20, Nakamura 30, Brennan 40, Vargas 50. So for a
hitting lesson where several coaches qualify, Reyes is offered first.

The full ordering the engine uses when picking a coach or a cage:

1. Anyone on the requirement's **preferred** list.
2. Then by **assignment priority**, lowest first.
3. Then **least recently used** — which spreads lessons fairly across coaches and rotates
   wear across cages.
4. Then by code, so the result is never random.

**If a customer picks a specific coach and that coach is not free, the system shows no
availability rather than quietly substituting someone else.** Handing a family Coach
Brennan when they asked for Coach Reyes, without saying so, is worse than showing nothing.
Substituting is an explicit staff action.

### 4.6 Time off

Coaches request time off at `/coach/availability`. A request that overlaps booked lessons
shows those lessons to the coach at request time and to you at approval time. Approving it
creates a block of kind `coach_time_off` against that coach's resource — the same
mechanism as a cage under maintenance, so the calendar and every booking screen agree.

Approving time off **does not** cancel the lessons inside it. Move or cancel them
deliberately, exactly as with a closure.

---

## 5. Creating a new service with no developer

This is the most important section in this guide, and the thing the platform was built
for. A service is a name, a shape in time, and a list of what it needs. Nothing in the
scheduling engine knows what a "HitTrax lesson" or a "birthday party" is — it reads your
requirement rows and matches resources. **Adding a service is filling in a form. There is
no code change and no release.**

`USER_JOURNEYS.md` Journey 8 walks the same ground from the database side. This section
walks the **screen**.

### 5.1 The worked example

We are going to build a **Softball Pitching Lesson**: 60 minutes of one-to-one softball
pitching instruction, on a cage with a mound, with a softball-qualified coach, $95, ages
8–18, standard cancellation policy, and an arm-health question.

Open `/admin/services` and press **New service**. You land on `/admin/services/new`.

The editor is one long form on the left and a live **Preview availability** panel on the
right. The preview is your safety net: it plans real allocations against the draft and
throws them away, so what it shows you is exactly what the scheduler would do. Watch it
as you work.

### 5.2 Step 1 — Basics

| Field | Value | Notes |
| --- | --- | --- |
| Name | Softball Pitching Lesson | |
| URL slug | `softball-pitching` | Leave empty and it is derived from the name. This becomes `/services/softball-pitching` |
| Category | Private Lessons | Groups it on the public site |
| Format | Appointment | See the table below |
| Short description | "One-on-one softball pitching instruction on a mound cage." | Shown in listings |
| Active | **On** | |
| Public | **Off, for now** | Build it invisible, publish when the preview is green |
| Bookable online | **Off, for now** | |
| Needs approval | Off | On means every booking waits for staff confirmation |

**Choosing the format.** Format tells the platform how the thing is sold and scheduled.

| Format | Use it for | Examples at ATD |
| --- | --- | --- |
| Appointment | Individually scheduled, one household at a time | Private lessons, cage rentals |
| Group session | One occurrence, many separate registrations | Group Hitting Clinic |
| Program | A multi-session series bought as a whole | Arm Care Program, Summer Skills Camp |
| Event | A one-off with many attendees | Parents' Night Out |
| Party | A package with a room, cages and a host | Birthday Party |
| Rental | The customer takes space for a stretch of time | Team Practice, Facility Buyout |

### 5.3 Step 2 — Scheduling: durations and buffers

| Field | Value | What it means |
| --- | --- | --- |
| Default duration | 60 min | What is pre-selected |
| Minimum duration | 30 min | Shortest the customer may choose |
| Maximum duration | 90 min | Longest |
| Duration increment | 30 min | The steps offered: 30, 60, 90 |
| Slot granularity | 15 min | How finely start times are offered: 4:00, 4:15, 4:30 … |
| Setup | 0 min | Time before the session for preparation |
| Cleanup | 0 min | Time after for reset |
| Buffer before | 0 min | Transition gap before |
| Buffer after | 5 min | Transition gap after |
| Lead time | 120 min | A customer cannot book less than 2 hours from now |
| Booking horizon | 120 days | How far ahead the calendar opens |

**How buffers actually work — the one thing people get wrong.** The cage is not held for
60 minutes; it is held for the whole *envelope*. Setup and buffer-before are added at the
front, cleanup and buffer-after at the back.

For this service: `0 + 0 = 0` minutes at the front and `5 + 0 = 5` minutes at the back.
A 4:00–5:00 PM lesson therefore blocks the cage 4:00–5:05 PM, and the next booking in that
cage can start at 5:05 PM, not 5:00 PM.

Compare with the HitTrax Hitting Lesson, which has 5 before and 10 after plus 5 setup and
5 cleanup: a one-hour HitTrax session ties up Cage 5 for **1 hour 25 minutes**. That is
correct — the simulator needs staging and reset — but it is why HitTrax availability looks
thinner than cage availability. If HitTrax is under-booked, this is the first number to
look at.

**Granularity versus increment.** Granularity is where sessions may *start*; increment is
how long they may *run*. A 15-minute granularity with a 30-minute increment gives you
plenty of start times without offering 45-minute lessons.

### 5.4 Step 3 — Capacity and eligibility

| Field | Value |
| --- | --- |
| Minimum participants | 1 |
| Maximum participants | 1 |
| Minimum age | 8 |
| Maximum age | 18 |
| Sport | Softball |

Age is checked against the participant's date of birth. For programs, age is measured on
the program's own date, not today, so a child who has a birthday between registering and
the camp is judged correctly.

### 5.5 Step 4 — Resource requirements (the heart of it)

Scroll to **Resource requirements**. One row per slot the service needs filled. Press
**Add requirement** twice.

**Requirement 1 — the coach**

| Field | Value |
| --- | --- |
| Label | Coach |
| Resource type | Coach |
| Quantity | 1 |
| Assignment | Automatic, customer may choose |
| Required attributes | (empty) |
| Required coach qualifications | Softball Specialist **and** Pitching Instruction |
| Buffer before / after | leave blank to inherit from the service |
| Starts late by / Ends early by | 0 / 0 |
| Optional | unchecked |

**Look at the preview panel now.** It says:

> **Blocked** — Coach needs 1 · 0 candidates

**This is the lesson.** Qualification filters are **"and", not "or"**. Selecting two
qualifications means *holds both*. Dana Nakamura holds Softball Specialist but not
Pitching Instruction; Tyler Callahan holds Pitching Instruction but not Softball
Specialist. Nobody holds both, so nobody qualifies, so the service can never be booked.

You have three ways to fix it, and the right one depends on what you actually mean:

| What you mean | Do this |
| --- | --- |
| "Dana teaches this" | Select only **Softball Specialist** |
| "Dana or Tyler, either is fine" | Create a new qualification, e.g. `softball_pitching` / "Softball Pitching", grant it to both, and require that one |
| "These two named coaches, nobody else, ever" | Leave qualifications empty and use the requirement's **allowed resources** list to name them |

We will take the second route, because it is the one that keeps working when you hire a
sixth coach. Add the qualification at `/admin/coaches`, grant it to Nakamura and Callahan,
come back, and select it alone.

The preview now says **OK — Coach needs 1 · 2 candidates**.

**Requirement 2 — the cage**

| Field | Value |
| --- | --- |
| Label | Mound Cage |
| Resource type | Batting Cage |
| Quantity | 1 |
| Assignment | Automatic |
| Required attributes | `has_mound` = true (choose the **true/false** type) |
| Buffer after | (blank — inherits the service's 5 minutes) |
| Optional | unchecked |

Preview: **OK — Mound Cage needs 1 · 2 candidates** (CAGE-1 and CAGE-5).

**The four assignment modes**

| Mode | Who chooses | Use it when |
| --- | --- | --- |
| Automatic | The engine, silently | The customer does not care which cage |
| Automatic, customer may choose | Engine picks, customer may pin a specific one | Coaches on private lessons |
| Customer chooses | The customer must pick | Cage rentals, where people have a favourite |
| Staff assign | Only staff | Camp coaches, party hosts, clinic staff |

**Quantities above one.** A requirement with quantity 2 draws two *different* resources —
the engine tracks what it has already taken, so it never hands you the same cage twice.
The Group Hitting Clinic uses 2 coaches and 2 cages; the Summer Skills Camp uses 3 coaches,
4 cages and the lobby; the Facility Buyout uses all 5 cages plus the party room.

**Offsets — "starts late by" and "ends early by".** These let one requirement occupy only
part of the booking. If a party host only needs to be present from 15 minutes in, set the
host row's *starts late by* to 15. The room is held for the whole window; the host is held
for the sub-window and stays free for something else in those first 15 minutes.

**Optional requirements.** Tick **Optional** and, if that resource cannot be found, the
booking goes ahead without it instead of failing. Use this sparingly — the usual case is
that a missing resource genuinely means "cannot run".

**Per-requirement buffers override the service's.** Setting *buffer after* to 20 on the
cage row alone means the cage stays blocked 20 minutes after the lesson while the coach is
released after 5.

### 5.6 Step 5 — Pricing

| Field | Value |
| --- | --- |
| Pricing model | Fixed |
| Base price | $95.00 |
| Tax rate | Leave as "no tax" unless your accountant says otherwise (see [§7.4](#74-a-note-on-tax)) |

Pricing models available: **Fixed** (one price), **Per minute** (rentals — the seeded 35 ft
cage is 75 cents a minute), **Per participant** (semi-private lessons at $60 a head),
**Free**, and the more specialised per-resource, per-coach-rate, tiered and package-only.

Then add **Pricing rules** for anything conditional. For this service, one rule:

| Field | Value |
| --- | --- |
| Name | Softball pitching — peak evening |
| Scope | Peak |
| Priority | 10 |
| Days it applies | Mon, Tue, Wed, Thu, Fri |
| From / Until | 4:00 PM / 8:30 PM |
| Effect | Set |
| Amount | $105.00 |

The existing facility-wide **Member discount** rule already applies to every service, so
members automatically get 10 percent off both prices. You do not add it here. See
[§7](#7-pricing-how-the-rule-pipeline-composes) for how the rules compose.

### 5.7 Step 6 — Add-ons

Scroll to **Add-ons** and tick the ones this service should offer. Available today:

| Add-on | Price | Charged | Also pulls in |
| --- | --- | --- | --- |
| Add HitTrax | $30.00 | per booking | The HitTrax unit, **and** forces the cage to be the HitTrax cage |
| Pitching Machine | $15.00 | per booking | A pitching machine |
| Additional Party Guest | $20.00 | per participant | — |
| Pizza & Drinks Package | $90.00 | per booking | — |
| Decorations & Party Favors | $65.00 | per booking | — |
| Extra 30 Minutes | $35.00 | per booking | Extends the booking by 30 minutes |

**Why "Add HitTrax" is worth understanding.** An add-on can do two things: *add* a
resource requirement, and *narrow* an existing one. "Add HitTrax" does both — it reserves
the HitTrax unit and it forces the lesson's cage requirement to a HitTrax-equipped cage.
Without the second half you would get a HitTrax unit reserved alongside a 35 ft cage it
does not live in, which is physically impossible. **If you create an add-on whose
equipment only works in one room, set both halves.**

For the Softball Pitching Lesson, link **Pitching Machine** only.

### 5.8 Step 7 — Intake questions

Press **Add question**.

| Field | Value |
| --- | --- |
| Question | Any current arm soreness or injury? |
| Key | `arm_status` (derived automatically if left blank) |
| Type | Long text |
| Asked of | Participant |
| Required | Yes |

**Asked of** matters: *Booking* asks once for the whole booking; *Participant* asks once
per person. Question types available are short text, long text, number, dropdown,
multi-select, yes/no, date, phone and email. Dropdowns take a list of options.

Answers are stored on the booking and shown to the coach in their session workspace.

### 5.9 Step 8 — Deposit, policy and waivers

| Field | Value | Notes |
| --- | --- | --- |
| Deposit required | No | Parties take a $150 deposit; a buyout takes 25 percent |
| Cancellation policy | Standard Lesson Policy | See [§9](#9-cancellation-policy-tiers) |
| Required waivers | General Liability & Assumption of Risk | Camps also require Camp Medical Authorization |

Deposits can be a flat amount or a percentage — set one, not both. The remainder becomes
the booking's balance and appears in the front desk's **Unpaid balances** section.

### 5.10 Step 9 — Verify with the preview before you publish

The **Preview availability** panel plans real allocations for the next seven days against
your draft and then discards them. Read it top to bottom:

1. **The headline** — "N bookable starts found", or "No bookable times in the next 7 days".
2. **The per-requirement list** — each requirement marked OK or Blocked, with how many
   candidates it found.
3. **Sample slots** — up to six real start times with the exact cage and coach that would
   be assigned. Sanity-check these against your own knowledge: are the times inside
   9:30 AM – 8:30 PM? Is it offering the coach you expected?
4. **"This service consumes"** — a plain-English summary, e.g. *1 × Coach, 1 × Batting Cage
   where has_mound=true*. Read it aloud. If it is not what you meant, fix it now.

**If the preview shows no availability, it is almost always one of these:**

| Symptom | Cause | Fix |
| --- | --- | --- |
| A requirement shows 0 candidates | Qualification list nobody satisfies | Require fewer, or create a combined qualification |
| A requirement shows 0 candidates | Attribute predicate matches no resource | Check spelling and, above all, the **type** (number vs text) |
| A requirement shows 0 candidates | Quantity larger than the number of matching resources | Reduce quantity or widen the predicate |
| Candidates exist but no slots | Coach availability never covers those hours | Check the weekly pattern at `/admin/coaches` |
| Candidates exist but no slots | Lead time longer than the preview window | Lower the lead time or preview a later week |
| Candidates exist but no slots | Duration plus buffers does not fit inside opening hours | Shorten the duration or the buffers |

**Only when the preview is green do you publish.**

### 5.11 Step 10 — Publish

Set **Public** on and **Bookable online** on, and save. The service appears at
`/services/softball-pitching` and in the booking flow at `/book` immediately. There is no
release and no engineer.

### 5.12 Retiring a service later

Set **Active** off. It vanishes from sale; every past booking, report and invoice stays
intact. Do not attempt to delete a service that has bookings — the platform deliberately
refuses, so that a live service cannot be erased out from under a family who booked it.

---

## 6. Camps, clinics and programs

A **program** is a multi-session thing sold as a whole: the Summer Skills Camp, the
six-week Arm Care Program, a school-break clinic. It sits on top of a service — the
service defines what each day *consumes* (coaches, cages, the lobby); the program defines
the dates, the price and the roster.

Open **Programs** at `/admin/programs`.

### 6.1 Building one

1. **Choose or create the underlying service.** Its format should be `program` (or `event`
   for a one-off like Parents' Night Out). Its resource requirements are what each session
   will hold. Summer Skills Camp, for example, requires 3 coaches, 4 cages and the lobby
   for check-in, with 15 minutes of setup and 30 minutes of cleanup around each day.
2. **Create the program** with:

| Field | Guidance |
| --- | --- |
| Name, slug, summary | The slug becomes `/programs/<slug>` |
| Starts on / Ends on | The span of the whole series |
| Registration opens / closes | Optional. Closing registration stops new sign-ups without hiding the page |
| Capacity | Total places. Enforced by the database, not just the screen |
| Minimum enrolment | Below this you may want to cancel; the system does not cancel for you |
| Min age / Max age | |
| Age as of date | Usually the first day of camp. Age is judged on this date, not on the registration date |
| Price | Full-series price |
| Drop-in price | Only if you allow single days |
| Deposit | Optional |
| Allow waitlist | Leave on |
| Sibling discount | Percentage off for a second child in the same household |
| Cancellation policy | Program & Camp Policy |
| Required waivers | Camps should require both General Liability and Camp Medical Authorization |
| Check-in / pickup window | Minutes either side of a session for arrivals and collection |
| Parent instructions | Free text shown on the registration page and in the confirmation |

3. **Add the sessions** — one row per day of the camp, numbered in order, each with a date
   and a start and end time.

### 6.2 Materialising the sessions

Creating session rows does **not** reserve anything yet. Nothing is held until you
**materialise** them. Materialising walks the sessions in order and, for each one, creates
a real booking and reserves every resource the service requires.

Do this as soon as the schedule is settled. Until you do, someone can book a private
lesson into a cage your camp needs.

**Materialising is all-or-nothing.** If any single session cannot be satisfied, the whole
run stops and nothing is written — you are told which session number failed and at what
time. That is deliberate: a camp with three of five days reserved is worse than a camp
with none, because it looks fine on the calendar.

### 6.3 When a session has no available resources

The message names the session number and its start time. Work through this list:

1. **Open `/admin/calendar` on that date** and look at what is already there. Nine times
   out of ten a lesson, a party or an earlier program is sitting in the cages you need.
2. **Count.** The camp needs 4 of 5 cages. One other booking in a cage at that hour is
   enough to break it.
3. **Choose a fix, in order of preference:**

| Fix | How |
| --- | --- |
| Move the camp session | Change that session's time to a quieter hour |
| Move the blocking booking | From `/admin/calendar`, drag it to another cage or time; the system re-validates and refuses if the new position does not work |
| Reduce what the session needs | If the camp genuinely runs fine on 3 cages, change the service requirement — but this affects every session |
| Cancel the blocking booking | Last resort. Cancel from `/admin/bookings` with a reason, and call the family |

4. **Materialise again.** It skips sessions that already have bookings, so re-running is
   safe.

**Prevention.** Build and materialise camps *before* you open the surrounding weeks for
private lessons, or block the cages you will need as an admin hold while the camp dates
are being agreed.

### 6.4 Registrations, waitlists and the last seat

When a program is full, registrations become waitlist entries automatically (as long as
the waitlist is allowed). The system row-locks the program while a registration is
processed, so two parents pressing "register" for the last seat at the same instant
resolve deterministically — one gets the place, one gets the waitlist, and the database
constraint would refuse to let capacity be exceeded even if something else tried.

When a place opens, up to three waiting households are offered it, and the offer expires
after the claim window (120 minutes by default).

---

## 7. Pricing: how the rule pipeline composes

Prices are not looked up; they are **built**, one step at a time, and every step is
recorded. That is why a customer, the front desk and your accountant all see the same
arithmetic, and why nobody has to reconstruct how a number was reached.

### 7.1 The order

The pipeline always runs in this order:

| # | Stage | Where it comes from |
| --- | --- | --- |
| 1 | **Base** | The service's pricing model and base price |
| 2 | **Pricing rules**, in ascending priority order | `/admin/services/[id]` → Pricing rules, plus facility-wide rules |
| 3 | **Add-ons** | What the customer ticked |
| 4 | **Sibling discount** | The `sibling_discount_percent` setting |
| 5 | **Promo code** | If entered and valid |
| 6 | **Tax** | Only if the service is marked taxable and has a tax rate |
| 7 | **Deposit split** | The service's deposit setting, applied to the total |

Within stage 2, rules run in **ascending priority number**, so a rule with priority 10
runs before one with priority 80. Seeded priorities: peak and off-peak 10, team rate 20,
coach premium 30, member discount 80. That ordering is what makes a member discount apply
to the *peak* price rather than the base price.

**Peak and off-peak never both fire.** If a peak rule matches, off-peak rules for the same
service are suppressed. You do not have to write mutually exclusive time windows.

### 7.2 A worked breakdown

A member family rents a 35 ft cage for 60 minutes on a Tuesday at 6:00 PM, adds a pitching
machine, brings two siblings, and uses a 10 percent promo code.

| # | Step | Arithmetic | Running total |
| --- | --- | --- | ---: |
| 1 | Base rate (60 min) | 75¢ × 60 | $45.00 |
| 2 | Peak cage rate (priority 10) — Mon–Fri 4:00–8:30 PM sets $1.00/min | 100¢ × 60 | $60.00 |
| — | Off-peak cage rate | *suppressed, because peak matched* | $60.00 |
| 3 | Member discount (priority 80) — 10% off | −$6.00 | $54.00 |
| 4 | Add-on: Pitching Machine | +$15.00 | $69.00 |
| 5 | Sibling discount, 10% | −$6.90 | $62.10 |
| 6 | Promo code, 10% | −$6.21 | $55.89 |
| 7 | Subtotal | | **$55.89** |
| 8 | Sales tax | *not applied — see §7.4* | $0.00 |
| 9 | **Total** | | **$55.89** |

Change one thing and watch the order matter: if the member discount ran *before* the peak
rule, the peak rule would overwrite it with a flat $60.00 and the member would get nothing.
That is exactly what priority numbers prevent.

A second, simpler example — a private hitting lesson with Marcus Reyes, for a member:

| # | Step | Arithmetic | Running total |
| --- | --- | --- | ---: |
| 1 | Base rate (fixed) | | $90.00 |
| 2 | Director premium — Reyes (priority 30) | +$15.00 | $105.00 |
| 3 | Member discount (priority 80) | −$10.50 | $94.50 |
| 4 | **Total** | | **$94.50** |

### 7.3 The effects you can use

| Effect | What it does | Good for |
| --- | --- | --- |
| Set | Replaces the running total | Peak / off-peak flat prices |
| Set per minute | Replaces it with rate × minutes | Peak rental rates |
| Set per participant | Replaces it with rate × people | Group pricing tiers |
| Add | Adds a fixed amount | Coach premiums |
| Amount off | Subtracts a fixed amount | Fixed-dollar promotions |
| Percent off | Subtracts a percentage | Member and early-bird discounts |
| Multiply | Multiplies the running total | Rarely needed |

Conditions you can attach to a rule: days of the week, a time-of-day window, an effective
date range, a specific coach, a specific resource, a membership plan, a duration range, a
participant-count range, and how many days ahead the booking is being made (for early-bird
or last-minute pricing). A condition left blank means "do not care".

### 7.4 A note on tax

Every service ships with **Taxable off**. A CT Sales Tax rate of 6.35 percent exists and is
ready to use, but no service currently points at it, so nothing is being taxed today.
If your accountant tells you a category is taxable, open each affected service, turn
**Taxable** on and select **CT Sales Tax**. Tax is then calculated on the subtotal after
every discount, which is the correct order.

### 7.5 Rate cards

A **rate card** is a named set of pricing rules. The **Standard Rate Card** is the default
and applies to everyone. The **Travel Team Rate Card** carries a discounted team practice
rate ($2.25 a minute instead of $3.00) and applies only to households assigned to it. Use
rate cards when a whole segment gets different prices, rather than writing a discount rule
per service.

---

## 8. Packages, memberships and the credit ledger

### 8.1 Packages

A package is prepaid credit. Current catalogue:

| Package | Credits | Unit | Price | Valid | Usable on |
| --- | ---: | --- | ---: | ---: | --- |
| 5 Private Lessons | 5 | session | $400.00 | 365 days | Hitting, pitching, catching, fielding lessons |
| 10 Private Lessons | 10 | session | $750.00 | 365 days | The same four |
| 10 Cage Hours | 10 | hour | $600.00 | 365 days | 35 ft and 50 ft rentals, **off-peak only** |
| 5 HitTrax Hours | 5 | hour | $650.00 | 180 days | HitTrax rental |

All four are **household-shared**, so siblings draw from the same balance. A package can
also be restricted to one participant, restricted to off-peak hours (as the cage package
is), or tied to specific coaches.

Packages are sold at the front desk (`/desk/payments`) or online, and customers see their
balance at `/account/packages`.

### 8.2 What the credit ledger is, and why you never edit a balance

A household's credit balance is **not a number someone types**. It is the running total of
an append-only list of transactions:

| Transaction kind | Meaning |
| --- | --- |
| `grant` | Credits created — usually at purchase |
| `redeem` | One credit spent on a booking |
| `refund` | A credit given back, e.g. a cancellation inside the free window |
| `forfeit` | A credit deliberately consumed, e.g. a late cancellation |
| `expire` | Credits lost to the validity period |
| `adjust` | A manual correction, always with a reason and an actor |
| `transfer_in` / `transfer_out` | Movement between packages |

The balance you see on screen is a mirror, rebuilt automatically every time a transaction
is written. **This is why balances are never edited directly.**

1. **Every change has a reason and an author.** "Why did the Alvarez family lose a credit?"
   is answered by reading one row, not by guessing.
2. **The balance can always be rebuilt.** If a mirror is ever wrong, it is recomputed from
   the ledger. If the balance were the truth, a bad edit would be unrecoverable.
3. **Refunds and cancellations stay honest.** When a booking is cancelled, the policy
   decides whether the credit comes back or is forfeited, and *either way a row is
   written*. A credit never simply disappears.
4. **Double-clicks cannot double-charge.** Only one redemption per booking per package is
   permitted, so a double-tapped "Pay" button cannot spend two credits.

**To correct a balance**, add an adjustment with a written reason. Never look for a field
to overwrite — there is not one, on purpose.

Account credit (store credit from cancellations and goodwill) works identically, and gift
card balances too.

### 8.3 Memberships

| Plan | Billing | Price | Included credits | Discount | Priority booking | Roll-over |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| Cage Club — Monthly | Monthly | $99.00 | 4 | 10% | 24 hours | Yes, up to 8 |
| Training Club — Monthly | Monthly | $249.00 | 6 | 15% | 48 hours | Yes, up to 6 |
| Family Annual | Annually | $1,499.00 | 60 | 20% | 72 hours | No |

- **Included credits** are granted each billing period as a package purchase, and appear
  in the same ledger.
- **Member discount** is applied by a facility-wide pricing rule at priority 80.
- **Priority booking** opens the calendar to members that many hours before everyone else.
- **Roll-over** carries unused credits into the next period, up to the cap.
- Members can be paused (frozen) for up to the plan's maximum freeze days.

A membership that fails payment moves to past-due; repeated failures are counted. Check
`/admin/payments` and the household's account page when a member reports a problem.

---

## 9. Cancellation policy tiers

A **policy** is a named set of **tiers**. Each tier says: *if the customer acts at least N
hours before the start, this is what happens.*

### 9.1 The three seeded policies

**Standard Lesson Policy** (default for bookings)

| Action | At least … before | Outcome | Refund | Fee | Package credit returned |
| --- | ---: | --- | ---: | ---: | --- |
| Cancel | 24 h | Full refund | 100% | — | Yes |
| Cancel | 12 h | Partial refund | 50% | — | Yes |
| Cancel | 0 h | Credit forfeited | 0% | — | No |
| Reschedule | 24 h | Free reschedule | — | — | Yes |
| Reschedule | 2 h | Reschedule fee | — | $15.00 | Yes |
| No-show | 0 h | Credit forfeited | 0% | — | No |

**Program & Camp Policy**

| Action | At least … before | Outcome | Refund |
| --- | ---: | --- | ---: |
| Cancel | 336 h (14 days) | Full refund | 100% |
| Cancel | 168 h (7 days) | Partial refund | 75% |
| Cancel | 48 h (2 days) | Account credit | 100% as credit |
| Cancel | 0 h | No refund | 0% |

**Party Policy**

| Action | At least … before | Outcome | Refund |
| --- | ---: | --- | ---: |
| Cancel | 336 h (14 days) | Partial refund | 100% |
| Cancel | 0 h | No refund | 0% |

### 9.2 How the engine picks a tier

1. It works out how many hours remain until the booking starts.
2. It sorts that policy's tiers for that action from the **largest** threshold down.
3. It takes the **first tier the customer still clears**.

So under the Standard Lesson Policy: 30 hours out → the 24-hour tier (full refund);
18 hours out → the 12-hour tier (50 percent); 5 hours out → the 0-hour tier (forfeited).

If a service has no policy attached, or a policy has no tier for that action, the decision
is **requires approval** and a manager must decide by hand. That is a safe default, not an
error, but a service in that state is worth fixing.

### 9.3 Designing a policy

1. **Decide the actions you need**: cancel, reschedule, no-show. Cover all three; a missing
   action means every case escalates to a manager.
2. **Work outside in.** Start with the generous tier at the largest number of hours, then
   add tightening tiers. Always finish with a **0-hour** tier — that is the catch-all for
   "they did it at the last minute", and without it the engine has nothing to fall back to.
3. **Choose an outcome per tier**: full refund, partial refund, account credit, credit
   forfeited, no refund, free reschedule, reschedule fee, cancellation fee, or requires
   approval.
4. **Decide the package-credit question separately.** A tier that gives no money back can
   still return the package credit — that is often the right answer for a family who
   cancelled two hours out for a genuine reason.
5. **Mark tiers that need approval** if you want a human in the loop even when the rule is
   clear.
6. **Attach the policy to services** in the service editor.

**A design tip.** Make the generous tier generous. The 24-hour full refund is what makes
people book two weeks out instead of two days out, and forward bookings are what fill your
Tuesday afternoons.

### 9.4 Overriding a decision

A manager can override the outcome of any single cancellation — a bigger refund, credit
where the policy said forfeit. The override is applied in the same operation as the
cancellation, and the reason and the full decision are written to the audit log. Overrides
are for genuine exceptions; a pattern of them means the policy is wrong and should be
edited.

---

## 10. Waivers

### 10.1 How they work

A waiver has a **template** (its identity — "General Liability & Assumption of Risk") and
one or more **versions** (the actual wording). A signature always points at a specific
*version*. That is what makes "has this family signed the current waiver?" a fact rather
than a judgement call.

Current templates:

| Template | Audience | Renewal | Re-signature required on new version |
| --- | --- | --- | --- |
| General Liability & Assumption of Risk | Participant | Every 12 months | Yes |
| Camp Medical Authorization & Pickup | Guardian | Every 12 months | Yes |
| Photo & Video Consent | Guardian | Never expires | No |

Every service requires the General Liability waiver. The Summer Skills Camp and Parents'
Night Out additionally require Camp Medical Authorization.

### 10.2 Publishing a new version

1. Have the new wording approved by counsel.
2. Create a **new version** of the template — never edit the text of a published version.
   Editing a signed version would change what people already agreed to.
3. Set:
   - **Version number** — the next one up.
   - **Effective from** — the date it becomes the current version.
   - **Requires re-signature** — the important switch, see below.
4. Save. From the effective date, the new version is the current one.

### 10.3 When a new version forces re-signature

| Setting | Effect | Choose it when |
| --- | --- | --- |
| **Requires re-signature: on** | Everyone who signed an earlier version becomes "signed an older version" immediately. They appear in **Missing waivers** on the front-desk board and are prompted at the kiosk | The legal substance changed — new risks, new assumption of liability, new medical authorisation |
| **Requires re-signature: off** | Existing signatures continue to count | The change is cosmetic — a typo, a phone number, formatting |

Nothing has to be back-filled either way. Because a signature points at a version, the
system works out who is stale automatically.

**Practical advice.** Turning re-signature on the week before a school-break camp will put
several hundred families into the Missing waivers list at once. Publish new versions in a
quiet week, and tell the desk it is coming.

There are three ways a family becomes "not covered":

| Reason shown | Meaning |
| --- | --- |
| Never signed | No signature for that template at all |
| Signed an older version | Signed, but a newer version requiring re-signature has been published |
| Expired | Signed the current version, but the renewal period has lapsed |

### 10.4 Overrides, and how they are audited

Sometimes a child has to play. A member of staff with the waiver-override permission can
record an **override** letting a participant take part unsigned.

- An override is always attributed to a named person and always carries a reason.
- It writes a `waiver.override` entry to the audit log with the participant, the actor and
  the reason.
- It covers that participant for the situation it was granted for — it is not a
  substitute for a signature and does not make the gap disappear from your records.

**Review overrides monthly** (see [§12](#12-the-audit-log)). A single override is an
operational necessity. A stream of them from the same person on the same template means a
process problem — usually that the waiver link is not being sent early enough. The
`waiver.missing` reminder currently goes out two days before the session; consider moving
it earlier.

---

## 11. Reports

Everything is computed live from bookings and reservations. There is no overnight batch,
so a report you refresh at 3:00 PM includes the 2:45 PM booking.

### 11.1 Dashboard — `/admin`

| Panel | The question it answers |
| --- | --- |
| Revenue today | How much have we taken today, across how many payments |
| Bookings today | How many sessions and how many people are expected |
| Outstanding balances | How much money is owed on booked sessions, across how many bookings |
| No-show rate | What share of finished sessions in the last 30 days were no-shows |
| Utilisation today | What share of available cage-minutes and rostered coach-minutes is committed, including buffers |
| Upcoming camps and programs | How full is each one, and how many are waiting |
| Packages expiring in 60 days | Which households are about to lose credit they paid for |

The no-show tile turns red at 10 percent or above. The packages card is the most
commercially useful thing on the screen — a call from the desk saying "you have four
lessons expiring next month" converts remarkably well.

### 11.2 Reports — `/admin/reports`

| Report | The question it answers |
| --- | --- |
| Last 30 days by category | Which parts of the business are actually earning — lessons, rentals, HitTrax, camps, parties |
| Resource load, last 30 days | Which cages and coaches are working hardest, shown relative to the busiest, so the shape of demand is visible even in a quiet month |
| Top services, last 90 days | Which individual services drive volume, and which have a no-show problem |

Financial columns are hidden from anyone without finance permission, so a coach opening
the same screen sees the operational picture without the money.

### 11.3 Payments — `/admin/payments`

Takings today, this week and this month; refunds in the last 30 days; the last 100
payments with method, card brand and last four digits, the household, who took it and any
note; and the last 25 refunds with their reasons. This is your daily reconciliation screen.

### 11.4 Other screens that answer questions

| Screen | Use it for |
| --- | --- |
| `/admin/bookings` | Filter by date range and status. The way to find everything on a closed day, or every no-show last month |
| `/admin/coaches` | Sessions and minutes booked per coach for the next 7 days, against their rostered minutes |
| `/admin/programs` | Fill rate and waitlist depth per program |
| `/admin/customers` | Household search, spend and visit history |
| `/desk/resources` | A live view of what every resource is doing right now |

---

## 12. The audit log

The audit log is an **append-only** record of consequential actions. It cannot be edited or
deleted — the database refuses the attempt, even from an administrator. That is the point:
its value comes entirely from the fact that nobody can tidy it up.

### 12.1 What is in an entry

| Field | What it tells you |
| --- | --- |
| Occurred at | When, to the second |
| Actor | Who did it — user, email and role at the time |
| Impersonated by | If someone was acting on another user's behalf |
| Action | What kind of thing happened, e.g. `booking.cancelled` |
| Entity type / id | What it happened to |
| Summary | A one-line plain-English description |
| Previous value / New value | The before and after, in full |
| Reason | The written justification, where one was required |
| Household / Booking / Payment | Links back to the customer records |
| IP address / User agent | Where it came from |

### 12.2 The actions worth watching

| Action | Why it matters |
| --- | --- |
| `booking.override_conflict` | Someone blocked or booked over an existing customer. Always has a written reason and the full list of who was affected |
| `booking.cancelled` | Includes the complete policy decision — which tier applied, refund, fee, whether a credit came back |
| `booking.no_show` | Marked at the desk |
| `waiver.override` | A participant was allowed to take part without a current signature |
| Payment, refund and discount actions | Every discount and refund is attributed to a named person |

### 12.3 How to read it

Because entries are indexed by entity, by actor, by location and by action, there are four
natural ways to ask a question:

1. **"What happened to this booking?"** — look up the entry list for that booking id. You
   get the whole life of it: created, rescheduled, cancelled, refunded, in order.
2. **"What did this person do?"** — look up by actor. Useful for training and for the rare
   occasion when it is not.
3. **"Show me every override this month."** — look up by action. This is your monthly
   review: conflict overrides, waiver overrides, price overrides, refunds.
4. **"What happened at this location on this day?"** — look up by location and date range.
   The first thing to run after an incident.

### 12.4 Monthly review routine

1. List every `booking.override_conflict` for the month. Each should correspond to a
   closure or an emergency you remember. One you do not recognise is worth a conversation.
2. List every `waiver.override`. See [§10.4](#104-overrides-and-how-they-are-audited).
3. List every refund and discount. Check they match the notes on the corresponding
   bookings.
4. Spot-check three cancellations against the policy tiers to confirm the engine is
   deciding what you expect.

A separate record of conflict overrides is also kept as first-class data, so operations can
report on them without reading the log line by line.
