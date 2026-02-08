# CLI MCP Server

## Fork note and shell selection

This repository is forked from https://github.com/MladenSU/cli-mcp-server. It adds support for choosing a specific shell executable via the `SHELL_EXEC` environment variable. When set to an absolute, executable path, shell-based commands use that shell instead of the default.

---

A secure Model Context Protocol (MCP) server implementation for executing controlled command-line operations with
comprehensive security features.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Python Version](https://img.shields.io/badge/python-3.10%2B-blue)
![MCP Protocol](https://img.shields.io/badge/MCP-Compatible-green)
[![smithery badge](https://smithery.ai/badge/cli-mcp-server)](https://smithery.ai/protocol/cli-mcp-server)
[![Python Tests](https://github.com/MladenSU/cli-mcp-server/actions/workflows/python-tests.yml/badge.svg)](https://github.com/MladenSU/cli-mcp-server/actions/workflows/python-tests.yml)

<a href="https://glama.ai/mcp/servers/q89277vzl1"><img width="380" height="200" src="https://glama.ai/mcp/servers/q89277vzl1/badge" /></a>

---

# Table of Contents

1. [Overview](#overview)
2. [Features](#features)
3. [Configuration](#configuration)
4. [Available Tools](#available-tools)
    - [run_command](#run_command)
    - [show_security_rules](#show_security_rules)
5. [Usage with Claude Desktop](#usage-with-claude-desktop)
    - [Development/Unpublished Servers Configuration](#developmentunpublished-servers-configuration)
    - [Published Servers Configuration](#published-servers-configuration)
6. [Security Features](#security-features)
7. [Error Handling](#error-handling)
8. [Development](#development)
    - [Prerequisites](#prerequisites)
    - [Testing](#testing)
    - [Building and Publishing](#building-and-publishing)
    - [Deploying with Supergateway](#deploying-with-supergateway)
    - [Debugging](#debugging)
9. [License](#license)

---

## Overview

This MCP server enables secure command-line execution with robust security measures including command whitelisting, path
validation, and execution controls. Perfect for providing controlled CLI access to LLM applications while maintaining security.

## Features

- 🔒 Secure command execution with strict validation
- ⚙️ Configurable command and flag whitelisting with 'all' option
- 🛡️ Path traversal prevention and validation
- 🚫 Shell operator injection protection
- ⏱️ Execution timeouts and length limits
- 📝 Detailed error reporting
- 🔄 Async operation support
- 🎯 Working directory restriction and validation

## Configuration

Configure the server using environment variables:

| Variable             | Description                                          | Default            |
|---------------------|------------------------------------------------------|-------------------|
| `ALLOWED_DIR`       | Base directory for command execution (Required)      | None (Required)   |
| `ALLOWED_COMMANDS`  | Comma-separated list of allowed commands or 'all'    | `ls,cat,pwd`      |
| `ALLOWED_FLAGS`     | Comma-separated list of allowed flags or 'all'       | `-l,-a,--help`    |
| `MAX_COMMAND_LENGTH`| Maximum command string length                        | `1024`            |
| `COMMAND_TIMEOUT`   | Command execution timeout (seconds)                  | `30`              |
| `ALLOW_SHELL_OPERATORS` | Allow shell operators (&&, \|\|, \|, >, etc.)    | `false`           |
| `SHELL_EXEC`        | Absolute path to the shell executable for shell commands | None          |

Note: Setting `ALLOWED_COMMANDS` or `ALLOWED_FLAGS` to 'all' will allow any command or flag respectively.

## Installation

To install CLI MCP Server for Claude Desktop automatically via [Smithery](https://smithery.ai/protocol/cli-mcp-server):

```bash
npx @smithery/cli install cli-mcp-server --client claude
```

## Available Tools

### run_command

Executes whitelisted CLI commands within allowed directories.

**Input Schema:**
```json
{
  "command": {
    "type": "string",
    "description": "Single command to execute (e.g., 'ls -l' or 'cat file.txt')"
  }
}
```

**Security Notes:**
- Shell operators (&&, |, >, >>) are not supported by default, but can be enabled with `ALLOW_SHELL_OPERATORS=true`
- Commands must be whitelisted unless ALLOWED_COMMANDS='all'
- Flags must be whitelisted unless ALLOWED_FLAGS='all'
- All paths are validated to be within ALLOWED_DIR

### show_security_rules

Displays current security configuration and restrictions, including:
- Working directory
- Allowed commands
- Allowed flags
- Security limits (max command length and timeout)

## Usage with Claude Desktop

Add to your `~/Library/Application\ Support/Claude/claude_desktop_config.json`:

> Development/Unpublished Servers Configuration

```json
{
  "mcpServers": {
    "cli-mcp-server": {
      "command": "uv",
      "args": [
        "--directory",
        "<path/to/the/repo>/cli-mcp-server",
        "run",
        "cli-mcp-server"
      ],
      "env": {
        "ALLOWED_DIR": "</your/desired/dir>",
        "ALLOWED_COMMANDS": "ls,cat,pwd,echo",
        "ALLOWED_FLAGS": "-l,-a,--help,--version",
        "MAX_COMMAND_LENGTH": "1024",
        "COMMAND_TIMEOUT": "30",
        "ALLOW_SHELL_OPERATORS": "false"
      }
    }
  }
}
```

> Published Servers Configuration

```json
{
  "mcpServers": {
    "cli-mcp-server": {
      "command": "uvx",
      "args": [
        "cli-mcp-server"
      ],
      "env": {
        "ALLOWED_DIR": "</your/desired/dir>",
        "ALLOWED_COMMANDS": "ls,cat,pwd,echo",
        "ALLOWED_FLAGS": "-l,-a,--help,--version",
        "MAX_COMMAND_LENGTH": "1024",
        "COMMAND_TIMEOUT": "30",
        "ALLOW_SHELL_OPERATORS": "false"
      }
    }
  }
}
```
> In case it's not working or showing in the UI, clear your cache via `uv clean`.

## Security Features

- ✅ Command whitelist enforcement with 'all' option
- ✅ Flag validation with 'all' option
- ✅ Path traversal prevention and normalization
- ✅ Shell operator blocking (with opt-in support via `ALLOW_SHELL_OPERATORS=true`)
- ✅ Command length limits
- ✅ Execution timeouts
- ✅ Working directory restrictions
- ✅ Symlink resolution and validation

## Error Handling

The server provides detailed error messages for:

- Security violations (CommandSecurityError)
- Command timeouts (CommandTimeoutError)
- Invalid command formats
- Path security violations
- Execution failures (CommandExecutionError)
- General command errors (CommandError)

## Development

### Prerequisites

- Python 3.10+
- MCP protocol library

### Testing

Run the local build + smoke test flow:

```bash
./scripts/build_run.sh
```

This script creates a virtual environment in `.venv/`, installs the package from the local
repository, and produces build artifacts in `dist/`.

### Building and Publishing

To prepare the package for distribution:

1. Sync dependencies and update lockfile:
    ```bash
    uv sync
    ```

2. Build package distributions:
    ```bash
    uv build
    ```

   > This will create source and wheel distributions in the `dist/` directory.

3. Publish to PyPI:
   ```bash
   uv publish --token {{YOUR_PYPI_API_TOKEN}}
   ```

### Streamable HTTP server (JSON)

If you want a direct streamable HTTP endpoint that **does not use SSE**, run the built-in
HTTP server. It emits `application/json` responses and streams as newline-delimited JSON
frames (NDJSON) to match the streamable HTTP protocol expectations.

```bash
MCP_HTTP_HOST=127.0.0.1 MCP_HTTP_PORT=8084 MCP_HTTP_PATH=/mcp cli-mcp-server-http
```

Clients should set `Accept: application/json` and send JSON-RPC requests to the configured
path (default `/mcp`). You can also override the bind settings with `MCP_HTTP_HOST`,
`MCP_HTTP_PORT`, and `MCP_HTTP_PATH`.

### Deploying with Supergateway

For local deployments using [Supergateway](https://github.com/supercorp-ai/supergateway), you can use:

```bash
./scripts/deploy_supergateway.sh start
```

The deploy script uses `scripts/build_run.sh` to prepare a local build and then launches
Supergateway with the locally built `cli-mcp-server` CLI. You can customize paths with
`REPO_DIR`, `VENV_DIR`, and `CLI_MCP_BIN`. Set `SKIP_BUILD=true` to skip rebuilding.

```bash
./scripts/deploy_supergateway.sh status
./scripts/deploy_supergateway.sh stop
```

### Debugging

Since MCP servers run over stdio, debugging can be challenging. For the best debugging
experience, we strongly recommend using the [MCP Inspector](https://github.com/modelcontextprotocol/inspector).

You can launch the MCP Inspector via [`npm`](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm) with
this command:

```bash
npx @modelcontextprotocol/inspector uv --directory {{your source code local directory}}/cli-mcp-server run cli-mcp-server
```

Upon launching, the Inspector will display a URL that you can access in your browser to begin debugging.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

For more information or support, please open an issue on the project repository.
