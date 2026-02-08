#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-8084}"
PATH_MCP="${PATH_MCP:-/mcp}"

ENV_FILE="${ENV_FILE:-.env}"
PIDFILE="${PIDFILE:-/var/run/supergateway-cli-mcp.pid}"
LOGFILE="${LOGFILE:-/var/log/supergateway-cli-mcp.log}"

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

  # Detach cleanly from terminal, survive logout, write pidfile
  nohup bash -lc "
    set -euo pipefail
    set -a
    source '$ENV_FILE'
    set +a
    exec npx -y supergateway \
      --stdio \"uvx cli-mcp-server\" \
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

