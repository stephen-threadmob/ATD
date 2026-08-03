-- =============================================================================
-- SEED 03 — A realistic, fully-booked operating day
--
-- Every booking below is created through atd.create_booking, which means it
-- went through the real allocation planner and the real exclusion constraint.
-- Nothing here is hand-placed onto a calendar; if two of these collided, this
-- file would fail to load. That is the point.
-- =============================================================================
set search_path = atd, public;

-- Demo households -------------------------------------------------------------
do $$
declare
  v_u uuid; v_h uuid; v_p uuid;
  families text[][] := array[
    array['Rivera','Maria','maria.rivera@example.com','+15555551201'],
    array['Chen','David','david.chen@example.com','+15555551202'],
    array['O''Brien','Katie','katie.obrien@example.com','+15555551203'],
    array['Patel','Anil','anil.patel@example.com','+15555551204'],
    array['Jackson','Tanya','tanya.jackson@example.com','+15555551205'],
    array['Nowak','Peter','peter.nowak@example.com','+15555551206'],
    array['Silva','Renata','renata.silva@example.com','+15555551207'],
    array['Brennan','Meghan','meghan.brennan2@example.com','+15555551208']
  ];
  kids text[][] := array[
    array['Mateo','baseball','11','R','R'],
    array['Ellie','softball','12','L','R'],
    array['Connor','baseball','14','R','R'],
    array['Arjun','baseball','10','R','R'],
    array['Jaylen','baseball','13','L','L'],
    array['Zofia','softball','11','R','R'],
    array['Lucas','baseball','9','R','R'],
    array['Nora','softball','13','R','R']
  ];
  i int;
begin
  for i in 1..array_length(families,1) loop
    insert into atd.users (email, phone, first_name, last_name, sms_consent_at, sms_consent_source)
    values (families[i][3]::atd.email, families[i][4]::atd.phone_e164,
            families[i][2], families[i][1], now() - interval '90 days', 'booking_checkout')
    returning id into v_u;

    insert into atd.households (location_id, name, primary_user_id, source)
    values ('00000000-0000-4000-8000-0000000010c1',
            families[i][1] || ' Family', v_u, 'online')
    returning id into v_h;

    insert into atd.household_members (household_id, user_id, is_primary, relationship)
    values (v_h, v_u, true, 'parent');

    insert into atd.participants
      (household_id, first_name, last_name, date_of_birth, sport, bats, throws,
       skill_level, team_name, shirt_size)
    values (v_h, kids[i][1], families[i][1],
            (current_date - (kids[i][3]::int * 365 + 40))::date,
            kids[i][2]::atd.sport, kids[i][4]::atd.throw_bat_hand, kids[i][5]::atd.throw_bat_hand,
            (array['Beginner','Intermediate','Advanced','Travel'])[1 + (i % 4)],
            (array['Wallingford Wolves','CT Thunder','Valley Storm','Elm City Elite'])[1 + (i % 4)],
            (array['YM','YL','AS','AM'])[1 + (i % 4)])
    returning id into v_p;

    insert into atd.emergency_contacts (household_id, participant_id, name, relationship, phone)
    values (v_h, v_p, families[i][2] || ' ' || families[i][1], 'Parent',
            families[i][4]::atd.phone_e164);

    -- A second child for two of the families, so sibling flows have real data.
    if i in (2,5) then
      insert into atd.participants
        (household_id, first_name, last_name, date_of_birth, sport, bats, throws, shirt_size)
      values (v_h, (array['Sofia','Marcus'])[case when i=2 then 1 else 2 end],
              families[i][1], (current_date - 9*365)::date, 'baseball','R','R','YM');
    end if;
  end loop;
end $$;

-- Waivers on file for most participants ---------------------------------------
insert into atd.signed_waivers
  (waiver_version_id, household_id, participant_id, signer_name, signer_relation,
   signature_data, ip_address, signed_at)
select wv.id, p.household_id, p.id,
       h.name || ' guardian', 'parent', 'Typed signature', '203.0.113.10',
       now() - interval '30 days'
  from atd.participants p
  join atd.households h on h.id = p.household_id
  cross join (select id from atd.waiver_versions
               where template_id = '77000000-0000-4000-8000-000000000001'
                 and retired_at is null) wv
 where p.first_name not in ('Lucas','Nora');   -- two gaps, so the desk has work

-- A membership and a package, so pricing paths are exercised -------------------
insert into atd.memberships (plan_id, household_id, status, current_period_start, current_period_end)
select 'c3000000-0000-4000-8000-000000000002', h.id, 'active',
       date_trunc('month', now()), date_trunc('month', now()) + interval '1 month'
  from atd.households h where h.name = 'Chen Family';

do $$
declare v_pp uuid; v_h uuid;
begin
  select id into v_h from atd.households where name = 'Rivera Family';
  insert into atd.package_purchases
    (package_definition_id, household_id, credits_granted, expires_on)
  values ('c2000000-0000-4000-8000-000000000002', v_h, 10, current_date + 365)
  returning id into v_pp;
  insert into atd.package_credit_transactions (package_purchase_id, kind, delta, note)
  values (v_pp, 'grant', 10, 'Purchased 10-lesson package');
  insert into atd.package_credit_transactions (package_purchase_id, kind, delta, note)
  values (v_pp, 'redeem', -3, 'Lessons taken to date');
end $$;

-- =============================================================================
-- The day itself.
--
-- Rather than hard-coding times (which go stale the moment the catalogue
-- changes), each booking asks atd.find_slots for the first genuinely available
-- slot inside a preferred window and takes it. The board that results is
-- therefore always internally consistent: it is what the engine says is
-- possible, not what a fixture author hoped was possible.
-- =============================================================================
create or replace function atd.demo_book(
  p_service uuid, p_day date, p_from time, p_to time,
  p_household text, p_minutes int default null, p_source text default 'online')
returns uuid language plpgsql as $fn$
declare
  tz text := 'America/New_York';
  v_slot record; v_h uuid; v_b uuid;
begin
  select id into v_h from atd.households where name = p_household;

  select * into v_slot
    from atd.find_slots(p_service, p_day, p_day, p_minutes, '{}'::jsonb, 200)
   where (starts_at at time zone tz)::time >= p_from
     and (ends_at   at time zone tz)::time <= p_to
   order by starts_at
   limit 1;

  if not found then
    raise notice 'demo: no slot for service % between % and %', p_service, p_from, p_to;
    return null;
  end if;

  v_b := atd.create_booking(
    p_service, v_slot.starts_at, v_slot.ends_at, v_h,
    array(select id from atd.participants where household_id = v_h order by date_of_birth limit 1),
    '{}'::jsonb, null, p_source);
  return v_b;
end $fn$;

do $$
declare
  d date; tz text := 'America/New_York';
  v_b uuid; v_block uuid;
begin
  -- Next Saturday: the facility is open 9:30-20:30 and coaches work the
  -- weekend morning shift, which produces the busiest, most interesting board.
  select g::date into d
    from generate_series((now() at time zone tz)::date + 1,
                         (now() at time zone tz)::date + 8, interval '1 day') g
   where extract(dow from g) = 6
   order by g limit 1;
  perform set_config('demo.day', d::text, false);

  -- Morning: private instruction fills the coaches.
  perform atd.demo_book('11000000-0000-4000-8000-000000000001', d, '09:30','10:45','Rivera Family');
  perform atd.demo_book('11000000-0000-4000-8000-000000000002', d, '09:30','11:00','Chen Family');
  perform atd.demo_book('11000000-0000-4000-8000-000000000003', d, '10:00','11:30','Jackson Family');
  perform atd.demo_book('11000000-0000-4000-8000-000000000001', d, '10:30','12:00','Patel Family');
  perform atd.demo_book('11000000-0000-4000-8000-000000000005', d, '11:00','12:30','O''Brien Family');
  perform atd.demo_book('11000000-0000-4000-8000-000000000004', d, '11:30','13:00','Nowak Family');
  perform atd.demo_book('11000000-0000-4000-8000-000000000001', d, '12:30','14:00','Silva Family');
  perform atd.demo_book('11000000-0000-4000-8000-000000000002', d, '13:00','14:30','Brennan Family');

  -- Rentals through the day.
  perform atd.demo_book('11000000-0000-4000-8000-000000000010', d, '09:30','11:00','Nowak Family',  60,'front_desk');
  perform atd.demo_book('11000000-0000-4000-8000-000000000010', d, '11:00','12:30','Jackson Family',60,'walk_in');
  perform atd.demo_book('11000000-0000-4000-8000-000000000012', d, '13:30','15:00','Chen Family',   60,'online');
  perform atd.demo_book('11000000-0000-4000-8000-000000000010', d, '18:30','20:30','Patel Family',  60,'online');

  -- Afternoon birthday party: party room + 2 cages + a host, one transaction.
  v_b := atd.demo_book('11000000-0000-4000-8000-000000000030', d, '15:00','18:00','Jackson Family');
  if v_b is not null then
    update atd.bookings
       set title = 'Jaylen''s 13th Birthday — Grand Slam Package',
           participant_count = 14,
           answers = jsonb_build_object('birthday_child','Jaylen Jackson, 13',
                                        'guest_count','14',
                                        'special_requests','Gluten-free pizza for one guest')
     where id = v_b;
    insert into atd.booking_addons (booking_id, addon_id, quantity, unit_price_cents, total_cents)
    values (v_b,'a1000000-0000-4000-8000-000000000004',1,9000,9000),
           (v_b,'a1000000-0000-4000-8000-000000000005',1,6500,6500);
  end if;

  -- Evening team practice: three cages plus lobby space.
  v_b := atd.demo_book('11000000-0000-4000-8000-000000000031', d, '18:00','20:30','Rivera Family',120,'admin');
  if v_b is not null then
    update atd.bookings set title = 'CT Thunder 13U — Team Practice', participant_count = 14
     where id = v_b;
  end if;

  -- Maintenance: netting inspection on whichever 35 ft cage is free mid-afternoon.
  declare v_res uuid;
  begin
    select r.id into v_res
      from atd.resources r
     where r.code in ('CAGE-4','CAGE-3','CAGE-2')
       and atd.free_slot_index(r.id,
             ((d + time '14:00') at time zone tz),
             ((d + time '15:30') at time zone tz)) is not null
     order by r.code desc limit 1;

    if v_res is not null then
      insert into atd.resource_blocks (location_id, kind, title, note, starts_at, ends_at)
      values ('00000000-0000-4000-8000-0000000010c1','maintenance',
              'Netting inspection', 'Annual safety inspection, vendor on site.',
              ((d + time '14:00') at time zone tz), ((d + time '15:30') at time zone tz))
      returning id into v_block;

      insert into atd.resource_reservations
        (location_id, resource_id, block_id, status, starts_at, ends_at, blocked_from, blocked_to)
      values ('00000000-0000-4000-8000-0000000010c1', v_res, v_block, 'confirmed',
              ((d + time '14:00') at time zone tz), ((d + time '15:30') at time zone tz),
              ((d + time '14:00') at time zone tz), ((d + time '15:30') at time zone tz));
    end if;
  end;
end $$;

-- Operational texture ---------------------------------------------------------
-- Price everything from the seeded service rates.
update atd.bookings b
   set subtotal_cents = case when s.pricing_model = 'per_minute'
                             then s.base_price_cents *
                                  (extract(epoch from (b.ends_at - b.starts_at))/60)::int
                             else s.base_price_cents end,
       total_cents    = case when s.pricing_model = 'per_minute'
                             then s.base_price_cents *
                                  (extract(epoch from (b.ends_at - b.starts_at))/60)::int
                             else s.base_price_cents end
  from atd.services s
 where s.id = b.service_id and b.total_cents = 0;

-- Morning sessions have already happened and are paid.
update atd.bookings
   set status = 'completed', checked_in_at = starts_at, completed_at = ends_at,
       paid_cents = total_cents
 where (starts_at at time zone 'America/New_York')::time < time '12:00';

-- Early-afternoon sessions are in the building now.
update atd.bookings
   set status = 'checked_in', checked_in_at = starts_at - interval '8 minutes',
       paid_cents = total_cents
 where (starts_at at time zone 'America/New_York')::time between time '12:00' and time '13:59'
   and status = 'confirmed';

-- One family owes a balance at the counter, so the desk board has real work.
update atd.bookings b
   set paid_cents = 0
  from atd.households h
 where h.id = b.household_id and h.name = 'Nowak Family'
   and b.status in ('confirmed','checked_in');

-- A live checkout hold, mid-flight.
select atd.create_hold(
  '11000000-0000-4000-8000-000000000010',
  ((current_setting('demo.day')::date + time '16:30') at time zone 'America/New_York'),
  ((current_setting('demo.day')::date + time '16:30') at time zone 'America/New_York') + interval '1 hour',
  'demo-live-hold',
  (select id from atd.households where name = 'Silva Family'),
  '{}'::jsonb, 600);

-- Two families waiting on a Saturday HitTrax lesson.
insert into atd.waitlist_entries
  (location_id, service_id, household_id, participant_id, desired_from, desired_to, status)
select '00000000-0000-4000-8000-0000000010c1',
       '11000000-0000-4000-8000-000000000005', h.id,
       (select id from atd.participants where household_id = h.id limit 1),
       ((current_setting('demo.day')::date + time '09:00') at time zone 'America/New_York'),
       ((current_setting('demo.day')::date + time '13:00') at time zone 'America/New_York'),
       'waiting'
  from atd.households h where h.name in ('Patel Family','Nowak Family');

drop function atd.demo_book(uuid, date, time, time, text, int, text);

-- =============================================================================
-- Published programs, so the customer-facing camps and clinics pages have real
-- inventory. Sessions are materialised through the engine, which means each
-- one really reserves its cages, coaches and lobby space.
-- =============================================================================
do $$
declare
  tz text := 'America/New_York';
  v_prog uuid; d date; i int; v_n int;
begin
  -- Summer Skills Camp: 4 consecutive weekdays, 9:30-13:30, capacity 24.
  select g::date into d
    from generate_series((now() at time zone tz)::date + 14,
                         (now() at time zone tz)::date + 28, interval '1 day') g
   where extract(dow from g) = 1 order by g limit 1;   -- a Monday

  insert into atd.programs (location_id, service_id, slug, name, summary, description,
      starts_on, ends_on, registration_opens_at, registration_closes_at,
      capacity, min_enrollment, min_age, max_age, age_as_of_date,
      price_cents, deposit_cents, sibling_discount_percent,
      collects_shirt_size, collects_lunch_choice, parent_instructions, status)
  values ('00000000-0000-4000-8000-0000000010c1','11000000-0000-4000-8000-000000000022',
      'summer-skills-camp-week-1','Summer Skills Camp — Week 1',
      'Four mornings of hitting, fielding and base running for ages 7–13.',
      'Players rotate through hitting, infield, outfield and base running stations with '
      || 'ATD coaches. Small groups by age. Bring a glove, bat, water bottle and lunch.',
      d, d + 3, now() - interval '20 days', (d - 2)::timestamptz,
      24, 8, 7, 13, d, 29900, 10000, 10,
      true, true,
      'Drop-off opens at 9:15 AM at the lobby. Pickup is 1:30–1:45 PM. '
      || 'Only adults on your authorized pickup list may collect your child.',
      'published')
  returning id into v_prog;

  -- Three coaches work camp mornings that week instead of evening lessons.
  insert into atd.coach_date_availability (coach_id, on_date, starts_at, ends_at, is_available, note)
  select c.id, d + g, time '09:00', time '14:00', true, 'Summer camp week'
    from atd.coaches c, generate_series(0,3) g
   where c.display_name in ('Marcus Reyes','Tyler Callahan','Joe Brennan');

  for i in 0..3 loop
    insert into atd.program_sessions (program_id, session_number, session_date, starts_at, ends_at)
    values (v_prog, i+1, d + i,
            (((d + i) + time '09:30') at time zone tz),
            (((d + i) + time '13:30') at time zone tz));
  end loop;
  v_n := atd.materialize_program_sessions(v_prog);
  raise notice 'summer camp: % sessions materialised', v_n;
  perform set_config('demo.camp', v_prog::text, false);

  -- Arm Care Program: six Wednesday evenings.
  select g::date into d
    from generate_series((now() at time zone tz)::date + 10,
                         (now() at time zone tz)::date + 24, interval '1 day') g
   where extract(dow from g) = 3 order by g limit 1;

  insert into atd.programs (location_id, service_id, slug, name, summary, description,
      starts_on, ends_on, capacity, min_enrollment, min_age, max_age, age_as_of_date,
      price_cents, status)
  values ('00000000-0000-4000-8000-0000000010c1','11000000-0000-4000-8000-000000000021',
      'arm-care-fall','Arm Care Program — Fall Block',
      'Six weeks of throwing health, mechanics and velocity work for ages 11–18.',
      'A progressive six-week block: mobility screen, band and plyo work, long toss '
      || 'progression, and weekly velocity tracking. Run by Sofia Vargas and Tyler Callahan.',
      d, d + 35, 10, 4, 11, 18, d, 39900, 'published')
  returning id into v_prog;

  for i in 0..5 loop
    insert into atd.program_sessions (program_id, session_number, session_date, starts_at, ends_at)
    values (v_prog, i+1, d + (i*7),
            (((d + (i*7)) + time '17:00') at time zone tz),
            (((d + (i*7)) + time '18:00') at time zone tz));
  end loop;
  v_n := atd.materialize_program_sessions(v_prog);
  raise notice 'arm care: % sessions materialised', v_n;

  -- Parents' Night Out: one Friday evening, nearly full so the waitlist path shows.
  select g::date into d
    from generate_series((now() at time zone tz)::date + 7,
                         (now() at time zone tz)::date + 21, interval '1 day') g
   where extract(dow from g) = 5 order by g limit 1;

  insert into atd.programs (location_id, service_id, slug, name, summary, description,
      starts_on, ends_on, capacity, min_age, max_age, age_as_of_date,
      price_cents, includes_lunch, status, allow_waitlist)
  values ('00000000-0000-4000-8000-0000000010c1','11000000-0000-4000-8000-000000000023',
      'parents-night-out-friday','Parents'' Night Out',
      'Three supervised hours of games, cage time and pizza for ages 5–12.',
      'Drop the kids with us from 5:30 to 8:30 PM. Wiffle ball, cage rotations, '
      || 'a movie in the party room, and pizza. Ages 5–12.',
      d, d, 24, 5, 12, d, 5500, true, 'published', true)
  returning id into v_prog;

  insert into atd.program_sessions (program_id, session_number, session_date, starts_at, ends_at)
  values (v_prog, 1, d, ((d + time '17:30') at time zone tz), ((d + time '20:30') at time zone tz));
  v_n := atd.materialize_program_sessions(v_prog);
  raise notice 'PNO: % sessions materialised', v_n;
  perform set_config('demo.pno', v_prog::text, false);
end $$;

-- Enrol real children so fill rates and rosters are not fabricated.
do $$
declare p record; r record; n int := 0;
begin
  for p in select pa.id, pa.household_id, pa.date_of_birth
             from atd.participants pa
             join atd.households h on h.id = pa.household_id
            order by pa.created_at
  loop
    exit when n >= 9;
    begin
      select * into r from atd.register_participant(
        current_setting('demo.camp')::uuid, p.id, p.household_id, 'full_series', null, true);
      n := n + 1;
    exception when others then null;   -- age-ineligible children are simply skipped
    end;
  end loop;
  raise notice 'camp enrolments: %', n;
end $$;

-- Fill the Parents' Night Out to capacity so its page shows a genuine waitlist.
update atd.programs set enrolled_count = capacity, status = 'full'
 where slug = 'parents-night-out-friday';
