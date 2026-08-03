# ATD Baseball Company — Staff Training

For everyone who works the counter and everyone who coaches. Keep this open on a tab for
your first two weeks.

Front desk lives at **`/desk`**. Coaches live at **`/coach`**. The lobby check-in screen is
**`/kiosk`**. If you can see a screen, you are allowed to use it — the system hides what you
are not permitted to do rather than letting you press it and fail.

**The facility:** ATD Baseball — Training Center, 1200 Diamond Way, Wallingford.
Open 9:30 AM – 8:30 PM, seven days.

| Code | What it is |
| --- | --- |
| CAGE-1 | 50 ft, has a mound |
| CAGE-2, CAGE-3, CAGE-4 | 35 ft |
| CAGE-5 | 70 ft, HitTrax, has a mound |
| HITTRAX-1 | The simulator itself. It lives in Cage 5 |
| MACHINE-1 / MACHINE-2 | Iron Mike (arm) / Hack Attack (wheel) |
| PARTY-1 | Party room, seats 24 |
| LOBBY | Waiting area — can host up to 3 things at once |

---

## Contents

**Front desk**

1. [Opening checklist](#1-opening-checklist)
2. [Closing checklist](#2-closing-checklist)
3. [The Today screen, section by section](#3-the-today-screen-section-by-section)
4. [Checking in a household](#4-checking-in-a-household)
5. [Taking a walk-in in three taps](#5-taking-a-walk-in-in-three-taps)
6. [Extending a rental](#6-extending-a-rental)
7. [Changing a cage or a coach on a live booking](#7-changing-a-cage-or-a-coach-on-a-live-booking)
8. [Same-day cancellations and no-shows](#8-same-day-cancellations-and-no-shows)
9. [Waitlist offers and claim windows](#9-waitlist-offers-and-claim-windows)
10. [Kiosk troubleshooting](#10-kiosk-troubleshooting)

**Coaches**

11. [Coach: your four screens](#11-coach-your-four-screens)

**Everyone**

12. [What to say](#12-what-to-say)
13. [When to get a manager](#13-when-to-get-a-manager)

---

## 1. Opening checklist

Allow ten minutes. Do it in this order.

1. Sign in and open **`/desk`**. The screen is called **Today's operations**. It refreshes
   itself every 30 seconds; the grey text at the top says how many seconds ago.
2. Read the red **Facility alerts** band at the top, if there is one. This is where
   maintenance, closures and weather blocks appear, with the times and which cages they
   affect. If a cage is down today, you need to know before the first family walks in.
3. Read the counts on each section heading. Write down anything that is not zero in
   **Missing waivers** and **Unpaid balances** — those are your phone calls for the morning.
4. Open **`/desk/resources`** and walk the floor against it. Every cage that the screen says
   is free should physically be free and tidy — nets up, buckets stocked, screens in place.
5. Check the kiosk in the lobby. It should be showing the navy **"Welcome to ATD — Check in
   here"** screen with three big buttons. If it is showing anything else, see
   [§10](#10-kiosk-troubleshooting).
6. Check the card terminal is powered and paired.
7. Look at the first hour under **Next 60 minutes** and know who is coming.

---

## 2. Closing checklist

1. **`/desk`** — **Not checked in** should be empty. Anything left there is a no-show that
   nobody marked. Mark it now ([§8](#8-same-day-cancellations-and-no-shows)); tomorrow it is
   guesswork.
2. **`/desk`** — **Unpaid balances**. Anything still outstanding after the family has left
   is a phone call for tomorrow. Add a note to the booking so the next person knows.
3. **`/desk/payments`** — count the till against the day's cash and cheque payments.
4. Walk the floor. Nets down or up per the closing standard, machines off and unplugged,
   HitTrax powered down, party room reset.
5. Tap **Start over** on the kiosk so it is not showing anybody's afternoon overnight.
   (It clears itself after 20 seconds of no touching, but check anyway.)
6. Last look at tomorrow's **Next 60 minutes** equivalent — open `/admin/bookings` if you
   have access, or ask a manager to flag anything unusual for the morning.

---

## 3. The Today screen, section by section

**`/desk`** — "Today's operations". Seven sections, each with a count badge. Zero is good.
Every booking row shows the time, the household, the players, the service, the cage code,
the coach, the status, any balance due, the household's phone number as a tap-to-call link,
and the confirmation code.

### Now
Sessions running right this second.

**What to do:** normally nothing. The buttons available are **Change cage**, **Change coach**
and **Add note** — for when something goes wrong mid-session.

### Next 60 minutes
Everyone arriving within the hour.

**What to do:** check them in as they walk through the door. This is your main working
section during a busy evening.

### Not checked in
Their session has started and nobody has checked them in.

**What to do, in order:**
1. Look around the lobby — very often they are here and nobody pressed the button.
2. If they are here, press **Check in**.
3. If they are not here and it is more than about ten minutes past, tap their phone number
   and call.
4. If you cannot reach them and the session is effectively lost, press **No-show**.
   See [§8](#8-same-day-cancellations-and-no-shows).

### Missing waivers
Someone coming in today does not have a current signed waiver. Each row tells you which
player, which waiver, and why: **never signed**, **expired**, or **signed an older version**.

**What to do:** press **Send waiver**. It emails the parent a link they can sign on their
phone in about a minute. If they are already standing in front of you, send them to the
kiosk — it will prompt for the signature as part of checking in.

**Nobody swings a bat without a current waiver.** If a parent refuses or cannot sign, that
is a manager decision, not yours.

### Unpaid balances
Money owed on a booking that is happening today.

**What to do:** press **Collect $X**. It takes you to `/desk/payments` with the booking
already loaded. If the button says **needs a manager**, you do not have payment permission
— get one.

### Cancellations and no-shows
Today's cancelled and missed sessions, for reference.

**What to do:** nothing routine. Add a note if a family explained themselves, so the
manager has the context when they review the week.

### Waitlist
Households waiting for an opening. Rows that have been offered a slot show the offered
time and when the offer expires.

**What to do:** see [§9](#9-waitlist-offers-and-claim-windows).

### If the board stops updating
An amber **"Not refreshing"** band appears and tells you how old the information is. Check
the network, then press **Refresh now**. Do not make decisions from a stale board — a slot
that looks free may have been taken.

---

## 4. Checking in a household

### The normal case

1. Find the family on `/desk` under **Next 60 minutes** (or **Not checked in**).
2. Press **Check in**.
3. Tell them which cage: it is on the row next to the pin icon, e.g. "CAGE-3, on your left".
4. The button changes to **Checked in** and the coach sees it on their own screen.

### They arrive and are not on the board

| Check | Then |
| --- | --- |
| Is it tomorrow's booking? | Look at the date on their confirmation email |
| Is it a different location? | We only have Wallingford, so this is rare |
| Did they book at all? | Search `/desk/customers` by name or phone. If there is no booking, treat it as a walk-in ([§5](#5-taking-a-walk-in-in-three-taps)) |

### Check-in when a waiver is missing

You will see the family in **both** the arrivals section and **Missing waivers**.

1. Press **Send waiver** on the Missing waivers row. The parent gets an email link.
2. Say: *"Before Maya goes in I just need a signature on the liability waiver — I've sent
   it to your email, it takes about thirty seconds on your phone. Or the screen by the door
   will walk you through it."*
3. Point them at the kiosk if they would rather do it there. Enter phone number, tap the
   player, sign, done.
4. The row disappears from Missing waivers within a few seconds of them signing.
5. **Then** check them in.

**If they cannot sign** — no phone, no email, wrong parent present — that needs a manager.
A manager can record an override that lets the child play, with a reason, and it is logged.
You cannot do this yourself and you should not try to talk your way around it.

### Check-in when a balance is owed

The row shows a red **"$X due"** badge.

1. Check them in first. Do not make a family stand in the doorway while you take a card —
   get the child into the cage.
2. Then press **Collect $X** and take payment at `/desk/payments`.
3. If the parent wants to pay later, that is fine — leave the balance and add a note
   saying when they said they would pay.
4. If you do not have payment permission the button says **needs a manager**. Check them
   in anyway and tell a manager there is money to collect.

---

## 5. Taking a walk-in in three taps

**`/desk/walk-in`**. The screen is built for someone standing at the counter with a family
watching, so the defaults are already right most of the time.

1. **Tap 1 — What do they want.** Big buttons, one per service, each showing the default
   length and price. Tap one. If they want a different length, tap a duration button
   underneath.
2. **Tap 2 — Free in the next 3 hours.** The screen already shows every genuinely free start
   time, with the cage code and coach on each button. Tap the time they want.
3. **Tap 3 — Book it.** Choose how they are paying (or leave it as "collect later") and
   press the book button.

You get a confirmation code on screen. Read it to them or point them at the email.

**The times on this screen are real.** They come from the same engine as the public website,
including buffers, coach hours and any cage that is down for maintenance. If a time is
offered, it is genuinely available.

### Who is booking

The right-hand panel is the household. Three cases:

| Case | What to do |
| --- | --- |
| Existing customer | Type a name or phone number, pick them, tick which players are in this session |
| Brand new family | Press the new-customer button, enter adult first and last name, email, phone, and the player's first name. Thirty seconds |
| Genuinely anonymous (a stranger paying cash for 30 minutes) | Leave the household blank and book it. It shows on the board as "Walk-in" |

Creating a customer needs the customer-write permission. If you do not have it the panel
says so — get a manager, or book it without a household and have someone attach the account
afterwards.

### Nothing is free

The screen says **"Nothing free in the next three hours"**. Options, in order:

1. Offer a **shorter** session — a 30-minute slot often fits where 60 does not.
2. Offer a **different service** — the 35 ft cages are busiest; the 50 ft or HitTrax cage
   may be open.
3. Offer a **later time** — check `/admin/calendar` if you have access, or the customer's
   own booking page at `/book`.
4. Offer the **waitlist** from their account page. If someone cancels, they get an
   automatic text.

---

## 6. Extending a rental

A family in a cage wants another half hour.

### When the next slot is free

1. Open `/desk/resources` and look at the cage they are in. If nothing follows them, you
   have room.
2. Extend the booking to the new end time. The system re-checks everything — the cage, the
   buffers, opening hours — and either accepts it or refuses. It will never let you create
   an overlap.
3. Take payment for the extra time.

Say: *"Yes — nobody's in after you, so I can add another half hour. That's $22.50 for the
extra thirty minutes. Want me to add it?"*

### When it is not free

The system will refuse the extension. Do not fight it — there is a genuine booking in that
cage, buffers included.

Say: *"I can't extend that one — there's a lesson coming into that cage at 6:30 and they
need it set up. What I can do is put you in Cage 4 from 6:30 for another half hour if you
want to move across, or I can get you booked in for tomorrow."*

Then check `/desk/walk-in` for a free slot in a different cage starting when theirs ends.
Moving cages mid-session is a perfectly good answer and families rarely mind.

**Never** promise time you have not confirmed on the screen. "I'm sure it's fine" is how
two families end up in the same cage.

---

## 7. Changing a cage or a coach on a live booking

Use this when a cage has a problem, a coach is unwell, or a family asks to move.

1. Find the booking on `/desk` — under **Now** or **Next 60 minutes**.
2. Press **Change cage** or **Change coach**.
3. A panel opens saying *"Finding what is free…"* and then lists what is genuinely free for
   that **whole window**, including buffers.
4. Tap the replacement. The booking moves. Everyone's screen updates — yours, the coach's,
   the calendar.

**If the panel says "Nothing else is free for that whole window"** there is genuinely
nothing. Options: shorten the session so it fits somewhere, move it to a later time, or get
a manager.

If the buttons say **needs a manager**, you do not hold the reassign permission.

**Changing a coach on a lesson a family specifically booked with a named coach is a
conversation, not a click.** Tell them first ([§12](#12-what-to-say)).

---

## 8. Same-day cancellations and no-shows

### What the system decides on its own

When a booking is cancelled, the system works out how many hours are left before the start
and applies the policy tier that matches. You do not calculate anything and you should not
promise anything before you see the screen.

For an ordinary lesson under the **Standard Lesson Policy**:

| They cancel | The system does |
| --- | --- |
| More than 24 hours ahead | Full refund; package credit comes back |
| Between 12 and 24 hours | 50 percent refund; package credit comes back |
| Under 12 hours | No refund; the session credit is forfeited |
| Rescheduling more than 24 hours ahead | Free |
| Rescheduling between 2 and 24 hours ahead | $15.00 change fee |
| No-show | Credit forfeited |

Camps and parties have their own, longer-notice policies. The screen always tells you the
outcome in plain English before anything is committed — read it out to the customer rather
than guessing.

### Marking a no-show

1. `/desk` → **Not checked in**.
2. Call them first. Genuinely — a lot of "no-shows" are a family sitting in the car park.
3. If it is a real no-show, press **No-show**.
4. What happens: the booking is marked as a no-show, every player on it is marked absent,
   and it is logged with your name on it.
5. **The cage is not handed back.** A no-show consumes the slot; it does not free it up.
   That is deliberate — the coach was there and the cage was held.

### What needs a manager

| Situation | Why |
| --- | --- |
| Any refund | Front-desk accounts cannot issue refunds |
| Overriding the policy outcome | Only a manager can give more back than the policy says |
| Waiving a no-show fee | Same reason |
| A cancellation the customer is angry about | Do not negotiate. Hand it over |

Say: *"Let me get my manager — she can look at that properly for you."* Do not say "the
computer won't let me".

---

## 9. Waitlist offers and claim windows

When a slot frees up — usually because someone cancelled — the system offers it to up to
three waiting households at once and texts them a claim link.

| Fact | Detail |
| --- | --- |
| How long they have | **120 minutes** by default |
| Who gets it | Up to three households, in waitlist order |
| Who wins | The first to click the link and complete it |
| What the others see | "That spot has already been claimed" |

On `/desk`, the **Waitlist** section shows who is waiting and, for offered rows, the offered
time and the exact expiry time.

**Two people cannot claim the same slot**, even if they click at the same second. The system
locks the offer while one is being processed.

### Common questions

**"I got a text but the link says it's gone."** Someone else claimed it first. Say:
*"I'm sorry — that one went to another family a few minutes ago. You're still on the list
and you keep your place, so the next opening comes to you first."* Then check whether
anything else genuinely suits them at `/desk/walk-in`.

**"My link expired."** Offers last two hours. Their waitlist place is not lost. Offer to
look for something now.

**"Can you just hold it for me?"** No — the whole point is that the offer is fair and
time-limited. But you can book them into any slot that is genuinely free right now.

**"Take me off the list."** They can do it themselves at `/account/waitlists`, or ask a
manager.

---

## 10. Kiosk troubleshooting

The lobby screen at **`/kiosk`**. Deliberately simple: no navigation, huge type, and it
clears itself after 20 seconds of nobody touching it so one family's afternoon is never on
screen when the next family walks up.

Customers check in three ways: **phone number**, **confirmation code**, or **scanning the QR
code** from their confirmation email.

| Problem | What is happening | Fix |
| --- | --- | --- |
| "We can't find that number" | The number on the account is different from the one they typed | Check the household at `/desk/customers` and check them in manually |
| "Not quite enough — keep going" | Fewer than four digits entered | Ask them to enter the full 10-digit number |
| Their booking is not shown | The kiosk only shows **today** | Check the date on their confirmation |
| Stuck on someone else's screen | Nobody pressed Start over | Press **Start over** at the top right |
| Screen frozen or blank | Browser or tablet problem | Reload the page; if that fails, restart the tablet and reopen `/kiosk` |
| QR scanner not reading | The scanner types into the screen and presses Enter | Try the confirmation-code option instead; the code is on their email |
| Waiver screen appears | Someone on the booking has no current waiver | Let them sign there — it is quicker than email. They tick the medical confirmation, type their full name, and press **Sign and continue** |
| They press "Not now" on the waiver | They are not covered | They still need to sign before playing. Deal with it at the counter |
| "There is a balance on this booking" | Money is owed | They still check in. Take the payment at the counter |
| Kiosk completely down | | Check everyone in manually from `/desk`. Nothing is lost — the kiosk is a convenience, not the system |

**What the kiosk deliberately does not show:** amounts owed, medical information, contact
details, or anything about other families. It shows first names, times, and two flags. Do
not ask anyone to use it to look something up for you.

---

## 11. Coach: your four screens

Sign in and you land on **`/coach`**. Four tabs at the bottom on a phone, along the top on a
laptop.

| Tab | Address | What it is for |
| --- | --- | --- |
| Today | `/coach` | Your sessions today, with attendance buttons |
| Calendar | `/coach/calendar` | Your week and month ahead |
| Availability | `/coach/availability` | The hours you work, specific dates, and time off |
| Earnings | `/coach/earnings` | Your own pay |

You see your own sessions and your own pay. Facility revenue, other coaches' pay and
customer payment details are not part of your account — not hidden, genuinely not there.

### 11.1 Setting your availability

**`/coach/availability`** has three cards.

**Weekly hours** — the pattern you normally work, day by day.

1. Set a from and to time for each day you work.
2. Press save.
3. **If removing hours would strip out lessons that are already booked, the screen shows
   you those lessons before you save**, not afterwards. Read the list. If there are
   conflicts, sort them with the front desk first — the lessons do not vanish just because
   you changed your hours.
4. When there is nothing in the way it says **"Nothing conflicts"** and saves cleanly.

**Specific dates** — a single date that differs from your pattern. Choose the date, say
whether you are available or not that day, and if available, from when to when. A specific
date always beats the weekly pattern.

**Two things worth knowing:**

- A lesson has to fit **entirely** inside your window, including the buffer after it. If
  your day ends at 8:30 PM, a 60-minute lesson with a 5-minute buffer cannot start at
  8:00 PM. Nobody is offered it.
- You have a **minimum lead time** — most coaches 2 or 3 hours. Nobody can book you inside
  that, which is what stops a lesson appearing on your phone 20 minutes before it starts.

### 11.2 Requesting time off

Bottom card on the same screen.

1. Enter the from and until dates, and a reason if you can — it makes approval quicker.
2. If lessons already fall inside that window, the screen tells you how many **before you
   submit**. Requesting time off does **not** cancel them.
3. Submit. A manager approves it.
4. Once approved, you are blocked out and nobody can book you.
5. **The existing lessons inside the window are still yours until someone moves them.**
   Talk to the desk about each one.

You can withdraw a request that has not been actioned.

### 11.3 Marking attendance

**`/coach`** → your session → the players are listed.

1. When the session starts, mark it started.
2. Tap each player: **Present**, **Absent**, **Late**, or **Excused**.
3. When you are done, mark the session complete.

Do it in the moment, not at the end of the night. Attendance drives the no-show reporting
the owner reads on Monday, and a session left as "unknown" is worthless data.

Before you start, the screen may warn you about:

- **No current waiver** — do not start. Send the player to the front desk.
- **Medical note on file** — if you can see the detail, read it. If you see only a flag
  saying there is a note, that is intentional: ask the director or the front desk. Medical
  detail is restricted, and that is not a slight on you.

### 11.4 Writing lesson notes

Open a session at `/coach/sessions/[booking]`, then the player.

1. **What happened in this session** — the main note. Write it for the *next* coach who
   sees this player, not for yourself. "Working front foot down, still drifting on
   off-speed. Cue: land closed." is useful. "Good session" is not.
2. **Focus areas** — tag the note so the player's history is searchable.
3. **Metrics** — optional numbers: exit velocity, spin, whatever you measured.
4. **Sharing** — you choose whether the parent sees a note. Default is staff-only. Share
   the ones a parent can act on; keep development observations internal until you are sure
   of them.

The player's previous notes are on the same screen. Read them before the session, not after.

### 11.5 Reading your earnings

**`/coach/earnings`**.

Four tiles: sessions taught, gross revenue, eligible revenue, and **your compensation**
(the number that matters, in red). Below that, a line per session, and pay-period tabs if
more than one period is open. There is an **Export CSV** button for your own records.

| Term | What it means |
| --- | --- |
| Gross revenue | What the customer paid for sessions you taught |
| Eligible revenue | The part of that your compensation is calculated on, after any exclusions |
| Your compensation | What you are owed |
| Adjustments | Corrections, each with a reason on its line |

House rates today: 60 percent of eligible revenue as standard, 70 percent for the hitting
director, and a flat $45.00 an hour for camp work. Compensation lines appear once a session
is settled, so today's lesson will not show up instantly.

If a number looks wrong, take it to the location administrator with the session date and
the confirmation code. Do not raise it with the customer.

---

## 12. What to say

Use these. They are honest, they do not blame "the system", and they leave you somewhere
to go.

| The moment | Say this | Do not say |
| --- | --- | --- |
| **The slot was taken while they were paying** | "That one's just gone, I'm sorry — someone finished checking out about a minute before you. I've got 5:15 in Cage 3 or 6:00 with the same coach. Which suits you better?" | "The system lost it" |
| **Their coach is out sick** | "Marcus is out today, I'm sorry. Dana has the same hitting qualification and is free at your time — or if you'd rather wait for Marcus specifically, I'll move you to Thursday at no charge." | "We'll just put you with someone else" (never swap a named coach silently) |
| **The camp is full** | "That one's full, but there are two on the waitlist ahead of you and places do come free. Shall I add you? You'd get a text the moment something opens, and you'd have two hours to grab it." | "You should have booked earlier" |
| **A refund is refused by policy** | "The policy on lessons is a full refund up to 24 hours out — this one's inside twelve, so it doesn't refund automatically. Let me get my manager, because she can look at the circumstances." | "There's nothing I can do" |
| **They want a refund and you have no permission** | "I can't process refunds from my account — let me get someone who can." | "I'm not allowed" |
| **They have no waiver and want to play** | "I just need a signature on the liability waiver before Maya can get in the cage — it's about thirty seconds on your phone, and I've just sent you the link." | "You can't play" |
| **They are late and the session is nearly over** | "You've got until 5:05 in Cage 2 — that's about twenty minutes. Shall I get you started now and I'll see if the coach can stretch a little at the end?" | "You've missed it" |
| **A cage is down** | "Cage 3 is out for repair today, so I've moved you to Cage 4 — same length, just the other side of the netting." | "Something's broken" |
| **You have to move a family mid-session** | "I need to move you to Cage 4 for the last half hour — there's a lesson coming into this one and they need it set up. It's the same cage size and I'll help you carry the bucket across." | "You have to move" |
| **A balance is owed and they are in a hurry** | "There's $45 outstanding on this — do you want to settle it now, or shall I leave it on the account and you can pay when you pick up?" | "You owe us money" |
| **A price is different from what they remember** | "Evenings after four are the peak rate, so that's the difference. Off-peak is quite a bit cheaper if a weekday morning ever works for you." | "It's always been that price" |
| **They ask you to hold a waitlist spot** | "I can't hold it, but you keep your place at the top of the list, so the next opening comes to you first. And I can look right now for anything that's free today." | "Fine, I'll hold it" |
| **You genuinely do not know** | "I'm not sure — let me find out rather than guess." | Guessing |

---

## 13. When to get a manager

Get one **cheerfully and early**. Handing something over quickly is good service; trying to
handle it and getting it wrong is not.

| Situation | Why it needs a manager |
| --- | --- |
| **Any refund** | Front-desk accounts cannot issue refunds. Set by the `allow_front_desk_refund` setting |
| **Any discount or price change** | Every discount is attributed to a named person, so it must be someone with the authority |
| **Overriding a cancellation policy** | Only a manager can give back more than the policy allows, and the reason is recorded |
| **Waiving a no-show fee** | Same reason |
| **Letting a child play without a signed waiver** | Requires the waiver-override permission. It is logged with the reason and the person's name. This exists for genuine emergencies |
| **Booking over an existing booking** | Requires the conflict-override permission plus a written reason, and shows the full list of affected families first |
| **Blocking a cage or closing the facility** | Requires the schedule-block permission |
| **Creating or editing a service, price or resource** | Configuration change — it affects everyone from that moment |
| **Cancelling a whole camp or program** | Many families, refunds and communications at once |
| **A customer complaint about money** | Do not negotiate at the counter |
| **A customer complaint about a coach** | Never discuss a colleague with a customer |
| **An injury, or anything that might become one** | Manager plus incident record, immediately. Never a judgement call at the desk |
| **A parent you do not recognise collecting a child** | Check the authorised-pickup list on the household account. If in doubt, do not release the child |
| **Anyone asking for another family's information** | Never, under any circumstances |
| **The system says something you do not believe** | Get someone before you work around it. The screen is almost always right, and working around it is how double-bookings happen |

**A general rule.** If you find yourself thinking "I'll just do it this once", that is the
signal to get a manager. The system asks for a manager precisely at the points where a
mistake is expensive or hard to undo.
