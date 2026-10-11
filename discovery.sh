#!/usr/bin/env bash
# === DISCOVERY SCRIPT — Грибний Радар ===
set -u

export SUPABASE_URL="${SUPABASE_URL:-https://wrukmuxdbkbmkygfasai.supabase.co}"
export SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY is required}"
export SUPABASE_SERVICE_KEY="${SUPABASE_SERVICE_KEY:?SUPABASE_SERVICE_KEY is required}"
export PROJECT_REF="wrukmuxdbkbmkygfasai"

REPORT="discovery-report-$(date +%Y%m%d-%H%M).md"
echo "# Discovery Report — $(date)" > "$REPORT"

# --- 11.1: Edge Functions ---
echo "## 11.1 Edge Functions" | tee -a "$REPORT"
FUNCTIONS=(
  guardian-session-create guardian-session-get guardian-session-track guardian-active
  guardian-ping guardian-extend guardian-exiting guardian-close guardian-cancel-close
  guardian-recover guardian-revoke guardian-tick guardian-notify guardian-retry
  guardian-register-device guardian-register-guardian-device guardian-webhook-sms
  guardian-sos guardian-sos-cancel guardian-session-gpx guardian-owner-gpx
  guardian-rescue-request guardian-rescue-get
)
for fn in "${FUNCTIONS[@]}"; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X OPTIONS \
    "$SUPABASE_URL/functions/v1/$fn" -H "apikey: $SUPABASE_ANON_KEY")
  echo "- $fn: $STATUS" | tee -a "$REPORT"
done

# --- 11.3: Migrations & tables via SQL RPC ---
echo "" | tee -a "$REPORT"
echo "## 11.3 Migrations & Tables" | tee -a "$REPORT"

cat <<'SQL' | tee -a "$REPORT"

### SQL для Dashboard → SQL Editor (виконати вручну):

-- 1. Extensions
SELECT extname, extversion FROM pg_extension
WHERE extname IN ('pg_cron','pg_net','postgis');

-- 2. Cron jobs
SELECT jobid, jobname, schedule, active FROM cron.job;

-- 3. Останні виконання guardian-tick
SELECT jobid, start_time, end_time, status, return_message
FROM cron.job_run_details
WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname='guardian-tick-every-minute')
ORDER BY start_time DESC LIMIT 20;

-- 4. Міграції
SELECT version, name, inserted_at
FROM supabase_migrations.schema_migrations
ORDER BY version;

-- 5. Таблиці Guardian
SELECT tablename FROM pg_tables
WHERE schemaname='public' AND tablename IN (
 'guardian_sessions','guardians','guardian_track','guardian_alerts',
 'guardian_notifications','guardian_rescue_requests','guardian_push_tokens',
 'user_push_tokens','guardian_tick_log','forest_polygons','users','regions'
) ORDER BY tablename;

-- 6. Фундаментальні таблиці
SELECT
  to_regclass('public.users') AS users_exists,
  to_regclass('public.regions') AS regions_exists,
  to_regclass('public.guardian_sessions') AS sessions_exists;

-- 7. RLS
SELECT relname, relrowsecurity FROM pg_class
WHERE relname IN (
 'guardian_sessions','guardians','guardian_track','guardian_alerts',
 'guardian_notifications','guardian_rescue_requests'
) AND relnamespace='public'::regnamespace;

-- 8. Користувачі
SELECT COUNT(*) AS total FROM auth.users;
SELECT id, email, email_confirmed_at, created_at
FROM auth.users ORDER BY created_at DESC LIMIT 5;
SELECT COUNT(*) AS public_users FROM public.users;
SQL

# --- 11.4: Secrets ---
echo "" | tee -a "$REPORT"
echo "## 11.4 Secrets" | tee -a "$REPORT"
if command -v supabase >/dev/null 2>&1; then
  supabase secrets list --project-ref "$PROJECT_REF" 2>&1 | tee -a "$REPORT"
else
  echo "(supabase CLI не встановлено — перевірте вручну в Dashboard → Edge Functions → Secrets)" | tee -a "$REPORT"
fi

# --- 11.5: web-guardian ---
echo "" | tee -a "$REPORT"
echo "## 11.5 web-guardian" | tee -a "$REPORT"

echo "### Локальна структура:" | tee -a "$REPORT"
ls -la web-guardian/ 2>/dev/null | tee -a "$REPORT" || echo "❌ web-guardian НЕ існує" | tee -a "$REPORT"
ls -la web-guardian/src/app/ 2>/dev/null | tee -a "$REPORT" || echo "❌ src/app НЕ існує" | tee -a "$REPORT"

echo "### Root Vercel:" | tee -a "$REPORT"
curl -s -o /dev/null -w "HTTP / → %{http_code}\n" \
  https://desktop-tutorial-eta-tan.vercel.app/ | tee -a "$REPORT"
curl -s -o /dev/null -w "HTTP /s/test → %{http_code}\n" \
  https://desktop-tutorial-eta-tan.vercel.app/s/test | tee -a "$REPORT"
curl -s -o /dev/null -w "HTTP /manifest.json → %{http_code}\n" \
  https://desktop-tutorial-eta-tan.vercel.app/manifest.json | tee -a "$REPORT"

echo "### Root Directory (перевірити в Dashboard → Settings → General):" | tee -a "$REPORT"

# --- 11.6-11.7: Firebase / TurboSMS env ---
echo "" | tee -a "$REPORT"
echo "## 11.6-11.7 Firebase / TurboSMS env" | tee -a "$REPORT"
echo "FIREBASE_SERVICE_ACCOUNT_JSON: ${FIREBASE_SERVICE_ACCOUNT_JSON:+SET}${FIREBASE_SERVICE_ACCOUNT_JSON:-NOT SET}" | tee -a "$REPORT"
echo "NEXT_PUBLIC_FIREBASE_VAPID_KEY: ${NEXT_PUBLIC_FIREBASE_VAPID_KEY:+SET}${NEXT_PUBLIC_FIREBASE_VAPID_KEY:-NOT SET}" | tee -a "$REPORT"
echo "TURBOSMS_TOKEN: ${TURBOSMS_TOKEN:+SET}${TURBOSMS_TOKEN:-NOT SET}" | tee -a "$REPORT"

echo ""
echo "✅ Звіт збережено: $REPORT"
echo "📋 Скопіюйте вміст і надішліть мені."
