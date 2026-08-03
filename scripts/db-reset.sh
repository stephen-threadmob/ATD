#!/usr/bin/env bash
# Rebuild the database from migrations + seed. Used by tests and local dev.
set -euo pipefail
cd "$(dirname "$0")/.."

PGHOST="${PGHOST:-localhost}"
PGUSER="${PGUSER:-postgres}"
PGDATABASE="${PGDATABASE:-atd}"
export PGHOST PGUSER PGDATABASE

psql -q -c "drop schema if exists atd cascade; drop schema if exists audit cascade; drop schema if exists t cascade;" >/dev/null

for f in supabase/migrations/*.sql; do
  psql -v ON_ERROR_STOP=1 -q -f "$f" >/dev/null
done

if [ "${SKIP_SEED:-0}" != "1" ]; then
  for f in supabase/seed/*.sql; do
    psql -v ON_ERROR_STOP=1 -q -f "$f" >/dev/null
  done
fi

echo "database rebuilt: $(psql -tAc "select count(*) from information_schema.tables where table_schema in ('atd','audit')") tables"
