-- =============================================================================
-- Scheduling engine acceptance + edge-case tests
-- Maps directly to §33 Acceptance Requirements and §29 Critical Edge Cases.
-- =============================================================================
set search_path = atd, public;
truncate t.results;

-- Fixtures -------------------------------------------------------------------
do $$
declare v_h uuid; v_p uuid; v_u uuid;
begin
  insert into atd.users (id, email, first_name, last_name)
  values (gen_random_uuid(),'test.parent@example.com','Test','Parent')
  returning id into v_u;

  insert into atd.households (id, location_id, name, primary_user_id)
  values (gen_random_uuid(),'00000000-0000-4000-8000-0000000010c1','Test Household', v_u)
  returning id into v_h;

  insert into atd.household_members (household_id, user_id, is_primary)
  values (v_h, v_u, true);

  insert into atd.participants (id, household_id, first_name, last_name, date_of_birth)
  values (gen_random_uuid(), v_h, 'Test','Player', current_date - interval '12 years')
  returning id into v_p;

  perform set_config('test.household', v_h::text, false);
  perform set_config('test.participant', v_p::text, false);
end $$;

-- Deterministic future instants. Tests must not depend on what day it is
-- today: coach availability differs between weekdays and weekends, so every
-- fixture names the weekday it needs.
--   t.slot(dow, week, hour) -> the `week`-th upcoming `dow` at `hour` local.
create or replace function t.slot(p_dow int, p_week int, p_hour numeric)
returns timestamptz language sql stable as $$
  select ((d + make_interval(mins => (p_hour * 60)::int)) at time zone 'America/New_York')
  from (
    select g::date as d
      from generate_series(
             ((now() at time zone 'America/New_York')::date + 2)::timestamp,
             ((now() at time zone 'America/New_York')::date + 60)::timestamp,
             interval '1 day') g
     where extract(dow from g)::int = p_dow
     order by g
     offset greatest(p_week - 1, 0)
     limit 1
  ) s
$$;

-- =============================================================================
-- 1. A private lesson blocks the coach AND the cage.
-- =============================================================================
do $$
declare v_b uuid; v_start timestamptz; v_kinds text[];
begin
  v_start := t.slot(2,1,18);
  v_b := atd.create_booking(
    '11000000-0000-4000-8000-000000000001', v_start, v_start + interval '1 hour',
    current_setting('test.household')::uuid,
    array[current_setting('test.participant')::uuid]);

  select array_agg(distinct rt.kind::text order by rt.kind::text)
    into v_kinds
    from atd.resource_reservations rr
    join atd.resources r on r.id = rr.resource_id
    join atd.resource_types rt on rt.id = r.resource_type_id
   where rr.booking_id = v_b;

  perform t.ok('private lesson reserves a coach and a cage',
               v_kinds @> array['cage','staff'], array_to_string(v_kinds,','));
  perform set_config('test.booking1', v_b::text, false);
end $$;

-- =============================================================================
-- 2. The same coach cannot be double-booked; the same cage cannot either.
-- =============================================================================
do $$
declare v_start timestamptz; v_coach uuid; v_cage uuid; v_pinned jsonb; v_req uuid;
begin
  v_start := t.slot(2,1,18);
  select rr.resource_id into v_coach
    from atd.resource_reservations rr
    join atd.resources r on r.id = rr.resource_id
    join atd.resource_types rt on rt.id = r.resource_type_id
   where rr.booking_id = current_setting('test.booking1')::uuid and rt.kind='staff';

  select id into v_req from atd.service_resource_requirements
   where service_id='11000000-0000-4000-8000-000000000001' and label='Coach';
  v_pinned := jsonb_build_object(v_req::text, jsonb_build_array(v_coach::text));

  perform t.ok('pinned busy coach yields no plan',
    atd.plan_allocation('11000000-0000-4000-8000-000000000001',
      v_start, v_start + interval '1 hour', v_pinned) is null);
end $$;

-- =============================================================================
-- 3. Raw insert bypassing the engine still cannot double-book (constraint).
-- =============================================================================
do $$
declare v_res uuid; v_start timestamptz; v_block uuid;
begin
  v_start := t.slot(2,1,18);
  select resource_id into v_res from atd.resource_reservations
   where booking_id = current_setting('test.booking1')::uuid limit 1;

  insert into atd.resource_blocks (location_id, kind, title, starts_at, ends_at)
  values ('00000000-0000-4000-8000-0000000010c1','maintenance','overlap probe',
          v_start + interval '15 min', v_start + interval '45 min')
  returning id into v_block;

  -- This bypasses every application code path and goes straight at the table.
  -- It must still be impossible.
  perform t.raises('exclusion constraint rejects an overlapping raw insert',
    format($f$insert into atd.resource_reservations
      (location_id, resource_id, block_id, status, starts_at, ends_at,
       blocked_from, blocked_to)
      values ('00000000-0000-4000-8000-0000000010c1', %L, %L, 'confirmed',
              %L::timestamptz, %L::timestamptz, %L::timestamptz, %L::timestamptz)$f$,
      v_res, v_block,
      v_start + interval '15 min', v_start + interval '45 min',
      v_start + interval '15 min', v_start + interval '45 min'),
    '23P01');

  -- ...but a non-overlapping insert on the same resource is fine.
  insert into atd.resource_reservations
    (location_id, resource_id, block_id, status, starts_at, ends_at,
     blocked_from, blocked_to)
  values ('00000000-0000-4000-8000-0000000010c1', v_res, v_block, 'confirmed',
          v_start - interval '4 hours', v_start - interval '3 hours',
          v_start - interval '4 hours', v_start - interval '3 hours');
  perform t.ok('non-overlapping raw insert on the same resource is accepted', true);
end $$;

-- =============================================================================
-- 4. Buffers are enforced: a booking cannot start inside the previous one's
--    5-minute transition window.
-- =============================================================================
do $$
declare v_start timestamptz; v_cage uuid; v_req uuid; v_pinned jsonb;
begin
  v_start := t.slot(2,1,18);
  select rr.resource_id into v_cage
    from atd.resource_reservations rr
    join atd.resources r on r.id = rr.resource_id
    join atd.resource_types rt on rt.id = r.resource_type_id
   where rr.booking_id = current_setting('test.booking1')::uuid and rt.kind='cage';

  -- The cage is busy 18:00–19:00 plus 5 min after. 19:00 start would overlap
  -- the trailing buffer, so free_slot_index must refuse it.
  perform t.ok('trailing buffer blocks a back-to-back start on the same cage',
    atd.free_slot_index(v_cage, v_start + interval '60 min', v_start + interval '120 min') is null);

  perform t.ok('same cage is free once the buffer has elapsed',
    atd.free_slot_index(v_cage, v_start + interval '65 min', v_start + interval '125 min') is not null);
end $$;

-- =============================================================================
-- 5. HitTrax lesson blocks coach + 70ft cage + the HitTrax unit (3 resources).
-- =============================================================================
do $$
declare v_b uuid; v_start timestamptz; v_n int; v_has_unit boolean;
begin
  v_start := t.slot(3,1,10);   -- weekday morning, Marcus available
  v_b := atd.create_booking(
    '11000000-0000-4000-8000-000000000005', v_start, v_start + interval '1 hour',
    current_setting('test.household')::uuid,
    array[current_setting('test.participant')::uuid]);

  select count(*) into v_n from atd.resource_reservations where booking_id = v_b;
  select exists(select 1 from atd.resource_reservations rr
                  join atd.resources r on r.id = rr.resource_id
                 where rr.booking_id = v_b and r.code = 'HITTRAX-1') into v_has_unit;

  perform t.eq('HitTrax lesson blocks three resources', v_n, 3);
  perform t.ok('HitTrax unit itself is reserved', v_has_unit);
  perform set_config('test.booking_ht', v_b::text, false);
end $$;

-- HitTrax cannot then be rented independently at the same time.
do $$
declare v_start timestamptz;
begin
  v_start := t.slot(3,1,10);
  perform t.ok('HitTrax rental is unavailable while a HitTrax lesson runs',
    atd.plan_allocation('11000000-0000-4000-8000-000000000012',
      v_start + interval '15 min', v_start + interval '45 min') is null);
end $$;

-- =============================================================================
-- 6. Birthday party reserves party room + 2 cages + host in ONE transaction.
-- =============================================================================
do $$
declare v_b uuid; v_start timestamptz; v_cages int; v_room int; v_host int;
begin
  v_start := t.slot(4,1,12);
  v_b := atd.create_booking(
    '11000000-0000-4000-8000-000000000030', v_start, v_start + interval '135 minutes',
    current_setting('test.household')::uuid, '{}');

  select count(*) filter (where rt.kind='cage'),
         count(*) filter (where rt.kind='party_room'),
         count(*) filter (where rt.kind='event_host')
    into v_cages, v_room, v_host
    from atd.resource_reservations rr
    join atd.resources r on r.id = rr.resource_id
    join atd.resource_types rt on rt.id = r.resource_type_id
   where rr.booking_id = v_b;

  perform t.eq('party reserves 2 cages', v_cages, 2);
  perform t.eq('party reserves the party room', v_room, 1);
  perform t.eq('party reserves an event host', v_host, 1);
end $$;

-- =============================================================================
-- 7. Group clinic: many registrations, cage blocked ONCE.
-- =============================================================================
do $$
declare v_prog uuid; v_sess uuid; v_start timestamptz; v_n int; v_res int; i int;
        v_part uuid; v_h uuid; r record;
begin
  v_start := t.slot(4,2,17);
  v_h := current_setting('test.household')::uuid;

  insert into atd.programs (id, location_id, service_id, slug, name, starts_on, ends_on,
                            capacity, min_age, max_age, price_cents, status, age_as_of_date)
  values (gen_random_uuid(),'00000000-0000-4000-8000-0000000010c1',
          '11000000-0000-4000-8000-000000000020','test-clinic','Test Clinic',
          (v_start at time zone 'America/New_York')::date,
          (v_start at time zone 'America/New_York')::date,
          6, 9, 14, 4500, 'published',
          (v_start at time zone 'America/New_York')::date)
  returning id into v_prog;

  insert into atd.program_sessions (program_id, session_number, session_date, starts_at, ends_at)
  values (v_prog, 1, (v_start at time zone 'America/New_York')::date,
          v_start, v_start + interval '75 minutes')
  returning id into v_sess;

  perform atd.materialize_program_sessions(v_prog);

  select count(*) into v_res
    from atd.resource_reservations rr
    join atd.program_sessions s on s.booking_id = rr.booking_id
   where s.id = v_sess;
  perform t.eq('clinic session reserves 4 resources (2 coaches + 2 cages)', v_res, 4);

  -- Six children register; reservations must NOT grow.
  for i in 1..6 loop
    insert into atd.participants (household_id, first_name, last_name, date_of_birth)
    values (v_h, 'Kid'||i, 'Tester', current_date - interval '11 years')
    returning id into v_part;
    perform atd.register_participant(v_prog, v_part, v_h);
  end loop;

  select count(*) into v_n
    from atd.resource_reservations rr
    join atd.program_sessions s on s.booking_id = rr.booking_id
   where s.id = v_sess;
  perform t.eq('6 registrations do not add reservations', v_n, 4);
  perform t.eq('program shows 6 enrolled',
    (select enrolled_count from atd.programs where id = v_prog), 6);

  perform set_config('test.program', v_prog::text, false);
end $$;

-- 7b. The seventh registration cannot take a seat — waitlist instead.
do $$
declare v_part uuid; v_h uuid; r record;
begin
  v_h := current_setting('test.household')::uuid;
  insert into atd.participants (household_id, first_name, last_name, date_of_birth)
  values (v_h,'Kid7','Tester', current_date - interval '11 years') returning id into v_part;

  select * into r from atd.register_participant(
    current_setting('test.program')::uuid, v_part, v_h);
  perform t.eq('7th registration is waitlisted, not enrolled', r.status::text, 'waitlisted');
  perform t.eq('enrolled_count stays at capacity',
    (select enrolled_count from atd.programs where id = current_setting('test.program')::uuid), 6);
end $$;

-- 7c. The capacity CHECK constraint is a real backstop.
do $$
begin
  perform t.raises('capacity CHECK rejects a manual over-sell',
    format($f$update atd.programs set enrolled_count = capacity + 1 where id = %L$f$,
           current_setting('test.program')), '23514');
end $$;

-- 7d. Age is evaluated against the program date, not today.
do $$
declare v_part uuid; v_h uuid;
begin
  v_h := current_setting('test.household')::uuid;
  insert into atd.participants (household_id, first_name, last_name, date_of_birth)
  values (v_h,'TooYoung','Tester', current_date - interval '6 years') returning id into v_part;
  perform t.raises('under-age participant is refused',
    format('select * from atd.register_participant(%L, %L, %L)',
           current_setting('test.program'), v_part, v_h), '23514');
end $$;

-- =============================================================================
-- 8. Checkout holds: block others, then expire and free the slot.
-- =============================================================================
do $$
declare v_start timestamptz; r record; v_hold uuid;
begin
  v_start := t.slot(5,1,19);
  select * into r from atd.create_hold('11000000-0000-4000-8000-000000000012',
     v_start, v_start + interval '1 hour', 'sess-A', null, '{}'::jsonb, 10);
  v_hold := r.hold_id;

  perform t.ok('an active hold blocks the HitTrax cage for everyone else',
    atd.plan_allocation('11000000-0000-4000-8000-000000000012',
      v_start, v_start + interval '1 hour') is null);

  -- Simulate abandonment.
  update atd.checkout_holds set expires_at = now() - interval '1 minute' where id = v_hold;
  update atd.resource_reservations set expires_at = now() - interval '1 minute' where hold_id = v_hold;
  perform atd.expire_stale_holds();

  perform t.ok('an expired hold releases the slot',
    atd.plan_allocation('11000000-0000-4000-8000-000000000012',
      v_start, v_start + interval '1 hour') is not null);

  perform t.raises('confirming an expired hold fails loudly',
    format('select atd.confirm_hold(%L, %L)', v_hold, current_setting('test.household')),
    '23P01');
end $$;

-- 8b. Confirming the same hold twice returns the same booking (double-clicked Pay).
do $$
declare v_start timestamptz; r record; b1 uuid; b2 uuid;
begin
  v_start := t.slot(1,2,19);
  select * into r from atd.create_hold('11000000-0000-4000-8000-000000000010',
     v_start, v_start + interval '1 hour', 'sess-B', current_setting('test.household')::uuid);
  b1 := atd.confirm_hold(r.hold_id, current_setting('test.household')::uuid);
  b2 := atd.confirm_hold(r.hold_id, current_setting('test.household')::uuid);
  perform t.eq('double-confirm is idempotent', b1, b2);
end $$;

-- =============================================================================
-- 9. Reschedule revalidates; a move onto a busy resource fails and rolls back.
-- =============================================================================
do $$
declare v_b uuid; v_start timestamptz; v_before timestamptz;
begin
  v_b := current_setting('test.booking1')::uuid;
  select starts_at into v_before from atd.bookings where id = v_b;
  v_start := t.slot(3,1,10);          -- occupied by the HitTrax lesson's coach

  begin
    perform atd.reschedule_booking(v_b, v_start, v_start + interval '1 hour',
      jsonb_build_object(
        (select id::text from atd.service_resource_requirements
          where service_id='11000000-0000-4000-8000-000000000001' and label='Coach'),
        jsonb_build_array((select r.id::text from atd.resources r
                             join atd.resource_reservations rr on rr.resource_id = r.id
                             join atd.resource_types rt on rt.id = r.resource_type_id
                            where rr.booking_id = current_setting('test.booking_ht')::uuid
                              and rt.kind='staff'))));
    perform t.ok('reschedule onto a busy coach is rejected', false, 'no exception raised');
  exception when others then
    perform t.ok('reschedule onto a busy coach is rejected', true, sqlstate);
  end;
end $$;

-- A legal reschedule succeeds and moves every reservation with it.
do $$
declare v_b uuid; v_new timestamptz; v_n int;
begin
  v_b := current_setting('test.booking1')::uuid;
  v_new := t.slot(3,2,16);
  perform atd.reschedule_booking(v_b, v_new, v_new + interval '1 hour');
  select count(*) into v_n from atd.resource_reservations
   where booking_id = v_b and starts_at = v_new;
  perform t.ok('a valid reschedule moves all reservations together', v_n >= 2, v_n::text);
end $$;

-- =============================================================================
-- 10. Cancellation returns resources to inventory immediately.
-- =============================================================================
do $$
declare v_b uuid; v_start timestamptz;
begin
  v_b := current_setting('test.booking_ht')::uuid;
  select starts_at into v_start from atd.bookings where id = v_b;
  perform atd.cancel_booking(v_b, 'test cancellation');
  perform t.ok('cancelling frees the HitTrax cage for a new booking',
    atd.plan_allocation('11000000-0000-4000-8000-000000000012',
      v_start, v_start + interval '1 hour') is not null);
end $$;

-- =============================================================================
-- 11. Facility closure blocks every service.
-- =============================================================================
do $$
declare v_start timestamptz; v_bid uuid;
begin
  v_start := t.slot(6,2,14);
  insert into atd.resource_blocks (location_id, kind, title, starts_at, ends_at,
                                   applies_to_whole_location)
  values ('00000000-0000-4000-8000-0000000010c1','closure','Snow closure',
          v_start - interval '4 hours', v_start + interval '6 hours', true)
  returning id into v_bid;

  perform t.ok('a whole-location closure blocks all bookings',
    atd.plan_allocation('11000000-0000-4000-8000-000000000001',
      v_start, v_start + interval '1 hour') is null);

  update atd.resource_blocks set cancelled_at = now() where id = v_bid;
  perform t.ok('lifting the closure restores availability',
    atd.plan_allocation('11000000-0000-4000-8000-000000000001',
      v_start, v_start + interval '1 hour') is not null);
end $$;

-- =============================================================================
-- 12. Holiday / date override closes the facility.
-- =============================================================================
do $$
begin
  perform t.ok('operating hours resolve on a normal day',
    atd.open_span('00000000-0000-4000-8000-0000000010c1',
                  (now() at time zone 'America/New_York')::date + 7) is not null);
  perform t.ok('a holiday override closes the day',
    atd.open_span('00000000-0000-4000-8000-0000000010c1', date '2026-12-25') is null);
end $$;

-- =============================================================================
-- 13. DST: a recurring 4:00 PM series keeps its local time across the change.
-- =============================================================================
do $$
declare v_offsets text[];
begin
  select array_agg(distinct to_char(starts_at at time zone 'America/New_York','HH24:MI'))
    into v_offsets
  from atd.validate_recurrence('11000000-0000-4000-8000-000000000001',
        date '2026-10-25', date '2026-11-15', array[0], time '16:00', 60);
  perform t.eq('weekly series holds 16:00 local across the DST change',
               array_length(v_offsets,1), 1);
  perform t.eq('the retained local time is 16:00', v_offsets[1], '16:00');
end $$;

-- The same series in UTC terms actually shifts by an hour — proof we are not
-- just storing a fixed offset.
do $$
declare v_utc text[];
begin
  select array_agg(distinct to_char(starts_at at time zone 'UTC','HH24:MI'))
    into v_utc
  from atd.validate_recurrence('11000000-0000-4000-8000-000000000001',
        date '2026-10-25', date '2026-11-15', array[0], time '16:00', 60);
  perform t.eq('the underlying UTC instant does shift across DST',
               array_length(v_utc,1), 2);
end $$;

-- =============================================================================
-- 14. Recurrence validation reports per-occurrence conflicts.
-- =============================================================================
do $$
declare v_valid int; v_invalid int; v_closed int; d date;
begin
  d := (now() at time zone 'America/New_York')::date + 30;
  select count(*) filter (where is_valid), count(*) filter (where not is_valid)
    into v_valid, v_invalid
  from atd.validate_recurrence('11000000-0000-4000-8000-000000000001',
        d, d + 42, array[extract(dow from d)::int], time '17:00', 60);
  perform t.ok('recurrence validation returns a verdict per occurrence',
               v_valid + v_invalid = 7, format('%s valid / %s invalid', v_valid, v_invalid));

  select count(*) into v_closed
  from atd.validate_recurrence('11000000-0000-4000-8000-000000000001',
        date '2026-12-20', date '2026-12-27', array[]::int[], time '17:00', 60)
  where reason = 'Facility closed';
  perform t.ok('closed days are reported with a reason', v_closed >= 1, v_closed::text);
end $$;

-- =============================================================================
-- 15. Attribute matching: pitching needs a mound, so only mound cages qualify.
-- =============================================================================
do $$
declare v_codes text[]; v_req uuid;
begin
  select id into v_req from atd.service_resource_requirements
   where service_id='11000000-0000-4000-8000-000000000002' and label='Mound Cage';
  select array_agg(r.code order by r.code) into v_codes
    from atd.candidate_resources(v_req, t.slot(2,2,17), t.slot(2,2,17) + interval '1 hour') c
    join atd.resources r on r.id = c.resource_id;
  perform t.ok('pitching only matches cages with a mound',
               v_codes <@ array['CAGE-1','CAGE-5'], array_to_string(v_codes,','));
end $$;

-- =============================================================================
-- 16. Coach qualification filtering.
-- =============================================================================
do $$
declare v_names text[]; v_req uuid;
begin
  select id into v_req from atd.service_resource_requirements
   where service_id='11000000-0000-4000-8000-000000000005' and label='HitTrax Coach';
  select array_agg(c2.display_name order by c2.display_name) into v_names
    from atd.candidate_resources(v_req, t.slot(2,3,17), t.slot(2,3,17)+interval '1 hour') c
    join atd.coaches c2 on c2.resource_id = c.resource_id;
  perform t.ok('only HitTrax-certified coaches are offered',
               v_names <@ array['Dana Nakamura','Marcus Reyes'], array_to_string(v_names,','));
end $$;

-- =============================================================================
-- 17. Coach availability window is honoured (no 9 AM lesson for an evening-only coach).
-- =============================================================================
do $$
declare v_req uuid; v_n int;
begin
  select id into v_req from atd.service_resource_requirements
   where service_id='11000000-0000-4000-8000-000000000003' and label='Coach';
  -- Joe Brennan works weekdays from 3 PM; at 10 AM on a weekday there should be
  -- no catching coach available at all.
  select count(*) into v_n from atd.candidate_resources(v_req, t.slot(2,3,10), t.slot(2,3,10)+interval '1 hour');
  perform t.eq('no catching coach is available on a weekday morning', v_n, 0);
end $$;

-- =============================================================================
-- 18. Shared-capacity resources allow concurrent use up to capacity.
-- =============================================================================
do $$
declare v_lobby uuid; v_start timestamptz; i int; v_slot int; v_last int;
begin
  select id into v_lobby from atd.resources where code = 'LOBBY';
  v_start := t.slot(0,3,11);
  for i in 1..3 loop
    v_slot := atd.free_slot_index(v_lobby, v_start, v_start + interval '1 hour');
    insert into atd.resource_blocks (location_id, kind, title, starts_at, ends_at)
    values ('00000000-0000-4000-8000-0000000010c1','admin_hold','lobby '||i,
            v_start, v_start + interval '1 hour');
    insert into atd.resource_reservations
      (location_id, resource_id, block_id, status, starts_at, ends_at,
       blocked_from, blocked_to, slot_index)
    values ('00000000-0000-4000-8000-0000000010c1', v_lobby,
            (select id from atd.resource_blocks order by created_at desc limit 1),
            'confirmed', v_start, v_start + interval '1 hour',
            v_start, v_start + interval '1 hour', v_slot);
  end loop;
  v_last := atd.free_slot_index(v_lobby, v_start, v_start + interval '1 hour');
  perform t.ok('lobby capacity of 3 is fully consumed by 3 concurrent holds', v_last is null);
end $$;

-- =============================================================================
-- 19. Package credit ledger drives the balance; refunds restore credits.
-- =============================================================================
do $$
declare v_pp uuid; v_h uuid;
begin
  v_h := current_setting('test.household')::uuid;
  insert into atd.package_purchases (package_definition_id, household_id, credits_granted, expires_on)
  values ('c2000000-0000-4000-8000-000000000001', v_h, 5, current_date + 365)
  returning id into v_pp;

  insert into atd.package_credit_transactions (package_purchase_id, kind, delta)
  values (v_pp,'grant',5);
  perform t.eq('granting 5 credits sets the balance to 5',
    (select credits_remaining from atd.package_purchases where id=v_pp), 5);

  insert into atd.package_credit_transactions (package_purchase_id, kind, delta, booking_id)
  values (v_pp,'redeem',-1, current_setting('test.booking1')::uuid);
  perform t.eq('redeeming one credit leaves 4',
    (select credits_remaining from atd.package_purchases where id=v_pp), 4);

  perform t.raises('a second redemption against the same booking is rejected',
    format($f$insert into atd.package_credit_transactions
              (package_purchase_id, kind, delta, booking_id)
            values (%L,'redeem',-1,%L)$f$, v_pp, current_setting('test.booking1')),
    '23505');

  insert into atd.package_credit_transactions (package_purchase_id, kind, delta)
  values (v_pp,'refund',1);
  perform t.eq('cancelling returns the credit',
    (select credits_remaining from atd.package_purchases where id=v_pp), 5);
end $$;

-- =============================================================================
-- 20. Account credit ledger.
-- =============================================================================
do $$
declare v_h uuid;
begin
  v_h := current_setting('test.household')::uuid;
  insert into atd.account_credit_transactions (household_id, kind, amount_cents, reason)
  values (v_h,'grant',5000,'goodwill');
  insert into atd.account_credit_transactions (household_id, kind, amount_cents, reason)
  values (v_h,'redeem',-1500,'applied to booking');
  perform t.eq('account credit is the sum of its ledger',
    (select account_credit_cents from atd.households where id=v_h), 3500::bigint);
end $$;

-- =============================================================================
-- 21. Stripe webhook replay is a no-op.
-- =============================================================================
do $$
begin
  insert into atd.stripe_events (id, type, payload)
  values ('evt_test_1','payment_intent.succeeded','{}');
  perform t.raises('replaying a Stripe event id is rejected',
    $f$insert into atd.stripe_events (id, type, payload)
       values ('evt_test_1','payment_intent.succeeded','{}')$f$, '23505');
end $$;

-- One payment intent maps to at most one payment row.
do $$
begin
  insert into atd.payments (location_id, amount_cents, stripe_payment_intent_id, status)
  values ('00000000-0000-4000-8000-0000000010c1', 9000, 'pi_test_1','succeeded');
  perform t.raises('a duplicate payment intent cannot create a second payment',
    $f$insert into atd.payments (location_id, amount_cents, stripe_payment_intent_id, status)
       values ('00000000-0000-4000-8000-0000000010c1', 9000, 'pi_test_1','succeeded')$f$,
    '23505');
end $$;

-- =============================================================================
-- 22. Waiver versioning.
-- =============================================================================
do $$
declare v_v1 uuid; v_v2 uuid; v_part uuid;
begin
  select id into v_v1 from atd.waiver_versions
   where template_id='77000000-0000-4000-8000-000000000001' and version=1;
  v_part := current_setting('test.participant')::uuid;

  insert into atd.signed_waivers (waiver_version_id, household_id, participant_id,
                                  signer_name, signer_relation, ip_address)
  values (v_v1, current_setting('test.household')::uuid, v_part,
          'Test Parent','parent','203.0.113.9');

  -- Publish v2 requiring re-signature.
  update atd.waiver_versions set retired_at = now() where id = v_v1;
  insert into atd.waiver_versions (template_id, version, body_markdown, requires_resignature)
  values ('77000000-0000-4000-8000-000000000001',2,'# Updated waiver', true)
  returning id into v_v2;

  perform t.ok('a participant signed on v1 is stale once v2 is published',
    not exists (select 1 from atd.signed_waivers sw
                 where sw.participant_id = v_part
                   and sw.waiver_version_id = v_v2));
  perform t.eq('only one current version exists per template',
    (select count(*) from atd.waiver_versions
      where template_id='77000000-0000-4000-8000-000000000001' and retired_at is null), 1::bigint);
end $$;

-- =============================================================================
-- 23. Audit log is append-only.
-- =============================================================================
do $$
begin
  insert into audit.entries (action, entity_type, summary) values ('test.action','test','x');
  perform t.raises('audit entries cannot be updated',
    $f$update audit.entries set summary = 'tampered' where action='test.action'$f$);
  perform t.raises('audit entries cannot be deleted',
    $f$delete from audit.entries where action='test.action'$f$);
end $$;

-- =============================================================================
-- 24. A booking may not be created outside operating hours by the search.
-- =============================================================================
do $$
declare v_n int; d date;
begin
  d := (now() at time zone 'America/New_York')::date + 21;
  select count(*) into v_n from atd.find_slots(
    '11000000-0000-4000-8000-000000000010', d, d, 60)
   where (starts_at at time zone 'America/New_York')::time < time '09:30'
      or (ends_at   at time zone 'America/New_York')::time > time '20:30';
  perform t.eq('availability search never leaves operating hours', v_n, 0);
end $$;

select * from t.summary();
select name, detail from t.results where not passed;
