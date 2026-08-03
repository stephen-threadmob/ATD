-- =============================================================================
-- 0012 Add-on aware allocation
-- -----------------------------------------------------------------------------
-- Problem this fixes: an add-on could previously declare that it PULLS a
-- resource ("Add HitTrax" -> reserve the HitTrax unit) but had no way to
-- CONSTRAIN the resources the host service already required. The result was a
-- physically impossible booking: the HitTrax unit reserved alongside a 35 ft
-- cage it does not live in.
--
-- An add-on now does both:
--   adds_resource_type_id      -> append a new requirement
--   constrains_resource_type_id-> narrow an existing requirement's attributes
--
-- Allocation planning is refactored around atd.effective_requirements(), so
-- availability search, holds, direct booking and rescheduling all see the same
-- add-on-adjusted requirement set. There is exactly one place that decides what
-- a booking consumes.
-- =============================================================================
set search_path = atd, public;

alter table atd.service_addons
  add column if not exists constrains_resource_type_id uuid
    references atd.resource_types(id) on delete set null,
  add column if not exists constrains_attributes jsonb not null default '{}'::jsonb;

comment on column atd.service_addons.constrains_attributes is
  'Merged into the matching requirement''s required_attributes when the add-on is selected.';

-- "Add HitTrax" now also forces the cage requirement to a HitTrax-equipped cage.
update atd.service_addons
   set constrains_resource_type_id = (
         select id from atd.resource_types
          where key = 'cage' and location_id = service_addons.location_id),
       constrains_attributes = '{"has_hittrax": true}'::jsonb
 where key = 'hittrax_addon';

-- ---------------------------------------------------------------------------
-- Effective requirement set = base requirements (attribute-narrowed by any
-- selected add-on) + requirements contributed by the add-ons themselves.
--
-- p_addons shape: [{"addon_id":"<uuid>","quantity":1}, ...]
-- ---------------------------------------------------------------------------
create or replace function atd.effective_requirements(
  p_service uuid, p_addons jsonb default '[]'::jsonb)
returns table (
  requirement_id uuid,
  label text,
  resource_type_id uuid,
  quantity int,
  is_optional boolean,
  required_attributes jsonb,
  allowed_resource_ids uuid[],
  preferred_resource_ids uuid[],
  excluded_resource_ids uuid[],
  required_qualification_ids uuid[],
  assignment_mode atd.assignment_mode,
  buffer_before int,
  buffer_after int,
  offset_start int,
  offset_end int,
  sort_order int)
language plpgsql stable as $$
declare
  svc record;
  v_addon_ids uuid[];
begin
  select * into svc from atd.services where id = p_service and deleted_at is null;
  if not found then return; end if;

  select coalesce(array_agg((e->>'addon_id')::uuid), '{}')
    into v_addon_ids
    from jsonb_array_elements(coalesce(p_addons,'[]'::jsonb)) e;

  -- Base requirements, with add-on attribute constraints merged in.
  return query
  select r.id,
         r.label,
         r.resource_type_id,
         r.quantity,
         r.is_optional,
         r.required_attributes || coalesce((
           select jsonb_object_agg(k, v)
             from atd.service_addons a,
                  lateral jsonb_each(a.constrains_attributes) as kv(k, v)
            where a.id = any(v_addon_ids)
              and a.constrains_resource_type_id = r.resource_type_id
         ), '{}'::jsonb) as required_attributes,
         r.allowed_resource_ids,
         r.preferred_resource_ids,
         r.excluded_resource_ids,
         r.required_qualification_ids,
         r.assignment_mode,
         coalesce(r.buffer_before_minutes, svc.buffer_before_minutes)
           + coalesce(r.setup_minutes, svc.setup_minutes),
         coalesce(r.buffer_after_minutes, svc.buffer_after_minutes)
           + coalesce(r.cleanup_minutes, svc.cleanup_minutes),
         r.offset_start_minutes,
         r.offset_end_minutes,
         r.sort_order
    from atd.service_resource_requirements r
   where r.service_id = p_service

  union all

  -- Requirements contributed by selected add-ons.
  select a.id,
         a.name,
         a.adds_resource_type_id,
         greatest(a.adds_resource_quantity, 1),
         false,
         a.adds_required_attributes,
         '{}'::uuid[], '{}'::uuid[], '{}'::uuid[], '{}'::uuid[],
         'auto'::atd.assignment_mode,
         svc.buffer_before_minutes + svc.setup_minutes,
         svc.buffer_after_minutes + svc.cleanup_minutes,
         0, 0,
         1000
    from atd.service_addons a
   where a.id = any(v_addon_ids)
     and a.adds_resource_type_id is not null
     and a.adds_resource_quantity > 0;
end $$;

-- ---------------------------------------------------------------------------
-- Generalised candidate lookup. The requirement-id version is kept as a thin
-- wrapper so existing callers and admin tooling keep working.
-- ---------------------------------------------------------------------------
create or replace function atd.candidate_resources_for(
  p_location uuid,
  p_resource_type uuid,
  p_attributes jsonb,
  p_allowed uuid[],
  p_excluded uuid[],
  p_preferred uuid[],
  p_qualifications uuid[],
  p_starts timestamptz,
  p_ends timestamptz)
returns table (resource_id uuid, is_preferred boolean, priority int)
language plpgsql stable as $$
declare v_tz text;
begin
  select timezone into v_tz from atd.locations where id = p_location;

  return query
  select res.id,
         (res.id = any(p_preferred)) as is_preferred,
         coalesce(c.assignment_priority, res.sort_order) as priority
    from atd.resources res
    left join atd.coaches c on c.resource_id = res.id and c.deleted_at is null
   where res.location_id = p_location
     and res.deleted_at is null
     and res.status = 'active'
     and res.resource_type_id = p_resource_type
     and not (res.id = any(p_excluded))
     and (cardinality(p_allowed) = 0 or res.id = any(p_allowed))
     and (p_attributes = '{}'::jsonb or res.attributes @> p_attributes)
     and (c.id is null or (
            c.is_active
        and (cardinality(p_qualifications) = 0 or (
              select count(distinct cq.qualification_id)
                from atd.coach_qualifications cq
               where cq.coach_id = c.id
                 and cq.qualification_id = any(p_qualifications)
                 and (cq.expires_on is null or cq.expires_on >= current_date)
             ) = cardinality(p_qualifications))
        and atd.coach_is_available(c.id, p_starts, p_ends, p_location)
     ))
     and (not exists (select 1 from atd.resource_availability_rules ra
                       where ra.resource_id = res.id)
          or exists (
            select 1 from atd.resource_availability_rules ra
             where ra.resource_id = res.id
               and ra.is_available
               and ra.day_of_week = extract(dow from (p_starts at time zone v_tz))::int
               and ra.starts_at <= (p_starts at time zone v_tz)::time
               and ra.ends_at   >= (p_ends   at time zone v_tz)::time))
   order by 2 desc, 3 asc, res.sort_order, res.code;
end $$;

create or replace function atd.candidate_resources(
  p_requirement uuid, p_starts timestamptz, p_ends timestamptz)
returns table (resource_id uuid, is_preferred boolean, priority int)
language plpgsql stable as $$
declare req record;
begin
  select r.*, s.location_id into req
    from atd.service_resource_requirements r
    join atd.services s on s.id = r.service_id
   where r.id = p_requirement;
  if not found then return; end if;

  return query select * from atd.candidate_resources_for(
    req.location_id, req.resource_type_id, req.required_attributes,
    req.allowed_resource_ids, req.excluded_resource_ids, req.preferred_resource_ids,
    req.required_qualification_ids, p_starts, p_ends);
end $$;

-- ---------------------------------------------------------------------------
-- plan_allocation, rebuilt on effective_requirements and add-on aware.
-- ---------------------------------------------------------------------------
create or replace function atd.plan_allocation(
  p_service uuid,
  p_starts timestamptz,
  p_ends timestamptz,
  p_pinned jsonb default '{}'::jsonb,
  p_ignore_booking uuid default null,
  p_addons jsonb default '[]'::jsonb)
returns jsonb language plpgsql stable as $$
declare
  svc record;
  req record;
  cand record;
  v_plan jsonb := '[]'::jsonb;
  v_taken uuid[] := '{}';
  v_chosen uuid[];
  v_pinned_list uuid[];
  v_rs timestamptz; v_re timestamptz;
  v_need int;
begin
  select * into svc from atd.services where id = p_service and deleted_at is null;
  if not found then return null; end if;

  if atd.location_is_blocked(svc.location_id, p_starts, p_ends) then
    return null;
  end if;

  for req in
    select * from atd.effective_requirements(p_service, p_addons)
     order by sort_order, requirement_id
  loop
    v_rs := p_starts + make_interval(mins => req.offset_start);
    v_re := p_ends   - make_interval(mins => req.offset_end);
    if v_re <= v_rs then v_re := v_rs + interval '1 minute'; end if;

    v_chosen := '{}';
    v_need := req.quantity;

    v_pinned_list := coalesce(
      (select array_agg((x)::uuid) from jsonb_array_elements_text(
          coalesce(p_pinned -> (req.requirement_id::text), '[]'::jsonb)) as t(x)), '{}');

    if cardinality(v_pinned_list) > 0 then
      for cand in
        select c.resource_id from atd.candidate_resources_for(
                 svc.location_id, req.resource_type_id, req.required_attributes,
                 req.allowed_resource_ids, req.excluded_resource_ids,
                 req.preferred_resource_ids, req.required_qualification_ids,
                 v_rs, v_re) c
         where c.resource_id = any(v_pinned_list)
      loop
        exit when v_need = 0;
        if not (cand.resource_id = any(v_taken))
           and atd.free_slot_index(cand.resource_id,
                 v_rs - make_interval(mins => req.buffer_before),
                 v_re + make_interval(mins => req.buffer_after)) is not null then
          v_chosen := v_chosen || cand.resource_id;
          v_taken  := v_taken  || cand.resource_id;
          v_need   := v_need - 1;
        end if;
      end loop;
      -- A pinned choice that is not free is a hard failure, never a silent swap.
      if v_need > 0 then
        return null;
      end if;
    end if;

    for cand in
      select c.resource_id from atd.candidate_resources_for(
               svc.location_id, req.resource_type_id, req.required_attributes,
               req.allowed_resource_ids, req.excluded_resource_ids,
               req.preferred_resource_ids, req.required_qualification_ids,
               v_rs, v_re) c
    loop
      exit when v_need = 0;
      continue when cand.resource_id = any(v_taken);
      if atd.free_slot_index(cand.resource_id,
            v_rs - make_interval(mins => req.buffer_before),
            v_re + make_interval(mins => req.buffer_after)) is not null then
        v_chosen := v_chosen || cand.resource_id;
        v_taken  := v_taken  || cand.resource_id;
        v_need   := v_need - 1;
      end if;
    end loop;

    if v_need > 0 then
      if req.is_optional then continue; end if;
      return null;
    end if;

    v_plan := v_plan || jsonb_build_object(
      'requirement_id', req.requirement_id,
      'label', req.label,
      'resource_ids', to_jsonb(v_chosen),
      'buffer_before', req.buffer_before,
      'buffer_after', req.buffer_after,
      'offset_start', req.offset_start,
      'offset_end', req.offset_end
    );
  end loop;

  return v_plan;
end $$;

-- ---------------------------------------------------------------------------
-- Thread add-ons through the public entry points.
-- ---------------------------------------------------------------------------
create or replace function atd.find_slots(
  p_service uuid,
  p_from date,
  p_to date,
  p_duration_minutes int default null,
  p_pinned jsonb default '{}'::jsonb,
  p_limit int default 200,
  p_addons jsonb default '[]'::jsonb)
returns table (starts_at timestamptz, ends_at timestamptz, plan jsonb)
language plpgsql as $$
declare
  svc record; d date; v_span tstzrange; v_cursor timestamptz;
  v_dur int; v_plan jsonb; v_found int := 0;
  v_min_start timestamptz; v_max_start timestamptz; v_extra int;
begin
  perform atd.expire_stale_holds();

  select * into svc from atd.services where id = p_service and deleted_at is null;
  if not found then return; end if;

  -- Add-ons may lengthen the session (e.g. "Extra 30 Minutes").
  select coalesce(sum(a.adds_minutes * greatest((e->>'quantity')::int,1)), 0)
    into v_extra
    from jsonb_array_elements(coalesce(p_addons,'[]'::jsonb)) e
    join atd.service_addons a on a.id = (e->>'addon_id')::uuid;

  v_dur := coalesce(p_duration_minutes, svc.default_duration_minutes) + coalesce(v_extra,0);
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
            p_service, v_cursor, v_cursor + make_interval(mins => v_dur),
            p_pinned, null, p_addons);
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

create or replace function atd.create_hold(
  p_service uuid,
  p_starts timestamptz,
  p_ends timestamptz,
  p_session_token text,
  p_household uuid default null,
  p_pinned jsonb default '{}'::jsonb,
  p_hold_minutes int default null,
  p_payload jsonb default '{}'::jsonb,
  p_addons jsonb default '[]'::jsonb)
returns table (hold_id uuid, expires_at timestamptz, plan jsonb)
language plpgsql as $$
declare
  svc record; v_plan jsonb; item jsonb; rid uuid;
  v_hold uuid; v_expires timestamptz; v_minutes int; v_slot int;
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

  v_plan := atd.plan_allocation(p_service, p_starts, p_ends, p_pinned, null, p_addons);
  if v_plan is null then
    raise exception 'no allocation available for service % at %', p_service, p_starts
      using errcode = 'exclusion_violation',
            hint = 'Another customer may have just taken this slot.';
  end if;

  insert into atd.checkout_holds
    (location_id, household_id, session_token, service_id, starts_at, ends_at, expires_at, payload)
  values (svc.location_id, p_household, p_session_token, p_service, p_starts, p_ends, v_expires,
          p_payload || jsonb_build_object('addons', coalesce(p_addons,'[]'::jsonb)))
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
              -- Add-on-derived rows reference an add-on id, not a requirement
              -- row, so only store the FK when it really is a requirement.
              (select r.id from atd.service_resource_requirements r
                where r.id = (item->>'requirement_id')::uuid),
              item->>'label',
              'hold', v_rs, v_re,
              (item->>'buffer_before')::int, (item->>'buffer_after')::int,
              v_rs, v_re, v_slot, v_expires);
    end loop;
  end loop;

  hold_id := v_hold; expires_at := v_expires; plan := v_plan;
  return next;
end $$;

create or replace function atd.create_booking(
  p_service uuid,
  p_starts timestamptz,
  p_ends timestamptz,
  p_household uuid,
  p_participants uuid[] default '{}',
  p_pinned jsonb default '{}'::jsonb,
  p_created_by uuid default null,
  p_source text default 'front_desk',
  p_status atd.booking_status default 'confirmed',
  p_addons jsonb default '[]'::jsonb)
returns uuid language plpgsql as $$
declare v_hold uuid; v_booking uuid; r record;
begin
  select * into r from atd.create_hold(
    p_service, p_starts, p_ends,
    'internal:' || coalesce(p_created_by::text,'system'),
    p_household, p_pinned, 5, '{}'::jsonb, p_addons);
  v_hold := r.hold_id;
  v_booking := atd.confirm_hold(v_hold, p_household, p_participants,
                                p_created_by, p_source, p_status);
  return v_booking;
end $$;

create or replace function atd.reschedule_booking(
  p_booking uuid,
  p_starts timestamptz,
  p_ends timestamptz,
  p_pinned jsonb default '{}'::jsonb,
  p_actor uuid default null,
  p_addons jsonb default '[]'::jsonb)
returns jsonb language plpgsql as $$
declare
  b record; v_plan jsonb; item jsonb; rid uuid; v_slot int;
  v_rs timestamptz; v_re timestamptz;
begin
  select * into b from atd.bookings where id = p_booking for update;
  if not found then
    raise exception 'booking % not found', p_booking using errcode='no_data_found';
  end if;

  delete from atd.resource_reservations where booking_id = p_booking;

  v_plan := atd.plan_allocation(b.service_id, p_starts, p_ends, p_pinned, p_booking, p_addons);
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
              (select r.id from atd.service_resource_requirements r
                where r.id = (item->>'requirement_id')::uuid),
              item->>'label',
              'confirmed', v_rs, v_re,
              (item->>'buffer_before')::int, (item->>'buffer_after')::int,
              v_rs, v_re, v_slot, p_actor);
    end loop;
  end loop;

  update atd.bookings set starts_at = p_starts, ends_at = p_ends where id = p_booking;
  return v_plan;
end $$;

-- materialize_program_sessions passes no add-ons but must use the new signature.
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
       starts_at, ends_at, blocked_from, blocked_to, timezone, title, source, created_by_user_id)
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
                (select r.id from atd.service_resource_requirements r
                  where r.id = (item->>'requirement_id')::uuid),
                item->>'label',
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

-- The old 5-argument plan_allocation signature is now ambiguous with the
-- 6-argument one for callers that pass 5 args; drop the stale variant.
drop function if exists atd.plan_allocation(uuid, timestamptz, timestamptz, jsonb, uuid);
drop function if exists atd.find_slots(uuid, date, date, int, jsonb, int);
drop function if exists atd.create_hold(uuid, timestamptz, timestamptz, text, uuid, jsonb, int, jsonb);
drop function if exists atd.create_booking(uuid, timestamptz, timestamptz, uuid, uuid[], jsonb, uuid, text, atd.booking_status);
drop function if exists atd.reschedule_booking(uuid, timestamptz, timestamptz, jsonb, uuid);
