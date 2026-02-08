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
  local timeout="${SUPERGATEWAY_WAIT_SECONDS:-20}"
  python - <<'PY'
import socket
import urllib.parse
import os
import time

url = os.environ["CHECK_URL"]
timeout = int(os.environ.get("CHECK_TIMEOUT", "20"))
parsed = urllib.parse.urlparse(url)
if not parsed.hostname or not parsed.port:
    raise SystemExit(f"Invalid SUPERGATEWAY_URL: {url}")

deadline = time.time() + timeout
while time.time() < deadline:
    try:
        with socket.create_connection((parsed.hostname, parsed.port), timeout=2):
            print(f"Supergateway reachable at {parsed.hostname}:{parsed.port}")
            raise SystemExit(0)
    except OSError:
        time.sleep(1)

raise SystemExit(f"Supergateway not reachable at {parsed.hostname}:{parsed.port} after {timeout}s")
PY
}

require_cli_bin() {
  local cli_bin="$1"
  if [[ ! -x "$cli_bin" ]]; then
    echo "ERROR: CLI binary not found or not executable: $cli_bin" >&2
    echo "Run scripts/build_run.sh or scripts/test_unit_python.sh first." >&2
    exit 1
  fi
}
