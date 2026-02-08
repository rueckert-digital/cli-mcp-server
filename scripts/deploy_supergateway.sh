#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
BUILD_SCRIPT="${BUILD_SCRIPT:-${SCRIPT_DIR}/build_run.sh}"
VENV_DIR="${VENV_DIR:-${REPO_DIR}/.venv}"

PORT="${PORT:-8084}"
PATH_MCP="${PATH_MCP:-/mcp}"

ENV_FILE="${ENV_FILE:-.env}"
PIDFILE="${PIDFILE:-/var/run/supergateway-cli-mcp.pid}"
LOGFILE="${LOGFILE:-/var/log/supergateway-cli-mcp.log}"
CLI_MCP_BIN="${CLI_MCP_BIN:-${VENV_DIR}/bin/cli-mcp-server}"

install_requirements() {
  if command -v lsof >/dev/null 2>&1 || command -v ss >/dev/null 2>&1; then
    return 0
  fi

  if command -v apt-get >/dev/null 2>&1; then
    echo "Installing requirements (lsof/iproute2) via apt-get..."
    sudo apt-get update -y
    sudo apt-get install -y lsof iproute2
  else
    echo "WARNING: apt-get not available; install lsof or ss manually." >&2
  fi
}

install_requirements

resolve_allowed_dir() {
  local candidate

  if [[ -n "${ALLOWED_DIR:-}" ]] && [[ -d "$ALLOWED_DIR" ]]; then
    return 0
  fi

  for candidate in "/DATA/repos/codex-cli-control-center" "/workspace/cli-mcp-server"; do
    if [[ -d "$candidate" ]]; then
      export ALLOWED_DIR="$candidate"
      return 0
    fi
  done

  return 1
}

# Prefer lsof (macOS/Linux), fallback to ss (Linux)
pids_on_port() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -t -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | sort -u || true
  elif command -v ss >/dev/null 2>&1; then
    # Extract pid=1234 from ss output
    ss -ltnp 2>/dev/null | awk -v p=":$PORT" '
      $4 ~ p && $0 ~ /pid=/ {
        match($0, /pid=([0-9]+)/, a); if (a[1]!="") print a[1]
      }' | sort -u || true
  else
    echo "ERROR: need lsof or ss to detect listeners on port $PORT" >&2
    exit 2
  fi
}

show_listeners() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true
  elif command -v ss >/dev/null 2>&1; then
    ss -ltnp | awk -v p=":$PORT" '$4 ~ p {print}' || true
  fi
}

kill_port() {
  local pids
  pids="$(pids_on_port | tr '\n' ' ' | xargs || true)"
  if [[ -z "${pids:-}" ]]; then
    echo "No process is listening on port $PORT."
    return 0
  fi

  echo "Killing listeners on port $PORT: $pids"
  # graceful
  kill -TERM $pids 2>/dev/null || true
  sleep 1

  # if still alive, force
  local still
  still="$(pids_on_port | tr '\n' ' ' | xargs || true)"
  if [[ -n "${still:-}" ]]; then
    echo "Force-killing remaining: $still"
    kill -KILL $still 2>/dev/null || true
  fi
}

is_running() {
  if [[ -f "$PIDFILE" ]]; then
    local pid
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

start_bg() {
  if is_running; then
    echo "Already running (pid $(cat "$PIDFILE"))."
    exit 0
  fi

  if [[ "${SKIP_BUILD:-false}" != "true" ]]; then
    if [[ ! -x "$BUILD_SCRIPT" ]]; then
      echo "ERROR: build script not found or not executable: $BUILD_SCRIPT" >&2
      exit 1
    fi
    echo "Preparing build via $BUILD_SCRIPT"
    VENV_DIR="$VENV_DIR" REPO_DIR="$REPO_DIR" "$BUILD_SCRIPT"
  fi

  if [[ ! -x "$CLI_MCP_BIN" ]]; then
    echo "ERROR: CLI not found at $CLI_MCP_BIN (set CLI_MCP_BIN if needed)" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$PIDFILE")" "$(dirname "$LOGFILE")"

  # Free the port if something else is using it
  if [[ -n "$(pids_on_port)" ]]; then
    echo "Port $PORT is busy. Current listeners:"
    show_listeners
    kill_port
  fi

  if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: ENV_FILE not found: $ENV_FILE" >&2
    exit 1
  fi

  set -a
  source "$ENV_FILE"
  set +a

  if ! resolve_allowed_dir; then
    echo "ERROR: ALLOWED_DIR not set to an existing directory." >&2
    exit 1
  fi

  # Detach cleanly from terminal, survive logout, write pidfile
  nohup bash -lc "
    set -euo pipefail
    set -a
    source '$ENV_FILE'
    ALLOWED_DIR='${ALLOWED_DIR}'
    set +a
    exec npx -y supergateway \
      --stdio \"$CLI_MCP_BIN\" \
      --outputTransport streamableHttp \
      --stateful \
      --port '$PORT' \
      --streamableHttpPath '$PATH_MCP'
  " >>"$LOGFILE" 2>&1 &

  echo $! >"$PIDFILE"
  disown || true

  echo "Started. pid=$(cat "$PIDFILE"), url=http://127.0.0.1:${PORT}${PATH_MCP}"
  echo "Logs: $LOGFILE"
}

stop() {
  if is_running; then
    local pid
    pid="$(cat "$PIDFILE")"
    echo "Stopping pid=$pid"
    kill -TERM "$pid" 2>/dev/null || true
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
      echo "Force-killing pid=$pid"
      kill -KILL "$pid" 2>/dev/null || true
    fi
    rm -f "$PIDFILE"
  fi

  # also ensure port is clean
  kill_port
  echo "Stopped."
}

status() {
  echo "=== Status (port $PORT) ==="
  if is_running; then
    echo "PIDFILE: $PIDFILE (pid $(cat "$PIDFILE"))"
  else
    echo "PIDFILE: not running"
  fi
  echo
  echo "Listeners:"
  show_listeners
  echo
  echo "Tail logs:"
  tail -n 30 "$LOGFILE" 2>/dev/null || true
}

case "${1:-}" in
  start)   start_bg ;;
  stop)    stop ;;
  restart) stop; start_bg ;;
  status)  status ;;
  kill-port) kill_port ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|kill-port}" >&2
    exit 2
    ;;
esac
