#!/usr/bin/env bash
set -Eeuo pipefail

load_env() {
  if [[ -f ".env" ]]; then
    echo "Sourcing .env ..."
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
  fi
}

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: ${name} is required." >&2
    exit 1
  fi
}

check_supergateway_url() {
  local url="$1"
  python - <<'PY'
import socket
import urllib.parse
import os

url = os.environ["CHECK_URL"]
parsed = urllib.parse.urlparse(url)
if not parsed.hostname or not parsed.port:
    raise SystemExit(f"Invalid SUPERGATEWAY_URL: {url}")

try:
    with socket.create_connection((parsed.hostname, parsed.port), timeout=2):
        print(f"Supergateway reachable at {parsed.hostname}:{parsed.port}")
except OSError as exc:
    raise SystemExit(f"Supergateway not reachable at {parsed.hostname}:{parsed.port}: {exc}")
PY
}

require_cli_bin() {
  local cli_bin="$1"
  if [[ ! -x "$cli_bin" ]]; then
    echo "ERROR: CLI binary not found or not executable: $cli_bin" >&2
    echo "Run scripts/build_run.sh or scripts/build_test.sh first." >&2
    exit 1
  fi
}
