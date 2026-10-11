#!/usr/bin/env bash
set -euo pipefail
PROJECT_REF="wrukmuxdbkbmkygfasai"
FUNCTIONS_DIR="supabase/functions"

mapfile -t ALL_FUNCS < <(find "$FUNCTIONS_DIR" -mindepth 1 -maxdepth 1 -type d \
  ! -name "_shared" ! -name "guardian-notify-test" -exec basename {} \; | sort)

echo "=== ${#ALL_FUNCS[@]} ФУНКЦІЙ (guardian-notify-test виключено) ==="
printf '  - %s\n' "${ALL_FUNCS[@]}"

FAILED=()
for fn in "${ALL_FUNCS[@]}"; do
  echo ""
  echo "▶ $fn"
  if supabase functions deploy "$fn" --project-ref "$PROJECT_REF" --no-verify-jwt; then
    echo "  ✅ OK"
  else
    echo "  ❌ FAILED"
    FAILED+=("$fn")
  fi
done

echo ""
echo "=== ПІДСУМОК ==="
echo "OK: $(( ${#ALL_FUNCS[@]} - ${#FAILED[@]} )) / ${#ALL_FUNCS[@]}"
if [ ${#FAILED[@]} -gt 0 ]; then
  printf '❌ FAILED: %s\n' "${FAILED[@]}"
  exit 1
fi
