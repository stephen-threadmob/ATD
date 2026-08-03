#!/usr/bin/env bash
# Rebuild the database, then run every SQL test file and report the tally.
set -euo pipefail
cd "$(dirname "$0")/.."
export PGHOST="${PGHOST:-localhost}" PGUSER="${PGUSER:-postgres}" PGDATABASE="${PGDATABASE:-atd}"

./scripts/db-reset.sh >/dev/null
psql -q -f tests/sql/00_harness.sql >/dev/null

for f in tests/sql/0[1-9]*.sql; do
  psql -v ON_ERROR_STOP=0 -f "$f" 2>&1 | grep -E "^psql.*ERROR" && echo "  ^ in $f" || true
done

psql -tAc "select case when passed then 'ok   ' else 'FAIL ' end || name ||
             coalesce('  [' || detail || ']','') from t.results order by id"
FAILED=$(psql -tAc "select count(*) from t.results where not passed")
TOTAL=$(psql -tAc "select count(*) from t.results")
echo
echo "sql tests: $((TOTAL-FAILED))/$TOTAL passed"
[ "$FAILED" = "0" ]
