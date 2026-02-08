#!/bin/bash

trap 'rc=$?; if [[ $rc -ne 124 ]]; then echo "❌ Error on line $LINENO (rc=$rc)" >&2; fi' ERR
set -Eeuo pipefail

export PYTHONUNBUFFERED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib_supergateway.sh"

load_env

SUPERGATEWAY_URL="${SUPERGATEWAY_URL:-http://127.0.0.1:8084/mcp}"

CHECK_URL="$SUPERGATEWAY_URL" check_supergateway_url "$SUPERGATEWAY_URL"

echo "Run e2e tests against Supergateway ..."
python -m unittest tests.test_e2e_supergateway -v
