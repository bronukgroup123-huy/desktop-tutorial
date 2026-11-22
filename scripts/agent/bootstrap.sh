#!/usr/bin/env bash
# Інструменти для автономного агента в новому хмарному контейнері (docs/agent/AUTONOMY.md):
# Flutter 3.47.9 (як у CI), Deno 2.5.x, PostgreSQL 16 + PostGIS + pg_cron для scripts/dev/local-db.
# Ідемпотентно: що вже є — пропускає. Друкує рядок `export PATH=...` для поточної сесії.
#
#   source <(scripts/agent/bootstrap.sh --env)   # лише PATH, якщо все встановлено
#   scripts/agent/bootstrap.sh                   # встановити відсутнє
set -euo pipefail
TOOLS=${AGENT_TOOLS:-$HOME/.agent-tools}
FLUTTER_VERSION=3.47.9
DENO_VERSION=2.5.6
mkdir -p "$TOOLS"
env_line="export PATH=$TOOLS/flutter/bin:$TOOLS/deno:\$PATH"
if [ "${1:-}" = "--env" ]; then echo "$env_line"; exit 0; fi

if [ ! -x "$TOOLS/deno/deno" ]; then
  echo "▶ Deno $DENO_VERSION"
  mkdir -p "$TOOLS/deno"
  curl -fsSL -o /tmp/deno.zip "https://github.com/denoland/deno/releases/download/v$DENO_VERSION/deno-x86_64-unknown-linux-gnu.zip"
  python3 -c "import zipfile;zipfile.ZipFile('/tmp/deno.zip').extractall('$TOOLS/deno')"
  chmod +x "$TOOLS/deno/deno"
fi

if [ ! -x "$TOOLS/flutter/bin/flutter" ]; then
  echo "▶ Flutter $FLUTTER_VERSION"
  git clone -q --depth 1 -b "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$TOOLS/flutter"
  "$TOOLS/flutter/bin/flutter" --version >/dev/null
fi

if ! dpkg -s postgresql-16-postgis-3 >/dev/null 2>&1 || ! dpkg -s postgresql-16-cron >/dev/null 2>&1; then
  echo "▶ PostGIS + pg_cron"
  apt-get install -y -q postgresql-16-postgis-3 postgresql-16-cron >/dev/null
fi
echo "$env_line"
