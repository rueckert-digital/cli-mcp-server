#!/bin/bash

trap 'rc=$?; if [[ $rc -ne 124 ]]; then echo "❌ Error on line $LINENO (rc=$rc)" >&2; fi' ERR
set -Ee

export PYTHONUNBUFFERED=1

if [[ -f ".env" ]]; then
  echo "Sourcing .env ..."
  set -a
  source .env
  set +a
fi

# prerequisites
echo "Prerequisites ..."
python -m venv .venv
source .venv/bin/activate
python -m pip install --quiet -U pip
python -m pip install --quiet .

# unittest
echo "Run unit tests ..."
python -m unittest discover --quiet -v

# start
echo "Run e2e tests ..."

set +e
#timeout 5 cli-mcp-server -k
#timeout 5 bash -c "printf '%s\n' '$req' | cli-mcp-server -k" >out.jsonl 2>err.log
#rc=$?
init='{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"bash-test","version":"0.0"}}}'
inited='{"jsonrpc":"2.0","method":"initialized","params":{}}'
call='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"show_security_rules","arguments":{}}}'

timeout 5 bash -c "printf '%s\n%s\n%s\n' '$init' '$inited' '$call' | cli-mcp-server" \
  > out.jsonl 2> err.log

rc=$?
set -e

# Countercheck
line="$(grep -m1 '"id":1' out.jsonl || true)"
echo "$line" | jq .
echo "$line" | jq -e '.jsonrpc=="2.0" and .id==1 and (has("result") or has("error"))' >/dev/null
echo "assert_rc=$?"

# rc=124 is expected: GNU timeout uses 124 when the command times out.
echo "rc=$rc"

