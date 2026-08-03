-- =============================================================================
-- Add-on aware allocation tests
-- =============================================================================
set search_path = atd, public;

do $$
declare
  v_h uuid; v_u uuid; v_start timestamptz;
  v_plan_plain jsonb; v_plan_ht jsonb;
  v_cage_codes text[]; v_types text[];
  v_addons jsonb;
begin
  insert into atd.users (email, first_name, last_name)
  values ('addon.test@example.com','Addon','Tester') returning id into v_u;
  insert into atd.households (location_id, name, primary_user_id)
  values ('00000000-0000-4000-8000-0000000010c1','Addon House', v_u) returning id into v_h;

  -- Wednesday 10:00 local, when Marcus (HitTrax certified) works.
  v_start := t.slot(3,1,10);
  v_addons := jsonb_build_array(
    jsonb_build_object('addon_id','a1000000-0000-4000-8000-000000000001','quantity',1));

  -- A plain private hitting lesson: coach + any cage.
  v_plan_plain := atd.plan_allocation('11000000-0000-4000-8000-000000000001',
                    v_start, v_start + interval '1 hour');
  perform t.eq('plain hitting lesson plans 2 requirements',
               jsonb_array_length(v_plan_plain), 2);

  -- Same lesson with "Add HitTrax": now three requirements, and the cage
  -- requirement has been narrowed to the HitTrax-equipped cage.
  v_plan_ht := atd.plan_allocation('11000000-0000-4000-8000-000000000001',
                 v_start, v_start + interval '1 hour', '{}'::jsonb, null, v_addons);
  perform t.eq('with the HitTrax add-on the lesson plans 3 requirements',
               jsonb_array_length(v_plan_ht), 3);

  select array_agg(distinct r.code order by r.code) into v_cage_codes
    from jsonb_array_elements(v_plan_ht) item,
         jsonb_array_elements_text(item->'resource_ids') as x(rid)
    join atd.resources r on r.id = x.rid::uuid
    join atd.resource_types rt on rt.id = r.resource_type_id
   where rt.key = 'cage';
  perform t.ok('the add-on narrows the cage to the HitTrax cage',
               v_cage_codes = array['CAGE-5'], array_to_string(v_cage_codes,','));

  select array_agg(distinct rt.key order by rt.key) into v_types
    from jsonb_array_elements(v_plan_ht) item,
         jsonb_array_elements_text(item->'resource_ids') as x(rid)
    join atd.resources r on r.id = x.rid::uuid
    join atd.resource_types rt on rt.id = r.resource_type_id;
  perform t.ok('the HitTrax unit is pulled in alongside coach and cage',
               v_types @> array['cage','hittrax','coach'], array_to_string(v_types,','));

  perform set_config('addon.household', v_h::text, false);
end $$;

-- A booking made with the add-on must actually block the HitTrax unit, so an
-- independent HitTrax rental at the same time is impossible.
do $$
declare v_b uuid; v_start timestamptz; v_addons jsonb;
begin
  v_start := t.slot(3,2,10);
  v_addons := jsonb_build_array(
    jsonb_build_object('addon_id','a1000000-0000-4000-8000-000000000001','quantity',1));

  v_b := atd.create_booking('11000000-0000-4000-8000-000000000001',
           v_start, v_start + interval '1 hour',
           current_setting('addon.household')::uuid, '{}', '{}'::jsonb,
           null, 'front_desk', 'confirmed', v_addons);

  perform t.eq('booking with the add-on reserves 3 resources',
    (select count(*)::int from atd.resource_reservations where booking_id = v_b), 3);

  perform t.ok('HitTrax rental is blocked by a lesson that added HitTrax',
    atd.plan_allocation('11000000-0000-4000-8000-000000000012',
      v_start + interval '10 min', v_start + interval '40 min') is null);
end $$;

-- Duration-extending add-ons lengthen the searched slot.
do $$
declare d date; v_a jsonb; v_len_plain int; v_len_ext int;
begin
  d := (now() at time zone 'America/New_York')::date + 25;
  v_a := jsonb_build_array(
    jsonb_build_object('addon_id','a1000000-0000-4000-8000-000000000006','quantity',1));

  select extract(epoch from (ends_at - starts_at))/60 into v_len_plain
    from atd.find_slots('11000000-0000-4000-8000-000000000010', d, d, 60, '{}'::jsonb, 1);
  select extract(epoch from (ends_at - starts_at))/60 into v_len_ext
    from atd.find_slots('11000000-0000-4000-8000-000000000010', d, d, 60, '{}'::jsonb, 1, v_a);

  perform t.eq('base cage rental slot is 60 minutes', v_len_plain, 60);
  perform t.eq('"Extra 30 Minutes" makes the searched slot 90 minutes', v_len_ext, 90);
end $$;
