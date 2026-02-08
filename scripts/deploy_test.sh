#!/bin/bash

trap 'rc=$?; if [[ $rc -ne 124 ]]; then echo "❌ Error on line $LINENO (rc=$rc)" >&2; fi' ERR
set -Eeuo pipefail

export PYTHONUNBUFFERED=1

if [[ -f ".env" ]]; then
  echo "Sourcing .env ..."
  set -a
  source .env
  set +a
fi

SUPERGATEWAY_URL="${SUPERGATEWAY_URL:-http://127.0.0.1:8084/mcp}"

python - <<'PY'
import socket
import urllib.parse
import os

url = os.environ["SUPERGATEWAY_URL"]
parsed = urllib.parse.urlparse(url)
if not parsed.hostname or not parsed.port:
    raise SystemExit(f"Invalid SUPERGATEWAY_URL: {url}")

try:
    with socket.create_connection((parsed.hostname, parsed.port), timeout=2):
        print(f"Supergateway reachable at {parsed.hostname}:{parsed.port}")
except OSError as exc:
    raise SystemExit(f"Supergateway not reachable at {parsed.hostname}:{parsed.port}: {exc}")
PY

echo "Preparing virtual environment ..."
python -m venv .venv
source .venv/bin/activate
python -m pip install --quiet -U pip
python -m pip install --quiet .

echo "Run e2e tests ..."
python -m unittest tests.test_e2e_supergateway -v
