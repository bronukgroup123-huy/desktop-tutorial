#!/usr/bin/env bash
# Застосувати всі міграції на чистій локальній БД (PostgreSQL 16 + PostGIS + pg_cron, без Docker)
# і прогнати SQL-тести supabase/tests/*.sql — як job «migrations» у CI, але локально.
#
#   sudo apt-get install -y postgresql-16-postgis-3 postgresql-16-cron   # раз
#   scripts/dev/local-db/run.sh            # міграції + усі SQL-тести
#   scripts/dev/local-db/run.sh --no-tests # лише міграції (БД лишається на порту 5498)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HERE="$ROOT/scripts/dev/local-db"
PGBIN=/usr/lib/postgresql/16/bin
DATA=${LOCAL_DB_DIR:-/tmp/mr-local-db}
PORT=${LOCAL_DB_PORT:-5498}
EXT=/usr/share/postgresql/16/extension
cp "$HERE"/ext/* "$EXT"/
run_pg() { if [ "$(id -u)" = 0 ]; then su postgres -c "$*"; else bash -c "$*"; fi; }
if [ -d "$DATA" ]; then run_pg "$PGBIN/pg_ctl -D $DATA -m immediate stop" >/dev/null 2>&1 || true; rm -rf "$DATA"; fi
mkdir -p "$DATA"; [ "$(id -u)" = 0 ] && chown postgres "$DATA"
run_pg "$PGBIN/initdb -D $DATA -U postgres -A trust >/dev/null"
cat >> "$DATA/postgresql.conf" <<CONF
shared_preload_libraries = 'pg_cron'
cron.database_name = 'postgres'
port = $PORT
unix_socket_directories = '/tmp'
CONF
run_pg "$PGBIN/pg_ctl -D $DATA -l $DATA/log -w start >/dev/null"
PSQL="psql -h /tmp -p $PORT -U postgres -d postgres -v ON_ERROR_STOP=1 -q"
$PSQL -f "$HERE/bootstrap.sql" >/dev/null
# кожна міграція — однією транзакцією, як у supabase db push
for f in "$ROOT"/supabase/migrations/*.sql; do
  if ! out=$($PSQL -1 -f "$f" 2>&1); then echo "✗ $(basename "$f")"; echo "$out" | grep -E "ERROR|LINE" | head -5; exit 1; fi
done
echo "✓ міграцій застосовано: $(ls "$ROOT"/supabase/migrations/*.sql | wc -l)"
[ "${1:-}" = "--no-tests" ] && exit 0
fail=0
for f in "$ROOT"/supabase/tests/*.sql; do
  if out=$($PSQL -f "$f" 2>&1); then echo "✓ $(basename "$f")"; else echo "✗ $(basename "$f")"; echo "$out" | grep -E "ERROR|NOTICE.*FAIL" | head -5; fail=1; fi
done
exit $fail
