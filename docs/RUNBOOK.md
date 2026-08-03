# ATD Baseball Company — Operations Runbook

For whoever keeps the platform running: the technical operator, the on-call person, or the
administrator standing in for them. It assumes you can reach the database and the hosting
console; it does not assume you wrote the code.

**Related reading:** [`ADMIN_GUIDE.md`](./ADMIN_GUIDE.md) for day-to-day configuration,
[`ROLES_AND_PERMISSIONS.md`](./ROLES_AND_PERMISSIONS.md) for who may do what,
[`DATA_DICTIONARY.md`](./DATA_DICTIONARY.md) and [`ERD.md`](./ERD.md) for the exact shape of
every table, [`PRD.md`](./PRD.md) §5 for the business rules the system is enforcing.

**The one thing to internalise before anything else.** Availability and reservation both
happen inside the database, in the same transaction, under the same locks. There is no
window in which the application "checks" and then "writes". Two cages cannot be given to
two families, and if someone says they were double-booked, the correct response is to prove
what actually happened — see [§5](#5-investigating-a-claimed-double-booking).

---

## Contents

1. [Health checks: what "healthy" looks like](#1-health-checks-what-healthy-looks-like)
2. [Background jobs that must run](#2-background-jobs-that-must-run)
3. [Common incidents](#3-common-incidents)
4. [Data problems](#4-data-problems)
5. [Investigating a claimed double-booking](#5-investigating-a-claimed-double-booking)
6. [Backup and restore](#6-backup-and-restore)
7. [Deploys: before and after](#7-deploys-before-and-after)

---

## 1. Health checks: what "healthy" looks like

Run these every morning, and again after any deploy or incident.

### 1.1 The five-minute check

| # | Check | Healthy looks like |
| --- | --- | --- |
| 1 | Load the public home page `/` | Renders in under two seconds |
| 2 | Load `/services` and open one service | Prices and descriptions render |
| 3 | Load `/book` and pick a service and a date | Real start times appear within a couple of seconds |
| 4 | Sign in as staff, load `/desk` | The board renders and the "updated Ns ago" counter is moving |
| 5 | Load `/admin` | The four tiles carry numbers, not dashes |
| 6 | Load `/kiosk` | The navy welcome screen with three buttons |
| 7 | Stripe dashboard → Webhooks | No growing "pending" or "failed" count on the ATD endpoint |

### 1.2 Database health

| Query in words | Healthy |
| --- | --- |
| Count reservations with status `hold` whose expiry is in the past | **0.** Anything above zero means the expiry sweep has not run — see [§2.1](#21-expire-stale-holds) |
| Count queued notifications scheduled for a time in the past | Under a handful. A growing number means the sender is stuck — see [§2.2](#22-send-queued-notifications) |
| Count `stripe_events` rows with a processing error recorded | **0** |
| Count waitlist offers past their expiry that are still marked as offered | **0** — see [§2.3](#23-expire-waitlist-offers) |
| Count package purchases past their expiry date still marked active | **0** — see [§2.4](#24-expire-packages) |
| Count memberships whose current period ended more than a day ago and are still active | **0** — see [§2.5](#25-renew-memberships) |
| Longest-running query | Under a second in normal operation |

### 1.3 Behavioural health — the checks that actually catch problems

Uptime is not the same as correctness. These three catch the failures that matter.

1. **Availability returns something.** Pick a popular service (private hitting lesson) and
   ask for the next seven days. If it returns nothing at all, availability is broken even
   though every page loads. Common causes: operating hours deleted, every coach marked
   inactive, a resource status changed, a whole-facility block left in place.
2. **Prices are sane.** Price one known booking and check it against the table in
   `ADMIN_GUIDE.md` §7.2. A pricing rule saved with the wrong effect can quietly halve
   your revenue while every page still renders.
3. **The board matches the calendar.** Count today's bookings on `/desk` and on
   `/admin/calendar`. They come from the same rows, so they must agree.

---

## 2. Background jobs that must run

Five jobs. Each one has a self-healing property or a manual fallback, so none of them is a
single point of catastrophe — but each has a real cost when it stops.

| Job | Suggested schedule | What breaks if it stops |
| --- | --- | --- |
| Expire stale holds | Every 2 minutes | Abandoned checkouts hold slots (self-heals at the next booking attempt) |
| Send queued notifications | Every minute | No confirmations, reminders, waiver chases or waitlist offers go out |
| Expire waitlist offers | Every 5 minutes | Offers stay claimable past their window; slots stay in limbo |
| Expire packages | Daily, 3:00 AM local | Customers keep spending credits they paid for and lost |
| Renew memberships | Daily, 3:15 AM local | Members do not receive their monthly credits |

Times are Wallingford local. Schedule the two daily jobs outside opening hours.

### 2.1 Expire stale holds

**What it does.** When a customer picks a slot, the resources are genuinely reserved for
them for 10 minutes (`checkout_hold_minutes`) while they pay. If they abandon the page,
those reservations must be released.

**How often.** Every 2 minutes.

**If it stops.** Mostly nothing, and this is worth understanding: **the same sweep runs at
the head of every availability search and every hold attempt.** So an abandoned checkout
never blocks a real customer for longer than its own lifetime, even with the job down. The
job exists to keep the tables tidy and to release holds during quiet periods when nobody is
searching. Consequences of it being down for a day: some stale hold rows accumulate; slot
counts on reports may be slightly off. Nobody is turned away.

**How to run it by hand.** Call the expiry function. It returns how many reservations it
released. Safe to run at any time, as often as you like.

### 2.2 Send queued notifications

**What it does.** Notifications are written to a queue with a scheduled send time, then
picked up and delivered by email or SMS. The queue holds booking confirmations, 24-hour
reminders, waiver-missing chases, waitlist offers, balance-due reminders and closure
notices.

**How often.** Every minute. Pick up everything queued whose scheduled time has passed,
mark it as sending, deliver it, then record sent or failed with a reason.

**If it stops.** This is the most damaging of the five, because nothing else covers for it:

- Customers get no booking confirmation and no confirmation code.
- No 24-hour reminders — expect the no-show rate to climb the following day.
- No waiver-missing emails — the front desk's Missing waivers list grows and gets sorted at
  the counter instead.
- **Waitlist offers never reach anyone**, so freed slots sit unclaimed for the entire
  120-minute window and are then wasted.
- Closure notices do not go out, so families drive to a closed building.

**Safety properties you can rely on.** Every notification carries a unique deduplication
key, so a job that is retried or accidentally run twice cannot send the same reminder
twice. Attempt counts are recorded, so a message failing repeatedly is visible rather than
silently looping.

**Recovery after an outage.** Queued messages are not lost; they are still sitting there
with a past scheduled time. When you restart the sender it will try to deliver all of them
at once. Before you do that:

1. Check how far back the backlog goes.
2. **Cancel anything now pointless** — a 24-hour reminder for a session that finished
   yesterday, a waitlist offer whose window closed. Set those to cancelled rather than
   letting them go out. A customer receiving a reminder for a lesson they already attended
   erodes trust in every message you send.
3. Then start the sender and watch the first hundred.

### 2.3 Expire waitlist offers

**What it does.** An offer gives a household a claim window (120 minutes by default,
`waitlist_claim_minutes`). When it lapses unclaimed the offer must be marked expired and the
entry returned to waiting so the slot can be offered onward.

**How often.** Every 5 minutes.

**If it stops.** Expired offers stay in the "offered" state. The household can no longer
claim (the claim path checks the expiry itself, so nobody sneaks in late) but nobody else is
offered the slot either. The freed cage sits unused and the waitlist stops moving. The
front-desk board keeps showing offers that are already dead, which is confusing at the
counter.

**Manual fallback.** A manager can offer a slot to a specific household from the
customer's account page.

### 2.4 Expire packages

**What it does.** Package credits have a validity period — 365 days for lessons and cage
hours, 180 days for HitTrax. Once past it, the remaining credits must be written off with an
`expire` transaction so the balance goes to zero and the purchase is marked expired.

**How often.** Daily, 3:00 AM local.

**If it stops.** Customers keep booking with credits they have technically lost. This is a
revenue leak and, worse, an awkward conversation when you catch up — you will be taking
credits away from people who watched the system accept them yesterday.

**Do it as a ledger entry, never by editing a balance.** Write an `expire` transaction with
the amount and a note; the balance is recomputed automatically. See
`ADMIN_GUIDE.md` §8.2 for why this matters.

**Recommended courtesy step.** Run a "expiring in 30 days" notice a month ahead. The owner's
dashboard already surfaces packages expiring within 60 days, which is a good prompt for the
desk to phone people.

### 2.5 Renew memberships

**What it does.** At each billing period roll-over: advance the period dates, grant the
plan's included credits as a new package purchase, apply roll-over rules (Cage Club carries
up to 8 credits, Training Club up to 6, Family Annual none), and reset the per-period
booking counter.

**How often.** Daily, 3:15 AM local — after package expiry, so that a member's expiring
credits and their new grant do not collide on the same night.

**If it stops.** Members do not receive their monthly credits. Cage Club members lose four
cage hours a month they have paid for. Expect calls within a day or two of the first
missed cycle.

**Interaction with Stripe.** Actual charging is Stripe's subscription billing; this job
handles the *entitlements*. If the Stripe webhook is backed up ([§3.1](#31-stripe-webhook-backlog))
memberships may show as past-due when payment actually succeeded. Clear the webhook backlog
first, then re-check.

---

## 3. Common incidents

### 3.1 Stripe webhook backlog

**Symptoms.** Bookings stuck in pending-payment. Customers say they paid but their booking
does not show as confirmed. Stripe's dashboard shows a growing pending or failed count on
the ATD endpoint.

**What you need to know about the design first:**

- The endpoint returns **400 only** when the signature does not verify. That is the one case
  where retrying is pointless and the request may not be from Stripe at all.
- It returns **200 for verified events, including duplicates.** The event id is the primary
  key of the events table, so a replay is stored once and processed once. Telling Stripe
  "received" is what stops a retry storm.
- It returns **500 only when the event could not be durably recorded.** If the row exists,
  the work can be finished later, and a 500 would just make Stripe redeliver something we
  already hold.

**Diagnosis, in order:**

1. **Are they 400s?** Then the signature is failing. Causes, in likelihood order:
   (a) the endpoint signing secret in the environment does not match the one in the Stripe
   dashboard — very common after rotating keys or promoting an environment;
   (b) something in front of the app is modifying the request body, since Stripe signs the
   exact bytes; (c) server clock skew beyond the tolerance window.
   **Fix:** correct the secret, redeploy, then replay the failed events from Stripe.
2. **Are they 500s?** The database was unreachable. Check the database first; Stripe will
   redeliver on its own once you are healthy.
3. **Are they 200s but nothing is happening?** The events are being stored and then failing
   during processing. Look for events with a recorded processing error, read the error, fix
   the cause, then reprocess those event ids.
4. **Is the endpoint URL right?** After a domain change, check the Stripe dashboard points
   at the live host.

**While you fix it.** Payments are safe — Stripe has the money and the event. Nothing is
lost. The front desk can confirm bookings manually from `/desk` for anyone who has proof of
payment, and note the confirmation code so you can reconcile afterwards.

**After you fix it.** Replay the failed events from the Stripe dashboard. Replay is a no-op
for anything already processed, so replaying a wide range is safe.

### 3.2 A stuck hold

**Symptom.** A slot shows as unavailable but the calendar shows nothing booked there.

**Cause.** A checkout hold whose expiry has passed but which has not been released, usually
because the expiry job is down *and* nobody has searched availability for that service
recently.

**Fix:**

1. Run the hold-expiry sweep by hand. This resolves it in almost every case, and returns a
   count of what it released.
2. If the slot is still blocked, look at the reservations for that resource in that window
   and find the offending row. Check what owns it — a booking, a block, or a hold. Each
   reservation has exactly one owner, so this is unambiguous:
   - **Owned by a hold** whose expiry has passed → the sweep should have caught it; run it
     again and check the job is actually scheduled.
   - **Owned by a block** → someone has blocked that resource. Look at the block's title
     and note; it may be a maintenance block that was never removed.
   - **Owned by a booking** → it is not a stuck hold, it is a real booking. Look at its
     status. A cancelled booking should have released its reservations; if it has not, that
     is a genuine bug worth escalating with the booking id.
3. Never delete a reservation row to "fix" a symptom without establishing which of the three
   owns it. Deleting a live booking's reservation gives away a cage that a family has paid
   for.

**Prevention.** Alert on "reservations in hold status whose expiry has passed" being above
zero for more than five minutes.

### 3.3 A booking that must be force-moved

**Situation.** A cage is out of action, a coach cannot make it, or an emergency needs the
space, and the booking has to move whether or not the ordinary path allows it.

**The safe path first.** Try the ordinary reschedule from `/admin/calendar` or `/desk`. It
frees the old reservations and re-plans inside a single transaction, so if the new position
does not work the original booking is left completely intact. It is not possible to end up
with a booking that has lost its old slot and not gained a new one.

**If the ordinary path refuses**, it is telling you the new position genuinely conflicts.
Options in order of preference:

1. **Move it somewhere that is free.** Use the change-cage or change-coach panel on `/desk`,
   which lists only what is genuinely free for the whole window including buffers.
2. **Shorten it** so it fits. A 60-minute lesson may fit as 45.
3. **Pin specific resources.** An administrator can reschedule while naming exactly which
   cage and coach to use. This still validates — it does not let you double-book — but it
   overrides the engine's automatic choice.
4. **Move the *other* booking** to make room, then move this one.
5. **Cancel and rebook.** Cancel with a reason, then create the new booking. This changes
   the confirmation code, so tell the family.

**What you must not do.** Do not edit reservation rows directly to force a move. The
overlap guarantee is enforced by a database constraint on those rows; hand-editing them
either fails outright or, worse, is the only way to create the exact situation the whole
system exists to prevent.

**Always record why.** Add a note to the booking and, if you overrode a conflict, the
written reason is captured automatically in the audit log.

### 3.4 A coach who left mid-season

**Do not delete the coach.** Their name is on past bookings, lesson notes, earnings records
and compensation lines. Deleting is refused by design.

**In this order:**

1. **Stop new bookings immediately.** Set the coach profile inactive, or turn off "accepts
   online booking". They vanish from availability at once; nothing existing is touched.
2. **List what is already booked.** `/admin/coaches` shows their sessions for the next seven
   days; `/admin/calendar` shows their lane; `/admin/bookings` finds the rest. Include
   program and camp sessions, where the coach may be one of several assigned.
3. **Reassign or cancel each future session.** For each: use the change-coach panel to find
   a qualified, available replacement, or cancel it with a reason and offer the family a
   move. Sessions where the family specifically chose that coach need a phone call, not an
   email.
4. **Watch for silent failures.** If the departing coach is the only holder of a
   qualification — Tyler Callahan is currently the only Pitching Instruction coach, and
   Dana Nakamura the only Softball Specialist — then removing them makes every service
   requiring that qualification **unbookable with no error message anywhere**. Availability
   simply returns nothing.
   - Open the affected service in the service editor and read the preview panel. It will
     say **Blocked — 0 candidates** on the coach requirement.
   - Fix by granting the qualification to another coach, widening the requirement, or
     deactivating the service until you have hired.
5. **Handle their programs.** Camp and clinic sessions already materialised hold the coach's
   resource. Reassign those bookings before the camp runs.
6. **Close their pay period** and export their earnings before revoking access.
7. **Revoke access last.** Set the user account inactive and remove their role. Do this
   after everything above — you may need to look at their calendar.
8. **Leave the coach profile in place**, inactive. History stays intact and reports for past
   periods keep working.

### 3.5 A mis-priced service

**Symptom.** Customers were charged the wrong amount — usually a pricing rule saved with the
wrong effect, the wrong priority, or an amount entered in dollars where cents were expected.

**All money is stored in whole cents.** A rule meant to charge $1.00 a minute is `100`. If
someone typed `1`, the service is being sold at one cent a minute.

**In this order:**

1. **Stop the bleeding.** Deactivate the offending pricing rule, or set the service
   inactive if you cannot immediately tell which rule is wrong. Deactivating a rule affects
   new bookings only.
2. **Confirm the correct price** by pricing a known example and comparing it to
   `ADMIN_GUIDE.md` §7.2.
3. **Find who was affected.** Every order stores its full price breakdown — every step, in
   order, with the rule that caused it. Search orders for the service in the affected date
   range and read the breakdowns. You do not have to reconstruct anything; the arithmetic
   was recorded at the time.
4. **Decide the remedy**, and make it the same for everyone:
   - **Undercharged?** In almost every case, absorb it. Chasing customers for more money
     after they have paid costs more goodwill than it recovers. Consider it only for large
     amounts on bookings that have not yet happened.
   - **Overcharged?** Refund the difference, every affected customer, proactively, with an
     apology. Do not wait to be asked.
5. **Fix the rule** and check the preview and a test price before saving.
6. **Record what happened** — a note on the affected bookings and an entry in your own
   incident log.

**Prevention.** After creating or editing any pricing rule, price one booking in the
affected window and one outside it. Two minutes of checking prevents this entirely.

### 3.6 The facility must close right now

See `ADMIN_GUIDE.md` §2.4 for the full procedure. The operator's short version:

1. Create a **whole-facility block** for the affected window from `/admin/calendar`.
2. It will refuse and list the affected bookings. Read the list.
3. Override with a written reason (requires the conflict-override permission).
4. Cancel or move each affected booking deliberately — the block does **not** cancel them.
5. Send the closure notice. Confirm the notification job is actually running before you
   rely on it ([§2.2](#22-send-queued-notifications)).

---

## 4. Data problems

### 4.1 Duplicate households

**How they happen.** A family books online as "Sarah Alvarez" with one email, then phones
and the desk creates "S. Alvarez" with a different phone number. Now there are two accounts,
credits split across both, waivers on the wrong one.

**Symptoms.** A customer says their package credits are missing. A player appears twice in a
search. Waivers show as unsigned for someone who definitely signed.

**Detection.** Look for households sharing a phone number, sharing an email, or with very
similar names created within a short window of each other. Run this monthly; duplicates are
much cheaper to merge before either side has much history.

**Before merging, gather:**

| For each duplicate | Check |
| --- | --- |
| Participants | Are they the same children, or genuinely different? |
| Bookings | Past and future, on both |
| Package purchases and remaining credits | On both |
| Memberships | Two active memberships is a billing problem as well as a data one |
| Account credit balance | On both |
| Signed waivers | Which participant record they are attached to |
| Saved cards | These belong to a Stripe customer and do not merge trivially |

**Merging, in order:**

1. **Choose the survivor** — normally the one with the membership, or failing that the one
   with more history.
2. **Move participants** to the survivor. If the same child exists on both, keep one record
   and reattach that child's bookings, waivers and lesson notes to it.
3. **Move bookings** by repointing them at the survivor household.
4. **Move package credits by writing ledger transactions, never by editing balances.**
   Write a `transfer_out` on the losing purchase and a `transfer_in` on the survivor, with a
   note naming the merge. Both balances then recompute correctly and the history explains
   itself. See `ADMIN_GUIDE.md` §8.2.
5. **Move account credit** the same way: one transaction out, one in, both with a reason.
6. **Handle memberships deliberately.** If both have one, cancel the duplicate subscription
   in Stripe as well as here, and refund any double-billed period.
7. **Deactivate the loser** rather than deleting it, and note on it which household it was
   merged into.
8. **Tell the family** which email and phone number are now on the account.

**Prevention.** Train the desk to search before creating — `/desk/customers` searches name,
email and phone. The quick-create form on the walk-in screen exists for genuinely new
families, not for saving ten seconds.

### 4.2 A resource that never gets booked

Almost always an attribute type problem. A cage saved with `length_ft` as the text "35"
rather than the number 35 will never match a service asking for the number. Nothing errors;
the cage is simply never a candidate.

**Check:** open `/admin/resources`, edit the resource, and compare its attribute types
against a working sibling. See `ADMIN_GUIDE.md` §3.3.

### 4.3 A service that shows no availability

Open the service in the editor and read the preview panel — it reports each requirement as
OK or Blocked with a candidate count and a reason. The diagnosis table in
`ADMIN_GUIDE.md` §5.10 lists every common cause and its fix.

---

## 5. Investigating a claimed double-booking

A customer or a coach says two bookings were given the same cage at the same time.

**They should not be able to be, and you can prove it either way in about five minutes.**

### 5.1 Why it should be impossible

- Every commitment of a resource — a booking, a checkout hold, a maintenance block, a
  closure, coach time off — becomes a row in the **same** reservations table. There is no
  second calendar to fall out of sync with.
- Each row stores a **blocked window**: the activity time with buffers, setup and cleanup
  pushed into it. A lesson from 4:00 to 5:00 with a five-minute after-buffer holds the cage
  from 4:00 to 5:05.
- The database carries an **exclusion constraint** across (resource, slot index, blocked
  window). Two blocking rows for the same resource and the same slot index whose windows
  overlap **cannot both exist**. The second insert fails.
- Shared-capacity resources — the lobby, capacity 3 — hand out a distinct slot index per
  concurrent reservation, so capacity is enforced by the same constraint rather than by
  application logic.
- Availability search, holds, direct booking, rescheduling and camp materialisation all go
  through the same planning function, so they cannot disagree about what a booking consumes.

### 5.2 How to prove what happened

1. **Get the two confirmation codes** and the cage code and time from the complainant.
2. **Look at the reservations for that resource in that window.** For each row you get: the
   resource, what owns it (booking, block, or hold — exactly one), the requirement label
   ("Coach", "Mound Cage", "HitTrax Unit"), the status, the activity start and end, the
   buffers, the blocked window, and the slot index.
3. **Read the result. There are only five possible answers:**

| What you see | What it means | What to tell them |
| --- | --- | --- |
| Two rows, overlapping blocked windows, same slot index, both blocking | A genuine constraint violation. This should be impossible | Escalate immediately with both booking ids. Do not resolve it quietly |
| Two rows, **adjacent but not overlapping** — one ends 5:05, the next starts 5:05 | Working correctly. The complaint is about *feel*, not double-booking | "They're back to back with a five-minute changeover" |
| Two rows, one with status cancelled or released | Not a double-booking. One was cancelled | Show the cancellation time |
| Two rows, **different cages** | Somebody walked into the wrong cage, or was told the wrong number | Check the codes on each booking and correct the person, not the data |
| Only one row | There is only one booking. The other family has a booking for a different time or day | Check the second confirmation code |

4. **Cross-check the audit log** for both booking ids. It gives you the whole life of each
   one in order: created, rescheduled, cancelled, and by whom. This is where you find "it
   was moved into that cage at 4:52 PM by a member of staff" — which is a *human* action,
   fully permitted and fully recorded, not a system failure.
5. **Check for a conflict override.** If someone blocked or booked over an existing booking,
   there is an override record naming the resource, the affected reservations, the written
   reason and the person. That is the single most likely explanation for a real-world
   collision, and it is not a bug — it is somebody exercising an authority they hold.

### 5.3 The likely real explanations, in order

1. **Two adjacent bookings.** Ninety percent of these. Families overlap in the doorway
   during the changeover buffer and it feels like a clash.
2. **A staff override.** Someone with the conflict-override permission deliberately booked
   or blocked over an existing booking, with a reason. Read the audit entry.
3. **The wrong cage number was communicated.** The reservation is correct; the sentence
   spoken at the counter was not.
4. **A cancelled booking that the family did not know was cancelled.**
5. **An actual constraint violation.** Essentially never. If you genuinely see one,
   escalate; do not patch the data.

---

## 6. Backup and restore

### 6.1 What must be backed up

| What | Why |
| --- | --- |
| The Postgres database | Everything. Bookings, customers, waivers, the audit log, the money ledgers |
| Uploaded files | Signed waiver documents, participant photos, anything in the files table |
| Environment configuration | Database URL, Stripe keys, the webhook signing secret |

Card details are never stored here — they live with Stripe, referenced by token. That is a
deliberate reduction in what a backup can leak, and it also means a database restore does
not restore payment credentials.

### 6.2 Expectations

| Measure | Target |
| --- | --- |
| Backup frequency | Continuous point-in-time recovery, or nightly full plus transaction logs |
| Retention | 30 days of daily, 12 months of monthly |
| Recovery point objective (how much data you can afford to lose) | 5 minutes |
| Recovery time objective (how long a restore may take) | 1 hour |
| Restore rehearsal | **Quarterly.** A backup nobody has restored is a hypothesis, not a backup |

### 6.3 Restore procedure

1. **Stop writes.** Put the application into maintenance so nothing new is created against a
   database you are about to replace.
2. **Record the exact restore point** you are targeting, and how much data will be lost
   between that point and the failure.
3. **Restore into a new database instance**, not over the top of the live one. If the
   restore is bad you still have the original.
4. **Verify before switching over:**
   - Count today's bookings and compare with what the front desk remembers.
   - Check that the audit log's most recent entry is close to the restore point.
   - Check that package and account-credit balances match the sum of their ledgers. They
     are rebuilt by trigger, so if they disagree the restore is incomplete.
   - Load `/admin` and `/desk` against the restored database.
5. **Point the application at the restored database** and take it out of maintenance.
6. **Reconcile the gap.** Anything created between the restore point and the failure is
   gone. In practice:
   - **Payments** — Stripe has them. Replay the webhook events for that window from the
     Stripe dashboard; they will be reprocessed and the bookings brought back into line.
   - **Bookings made in the gap** — the customers have confirmation emails you no longer
     have records of. Ask the desk to re-enter anything a customer produces, and expect a
     few days of it.
   - **Waivers signed in the gap** — those families will be prompted again. Unavoidable.
7. **Write up what happened**, including the actual recovery point and time achieved.

### 6.4 What you cannot restore

The audit log is append-only and immutable *by design* — the database refuses updates and
deletes even from the owner. That protects it from tampering, but it does not protect it
from a lost backup. **Its evidentiary value depends entirely on your backups.** Treat the
backup schedule as a compliance control, not an IT chore.

---

## 7. Deploys: before and after

### 7.1 Before

1. **Pick the window.** The facility is open 9:30 AM – 8:30 PM daily. Deploy before 9:00 AM
   or after 9:00 PM. Never deploy during a school-break camp week.
2. **Run the checks:**
   - Type checking passes.
   - The SQL test suite passes — it exercises the scheduling engine and the add-on-aware
     allocation.
   - The concurrency test passes. This is the important one: it fires simultaneous booking
     attempts at the same slot and asserts that exactly one succeeds. **Never ship a change
     to scheduling, holds or reservations with this test failing or skipped.**
3. **Take a fresh backup** and note the restore point.
4. **Review any database migration.** Read it. Confirm it is additive where possible, and
   know how to reverse it if it is not.
5. **Capture a "before" snapshot** for comparison afterwards: today's booking count,
   today's revenue figure, the number of active services, and the price of one known
   booking.
6. **Tell the front desk** a deploy is happening and what to watch for.

### 7.2 After

Work through this within ten minutes of the deploy.

| # | Check | Pass looks like |
| --- | --- | --- |
| 1 | Public home page and one service page | Render, with prices |
| 2 | `/book` — pick a service and a date | Real times appear |
| 3 | Availability for a known-busy service | Same shape as before the deploy, not suddenly empty and not suddenly wide open |
| 4 | Price one known booking | Matches your "before" figure to the cent |
| 5 | `/desk` | Board renders; today's counts match the "before" snapshot |
| 6 | `/admin` | Tiles carry numbers |
| 7 | `/kiosk` | Welcome screen |
| 8 | `/coach` as a coach account | Today's sessions listed |
| 9 | Make a real test booking end to end, then cancel it | Succeeds; the cancellation returns the slot |
| 10 | Stripe webhook endpoint | Sends a test event, gets 200 |
| 11 | All five background jobs | Scheduled and have run since the deploy |
| 12 | Error logs | No new error class in the first ten minutes |

### 7.3 Rolling back

1. **Application-only change, no migration** — redeploy the previous build. Straightforward.
2. **Change including a migration** — do **not** reflexively restore the database. A restore
   loses every booking taken since the deploy. Prefer, in order:
   - Redeploy the previous application build if it still works against the new schema (it
     usually does, when the migration was additive).
   - Apply a corrective migration.
   - Restore from backup only if the data itself is corrupted, and then follow
     [§6.3](#63-restore-procedure) including the reconciliation step.
3. **Tell the front desk** what changed and what to do in the meantime.

### 7.4 Two things that make deploys safe here

Worth knowing, because they change how much you need to worry:

- **The scheduling rules live in the database, not the application.** A frontend deploy
  cannot introduce a double-booking, because the guarantee is a database constraint that the
  application cannot bypass.
- **New services, prices, resources, coaches and policies are configuration, not code.**
  Most of what the business wants changed does not need a deploy at all. If someone is
  asking for a release to add a service, point them at `ADMIN_GUIDE.md` §5.
