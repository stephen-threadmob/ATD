#!/usr/bin/env bash
# =============================================================================
# Concurrency proof. These are the tests a single-connection suite cannot do:
# N real client connections hitting the same slot at the same instant.
#
# Success criterion is NOT "no errors". It is "exactly one winner".
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")/../.."

export PGHOST="${PGHOST:-localhost}" PGUSER="${PGUSER:-postgres}" PGDATABASE="${PGDATABASE:-atd}"
N="${N:-12}"
PASS=0; FAIL=0
ok(){ if [ "$1" = "1" ]; then echo "ok    $2"; PASS=$((PASS+1)); else echo "FAIL  $2 — $3"; FAIL=$((FAIL+1)); fi }

psql -q -c "drop table if exists race_log;" \
     -c "create table race_log(worker int, outcome text, detail text, at timestamptz default clock_timestamp());" >/dev/null

HH=$(psql -tAc "select id from atd.households limit 1")
if [ -z "$HH" ]; then
  HH=$(psql -tAc "
    with u as (insert into atd.users(email,first_name,last_name)
               values('race@example.com','Race','Tester') returning id)
    insert into atd.households(location_id,name,primary_user_id)
    select '00000000-0000-4000-8000-0000000010c1','Race House', u.id from u returning id" | head -1)
fi

# -----------------------------------------------------------------------------
# Race 1: N customers check out the SAME HitTrax slot simultaneously.
# The HitTrax cage and unit are singletons, so exactly one may win.
# -----------------------------------------------------------------------------
SLOT=$(psql -tAc "select (((now() at time zone 'America/New_York')::date + 45 + interval '13 hours') at time zone 'America/New_York')")

for i in $(seq 1 "$N"); do
  psql -q -v ON_ERROR_STOP=0 >/dev/null 2>&1 <<SQL &
begin;
-- Everyone waits on the same advisory gate, then is released together, so the
-- requests genuinely overlap instead of trickling in.
select pg_advisory_xact_lock_shared(424242);
do \$\$
declare r record;
begin
  select * into r from atd.create_hold(
    '11000000-0000-4000-8000-000000000012',
    '$SLOT'::timestamptz, '$SLOT'::timestamptz + interval '1 hour',
    'race-$i', '$HH'::uuid, '{}'::jsonb, 10);
  perform atd.confirm_hold(r.hold_id, '$HH'::uuid);
  insert into race_log(worker, outcome) values ($i, 'won');
exception when others then
  insert into race_log(worker, outcome, detail) values ($i, 'lost', sqlstate);
end \$\$;
commit;
SQL
done
wait

WON=$(psql -tAc "select count(*) from race_log where outcome='won'")
RES=$(psql -tAc "select count(*) from atd.resource_reservations rr join atd.resources r on r.id=rr.resource_id where r.code='HITTRAX-1' and rr.is_blocking and rr.starts_at='$SLOT'::timestamptz")
[ "$WON" = "1" ] && ok 1 "$N concurrent checkouts for one HitTrax slot -> exactly 1 winner" \
                 || ok 0 "$N concurrent checkouts for one HitTrax slot -> exactly 1 winner" "winners=$WON"
[ "$RES" = "1" ] && ok 1 "exactly one blocking reservation exists on the HitTrax unit" \
                 || ok 0 "exactly one blocking reservation exists on the HitTrax unit" "reservations=$RES"

# -----------------------------------------------------------------------------
# Race 2: N registrations for the FINAL seat in a program.
# -----------------------------------------------------------------------------
psql -q >/dev/null <<SQL
delete from race_log;
delete from atd.registrations where program_id in (select id from atd.programs where slug='race-camp');
delete from atd.programs where slug='race-camp';
insert into atd.programs (location_id, service_id, slug, name, starts_on, ends_on,
                          capacity, price_cents, status, min_age, max_age)
values ('00000000-0000-4000-8000-0000000010c1',
        '11000000-0000-4000-8000-000000000020','race-camp','Race Camp',
        current_date + 40, current_date + 40, 1, 5000, 'published', 5, 18);
SQL
PROG=$(psql -tAc "select id from atd.programs where slug='race-camp'")

# One distinct child per worker, so the unique-seat index is not what saves us.
for i in $(seq 1 "$N"); do
  psql -tAc "insert into atd.participants(household_id,first_name,last_name,date_of_birth)
             values('$HH','Racer$i','Kid', current_date - interval '11 years') returning id" \
    | head -1 >/tmp/race_p_$i
done

for i in $(seq 1 "$N"); do
  P=$(cat /tmp/race_p_$i)
  psql -q -v ON_ERROR_STOP=0 >/dev/null 2>&1 <<SQL &
begin;
select pg_advisory_xact_lock_shared(515151);
do \$\$
declare r record;
begin
  select * into r from atd.register_participant('$PROG'::uuid, '$P'::uuid, '$HH'::uuid, 'full_series', null, false);
  insert into race_log(worker, outcome, detail) values ($i, r.status::text, null);
exception when others then
  insert into race_log(worker, outcome, detail) values ($i, 'error', sqlstate);
end \$\$;
commit;
SQL
done
wait

REG=$(psql -tAc "select count(*) from race_log where outcome='registered'")
ENR=$(psql -tAc "select enrolled_count from atd.programs where id='$PROG'")
[ "$REG" = "1" ] && ok 1 "$N concurrent registrations for the final seat -> exactly 1 registered" \
                 || ok 0 "$N concurrent registrations for the final seat -> exactly 1 registered" "registered=$REG"
[ "$ENR" = "1" ] && ok 1 "program enrolled_count never exceeds capacity" \
                 || ok 0 "program enrolled_count never exceeds capacity" "enrolled=$ENR"

# -----------------------------------------------------------------------------
# Race 3: the same hold confirmed concurrently (double-clicked Pay across tabs).
# -----------------------------------------------------------------------------
SLOT2=$(psql -tAc "select (((now() at time zone 'America/New_York')::date + 46 + interval '11 hours') at time zone 'America/New_York')")
HOLD=$(psql -tAc "select hold_id from atd.create_hold('11000000-0000-4000-8000-000000000010','$SLOT2'::timestamptz,'$SLOT2'::timestamptz + interval '1 hour','dbl','$HH'::uuid,'{}'::jsonb,15)")
psql -q >/dev/null <<SQL
delete from race_log;
SQL
for i in 1 2 3 4 5 6; do
  psql -q -v ON_ERROR_STOP=0 >/dev/null 2>&1 <<SQL &
begin;
select pg_advisory_xact_lock_shared(616161);
do \$\$
declare b uuid;
begin
  b := atd.confirm_hold('$HOLD'::uuid, '$HH'::uuid);
  insert into race_log(worker, outcome, detail) values ($i,'ok', b::text);
exception when others then
  insert into race_log(worker, outcome, detail) values ($i,'error', sqlstate);
end \$\$;
commit;
SQL
done
wait
DISTINCT=$(psql -tAc "select count(distinct detail) from race_log where outcome='ok'")
BOOKINGS=$(psql -tAc "select count(*) from atd.bookings where starts_at='$SLOT2'::timestamptz")
[ "$DISTINCT" = "1" ] && ok 1 "concurrent confirms of one hold produce a single booking id" \
                      || ok 0 "concurrent confirms of one hold produce a single booking id" "distinct=$DISTINCT"
[ "$BOOKINGS" = "1" ] && ok 1 "only one booking row exists for the double-clicked checkout" \
                      || ok 0 "only one booking row exists for the double-clicked checkout" "bookings=$BOOKINGS"

echo
echo "concurrency: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
