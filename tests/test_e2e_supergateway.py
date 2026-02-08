import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.parse
import urllib.request


def _post_json(url: str, payload: dict, headers: dict, timeout: int = 10) -> tuple[int, dict, str]:
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(url, data=data, headers=headers, method="POST")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        body = response.read().decode("utf-8")
        normalized_headers = {key.lower(): value for key, value in response.headers.items()}
        return response.status, normalized_headers, body


def _parse_response_body(body: str) -> dict:
    stripped = body.strip()
    if stripped:
        try:
            return json.loads(stripped)
        except json.JSONDecodeError:
            pass
    # Streamable HTTP responses can be newline-delimited JSON chunks.
    for line in body.splitlines():
        chunk = line.strip()
        if not chunk:
            continue
        try:
            return json.loads(chunk)
        except json.JSONDecodeError:
            continue
    raise AssertionError(f"Unable to parse streamable response body: {body!r}")


def _is_port_open(host: str, port: int, timeout: float = 0.5) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def _wait_for_port(host: str, port: int, timeout: float = 20.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if _is_port_open(host, port):
            return
        time.sleep(0.5)
    raise TimeoutError(f"Timed out waiting for streamable HTTP server on {host}:{port}")


class TestSupergatewayE2E(unittest.TestCase):
    _http_process: subprocess.Popen | None = None
    _http_tempdir: tempfile.TemporaryDirectory | None = None
    _base_url: str = ""

    @classmethod
    def setUpClass(cls) -> None:
        url = os.getenv("MCP_HTTP_URL") or os.getenv(
            "SUPERGATEWAY_URL", "http://127.0.0.1:8084/mcp"
        )
        parsed = urllib.parse.urlparse(url)
        if not parsed.hostname or not parsed.port:
            raise RuntimeError(f"Invalid MCP_HTTP_URL/SUPERGATEWAY_URL: {url}")
        cls._base_url = url

        if _is_port_open(parsed.hostname, parsed.port):
            return

        cls._http_tempdir = tempfile.TemporaryDirectory()
        env = os.environ.copy()
        env.setdefault("ALLOWED_DIR", cls._http_tempdir.name)
        env.setdefault("ALLOWED_COMMANDS", "all")
        env.setdefault("ALLOWED_FLAGS", "all")
        env.setdefault("ALLOW_SHELL_OPERATORS", "true")
        env.setdefault("MCP_HTTP_HOST", parsed.hostname)
        env.setdefault("MCP_HTTP_PORT", str(parsed.port))
        env.setdefault("MCP_HTTP_PATH", parsed.path or "/mcp")

        cls._http_process = subprocess.Popen(
            [sys.executable, "-m", "cli_mcp_server.streamable_http"],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        _wait_for_port(parsed.hostname, parsed.port)

    @classmethod
    def tearDownClass(cls) -> None:
        if cls._http_process:
            cls._http_process.terminate()
            try:
                cls._http_process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                cls._http_process.kill()
                cls._http_process.wait(timeout=5)
        if cls._http_tempdir:
            cls._http_tempdir.cleanup()

    def test_supergateway_endpoints(self) -> None:
        url = self._base_url
        base_headers = {
            "accept": "application/json",
            "content-type": "application/json",
        }

        init_payload = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-11-25",
                "capabilities": {},
                "clientInfo": {"name": "e2e-client", "version": "0.1.0"},
            },
        }

        status, init_headers, init_body = _post_json(url, init_payload, base_headers)
        self.assertEqual(status, 200, f"Unexpected init status: {status}, body={init_body}")
        init_response = _parse_response_body(init_body)
        self.assertIn("result", init_response, f"Init response missing result: {init_response}")

        session_id = init_headers.get("mcp-session-id")
        self.assertTrue(session_id, "Missing mcp-session-id header from initialize")

        headers = dict(base_headers)
        headers["mcp-session-id"] = session_id
        if init_headers.get("mcp-protocol-version"):
            headers["mcp-protocol-version"] = init_headers["mcp-protocol-version"]

        init_notification = {
            "jsonrpc": "2.0",
            "method": "notifications/initialized",
            "params": {},
        }
        notify_status, _, notify_body = _post_json(url, init_notification, headers)
        self.assertEqual(
            notify_status,
            202,
            f"Unexpected initialized notification status: {notify_status}, body={notify_body}",
        )

        tools_list = {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}}
        tools_status, _, tools_body = _post_json(url, tools_list, headers)
        self.assertEqual(
            tools_status,
            200,
            f"Unexpected tools/list status: {tools_status}, body={tools_body}",
        )
        tools_response = _parse_response_body(tools_body)
        tool_names = {tool["name"] for tool in tools_response["result"]["tools"]}
        self.assertIn("run_command", tool_names)
        self.assertIn("show_security_rules", tool_names)

        echo_shell = {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {"name": "run_command", "arguments": {"command": "echo $SHELL"}},
        }
        echo_status, _, echo_body = _post_json(url, echo_shell, headers)
        self.assertEqual(
            echo_status,
            200,
            f"Unexpected run_command echo status: {echo_status}, body={echo_body}",
        )
        echo_response = _parse_response_body(echo_body)
        echo_text = "\n".join(item["text"] for item in echo_response["result"]["content"])
        self.assertIn("Command completed with return code: 0", echo_text)

        list_dir = {
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {"name": "run_command", "arguments": {"command": "ls -l"}},
        }
        ls_status, _, ls_body = _post_json(url, list_dir, headers)
        self.assertEqual(
            ls_status,
            200,
            f"Unexpected run_command ls status: {ls_status}, body={ls_body}",
        )
        ls_response = _parse_response_body(ls_body)
        ls_text = "\n".join(item["text"] for item in ls_response["result"]["content"])
        self.assertIn("Command completed with return code: 0", ls_text)

        security_call = {
            "jsonrpc": "2.0",
            "id": 5,
            "method": "tools/call",
            "params": {"name": "show_security_rules", "arguments": {}},
        }
        security_status, _, security_body = _post_json(url, security_call, headers)
        self.assertEqual(
            security_status,
            200,
            f"Unexpected show_security_rules status: {security_status}, body={security_body}",
        )
        security_response = _parse_response_body(security_body)
        security_text = "\n".join(item["text"] for item in security_response["result"]["content"])
        self.assertIn("Security Configuration", security_text)


if __name__ == "__main__":
    unittest.main()
