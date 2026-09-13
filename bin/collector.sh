#!/usr/bin/env bash
# Fetches Indian mainboard IPO data (ipowatch.in) and prints one JSON object
# to stdout for the ipo-tracker bar widget. No API keys, no AI — plain HTTP.
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# Prefer the system python3; fall back to the session interpreter if present.
PY=""
for candidate in python3 "${PYTHON:-}"; do
  if command -v "$candidate" >/dev/null 2>&1; then PY="$candidate"; break; fi
done
if [[ -z "$PY" ]]; then
  printf '{"status":"ok","error":"python3 not found","updatedAt":"now","ipos":[]}\n'
  exit 0
fi

exec "$PY" "$PLUGIN_DIR/collector.py"