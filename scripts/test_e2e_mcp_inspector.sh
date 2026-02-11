#!/bin/bash

trap 'rc=$?; if [[ $rc -ne 124 ]]; then echo "❌ Error on line $LINENO (rc=$rc)" >&2; fi' ERR
set -Eeuo pipefail

export PYTHONUNBUFFERED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib_supergateway.sh"

load_env

ENV_SHELL_EXEC="${SHELL_EXEC:-default}"
ENV_SHELL_EXEC_BASENAME="$(basename "$ENV_SHELL_EXEC")"

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
  echo 

  assert_contains() {
    local output="$1"
    local needle="$2"
    local context="$3"
    echo "[test] ${context} ..."
    # debug output for "echo $SHELL"
    if [[ "${context}" == "tools/call run_command echo" ]]; then
      echo "$output"
    fi
    if ! echo "$output" | grep -q "$needle"; then
      echo "❌ Missing expected output for ${context}" >&2
      echo "Expected: ${needle}" >&2
      echo "Actual output:" >&2
      echo "$output" >&2
      exit 1
    fi
    echo
  }

  local tools_output
  tools_output="$(run_inspector "$url" --method tools/list)"
  assert_contains "$tools_output" "run_command" "tools/list"
  assert_contains "$tools_output" "show_security_rules" "tools/list"

  local security_output
  security_output="$(run_inspector "$url" --method tools/call --tool-name show_security_rules)"
  assert_contains "$security_output" "Security Configuration" "tools/call show_security_rules"

  local echo_output
  echo_output="$(run_inspector "$url" --method tools/call --tool-name run_command --tool-arg "command=echo shell_exec=$ENV_SHELL_EXEC shell_args=${SHELL_EXEC_ARGS:-} && echo exe=\\$(readlink -f /proc/$$/exe)")"
  assert_contains "$echo_output" "Command completed with return code: 0" "tools/call run_command echo"
  assert_contains "$echo_output" "$ENV_SHELL_EXEC_BASENAME" "tools/call run_command echo"

  local ls_output
  ls_output="$(run_inspector "$url" --method tools/call --tool-name run_command --tool-arg "command=ls -s")"
  assert_contains "$ls_output" "Command completed with return code: 0" "tools/call run_command ls"
}

CHECK_URL="$SUPERGATEWAY_URL" check_supergateway_url "$SUPERGATEWAY_URL"

echo "Running MCP Inspector e2e against Supergateway: ${SUPERGATEWAY_URL}"
run_suite "$SUPERGATEWAY_URL" "Supergateway"
