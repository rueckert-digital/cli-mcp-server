#!/bin/bash

trap 'rc=$?; if [[ $rc -ne 124 ]]; then echo "❌ Error on line $LINENO (rc=$rc)" >&2; fi' ERR
set -Eeuo pipefail

export PYTHONUNBUFFERED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib_supergateway.sh"

load_env

VENV_DIR="${VENV_DIR:-.venv}"
CLI_MCP_BIN="${CLI_MCP_BIN:-${VENV_DIR}/bin/cli-mcp-server}"

require_cli_bin "$CLI_MCP_BIN"

PORT="${PORT:-8084}"
SUPERGATEWAY_URL="${SUPERGATEWAY_URL:-http://127.0.0.1:${PORT}/mcp}"

run_inspector() {
  local url="$1"
  shift
  npx -y @modelcontextprotocol/inspector \
    --cli \
    --transport http \
    --header "accept: application/json, text/event-stream" \
    -- "$url" "$@"
}

run_suite() {
  local url="$1"
  local label="$2"
  echo "==> Inspector e2e: ${label}"

  local tools_output
  tools_output="$(run_inspector "$url" --method tools/list)"
  echo "$tools_output" | grep -q "run_command"
  echo "$tools_output" | grep -q "show_security_rules"

  local security_output
  security_output="$(run_inspector "$url" --method tools/call --tool-name show_security_rules)"
  echo "$security_output" | grep -q "Security Configuration"

  local echo_output
  echo_output="$(run_inspector "$url" --method tools/call --tool-name run_command --tool-arg "command=echo \\$SHELL")"
  echo "$echo_output" | grep -q "Command completed with return code: 0"

  local ls_output
  ls_output="$(run_inspector "$url" --method tools/call --tool-name run_command --tool-arg "command=ls -s")"
  echo "$ls_output" | grep -q "Command completed with return code: 0"
}

CHECK_URL="$SUPERGATEWAY_URL" check_supergateway_url "$SUPERGATEWAY_URL"

echo "Running MCP Inspector e2e against Supergateway: ${SUPERGATEWAY_URL}"
run_suite "$SUPERGATEWAY_URL" "Supergateway"
