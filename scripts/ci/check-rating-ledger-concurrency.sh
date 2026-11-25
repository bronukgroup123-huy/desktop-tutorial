#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <postgres-connection-string>" >&2
  exit 2
fi

database_url=$1
test_user='bbbb0001-0000-4000-8000-00000000f001'
tmp_dir=$(mktemp -d)
first_pid=''
second_pid=''

cleanup() {
  if [ -n "$first_pid" ]; then kill "$first_pid" 2>/dev/null || true; fi
  if [ -n "$second_pid" ]; then kill "$second_pid" 2>/dev/null || true; fi
  psql "$database_url" -v ON_ERROR_STOP=1 -q \
    -c "DELETE FROM auth.users WHERE id = '$test_user';" >/dev/null 2>&1 || true
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

psql "$database_url" -v ON_ERROR_STOP=1 -q <<SQL
DELETE FROM auth.users WHERE id = '$test_user';
INSERT INTO auth.users (id, email)
VALUES ('$test_user', 'rating-concurrency@test.local');
SQL

psql "$database_url" -v ON_ERROR_STOP=1 -q >"$tmp_dir/first.log" 2>&1 <<SQL &
BEGIN;
SET LOCAL application_name = 'rating_concurrency_first';
INSERT INTO public.rating_events (user_id, delta, reason)
VALUES ('$test_user', 1, 'pick_exif');
SELECT pg_sleep(3);
COMMIT;
SQL
first_pid=$!

first_ready=false
for _ in $(seq 1 50); do
  if [ "$(psql "$database_url" -v ON_ERROR_STOP=1 -Atq -c \
    "SELECT count(*) FROM pg_stat_activity WHERE application_name = 'rating_concurrency_first' AND wait_event = 'PgSleep';")" = '1' ]; then
    first_ready=true
    break
  fi
  sleep 0.1
done
if [ "$first_ready" != true ]; then
  echo 'first rating transaction did not reach the synchronization point' >&2
  cat "$tmp_dir/first.log" >&2
  exit 1
fi

psql "$database_url" -v ON_ERROR_STOP=1 -q >"$tmp_dir/second.log" 2>&1 <<SQL &
BEGIN;
INSERT INTO public.rating_events (user_id, delta, reason)
VALUES ('$test_user', 1, 'pick_exif');
COMMIT;
SQL
second_pid=$!

wait "$first_pid"
first_pid=''
wait "$second_pid"
second_pid=''

result=$(psql "$database_url" -v ON_ERROR_STOP=1 -Atq -c "
  SELECT u.rating::text || ':' || coalesce(sum(e.delta), 0)::text || ':' || count(e.id)::text
  FROM public.users u
  LEFT JOIN public.rating_events e ON e.user_id = u.id
  WHERE u.id = '$test_user'
  GROUP BY u.rating;
")

if [ "$result" != '2:2:2' ]; then
  echo "rating ledger lost a concurrent update: rating:event_sum:event_count=$result, expected 2:2:2" >&2
  exit 1
fi

echo 'rating ledger concurrency: 2 events, rating 2'
