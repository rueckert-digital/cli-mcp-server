import os
import socket
import unittest
import urllib.parse
import urllib.request
import urllib.error
import json


def _read_response_body(response: urllib.response.addinfourl) -> str:
    content_type = response.headers.get("content-type", "")
    if content_type.startswith("text/event-stream"):
        lines = []
        while True:
            line = response.readline().decode("utf-8")
            if not line:
                break
            lines.append(line)
            if line.startswith("data: "):
                break
        return "".join(lines)
    return response.read().decode("utf-8")


def _post_json(url: str, payload: dict, headers: dict, timeout: int = 10) -> tuple[int, dict, str]:
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = _read_response_body(response)
            normalized_headers = {key.lower(): value for key, value in response.headers.items()}
            return response.status, normalized_headers, body
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8") if exc.fp else ""
        normalized_headers = {key.lower(): value for key, value in exc.headers.items()}
        return exc.code, normalized_headers, body


def _parse_response_body(body: str) -> dict:
    stripped = body.lstrip()
    if stripped.startswith("{"):
        return json.loads(stripped)
    for line in body.splitlines():
        if line.startswith("data: "):
            return json.loads(line[len("data: "):])
    raise AssertionError(f"Unable to parse response body: {body!r}")


def _is_port_open(host: str, port: int, timeout: float = 0.5) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


class TestSupergatewayE2E(unittest.TestCase):
    _base_url: str = ""

    @classmethod
    def setUpClass(cls) -> None:
        port = os.getenv("PORT", "8084")
        url = os.getenv("SUPERGATEWAY_URL", f"http://127.0.0.1:{port}/mcp")
        parsed = urllib.parse.urlparse(url)
        if not parsed.hostname or not parsed.port:
            raise RuntimeError(f"Invalid SUPERGATEWAY_URL: {url}")
        cls._base_url = url

        if not _is_port_open(parsed.hostname, parsed.port):
            raise RuntimeError(
                "Supergateway is not reachable. Start it before running e2e tests. "
                f"Expected listening at {parsed.hostname}:{parsed.port}."
            )

    def test_supergateway_endpoints(self) -> None:
        url = self._base_url
        print("[e2e] Supergateway client checks starting")
        base_headers = {
            "accept": "application/json, text/event-stream",
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
        print("[e2e][initialize] ok")

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
        print("[e2e][notifications/initialized] ok")

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
        print("[e2e][tools/list] ok")

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
        print("[e2e][tools/call run_command echo] ok")

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
        print("[e2e][tools/call run_command ls] ok")

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
        print("[e2e][tools/call show_security_rules] ok")

        print("[e2e] Supergateway client checks done")


if __name__ == "__main__":
    unittest.main()
