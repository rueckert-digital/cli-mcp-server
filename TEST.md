# Testing Guide

This repository uses **three layers of tests**:

1. **Python unit tests** (fast, isolated).
2. **Python e2e tests** against a running Supergateway instance.
3. **MCP Inspector e2e tests** against a running Supergateway instance.

---

## Quick Start (HITL)

> All commands assume you are in the repo root.

### 1) Build + Unit Tests

```bash
./scripts/test_unit_python.sh
```

### 2) Start Supergateway

```bash
./scripts/deploy_supergateway.sh start
```

### 3) Python e2e

```bash
./scripts/test_e2e_python.sh
```

### 4) MCP Inspector e2e

```bash
./scripts/test_e2e_mcp_inspector.sh
```

### 5) Stop Supergateway

```bash
./scripts/deploy_supergateway.sh stop
```

---

## Developer Notes

### Environment (.env)

Use `.env` to configure the Supergateway port and security policy:

```
PORT=8084
ALLOWED_DIR=/path/to/allowed/workdir
ALLOWED_COMMANDS=all
ALLOWED_FLAGS=all
ALLOW_SHELL_OPERATORS=true
```

> `PORT` is consumed by `deploy_supergateway.sh`, the e2e scripts, and the e2e test.

### Python Tests

* **Unit tests:** `tests/test_cli_mcp_server.py`
* **E2E tests:** `tests/test_e2e_supergateway.py` (requires Supergateway running)

If you add new tools or change tool outputs, update the e2e assertions in
`tests/test_e2e_supergateway.py` to validate the new behavior.

### Shell / MCP Inspector Tests

`scripts/test_e2e_mcp_inspector.sh` drives the MCP Inspector CLI to hit the
Supergateway streamable HTTP endpoint and validate:

* `tools/list`
* `tools/call show_security_rules`
* `tools/call run_command` (echo + ls)

---

## Dependency Graph

```
            ┌──────────────────────────────┐
            │      scripts/build_run.sh     │
            └──────────────┬───────────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │ scripts/test_unit_...  │
              └────────────────────────┘
                           │
                           ▼
     ┌───────────────────────────────────────────┐
     │ scripts/deploy_supergateway.sh (start)    │
     └───────────────────────────┬───────────────┘
                                 │
                                 ▼
           ┌────────────────────────────────────┐
           │ scripts/test_e2e_python.sh          │
           └────────────────────────────────────┘
                                 │
                                 ▼
           ┌────────────────────────────────────┐
           │ scripts/test_e2e_mcp_inspector.sh   │
           └────────────────────────────────────┘
                                 │
                                 ▼
     ┌───────────────────────────────────────────┐
     │ scripts/deploy_supergateway.sh (stop)     │
     └───────────────────────────────────────────┘
```

---

## Extending Tests

### Add a Python unit test

1. Add a new test method to `tests/test_cli_mcp_server.py`.
2. Ensure it is deterministic and runs in isolation.

### Add a Python e2e check

1. Update `tests/test_e2e_supergateway.py`.
2. Keep the test step output consistent with the existing `[e2e][step]` log format.

### Add a MCP Inspector e2e check

1. Extend `scripts/test_e2e_mcp_inspector.sh`.
2. Reuse `run_suite` and add a new Inspector CLI call with a `grep -q` assertion.
