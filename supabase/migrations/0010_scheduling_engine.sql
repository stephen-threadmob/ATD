-- =============================================================================
-- 0010 The scheduling engine
-- -----------------------------------------------------------------------------
-- Everything here runs inside the database so that availability calculation and
-- reservation acquisition observe the SAME snapshot and the SAME locks. Any
-- design where the app checks availability over one connection and writes over
-- another has a race window; this one does not.
--
-- Public entry points:
--   atd.expire_stale_holds()          sweep abandoned checkouts
--   atd.find_slots(...)               availability search (returns assignments)
--   atd.create_hold(...)              atomically hold every required resource
--   atd.confirm_hold(...)             hold -> confirmed booking, atomically
--   atd.release_hold(...)             explicit abandon
--   atd.reschedule_booking(...)       move/resize with full revalidation
--   atd.validate_recurrence(...)      per-occurrence conflict report
-- =============================================================================
set search_path = atd, public;

-- ---------------------------------------------------------------------------
-- 1. Hold expiry sweep. Called at the head of every allocation path, so an
--    abandoned checkout never blocks a real customer for longer than its TTL
--    even if the background job is down.
-- ---------------------------------------------------------------------------
create or replace function atd.expire_stale_holds(p_location uuid default null)
returns int language plpgsql as $$
declare v_count int;
begin
  with expired as (
    update atd.resource_reservations r
       set status = 'released', released_at = now()
     where r.status = 'hold'
       and r.expires_at < now()
       and (p_location is null or r.location_id = p_location)
    returning r.hold_id
  )
  select count(*) into v_count from expired;

  update atd.checkout_holds h
     set released_at = now()
   where h.released_at is null
     and h.converted_booking_id is null
     and h.expires_at < now()
     and (p_location is null or h.location_id = p_location);

  return coalesce(v_count, 0);
end $$;

-- ---------------------------------------------------------------------------
-- 2. Operating hours resolution for one local date, DST-correct.
--    Returns NULL when the facility is closed that day.
-- ---------------------------------------------------------------------------
create or replace function atd.open_span(p_location uuid, p_date date)
returns tstzrange language plpgsql stable as $$
declare
  v_tz text;
  v_open time; v_close time;
  v_override record;
  v_dow int;
begin
  select timezone into v_tz from atd.locations where id = p_location;
  if v_tz is null then return null; end if;

  select * into v_override from atd.date_overrides
   where location_id = p_location and on_date = p_date;

  if found then
    if v_override.is_closed then return null; end if;
    v_open := v_override.opens_at; v_close := v_override.closes_at;
  else
    v_dow := extract(dow from p_date)::int;
    select oh.opens_at, oh.closes_at into v_open, v_close
      from atd.operating_hours oh
      join atd.operating_hour_sets s on s.id = oh.hour_set_id
     where s.location_id = p_location
       and oh.day_of_week = v_dow
       and not oh.is_closed
       and (s.effective_from is null or s.effective_from <= p_date)
       and (s.effective_to   is null or s.effective_to   >= p_date)
     order by s.priority desc, s.is_default asc
     limit 1;
    if v_open is null then return null; end if;
  end if;

  -- Build the instant in the location's zone. `timestamp AT TIME ZONE tz`
  -- resolves DST correctly for the given local wall clock.
  return tstzrange(
    ((p_date + v_open)  at time zone v_tz),
    ((p_date + v_close) at time zone v_tz),
    '[)');
end $$;

-- ---------------------------------------------------------------------------
-- 3. Is a coach available (rules + date overrides + workload caps)?
-- ---------------------------------------------------------------------------
create or replace function atd.coach_is_available(
  p_coach uuid, p_starts timestamptz, p_ends timestamptz, p_location uuid)
returns boolean language plpgsql stable as $$
declare
  v_tz text; v_local_date date; v_start_t time; v_end_t time; v_dow int;
  v_ok boolean := false;
  v_coach record;
  v_day_minutes int;
  v_day_sessions int;
begin
  select * into v_coach from atd.coaches where id = p_coach and deleted_at is null and is_active;
  if not found then return false; end if;

  select timezone into v_tz from atd.locations where id = p_location;
  v_local_date := (p_starts at time zone v_tz)::date;
  v_start_t    := (p_starts at time zone v_tz)::time;
  v_end_t      := (p_ends   at time zone v_tz)::time;
  v_dow        := extract(dow from (p_starts at time zone v_tz))::int;

  -- Lead time.
  if p_starts < now() + make_interval(mins => v_coach.min_lead_time_minutes) then
    return false;
  end if;

  -- Date-specific override wins outright.
  if exists (select 1 from atd.coach_date_availability d
              where d.coach_id = p_coach and d.on_date = v_local_date) then
    select exists (
      select 1 from atd.coach_date_availability d
       where d.coach_id = p_coach and d.on_date = v_local_date
         and d.is_available
         and d.starts_at <= v_start_t and d.ends_at >= v_end_t
    ) into v_ok;
    if not v_ok then return false; end if;
  else
    select exists (
      select 1 from atd.coach_availability_rules r
       where r.coach_id = p_coach
         and r.day_of_week = v_dow
         and r.is_available
         and (r.location_id is null or r.location_id = p_location)
         and (r.effective_from is null or r.effective_from <= v_local_date)
         and (r.effective_to   is null or r.effective_to   >= v_local_date)
         and r.starts_at <= v_start_t and r.ends_at >= v_end_t
    ) into v_ok;
    if not v_ok then return false; end if;
  end if;

  -- Workload caps for that local day.
  if v_coach.max_sessions_per_day is not null then
    select count(*) into v_day_sessions
      from atd.resource_reservations rr
     where rr.resource_id = v_coach.resource_id
       and rr.is_blocking
       and (rr.starts_at at time zone v_tz)::date = v_local_date;
    if v_day_sessions >= v_coach.max_sessions_per_day then return false; end if;
  end if;

  if v_coach.max_consecutive_minutes is not null then
    select coalesce(sum(extract(epoch from (rr.ends_at - rr.starts_at))/60),0)::int
      into v_day_minutes
      from atd.resource_reservations rr
     where rr.resource_id = v_coach.resource_id
       and rr.is_blocking
       and (rr.starts_at at time zone v_tz)::date = v_local_date;
    if v_day_minutes + extract(epoch from (p_ends - p_starts))/60
       > v_coach.max_consecutive_minutes then
      return false;
    end if;
  end if;

  return true;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Candidate resources for one requirement, ordered by preference.
--    Preference order: explicitly preferred → assignment_priority (coaches)
--    → least-recently-used → code. "Least recently used" spreads lessons
--    fairly across coaches and rotates cage wear.
-- ---------------------------------------------------------------------------
create or replace function atd.candidate_resources(
  p_requirement uuid, p_starts timestamptz, p_ends timestamptz)
returns table (resource_id uuid, is_preferred boolean, priority int)
language plpgsql stable as $$
declare
  req record;
  v_location uuid;
begin
  select r.*, s.location_id into req
    from atd.service_resource_requirements r
    join atd.services s on s.id = r.service_id
   where r.id = p_requirement;
  if not found then return; end if;
  v_location := req.location_id;

  return query
  select res.id,
         (res.id = any(req.preferred_resource_ids)) as is_preferred,
         coalesce(c.assignment_priority, res.sort_order) as priority
    from atd.resources res
    left join atd.coaches c on c.resource_id = res.id and c.deleted_at is null
   where res.location_id = v_location
     and res.deleted_at is null
     and res.status = 'active'
     and res.resource_type_id = req.resource_type_id
     and not (res.id = any(req.excluded_resource_ids))
     and (cardinality(req.allowed_resource_ids) = 0 or res.id = any(req.allowed_resource_ids))
     and (req.required_attributes = '{}'::jsonb or res.attributes @> req.required_attributes)
     -- Coach slots additionally honour qualifications, availability, opt-in.
     and (c.id is null or (
            c.is_active
        and (cardinality(req.required_qualification_ids) = 0 or (
              select count(distinct cq.qualification_id)
                from atd.coach_qualifications cq
               where cq.coach_id = c.id
                 and cq.qualification_id = any(req.required_qualification_ids)
                 and (cq.expires_on is null or cq.expires_on >= current_date)
             ) = cardinality(req.required_qualification_ids))
        and atd.coach_is_available(c.id, p_starts, p_ends, v_location)
     ))
     -- Resource-level weekly availability windows, when defined.
     and (not exists (select 1 from atd.resource_availability_rules ra
                       where ra.resource_id = res.id)
          or exists (
            select 1 from atd.resource_availability_rules ra
             where ra.resource_id = res.id
               and ra.is_available
               and ra.day_of_week = extract(dow from (p_starts at time zone
                     (select timezone from atd.locations where id = v_location)))::int
               and ra.starts_at <= (p_starts at time zone
                     (select timezone from atd.locations where id = v_location))::time
               and ra.ends_at   >= (p_ends at time zone
                     (select timezone from atd.locations where id = v_location))::time))
   order by 2 desc, 3 asc, res.sort_order, res.code;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Free-slot probe. Honours capacity>1 by looking for any unclaimed index.
-- ---------------------------------------------------------------------------
create or replace function atd.free_slot_index(
  p_resource uuid, p_from timestamptz, p_to timestamptz,
  p_ignore_reservation uuid default null)
returns int language plpgsql stable as $$
declare
  v_capacity int;
  i int;
begin
  select capacity into v_capacity from atd.resources where id = p_resource;
  if v_capacity is null then return null; end if;

  for i in 0 .. v_capacity - 1 loop
    if not exists (
      select 1 from atd.resource_reservations rr
       where rr.resource_id = p_resource
         and rr.slot_index = i
         and rr.is_blocking
         and rr.blocking_span && tstzrange(p_from, p_to, '[)')
         and (p_ignore_reservation is null or rr.id <> p_ignore_reservation)
    ) then
      return i;
    end if;
  end loop;
  return null;
end $$;

-- Whole-facility closures block everything without needing a row per resource.
create or replace function atd.location_is_blocked(
  p_location uuid, p_from timestamptz, p_to timestamptz)
returns boolean language sql stable as $$
  select exists (
    select 1 from atd.resource_blocks b
     where b.location_id = p_location
       and b.applies_to_whole_location
       and b.cancelled_at is null
       and tstzrange(b.starts_at, b.ends_at, '[)') && tstzrange(p_from, p_to, '[)')
  )
$$;

-- ---------------------------------------------------------------------------
-- 6. Plan an allocation: can this service run at this instant, and with what?
--    Returns a JSONB plan; NULL when the slot is not satisfiable.
--    Shape: [{"requirement_id":..,"label":..,"resource_ids":[..],
--             "buffer_before":5,"buffer_after":5,"offset_start":0,"offset_end":0}]
-- ---------------------------------------------------------------------------
create or replace function atd.plan_allocation(
  p_service uuid,
  p_starts timestamptz,
  p_ends timestamptz,
  p_pinned jsonb default '{}'::jsonb,      -- {"<requirement_id>": ["<resource_id>"]}
  p_ignore_booking uuid default null)
returns jsonb language plpgsql stable as $$
declare
  svc record;
  req record;
  v_plan jsonb := '[]'::jsonb;
  v_taken uuid[] := '{}';
  v_chosen uuid[];
  v_pinned_list uuid[];
  cand record;
  v_bb int; v_ba int;
  v_rs timestamptz; v_re timestamptz;
  v_need int;
begin
  select * into svc from atd.services where id = p_service and deleted_at is null;
  if not found then return null; end if;

  if atd.location_is_blocked(svc.location_id, p_starts, p_ends) then
    return null;
  end if;

  for req in
    select * from atd.service_resource_requirements
     where service_id = p_service order by sort_order, id
  loop
    v_bb := coalesce(req.buffer_before_minutes, svc.buffer_before_minutes) + coalesce(req.setup_minutes, svc.setup_minutes);
    v_ba := coalesce(req.buffer_after_minutes,  svc.buffer_after_minutes)  + coalesce(req.cleanup_minutes, svc.cleanup_minutes);
    v_rs := p_starts + make_interval(mins => req.offset_start_minutes);
    v_re := p_ends   - make_interval(mins => req.offset_end_minutes);
    if v_re <= v_rs then v_re := v_rs + interval '1 minute'; end if;

    v_chosen := '{}';
    v_need := req.quantity;

    -- Honour pinned choices (customer picked a coach / admin picked a cage).
    v_pinned_list := coalesce(
      (select array_agg((x)::uuid) from jsonb_array_elements_text(
          coalesce(p_pinned -> (req.id::text), '[]'::jsonb)) as t(x)), '{}');

    if cardinality(v_pinned_list) > 0 then
      for cand in
        select c.resource_id from atd.candidate_resources(req.id, v_rs, v_re) c
         where c.resource_id = any(v_pinned_list)
      loop
        exit when v_need = 0;
        if not (cand.resource_id = any(v_taken))
           and atd.free_slot_index(cand.resource_id,
                 v_rs - make_interval(mins => v_bb),
                 v_re + make_interval(mins => v_ba)) is not null then
          v_chosen := v_chosen || cand.resource_id;
          v_taken  := v_taken  || cand.resource_id;
          v_need   := v_need - 1;
        end if;
      end loop;
      -- A pinned choice that is not free is a hard failure, never a silent
      -- swap. If a customer picked Coach Reyes, handing them Coach Brennan
      -- without saying so is worse than showing no availability. Substitution
      -- is an explicit admin action (reschedule_booking with new pins).
      if v_need > 0 then
        return null;
      end if;
    end if;

    for cand in select c.resource_id from atd.candidate_resources(req.id, v_rs, v_re) c
    loop
      exit when v_need = 0;
      continue when cand.resource_id = any(v_taken);
      if atd.free_slot_index(cand.resource_id,
            v_rs - make_interval(mins => v_bb),
            v_re + make_interval(mins => v_ba)) is not null then
        v_chosen := v_chosen || cand.resource_id;
        v_taken  := v_taken  || cand.resource_id;
        v_need   := v_need - 1;
      end if;
    end loop;

    if v_need > 0 then
      if req.is_optional then
        continue;
      end if;
      return null;                     -- requirement unsatisfiable → no slot
    end if;

    v_plan := v_plan || jsonb_build_object(
      'requirement_id', req.id,
      'label', req.label,
      'resource_ids', to_jsonb(v_chosen),
      'buffer_before', v_bb,
      'buffer_after', v_ba,
      'offset_start', req.offset_start_minutes,
      'offset_end', req.offset_end_minutes
    );
  end loop;

  return v_plan;
end $$;

-- ---------------------------------------------------------------------------
-- 7. Availability search. Walks the open window at the service's granularity
--    and returns only instants where EVERY requirement can be met.
-- ---------------------------------------------------------------------------
create or replace function atd.find_slots(
  p_service uuid,
  p_from date,
  p_to date,
  p_duration_minutes int default null,
  p_pinned jsonb default '{}'::jsonb,
  p_limit int default 200)
returns table (starts_at timestamptz, ends_at timestamptz, plan jsonb)
language plpgsql as $$
declare
  svc record;
  d date;
  v_span tstzrange;
  v_cursor timestamptz;
  v_dur int;
  v_plan jsonb;
  v_found int := 0;
  v_min_start timestamptz;
  v_max_start timestamptz;
begin
  perform atd.expire_stale_holds();

  select * into svc from atd.services where id = p_service and deleted_at is null;
  if not found then return; end if;

  v_dur := coalesce(p_duration_minutes, svc.default_duration_minutes);
  v_min_start := now() + make_interval(mins => svc.min_lead_minutes);
  v_max_start := now() + make_interval(days => svc.max_horizon_days);

  d := p_from;
  while d <= p_to loop
    v_span := atd.open_span(svc.location_id, d);
    if v_span is not null then
      v_cursor := lower(v_span);
      while v_cursor + make_interval(mins => v_dur) <= upper(v_span) loop
        if v_cursor >= v_min_start and v_cursor <= v_max_start then
          v_plan := atd.plan_allocation(
            p_service, v_cursor, v_cursor + make_interval(mins => v_dur), p_pinned);
          if v_plan is not null then
            starts_at := v_cursor;
            ends_at   := v_cursor + make_interval(mins => v_dur);
            plan      := v_plan;
            v_found   := v_found + 1;
            return next;
            if v_found >= p_limit then return; end if;
          end if;
        end if;
        v_cursor := v_cursor + make_interval(mins => greatest(svc.slot_granularity_minutes, 5));
      end loop;
    end if;
    d := d + 1;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 8. create_hold — atomically reserve every resource the service needs.
--    Any exclusion violation aborts the whole hold; there is no partial hold.
-- ---------------------------------------------------------------------------
create or replace function atd.create_hold(
  p_service uuid,
  p_starts timestamptz,
  p_ends timestamptz,
  p_session_token text,
  p_household uuid default null,
  p_pinned jsonb default '{}'::jsonb,
  p_hold_minutes int default null,
  p_payload jsonb default '{}'::jsonb)
returns table (hold_id uuid, expires_at timestamptz, plan jsonb)
language plpgsql as $$
declare
  svc record;
  v_plan jsonb;
  item jsonb;
  rid uuid;
  v_hold uuid;
  v_expires timestamptz;
  v_minutes int;
  v_slot int;
  v_rs timestamptz; v_re timestamptz;
begin
  perform atd.expire_stale_holds();

  select * into svc from atd.services where id = p_service and deleted_at is null;
  if not found then
    raise exception 'service % not found', p_service using errcode = 'no_data_found';
  end if;

  v_minutes := coalesce(p_hold_minutes,
                 (select (settings->>'checkout_hold_minutes')::int
                    from atd.locations where id = svc.location_id), 10);
  v_expires := now() + make_interval(mins => v_minutes);

  v_plan := atd.plan_allocation(p_service, p_starts, p_ends, p_pinned);
  if v_plan is null then
    raise exception 'no allocation available for service % at %', p_service, p_starts
      using errcode = 'exclusion_violation',
            hint = 'Another customer may have just taken this slot.';
  end if;

  insert into atd.checkout_holds
    (location_id, household_id, session_token, service_id, starts_at, ends_at, expires_at, payload)
  values (svc.location_id, p_household, p_session_token, p_service, p_starts, p_ends, v_expires, p_payload)
  returning id into v_hold;

  for item in select * from jsonb_array_elements(v_plan) loop
    v_rs := p_starts + make_interval(mins => (item->>'offset_start')::int);
    v_re := p_ends   - make_interval(mins => (item->>'offset_end')::int);
    if v_re <= v_rs then v_re := v_rs + interval '1 minute'; end if;

    for rid in select (x)::uuid from jsonb_array_elements_text(item->'resource_ids') as t(x) loop
      v_slot := atd.free_slot_index(rid,
                  v_rs - make_interval(mins => (item->>'buffer_before')::int),
                  v_re + make_interval(mins => (item->>'buffer_after')::int));
      if v_slot is null then
        raise exception 'resource % became unavailable during hold', rid
          using errcode = 'exclusion_violation';
      end if;

      insert into atd.resource_reservations
        (location_id, resource_id, hold_id, requirement_id, requirement_label,
         status, starts_at, ends_at, buffer_before_minutes, buffer_after_minutes,
         blocked_from, blocked_to, slot_index, expires_at)
      values (svc.location_id, rid, v_hold,
              (item->>'requirement_id')::uuid, item->>'label',
              'hold', v_rs, v_re,
              (item->>'buffer_before')::int, (item->>'buffer_after')::int,
              v_rs, v_re, v_slot, v_expires);
    end loop;
  end loop;

  hold_id := v_hold; expires_at := v_expires; plan := v_plan;
  return next;
end $$;

create or replace function atd.release_hold(p_hold uuid)
returns void language plpgsql as $$
begin
  update atd.resource_reservations
     set status = 'released', released_at = now()
   where hold_id = p_hold and status = 'hold';
  update atd.checkout_holds set released_at = now()
   where id = p_hold and released_at is null;
end $$;

-- ---------------------------------------------------------------------------
-- 9. confirm_hold — promote a hold into a real booking in ONE transaction.
--    Re-validates that the hold is still live; a caller that lost the hold is
--    told so rather than silently double-booking.
-- ---------------------------------------------------------------------------
create or replace function atd.confirm_hold(
  p_hold uuid,
  p_household uuid,
  p_participants uuid[] default '{}',
  p_created_by uuid default null,
  p_source text default 'online',
  p_status atd.booking_status default 'confirmed',
  p_answers jsonb default '{}'::jsonb,
  p_note text default null)
returns uuid language plpgsql as $$
declare
  h record;
  v_booking uuid;
  p uuid;
begin
  select * into h from atd.checkout_holds where id = p_hold for update;
  if not found then
    raise exception 'hold % not found', p_hold using errcode = 'no_data_found';
  end if;
  -- Idempotency is checked FIRST. confirm_hold marks the hold released once it
  -- converts, so a double-clicked Pay button must see the existing booking
  -- rather than a "hold was released" error.
  if h.converted_booking_id is not null then
    return h.converted_booking_id;
  end if;
  if h.released_at is not null then
    raise exception 'hold % was released' , p_hold using errcode = 'exclusion_violation';
  end if;
  if h.expires_at < now() then
    perform atd.release_hold(p_hold);
    raise exception 'hold % expired', p_hold using errcode = 'exclusion_violation';
  end if;

  insert into atd.bookings
    (location_id, service_id, household_id, status, starts_at, ends_at,
     blocked_from, blocked_to, timezone, participant_count, source,
     created_by_user_id, answers, customer_note)
  values (h.location_id, h.service_id, p_household, p_status, h.starts_at, h.ends_at,
          h.starts_at, h.ends_at,
          (select timezone from atd.locations where id = h.location_id),
          greatest(coalesce(array_length(p_participants,1),1),1), p_source,
          p_created_by, p_answers, p_note)
  returning id into v_booking;

  -- Hand the held reservations to the booking. The exclusion constraint is
  -- untouched by this because the rows keep blocking throughout.
  update atd.resource_reservations
     set hold_id = null, booking_id = v_booking, status = 'confirmed',
         expires_at = null
   where hold_id = p_hold and status = 'hold';

  update atd.checkout_holds
     set converted_booking_id = v_booking, released_at = now()
   where id = p_hold;

  if p_participants is not null then
    foreach p in array p_participants loop
      insert into atd.booking_participants (booking_id, participant_id)
      values (v_booking, p)
      on conflict (booking_id, participant_id) do nothing;
    end loop;
  end if;

  return v_booking;
end $$;

-- ---------------------------------------------------------------------------
-- 10. Direct booking (front desk / admin / walk-in), no separate hold step.
-- ---------------------------------------------------------------------------
create or replace function atd.create_booking(
  p_service uuid,
  p_starts timestamptz,
  p_ends timestamptz,
  p_household uuid,
  p_participants uuid[] default '{}',
  p_pinned jsonb default '{}'::jsonb,
  p_created_by uuid default null,
  p_source text default 'front_desk',
  p_status atd.booking_status default 'confirmed')
returns uuid language plpgsql as $$
declare
  v_hold uuid; v_booking uuid; r record;
begin
  select * into r from atd.create_hold(
    p_service, p_starts, p_ends,
    'internal:' || coalesce(p_created_by::text,'system'),
    p_household, p_pinned, 5);
  v_hold := r.hold_id;
  v_booking := atd.confirm_hold(v_hold, p_household, p_participants,
                                p_created_by, p_source, p_status);
  return v_booking;
end $$;

-- ---------------------------------------------------------------------------
-- 11. Reschedule / resize. Frees the old reservations and re-plans inside the
--     same transaction, so a failed move leaves the original booking intact.
-- ---------------------------------------------------------------------------
create or replace function atd.reschedule_booking(
  p_booking uuid,
  p_starts timestamptz,
  p_ends timestamptz,
  p_pinned jsonb default '{}'::jsonb,
  p_actor uuid default null)
returns jsonb language plpgsql as $$
declare
  b record; v_plan jsonb; item jsonb; rid uuid; v_slot int;
  v_rs timestamptz; v_re timestamptz;
begin
  select * into b from atd.bookings where id = p_booking for update;
  if not found then
    raise exception 'booking % not found', p_booking using errcode='no_data_found';
  end if;

  -- Drop old reservations first so the booking does not conflict with itself.
  delete from atd.resource_reservations where booking_id = p_booking;

  v_plan := atd.plan_allocation(b.service_id, p_starts, p_ends, p_pinned);
  if v_plan is null then
    raise exception 'cannot reschedule booking %: resources unavailable at %',
      p_booking, p_starts using errcode = 'exclusion_violation';
  end if;

  for item in select * from jsonb_array_elements(v_plan) loop
    v_rs := p_starts + make_interval(mins => (item->>'offset_start')::int);
    v_re := p_ends   - make_interval(mins => (item->>'offset_end')::int);
    if v_re <= v_rs then v_re := v_rs + interval '1 minute'; end if;
    for rid in select (x)::uuid from jsonb_array_elements_text(item->'resource_ids') as t(x) loop
      v_slot := atd.free_slot_index(rid,
                  v_rs - make_interval(mins => (item->>'buffer_before')::int),
                  v_re + make_interval(mins => (item->>'buffer_after')::int));
      if v_slot is null then
        raise exception 'resource % unavailable', rid using errcode='exclusion_violation';
      end if;
      insert into atd.resource_reservations
        (location_id, resource_id, booking_id, requirement_id, requirement_label,
         status, starts_at, ends_at, buffer_before_minutes, buffer_after_minutes,
         blocked_from, blocked_to, slot_index, created_by)
      values (b.location_id, rid, p_booking,
              (item->>'requirement_id')::uuid, item->>'label',
              'confirmed', v_rs, v_re,
              (item->>'buffer_before')::int, (item->>'buffer_after')::int,
              v_rs, v_re, v_slot, p_actor);
    end loop;
  end loop;

  update atd.bookings set starts_at = p_starts, ends_at = p_ends where id = p_booking;
  return v_plan;
end $$;

-- ---------------------------------------------------------------------------
-- 12. Cancellation returns the resources to inventory immediately.
-- ---------------------------------------------------------------------------
create or replace function atd.cancel_booking(
  p_booking uuid, p_reason text default null, p_actor uuid default null,
  p_status atd.booking_status default 'cancelled')
returns void language plpgsql as $$
begin
  update atd.resource_reservations
     set status = 'cancelled', released_at = now()
   where booking_id = p_booking and status in ('confirmed','hold','tentative','in_progress');

  update atd.bookings
     set status = p_status, cancelled_at = now(),
         cancelled_by_user_id = p_actor, cancellation_reason = p_reason
   where id = p_booking;
end $$;

-- ---------------------------------------------------------------------------
-- 13. Recurrence validation. Reports every occurrence with its verdict BEFORE
--     anything is written, which is what the admin UI shows.
-- ---------------------------------------------------------------------------
create or replace function atd.validate_recurrence(
  p_service uuid,
  p_start_date date,
  p_end_date date,
  p_weekdays int[],
  p_start_time time,
  p_duration_minutes int,
  p_interval int default 1,
  p_pinned jsonb default '{}'::jsonb,
  p_skip_dates date[] default '{}')
returns table (occurrence_date date, starts_at timestamptz, ends_at timestamptz,
               is_valid boolean, reason text, plan jsonb)
language plpgsql as $$
declare
  svc record; v_tz text; d date; wk int := 0; v_plan jsonb;
  v_start timestamptz; v_end timestamptz; v_open tstzrange;
begin
  select * into svc from atd.services where id = p_service;
  if not found then return; end if;
  select timezone into v_tz from atd.locations where id = svc.location_id;

  d := p_start_date;
  while d <= p_end_date loop
    if (cardinality(p_weekdays) = 0 or extract(dow from d)::int = any(p_weekdays))
       and not (d = any(p_skip_dates))
       and (p_interval <= 1 or ((d - p_start_date) / 7) % p_interval = 0)
    then
      -- Local wall clock → instant, so a series spanning a DST change keeps
      -- its 4:00 PM slot instead of drifting an hour.
      v_start := ((d + p_start_time) at time zone v_tz);
      v_end   := v_start + make_interval(mins => p_duration_minutes);
      occurrence_date := d; starts_at := v_start; ends_at := v_end;

      v_open := atd.open_span(svc.location_id, d);
      if v_open is null then
        is_valid := false; reason := 'Facility closed'; plan := null;
      elsif v_start < lower(v_open) or v_end > upper(v_open) then
        is_valid := false; reason := 'Outside operating hours'; plan := null;
      else
        v_plan := atd.plan_allocation(p_service, v_start, v_end, p_pinned);
        if v_plan is null then
          is_valid := false; reason := 'Required resources unavailable'; plan := null;
        else
          is_valid := true; reason := null; plan := v_plan;
        end if;
      end if;
      return next;
    end if;
    d := d + 1;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 14. Program session materialisation: one booking + reservations per session.
-- ---------------------------------------------------------------------------
create or replace function atd.materialize_program_sessions(
  p_program uuid, p_pinned jsonb default '{}'::jsonb, p_actor uuid default null)
returns int language plpgsql as $$
declare
  prog record; sess record; v_booking uuid; v_count int := 0;
  v_plan jsonb; item jsonb; rid uuid; v_slot int;
  v_rs timestamptz; v_re timestamptz;
begin
  select * into prog from atd.programs where id = p_program;
  if not found then
    raise exception 'program % not found', p_program using errcode='no_data_found';
  end if;

  for sess in select * from atd.program_sessions
               where program_id = p_program and booking_id is null and not is_cancelled
               order by session_number
  loop
    v_plan := atd.plan_allocation(prog.service_id, sess.starts_at, sess.ends_at, p_pinned);
    if v_plan is null then
      raise exception 'program % session % has no available resources at %',
        p_program, sess.session_number, sess.starts_at using errcode='exclusion_violation';
    end if;

    insert into atd.bookings
      (location_id, service_id, program_id, program_session_id, status,
       starts_at, ends_at, blocked_from, blocked_to, timezone, title, source,
       created_by_user_id)
    values (prog.location_id, prog.service_id, p_program, sess.id, 'confirmed',
            sess.starts_at, sess.ends_at, sess.starts_at, sess.ends_at,
            (select timezone from atd.locations where id = prog.location_id),
            prog.name || ' — session ' || sess.session_number, 'admin', p_actor)
    returning id into v_booking;

    for item in select * from jsonb_array_elements(v_plan) loop
      v_rs := sess.starts_at + make_interval(mins => (item->>'offset_start')::int);
      v_re := sess.ends_at   - make_interval(mins => (item->>'offset_end')::int);
      if v_re <= v_rs then v_re := v_rs + interval '1 minute'; end if;
      for rid in select (x)::uuid from jsonb_array_elements_text(item->'resource_ids') as t(x) loop
        v_slot := atd.free_slot_index(rid,
                    v_rs - make_interval(mins => (item->>'buffer_before')::int),
                    v_re + make_interval(mins => (item->>'buffer_after')::int));
        if v_slot is null then
          raise exception 'resource % unavailable for program session %', rid, sess.id
            using errcode='exclusion_violation';
        end if;
        insert into atd.resource_reservations
          (location_id, resource_id, booking_id, requirement_id, requirement_label,
           status, starts_at, ends_at, buffer_before_minutes, buffer_after_minutes,
           blocked_from, blocked_to, slot_index, created_by)
        values (prog.location_id, rid, v_booking,
                (item->>'requirement_id')::uuid, item->>'label',
                'confirmed', v_rs, v_re,
                (item->>'buffer_before')::int, (item->>'buffer_after')::int,
                v_rs, v_re, v_slot, p_actor);
      end loop;
    end loop;

    update atd.program_sessions set booking_id = v_booking where id = sess.id;
    v_count := v_count + 1;
  end loop;

  return v_count;
end $$;

-- ---------------------------------------------------------------------------
-- 15. Register a participant for a program. Row-locks the program so the
--     final-spot race resolves deterministically; the CHECK constraint is the
--     backstop if anything ever bypasses this function.
-- ---------------------------------------------------------------------------
create or replace function atd.register_participant(
  p_program uuid,
  p_participant uuid,
  p_household uuid,
  p_kind text default 'full_series',
  p_session uuid default null,
  p_allow_waitlist boolean default true)
returns table (registration_id uuid, status atd.registration_status)
language plpgsql as $$
declare
  prog record; part record; v_age int; v_seats int; v_reg uuid; v_as_of date;
begin
  -- FOR UPDATE serialises concurrent claims on the last seat.
  select * into prog from atd.programs where id = p_program for update;
  if not found then
    raise exception 'program % not found', p_program using errcode='no_data_found';
  end if;
  if prog.status not in ('published','full') then
    raise exception 'program % is not open for registration', p_program
      using errcode='check_violation';
  end if;
  if prog.registration_closes_at is not null and now() > prog.registration_closes_at then
    raise exception 'registration closed for program %', p_program using errcode='check_violation';
  end if;

  select * into part from atd.participants where id = p_participant;
  v_as_of := coalesce(prog.age_as_of_date, prog.starts_on);
  v_age := atd.age_on(part.date_of_birth, v_as_of);

  -- Age is evaluated against the program date, not today, so a child who has a
  -- birthday between registration and the camp is judged correctly.
  if prog.min_age is not null and v_age is not null and v_age < prog.min_age then
    raise exception 'participant is % on %, below program minimum %', v_age, v_as_of, prog.min_age
      using errcode='check_violation';
  end if;
  if prog.max_age is not null and v_age is not null and v_age > prog.max_age then
    raise exception 'participant is % on %, above program maximum %', v_age, v_as_of, prog.max_age
      using errcode='check_violation';
  end if;

  v_seats := prog.capacity - prog.enrolled_count;

  if v_seats <= 0 then
    if not (p_allow_waitlist and prog.allow_waitlist) then
      raise exception 'program % is full', p_program using errcode='check_violation';
    end if;
    insert into atd.waitlist_entries
      (location_id, program_id, household_id, participant_id, status)
    values (prog.location_id, p_program, p_household, p_participant, 'waiting');
    insert into atd.registrations
      (program_id, program_session_id, household_id, participant_id, status,
       registration_kind, age_at_registration)
    values (p_program, p_session, p_household, p_participant, 'waitlisted',
            p_kind, v_age)
    returning id into v_reg;
    registration_id := v_reg; status := 'waitlisted'; return next; return;
  end if;

  insert into atd.registrations
    (program_id, program_session_id, household_id, participant_id, status,
     registration_kind, price_cents, age_at_registration)
  values (p_program, p_session, p_household, p_participant, 'registered',
          p_kind, case when p_kind = 'full_series' then prog.price_cents
                       else coalesce(prog.drop_in_price_cents, prog.price_cents) end,
          v_age)
  returning id into v_reg;

  -- Alias required: the OUT parameter `status` would otherwise shadow the column.
  update atd.programs p
     set status = case when p.enrolled_count >= p.capacity then 'full' else p.status end
   where p.id = p_program;

  registration_id := v_reg; status := 'registered'; return next;
end $$;
